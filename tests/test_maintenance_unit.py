"""Management validation, HTTP boundaries and parameter binding without SQL Server."""
from decimal import Decimal
from unittest.mock import MagicMock

import pyodbc
import pytest

from app.dao import auth_dao, maintenance_dao as dao
from app.errors import AppError
from app.services import maintenance_service as service

CASES = {
    "products": {"product_id": "PTEST", "product_name": "测试商品", "base_price": "8.50", "status": "下架"},
    "ingredients": {"ingredient_id": "ITEST", "ingredient_name": "测试原料", "unit": "ml", "status": "可用"},
    "employees": {"employee_id": "ETEST", "name": "测试员工", "salary": "0", "role": "店员", "status": "在职"},
    "specifications": {"spec_id": "STEST", "spec_type": "杯型", "spec_name": "测试杯型"},
    "product-specifications": {"product_id": "PTEST", "spec_id": "STEST", "price_delta": "-0.50", "status": "停用"},
    "recipes": {"product_id": "PTEST", "ingredient_id": "ITEST", "base_amount": "2"},
    "specification-ingredients": {"product_id": "PTEST", "spec_id": "STEST", "ingredient_id": "ITEST", "factor": "0"},
    "addons": {"addon_id": "ATEST", "addon_name": "测试加料", "price": "0", "ingredient_id": "ITEST", "extra_amount": "1", "status": "缺货"},
    "duty-rosters": {"duty_id": "DTEST", "employee_id": "ETEST", "start_time": "2099-01-01T08:00:00", "end_time": "2099-01-01T16:00:00"},
}


@pytest.fixture
def manager(monkeypatch):
    monkeypatch.setattr(auth_dao, "business_role", lambda conn: {"manager": 1})
    conn = MagicMock()
    conn.cursor.return_value.description = None
    conn.cursor.return_value.nextset.return_value = False
    return conn


@pytest.mark.parametrize("resource", CASES)
def test_all_nine_bind_parameters_and_close(manager, resource):
    result = service.save_record(manager, resource, CASES[resource])
    cursor = manager.cursor.return_value
    sql, *parameters = cursor.execute.call_args.args
    assert sql.startswith("EXEC teabar_api.usp_Save")
    assert sql.count("?") == len(parameters) == len(dao.RESOURCES[resource].fields)
    assert all(value not in sql for value in CASES[resource].values())
    assert result["saved"] is True
    cursor.close.assert_called_once()


@pytest.mark.parametrize("field,value", [("base_price", "NaN"), ("base_price", "Infinity"),
    ("base_price", "1.001"), ("base_price", "100000000"), ("base_price", True),
    ("base_price", -1), ("product_id", "x';--"), ("product_name", []),
    ("product_name", "😀" * 26), ("product_name", " "), ("status", "停用"), ("stock", 100)])
def test_bad_inputs_never_reach_write(manager, field, value):
    body = dict(CASES["products"], **{field: value})
    with pytest.raises(AppError) as error:
        service.save_record(manager, "products", body)
    assert error.value.status == 400
    manager.cursor.assert_not_called()


@pytest.mark.parametrize("resource", ["recipes", "specification-ingredients"])
def test_remove_requires_boolean_and_sends_null_amount(manager, resource):
    body = {k: CASES[resource][k] for k in dao.RESOURCES[resource].keys}
    with pytest.raises(AppError):
        service.save_record(manager, resource, dict(body, remove="false"))
    result = service.save_record(manager, resource, dict(body, remove=True))
    assert result["removed"] is True
    assert manager.cursor.return_value.execute.call_args.args[-2:] == (None, True)


@pytest.mark.parametrize("changes", [{"end_time": "2099-01-01T08:00:00"},
    {"start_time": "2099-01-01T08:00:00Z"}, {"start_time": "2099-02-30T08:00:00"},
    {"start_time": "2099-01-01T08:00:00.1"}])
def test_invalid_duty_times(manager, changes):
    with pytest.raises(AppError):
        service.save_record(manager, "duty-rosters", dict(CASES["duty-rosters"], **changes))
    manager.cursor.assert_not_called()


def test_reads_include_inactive_rows_and_serialize_decimal(manager):
    cursor = manager.cursor.return_value
    cursor.description = [("product_id",), ("status",), ("base_price",)]
    cursor.fetchall.return_value = [("PTEST", "下架", Decimal("8.50"))]
    assert service.list_records(manager, "products")[0]["base_price"] == "8.50"
    assert "WHERE" not in cursor.execute.call_args.args[0]
    service.list_records(manager, "products", {"status": "下架"})
    assert "status = ?" in cursor.execute.call_args.args[0]
    assert cursor.execute.call_args.args[1] == "下架"


def test_composite_detail_and_missing_record(manager):
    with pytest.raises(AppError) as error:
        service.get_record(manager, "recipes", ["PTEST", "ITEST"])
    assert error.value.status == 404
    assert manager.cursor.return_value.execute.call_args.args[1:] == ("PTEST", "ITEST")


def test_deferred_database_error_is_not_success(manager):
    cursor = manager.cursor.return_value
    cursor.nextset.side_effect = pyodbc.Error("42000", "private SQL details (52121)")
    with pytest.raises(AppError) as error:
        service.save_record(manager, "duty-rosters", CASES["duty-rosters"])
    assert error.value.code == "duty_overlap"
    assert "private" not in error.value.message
    cursor.close.assert_called_once()


@pytest.mark.parametrize("resource", CASES)
@pytest.mark.parametrize("role", ["customer", "member", "clerk"])
def test_direct_services_reject_non_managers(manager, monkeypatch, resource, role):
    monkeypatch.setattr(auth_dao, "business_role", lambda conn: {role: 1})
    for action in (lambda: service.save_record(manager, resource, CASES[resource]),
                   lambda: service.list_records(manager, resource),
                   lambda: service.get_record(manager, resource, ["X"])):
        with pytest.raises(AppError) as error:
            action()
        assert error.value.status == 403
    manager.cursor.assert_not_called()


@pytest.fixture
def http_manager(app, client, monkeypatch):
    # Keep real session_scope, role checks and CSRF; mock only DB transport/identity.
    context = {"account_id": 1, "session_version": 1, "app_role": "manager", "principal_name": "web_manager"}
    db = MagicMock()
    conn = db.connection.return_value.__enter__.return_value
    monkeypatch.setitem(app.extensions, "teabar_db", db)
    monkeypatch.setattr(auth_dao, "get_context", lambda *args: dict(context))
    with client.session_transaction() as session:
        session["auth"] = dict(context)
        session["csrf_token"] = "test-token"
    return conn, context


@pytest.mark.parametrize("resource", CASES)
def test_http_roundtrip_dispatch_and_csrf(client, http_manager, monkeypatch, resource):
    save = MagicMock()
    read = MagicMock(return_value=[CASES[resource]])
    monkeypatch.setattr(dao, "save_record", save)
    monkeypatch.setattr(dao, "list_records", read)
    path = "/api/admin/" + resource
    assert client.post(path, json=CASES[resource]).status_code == 400
    save.assert_not_called()
    assert client.post(path, json=CASES[resource], headers={"X-CSRF-Token": "test-token"}).status_code == 200
    save.assert_called_once()
    response = client.get(path)
    assert response.status_code == 200
    assert resource.replace("-", "_") in response.get_json()
    keys = "/".join(CASES[resource][k] for k in dao.RESOURCES[resource].keys)
    assert client.get(path + "/" + keys).status_code == 200


@pytest.mark.parametrize("resource", CASES)
def test_http_clerk_cannot_read_or_write(client, http_manager, resource):
    _, context = http_manager
    context.update(app_role="clerk", principal_name="web_clerk")
    with client.session_transaction() as session:
        session["auth"] = dict(context)
    path = "/api/admin/" + resource
    assert client.get(path).status_code == 403
    assert client.post(path, json=CASES[resource], headers={"X-CSRF-Token": "test-token"}).status_code == 403


def test_http_malformed_payload_and_duplicate_filter(client, http_manager):
    assert client.post("/api/admin/products", json=[], headers={"X-CSRF-Token": "test-token"}).status_code == 400
    assert client.get("/api/admin/products?status=在售&status=下架").status_code == 400
    assert client.get("/api/admin/products?sql=DROP").status_code == 400


@pytest.mark.parametrize("resource", CASES)
def test_anonymous_requests_require_login(client, resource):
    assert client.get("/api/admin/" + resource).status_code == 401
