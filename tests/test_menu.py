"""菜单与规格目录。"""

from __future__ import annotations


def test_menu_api_returns_available_catalog(catalog):
    data = catalog.catalog()
    assert data["products"], "菜单不应为空"
    assert len(data["products"]) == 4
    assert data["addons"], "加料列表不应为空"
    for product in data["products"]:
        assert product["spec_types"], f"{product['product_id']} 应有规格类型"
        # 三种规格类型：杯型/温度/糖度
        assert set(product["spec_types"]) == {"杯型", "温度", "糖度"}
        assert product["base_price"]


def test_menu_page_renders(client, login):
    login("guesta")
    catalog = client.get("/api/menu").get_json()
    response = client.get("/menu")
    assert response.status_code == 200
    html = response.get_data(as_text=True)
    assert "菜单" in html
    for product in catalog["products"]:
        assert product["product_name"] in html


def test_anonymous_can_browse_menu_but_not_checkout(client):
    response = client.get("/menu")
    assert response.status_code == 200
    assert client.get("/api/menu").status_code == 200
    response = client.get("/orders/new", follow_redirects=False)
    assert response.status_code == 302
    assert "/login" in response.headers["Location"]
