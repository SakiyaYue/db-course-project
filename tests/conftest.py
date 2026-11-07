"""pytest 共享夹具：固定连接独立的 TeabarDB_Phase2_Test，避免污染工作库。"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pyodbc
import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

# Fail closed: integration fixtures must never target the source or demo database.
_test_database = os.environ.get("TEABAR_TEST_DB", "TeabarDB_Phase2_Test")
if _test_database != "TeabarDB_Phase2_Test":
    raise RuntimeError("pytest 仅允许独立 TeabarDB_Phase2_Test，拒绝源库/工作库/其他目标")
os.environ["TEABAR_DB_NAME"] = _test_database
os.environ.setdefault("TEABAR_SECRET_KEY", "pytest-insecure-key")

from app import create_app  # noqa: E402
from app.services import order_service  # noqa: E402

ACCOUNTS = {
    "guesta": "Guest#2026",
    "guestb": "Guest#2026",
    "membera": "Member#2026",
    "memberb": "Member#2026",
    "clerk1": "Clerk#2026",
    "manager1": "Manager#2026",
}


@pytest.fixture(scope="session")
def app():
    application = create_app()
    application.config.update(TESTING=True)
    return application


@pytest.fixture()
def client(app):
    return app.test_client()


@pytest.fixture()
def cfg(app):
    return app.extensions["teabar_config"]


@pytest.fixture()
def dbo(app, cfg):
    """以 Windows 集成身份直连测试库，仅用于核对/恢复测试数据。"""
    conn = pyodbc.connect(cfg.connection_string("teabar-pytest"), autocommit=True)
    try:
        yield conn
    finally:
        conn.close()


@pytest.fixture()
def login(client):
    def _login(name: str, password: str | None = None):
        password = ACCOUNTS.get(name, password) if password is None else password
        token = client.get("/api/csrf").get_json()["csrf_token"]
        return client.post(
            "/login",
            data={"login_name": name, "password": password, "csrf_token": token},
        )

    return _login


@pytest.fixture()
def csrf(client):
    def _csrf() -> str:
        return client.get("/api/csrf").get_json()["csrf_token"]

    return _csrf


@pytest.fixture()
def catalog(app, client, login):
    """登录游客并返回目录与下单辅助函数。"""

    login("guesta")

    def _catalog() -> dict:
        response = client.get("/api/menu")
        assert response.status_code == 200
        return response.get_json()

    def _place(product_index: int = 0, quantity: int = 1) -> dict:
        data = _catalog()
        product = data["products"][product_index]
        spec_ids = [specs[0]["spec_id"] for specs in product["spec_types"].values()]
        token = client.get("/api/csrf").get_json()["csrf_token"]
        response = client.post(
            "/api/orders",
            json={
                "items": [
                    {
                        "product_id": product["product_id"],
                        "quantity": quantity,
                        "specs": spec_ids,
                        "addons": [],
                    }
                ],
                "payment_succeeded": True,
            },
            headers={"X-CSRF-Token": token},
        )
        assert response.status_code == 201, response.get_data(as_text=True)
        return response.get_json()

    _place.catalog = _catalog  # type: ignore[attr-defined]
    return _place


@pytest.fixture()
def sample_order(app, cfg):
    """以 web_guest_a 身份直接经 service/DAO 建单，返回过程结果行。"""
    conn = pyodbc.connect(cfg.connection_string("teabar-pytest"), autocommit=True)
    cursor = conn.cursor()
    try:
        cursor.execute("EXECUTE AS USER = 'web_guest_a';")
        try:
            return order_service.place_paid_order(
                conn,
                {
                    "items": [
                        {
                            "product_id": "P001",
                            "quantity": 1,
                            "specs": ["S007", "S004", "S001"],
                            "addons": [],
                        }
                    ],
                    "payment_succeeded": True,
                },
            )
        finally:
            cursor.execute("REVERT;")
    finally:
        cursor.close()
        conn.close()
