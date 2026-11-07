"""Request idempotency over the real Web/SQL boundary in the isolated test DB."""
import secrets


def _payload(quantity=1, payment=True):
    return {"items":[{"product_id":"P001","quantity":quantity,"specs":["S007","S004","S001"],"addons":[]}], "payment_succeeded":payment}


def _send(client, token, payload, header=True):
    csrf = client.get("/api/csrf").get_json()["csrf_token"]
    headers = {"X-CSRF-Token":csrf}
    if header:
        headers["Idempotency-Key"] = token
    else:
        payload = dict(payload, request_token=token)
    return client.post("/api/orders", json=payload, headers=headers)


def _stocks(dbo):
    return tuple(tuple(row) for row in dbo.execute("SELECT ingredient_id, stock FROM dbo.Ingredient ORDER BY ingredient_id").fetchall())


def _count(dbo):
    return dbo.execute("SELECT COUNT(*) FROM dbo.SalesOrder").fetchone()[0]


def test_same_token_replays_same_order_without_second_stock_deduction(client, login, dbo):
    login("guesta")
    token = secrets.token_urlsafe(24)
    before = _count(dbo)
    first = _send(client, token, _payload())
    assert first.status_code == 201, first.get_data(as_text=True)
    after_first = _stocks(dbo)
    second = _send(client, token, _payload(), header=False)
    assert second.status_code == 201, second.get_data(as_text=True)
    assert second.get_json() == first.get_json()
    assert _count(dbo) == before + 1
    assert _stocks(dbo) == after_first


def test_same_token_different_payload_is_conflict_without_write(client, login, dbo):
    login("guesta")
    token = secrets.token_urlsafe(24)
    assert _send(client, token, _payload()).status_code == 201
    stocks, count = _stocks(dbo), _count(dbo)
    conflict = _send(client, token, _payload(quantity=2))
    assert conflict.status_code == 409
    assert conflict.get_json()["error"]["code"] == "request_conflict"
    assert _stocks(dbo) == stocks and _count(dbo) == count


def test_same_token_is_scoped_to_authenticated_buyer(client, login):
    token = secrets.token_urlsafe(24)
    login("guesta")
    first = _send(client, token, _payload())
    assert first.status_code == 201
    login("guestb")
    second = _send(client, token, _payload())
    assert second.status_code == 201
    assert first.get_json()["order_id"] != second.get_json()["order_id"]
    assert client.get("/api/my/orders/" + first.get_json()["order_id"]).status_code == 404


def test_failed_payment_does_not_consume_request_token(client, login, dbo):
    login("guesta")
    token = secrets.token_urlsafe(24)
    count, stocks = _count(dbo), _stocks(dbo)
    failure = _send(client, token, _payload(payment=False))
    assert failure.status_code == 402
    assert _count(dbo) == count and _stocks(dbo) == stocks
    success = _send(client, token, _payload(payment=True))
    assert success.status_code == 201, success.get_data(as_text=True)
    assert _count(dbo) == count + 1



def test_concurrent_same_token_commits_once_across_independent_sessions(app, dbo):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier
    token = secrets.token_urlsafe(24)
    before_count = _count(dbo)
    before_stock = dict(_stocks(dbo))
    ready = Barrier(2)
    def submit():
        # A client/cookie jar per worker: no shared Flask session or request context.
        with app.test_client() as worker:
            csrf = worker.get("/api/csrf").get_json()["csrf_token"]
            logged = worker.post("/login", data={"login_name":"guesta", "password":"Guest#2026", "csrf_token":csrf})
            assert logged.status_code == 302
            csrf = worker.get("/api/csrf").get_json()["csrf_token"]
            ready.wait(timeout=10)
            response = worker.post("/api/orders", json=_payload(), headers={"X-CSRF-Token":csrf,"Idempotency-Key":token})
            return response.status_code, response.get_json()
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(submit) for _ in range(2)]
        results = [future.result(timeout=30) for future in futures]
    assert [status for status, _ in results] == [201, 201], results
    assert results[0][1] == results[1][1]
    assert _count(dbo) == before_count + 1
    order_id = results[0][1]["order_id"]
    consumption = dict(dbo.execute("SELECT ingredient_id, SUM(amount) FROM dbo.OrderItemIngredient WHERE item_id IN (SELECT item_id FROM dbo.OrderItem WHERE order_id = ?) GROUP BY ingredient_id",order_id).fetchall())
    assert consumption
    for ingredient, stock in _stocks(dbo):
        assert stock == before_stock[ingredient] - consumption.get(ingredient, 0)
    receipts = dbo.execute("SELECT COUNT(*) FROM teabar_auth.WebOrderRequest WHERE request_token = ?",token).fetchone()[0]
    assert receipts == 1


def test_request_tokens_are_case_sensitive(client, login, dbo):
    login("guesta")
    lower = "case_token_" + secrets.token_hex(16)
    upper = lower.upper()
    before = _count(dbo)
    first = _send(client, lower, _payload())
    second = _send(client, upper, _payload())
    assert first.status_code == second.status_code == 201
    assert first.get_json()["order_id"] != second.get_json()["order_id"]
    assert _count(dbo) == before + 2
