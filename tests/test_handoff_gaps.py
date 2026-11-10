"""Real HTTP/SQL regression for staff refunds, history and buyer-scoped snapshots."""
from decimal import Decimal

import pyodbc
import pytest

from app.dao.common import query


def post(client, path, body=None):
    token = client.get("/api/csrf").get_json()["csrf_token"]
    return client.post(path, json=body, headers={"X-CSRF-Token": token})


def place(client, login, account="guesta"):
    login(account)
    result = post(client, "/api/orders", {"items": [{"product_id": "P001", "quantity": 1,
                       "specs": ["S007", "S004", "S001"], "addons": []}], "payment_succeeded": True})
    assert result.status_code == 201, result.get_json()
    return result.get_json()["order_id"]


def stocks(dbo):
    return {r[0]: r[1] for r in dbo.execute("SELECT ingredient_id, stock FROM dbo.Ingredient").fetchall()}


@pytest.mark.parametrize("staff", ["clerk1", "manager1"])
def test_staff_refund_snapshot_and_repeat(client, login, dbo, staff):
    before = stocks(dbo)
    oid = place(client, login)
    login(staff)
    path = f"/api/work/orders/{oid}/refund"
    assert client.post(path).status_code == 400  # CSRF is still mandatory.
    assert post(client, path).status_code == 200
    assert stocks(dbo) == before
    assert post(client, path).status_code == 409
    assert stocks(dbo) == before


@pytest.mark.parametrize("state", ["制作中", "待取餐", "已完成"])
def test_staff_cannot_refund_non_queue(client, login, dbo, state):
    oid = place(client, login)
    login("clerk1")
    for next_state in ("制作中", "待取餐", "已完成"):
        assert post(client, f"/api/work/orders/{oid}/advance", {"next_status": next_state}).status_code == 200
        if next_state == state:
            break
    before = stocks(dbo)
    assert post(client, f"/api/work/orders/{oid}/refund").status_code == 409
    assert stocks(dbo) == before


@pytest.mark.parametrize("buyer,other,principal", [("guesta", "guestb", "web_guest_b"),
                                                  ("membera", "memberb", "web_member_b")])
def test_consumption_isolated_in_http_and_sql(client, login, dbo, buyer, other, principal):
    oid = place(client, login, buyer)
    detail = client.get(f"/api/my/orders/{oid}").get_json()
    assert detail["consumption"]
    actual = { (r["item_id"], r["ingredient_id"]): Decimal(r["amount"]) for r in detail["consumption"] }
    expected = {(r[0], r[1]): r[2] for r in dbo.execute(
        "SELECT c.item_id,c.ingredient_id,c.amount FROM dbo.OrderItemIngredient c "
        "JOIN dbo.OrderItem i ON i.item_id=c.item_id WHERE i.order_id=?", oid).fetchall()}
    assert actual == expected
    page = client.get(f"/my/orders/{oid}")
    assert page.status_code == 200 and "原料消耗快照" in page.get_data(as_text=True)
    login(other)
    assert client.get(f"/api/my/orders/{oid}").status_code == 404
    query(dbo, f"EXECUTE AS USER = '{principal}'")  # fixed parametrized test identities
    try:
        assert query(dbo, "SELECT * FROM teabar_api.vw_MyConsumption WHERE order_id=?", oid) == []
        with pytest.raises(pyodbc.Error):
            query(dbo, "SELECT TOP (1) * FROM dbo.OrderItemIngredient")
    finally:
        query(dbo, "REVERT")


def test_complete_history_and_snapshots(client, login, dbo):
    oid = place(client, login)
    own = client.get(f"/api/my/orders/{oid}").get_json()
    assert post(client, f"/api/my/orders/{oid}/refund").status_code == 200
    old_time = dbo.execute("SELECT order_time FROM dbo.SalesOrder WHERE order_id=?", oid).fetchone()[0]
    old_price = dbo.execute("SELECT base_price FROM dbo.Product WHERE product_id='P001'").fetchone()[0]
    try:
        dbo.execute("UPDATE dbo.SalesOrder SET order_time='2001-01-01T23:59:59' WHERE order_id=?", oid)
        dbo.execute("UPDATE dbo.Product SET base_price=99 WHERE product_id='P001'")
        login("clerk1")
        assert client.get(f"/api/work/orders/{oid}").status_code == 404
        login("manager1")
        listing = client.get(f"/api/admin/orders?order_id={oid}&date_from=2001-01-01&date_to=2001-01-01&status=已取消").get_json()
        assert [r["order_id"] for r in listing["orders"]] == [oid]
        detail = client.get(f"/api/admin/orders/{oid}")
        assert detail.status_code == 200
        for key in ("items", "specs", "addons", "consumption"):
            assert detail.get_json()[key] == own[key]
        assert client.get("/api/admin/orders/NOEXIST").status_code == 404
        first = client.get("/api/admin/orders?page_size=1").get_json()
        second = client.get("/api/admin/orders?page_size=1&page=2").get_json()
        assert first["has_more"] and first["orders"][0]["order_id"] != second["orders"][0]["order_id"]
        assert client.get("/api/admin/orders?page=1&page=2").status_code == 400
    finally:
        dbo.execute("UPDATE dbo.SalesOrder SET order_time=? WHERE order_id=?", old_time, oid)
        dbo.execute("UPDATE dbo.Product SET base_price=? WHERE product_id='P001'", old_price)


@pytest.mark.parametrize("account", ["guesta", "membera", "clerk1"])
def test_history_and_manager_member_route_reject_other_roles(client, login, account):
    login(account)
    assert client.get("/api/admin/orders").status_code == 403
    assert client.get("/api/admin/orders/O001").status_code == 403
    assert post(client, "/api/admin/members", {}).status_code == 403
    if account != "clerk1":
        assert post(client, "/api/work/orders/O001/refund").status_code == 403


def test_manager_member_alias_and_no_truncation(client, login, dbo):
    login("manager1")
    original = dbo.execute("SELECT name,phone FROM dbo.Member WHERE member_id='M001'").fetchone()
    try:
        body = {"member_id": "M001", "name": "字" * 50, "phone": original[1]}
        assert post(client, "/api/admin/members", body).status_code == 200
        assert client.get("/api/admin/members?phone=" + original[1]).get_json()["name"] == "字" * 50
        for change in ({"name": "字" * 51}, {"phone": "1234567"}, {"phone": 13800000000}):
            assert post(client, "/api/admin/members", dict(body, **change)).status_code == 400
        assert dbo.execute("SELECT name FROM dbo.Member WHERE member_id='M001'").fetchone()[0] == "字" * 50
    finally:
        dbo.execute("UPDATE dbo.Member SET name=?,phone=? WHERE member_id='M001'", original[0], original[1])


def test_staff_html_refund(client, login):
    oid = place(client, login)
    login("clerk1")
    page = client.get(f"/work/orders/{oid}")
    assert page.status_code == 200 and "协助退款" in page.get_data(as_text=True)
    response = post(client, f"/work/orders/{oid}/refund")
    assert response.status_code == 302
    assert client.get(response.location).status_code == 200


def test_anonymous_history_requires_login(client):
    assert client.get("/api/admin/orders").status_code == 401
    assert client.get("/api/admin/orders/O001").status_code == 401
