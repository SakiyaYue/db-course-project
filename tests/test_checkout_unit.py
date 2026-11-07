"""HTML contract regressions using mocked business calls (no database required)."""
import json
import re
from contextlib import contextmanager
from unittest.mock import MagicMock

import pytest
from flask import g
from werkzeug.datastructures import MultiDict

from app.errors import AppError
from app.routes import menu_routes, order_routes
from app.services import menu_service, order_service


@pytest.fixture
def html_checkout(client, monkeypatch):
    conn = MagicMock()
    ctx = {"app_role": "customer", "account_id": 1}
    @contextmanager
    def scope(**kwargs):
        g.business_context = ctx
        g.business_connection = conn
        yield conn, ctx
    monkeypatch.setattr(menu_routes, "session_scope", scope)
    monkeypatch.setattr(order_routes, "session_scope", scope)
    monkeypatch.setattr(menu_service, "load_catalog", lambda conn: {
        "products": [{"product_id": "P001", "product_name": "Lemon", "base_price": "6.00", "spec_types": {"sugar": [{"spec_id": "S001", "spec_name": "normal", "price_delta": "0.00"}]}}], "addons": []})
    with client.session_transaction() as session:
        session["auth"] = ctx
    return client


def test_checkout_presents_multi_item_and_payment_controls(html_checkout):
    response = html_checkout.get("/orders/new")
    assert response.status_code == 200
    html = response.get_data(as_text=True)
    assert 'name="items_json"' in html
    assert 'id="add-item"' in html
    assert 'name="payment_succeeded"' in html
    assert 'name="request_token"' in html


def test_html_error_retains_basket_payment_and_request_token(html_checkout, monkeypatch):
    client = html_checkout
    get = client.get("/orders/new")
    html = get.get_data(as_text=True)
    request_token = re.search(r'name="request_token" value="([^"]+)"', html).group(1)
    csrf = client.get("/api/csrf").get_json()["csrf_token"]
    items = [{"product_id":"P001", "quantity":2, "specs":["S001"], "addons":[]}]
    monkeypatch.setattr(order_service, "place_paid_order", MagicMock(side_effect=AppError("payment_failed", "付款失败", 402)))
    response = client.post("/orders", data={"csrf_token":csrf, "request_token": request_token, "items_json":json.dumps(items), "payment_succeeded":"false"})
    assert response.status_code == 402
    assert "Location" not in response.headers
    rendered = response.get_data(as_text=True)
    saved = json.loads(re.search(r'<script id="saved-data" type="application/json">(.*?)</script>', rendered, re.S).group(1))
    assert saved["items"] == items
    assert saved["payment_succeeded"] is False
    assert request_token in rendered
    assert "付款失败" in rendered


def test_form_contract_preserves_multiple_items_and_payment_failure():
    items = [{"product_id":"P001","quantity":1,"specs":["S001"],"addons":[]}, {"product_id":"P002","quantity":2,"specs":["S002"],"addons":[]}]
    result = order_service.payload_from_form(MultiDict({"items_json":json.dumps(items),"payment_succeeded":"false"}))
    assert result["items"] == items
    assert result["payment_succeeded"] is False
