"""Configuration, observability and diagnostic disclosure regressions."""
import json
import logging
from contextlib import contextmanager
from unittest.mock import MagicMock

import pyodbc
import pytest
from flask import g

import app as app_module
from app.config import Config
from app.errors import translate_db_error
from app.routes import api_routes
from app.services import order_service


@pytest.mark.parametrize("environment", ["demo", "test", "production"])
def test_non_development_requires_explicit_secret(monkeypatch, environment):
    monkeypatch.delenv("TEABAR_SECRET_KEY", raising=False)
    monkeypatch.setenv("TEABAR_ENV", environment)
    with pytest.raises(RuntimeError, match="TEABAR_SECRET_KEY"):
        Config.from_env()


def test_development_secret_is_random_per_config_load(monkeypatch):
    monkeypatch.delenv("TEABAR_SECRET_KEY", raising=False)
    monkeypatch.setenv("TEABAR_ENV", "development")
    first, second = Config.from_env(), Config.from_env()
    assert first.secret_key != second.secret_key
    assert len(first.secret_key) >= 32


@pytest.mark.parametrize("secret", ["dev-only-insecure-key", "dev-only-change-me"])
def test_example_secrets_are_rejected(monkeypatch, secret):
    monkeypatch.setenv("TEABAR_SECRET_KEY", secret)
    with pytest.raises(RuntimeError):
        Config.from_env()


def test_business_error_audit_has_context_but_not_sensitive_input(app, client, monkeypatch, caplog):
    connection = MagicMock()
    ctx = {"account_id": 7, "app_role": "customer"}
    @contextmanager
    def scope(**kwargs):
        g.business_context = ctx
        g.business_connection = connection
        yield connection, ctx
    monkeypatch.setattr(api_routes, "session_scope", scope)
    attack = "P001'; DROP TABLE dbo.Product;--"
    password = "SensitivePasswordShouldNeverAppear"
    def fail(conn, payload):
        raise translate_db_error(pyodbc.Error("23000", f"private SQL {attack} password={password} (52016)"))
    monkeypatch.setattr(order_service, "place_paid_order", fail)
    with client.session_transaction() as session:
        session["auth"] = ctx
    csrf = client.get("/api/csrf").get_json()["csrf_token"]
    with caplog.at_level(logging.INFO, logger=app.logger.name):
        response = client.post("/api/orders", json={"items":[{"product_id":attack}], "password":password}, headers={"X-CSRF-Token":csrf})
    assert response.status_code == 409
    records = [json.loads(record.getMessage()[8:]) for record in caplog.records if record.getMessage().startswith("request ")]
    audit = records[-1]
    assert audit["request_id"] == response.headers["X-Request-ID"]
    assert audit["account_id"] == 7 and audit["role"] == "customer"
    assert audit["error_code"] == "stock_insufficient"
    assert audit["sql_number"] == 52016
    assert audit["result"] == "failed"
    assert audit["operation"] == "api.create_order"
    assert attack not in caplog.text and password not in caplog.text
    assert attack not in response.get_data(as_text=True)


def test_health_response_does_not_disclose_database_login(app, client, monkeypatch):
    @contextmanager
    def connection(*args):
        yield MagicMock()
    monkeypatch.setattr(app.extensions["teabar_db"], "connection", connection)
    monkeypatch.setattr(app_module, "health", lambda conn: None)
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.get_json() == {"status":"ok"}
