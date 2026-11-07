"""店员工作台：状态流转、越权与积分。"""

from __future__ import annotations

P001_SPECS = ["S007", "S004", "S001"]


def _token(client) -> str:
    return client.get("/api/csrf").get_json()["csrf_token"]


def _order_as_membera(client, login) -> dict:
    login("membera")
    response = client.post(
        "/api/orders",
        json={
            "items": [
                {
                    "product_id": "P001",
                    "quantity": 1,
                    "specs": list(P001_SPECS),
                    "addons": [],
                }
            ],
            "payment_succeeded": True,
        },
        headers={"X-CSRF-Token": _token(client)},
    )
    assert response.status_code == 201, response.get_data(as_text=True)
    return response.get_json()


def _advance(client, order_id: str, status: str):
    return client.post(
        f"/api/work/orders/{order_id}/advance",
        json={"next_status": status},
        headers={"X-CSRF-Token": _token(client)},
    )


def test_clerk_advances_order_to_completed(client, login, sample_order):
    login("clerk1")
    order_id = sample_order["order_id"]

    for status in ("制作中", "待取餐", "已完成"):
        response = _advance(client, order_id, status)
        assert response.status_code == 200, response.get_data(as_text=True)
        assert response.get_json()["status"] == status

    again = _advance(client, order_id, "已完成")
    assert again.status_code == 409
    assert again.get_json()["error"]["code"] == "status_transition"


def test_work_order_detail_includes_consumption(client, login, sample_order):
    login("clerk1")
    detail = client.get(f"/api/work/orders/{sample_order['order_id']}").get_json()
    assert detail["order_id"] == sample_order["order_id"]
    assert detail["items"]
    assert detail["consumption"], "应返回原料消耗"


def test_work_pages_for_staff(client, login):
    login("clerk1")
    for path in ("/work/orders", "/work/team"):
        assert client.get(path).status_code == 200
    assert client.get("/api/work/orders").status_code == 200
    assert client.get("/api/work/team").status_code == 200


def test_customer_cannot_advance_order(client, login, sample_order):
    login("guesta")
    response = _advance(client, sample_order["order_id"], "制作中")
    assert response.status_code == 403
    assert response.get_json()["error"]["code"] == "forbidden"


def test_clerk_cannot_access_admin(client, login):
    login("clerk1")
    assert client.get("/api/admin/stats").status_code == 403
    assert client.get("/api/admin/stock").status_code == 403


def test_member_points_awarded_on_completion(client, login, dbo):
    order = _order_as_membera(client, login)
    before = dbo.execute(
        "SELECT points FROM dbo.Member WHERE member_id = 'M001'"
    ).fetchone()[0]
    try:
        login("clerk1")
        for status in ("制作中", "待取餐", "已完成"):
            assert _advance(client, order["order_id"], status).status_code == 200
        after = dbo.execute(
            "SELECT points FROM dbo.Member WHERE member_id = 'M001'"
        ).fetchone()[0]
        assert after == before + 6, "P001 单杯 6.00 元，完成应得 6 积分"
    finally:
        dbo.execute(
            "UPDATE dbo.Member SET points = ? WHERE member_id = 'M001'", before
        )
