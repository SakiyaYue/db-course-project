"""店长统计、库存与人员/会员维护。"""

from __future__ import annotations


def _token(client) -> str:
    return client.get("/api/csrf").get_json()["csrf_token"]


def test_manager_stats(client, login):
    login("manager1")
    response = client.get("/api/admin/stats")
    assert response.status_code == 200
    data = response.get_json()
    assert isinstance(data["daily"], list)
    assert isinstance(data["products"], list)
    if data["daily"]:
        dates = {row["sale_date"] for row in data["daily"]}
        assert "2026-10-04" in dates, "初始样例的 10-04 日销售应保留"


def test_manager_pages_render(client, login):
    login("manager1")
    for path in ("/admin/stats", "/admin/stock", "/admin/employees", "/admin/members"):
        assert client.get(path).status_code == 200


def test_ingredients_and_employees(client, login):
    login("manager1")
    ingredients = client.get("/api/admin/stock").get_json()["ingredients"]
    assert len(ingredients) == 9
    assert all("stock" in row for row in ingredients)

    employees = client.get("/api/admin/employees").get_json()["employees"]
    assert len(employees) == 4


def test_find_member_by_phone(client, login):
    login("manager1")
    response = client.get("/api/admin/members?phone=13800000001")
    assert response.status_code == 200
    assert response.get_json()["member_id"] == "M001"

    missing = client.get("/api/admin/members?phone=13999999999")
    assert missing.status_code == 404
    assert missing.get_json()["error"]["code"] == "member_not_found"

    bad = client.get("/api/admin/members?phone=abc")
    assert bad.status_code == 400
    assert bad.get_json()["error"]["code"] == "invalid_phone"


def test_adjust_stock_roundtrip(client, login, dbo):
    login("manager1")
    original = dbo.execute(
        "SELECT stock FROM dbo.Ingredient WHERE ingredient_id = 'I001'"
    ).fetchone()[0]
    try:
        added = client.post(
            "/api/admin/stock",
            json={"ingredient_id": "I001", "operation": "补库", "amount": "1.00"},
            headers={"X-CSRF-Token": _token(client)},
        )
        assert added.status_code == 200, added.get_data(as_text=True)
        assert added.get_json()["stock"] == f"{original + 1:.2f}"

        restored = client.post(
            "/api/admin/stock",
            json={"ingredient_id": "I001", "operation": "盘点", "amount": str(original)},
            headers={"X-CSRF-Token": _token(client)},
        )
        assert restored.status_code == 200
        assert restored.get_json()["stock"] == f"{original:.2f}"
    finally:
        dbo.execute(
            "UPDATE dbo.Ingredient SET stock = ? WHERE ingredient_id = 'I001'", original
        )


def test_customer_cannot_access_admin(client, login):
    login("guesta")
    for path in ("/api/admin/stats", "/api/admin/stock", "/api/admin/employees"):
        response = client.get(path)
        assert response.status_code == 403
        assert response.get_json()["error"]["code"] == "forbidden"
