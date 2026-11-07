"""下单、退款与本人数据隔离。"""

from __future__ import annotations

P001_SPECS = ["S007", "S004", "S001"]


def _token(client) -> str:
    return client.get("/api/csrf").get_json()["csrf_token"]


def _post_order(client, payload):
    return client.post(
        "/api/orders", json=payload, headers={"X-CSRF-Token": _token(client)}
    )


def _valid_payload(**overrides) -> dict:
    payload = {
        "items": [
            {
                "product_id": "P001",
                "quantity": 1,
                "specs": list(P001_SPECS),
                "addons": [],
            }
        ],
        "payment_succeeded": True,
    }
    payload.update(overrides)
    return payload


def _order_count(dbo) -> int:
    return dbo.execute("SELECT COUNT(*) FROM dbo.SalesOrder").fetchone()[0]


def test_place_order_and_read_back(client, login, csrf):
    login("guesta")
    response = _post_order(client, _valid_payload())
    assert response.status_code == 201, response.get_data(as_text=True)
    order = response.get_json()
    assert order["status"] == "排队中"
    assert order["total_amount"] == "6.00"

    listing = client.get("/api/my/orders").get_json()["orders"]
    assert order["order_id"] in [row["order_id"] for row in listing]

    detail = client.get(f"/api/my/orders/{order['order_id']}").get_json()
    assert detail["order_id"] == order["order_id"]
    assert len(detail["items"]) == 1
    assert len(detail["specs"]) == 3
    assert detail["items"][0]["product_id"] == "P001"


def test_refund_queue_order_and_repeat_rejected(client, login):
    login("guesta")
    order = _post_order(client, _valid_payload()).get_json()

    refund = client.post(
        f"/api/my/orders/{order['order_id']}/refund",
        headers={"X-CSRF-Token": _token(client)},
    )
    assert refund.status_code == 200, refund.get_data(as_text=True)
    assert refund.get_json()["status"] == "已取消"

    repeat = client.post(
        f"/api/my/orders/{order['order_id']}/refund",
        headers={"X-CSRF-Token": _token(client)},
    )
    assert repeat.status_code == 409
    assert repeat.get_json()["error"]["code"] == "refund_state"


def test_order_isolated_between_buyers(client, login):
    login("guesta")
    order = _post_order(client, _valid_payload()).get_json()

    login("guestb")
    assert client.get(f"/api/my/orders/{order['order_id']}").status_code == 404
    listing = client.get("/api/my/orders").get_json()["orders"]
    assert order["order_id"] not in [row["order_id"] for row in listing]


def test_payment_failure_creates_no_order(client, login, dbo):
    login("guesta")
    before = _order_count(dbo)
    response = _post_order(client, _valid_payload(payment_succeeded=False))
    assert response.status_code == 402
    assert response.get_json()["error"]["code"] == "payment_failed"
    assert _order_count(dbo) == before


def test_payload_validation(client, login):
    login("guesta")

    empty = _post_order(client, {"items": [], "payment_succeeded": True})
    assert empty.status_code == 400
    assert empty.get_json()["error"]["code"] == "invalid_items"

    bad_quantity = _post_order(
        client,
        {
            "items": [{"product_id": "P001", "quantity": 0, "specs": P001_SPECS}],
            "payment_succeeded": True,
        },
    )
    assert bad_quantity.status_code == 400
    assert bad_quantity.get_json()["error"]["code"] == "invalid_quantity"

    duplicate_spec = _post_order(
        client,
        {
            "items": [
                {
                    "product_id": "P001",
                    "quantity": 1,
                    "specs": ["S007", "S007", "S004", "S001"],
                }
            ],
            "payment_succeeded": True,
        },
    )
    assert duplicate_spec.status_code == 400
    assert duplicate_spec.get_json()["error"]["code"] == "invalid_selection"


def test_database_validation_errors(client, login):
    login("guesta")

    missing = _post_order(
        client,
        {
            "items": [{"product_id": "P001", "quantity": 1, "specs": []}],
            "payment_succeeded": True,
        },
    )
    assert missing.status_code == 400
    assert missing.get_json()["error"]["code"] == "spec_missing"

    bad_spec = _post_order(
        client,
        {
            "items": [
                {"product_id": "P001", "quantity": 1, "specs": ["S007", "S004", "S999"]}
            ],
            "payment_succeeded": True,
        },
    )
    assert bad_spec.status_code == 400
    assert bad_spec.get_json()["error"]["code"] == "spec_invalid"

    bad_product = _post_order(
        client,
        {
            "items": [
                {"product_id": "P999", "quantity": 1, "specs": list(P001_SPECS)}
            ],
            "payment_succeeded": True,
        },
    )
    assert bad_product.status_code == 409
    assert bad_product.get_json()["error"]["code"] == "product_unavailable"


def test_stock_insufficient_rolls_back(client, login, dbo):
    login("guesta")
    before = _order_count(dbo)

    ingredients = [
        row[0]
        for row in dbo.execute(
            "SELECT DISTINCT ingredient_id FROM dbo.Recipe WHERE product_id = 'P001'"
        ).fetchall()
    ]
    assert ingredients, "P001 应有配方"
    saved = {
        ingredient: dbo.execute(
            "SELECT stock FROM dbo.Ingredient WHERE ingredient_id = ?", ingredient
        ).fetchone()[0]
        for ingredient in ingredients
    }
    try:
        for ingredient in ingredients:
            dbo.execute(
                "UPDATE dbo.Ingredient SET stock = 0 WHERE ingredient_id = ?", ingredient
            )
        response = _post_order(client, _valid_payload())
        assert response.status_code == 409
        assert response.get_json()["error"]["code"] == "stock_insufficient"
        assert _order_count(dbo) == before
    finally:
        for ingredient, stock in saved.items():
            dbo.execute(
                "UPDATE dbo.Ingredient SET stock = ? WHERE ingredient_id = ?",
                stock,
                ingredient,
            )
