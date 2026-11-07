"""登录、会话复核与 CSRF。"""

from __future__ import annotations


def test_login_page(client):
    response = client.get("/login")
    assert response.status_code == 200
    assert "登录" in response.get_data(as_text=True)


def test_login_with_wrong_password_rejected(client, login):
    response = login("guesta", "Wrong#2026")
    assert response.status_code == 401
    assert "登录名或密码不正确" in response.get_data(as_text=True)


def test_login_success_sets_role(client, login):
    response = login("guesta")
    assert response.status_code == 302
    assert response.headers["Location"].endswith("/menu")

    me = client.get("/api/me")
    assert me.status_code == 200
    body = me.get_json()
    assert body["app_role"] == "customer"
    assert body["principal_name"] == "web_guest_a"
    assert body["login_name"] == "guesta"
    assert body["member"] is None


def test_member_login_exposes_own_member(client, login):
    login("membera")
    body = client.get("/api/me").get_json()
    assert body["app_role"] == "member"
    assert body["member"]["member_id"] == "M001"


def test_logout_clears_session(client, login, csrf):
    login("guesta")
    token = csrf()
    response = client.post("/logout", data={"csrf_token": token})
    assert response.status_code == 302
    assert client.get("/api/me").status_code == 401


def test_api_requires_login(client):
    assert client.get("/api/me").status_code == 401
    assert client.get("/api/menu").status_code == 200


def test_post_requires_csrf(client):
    response = client.post("/api/orders", json={"items": []})
    assert response.status_code == 400
    assert response.get_json()["error"]["code"] == "csrf_failed"


def test_bumped_session_version_rejects_old_session(client, login, dbo):
    login("guesta")
    assert client.get("/api/me").status_code == 200
    try:
        dbo.execute(
            "UPDATE teabar_auth.WebAccount SET session_version = session_version + 1 "
            "WHERE login_name = ?",
            "guesta",
        )
        response = client.get("/api/me")
        assert response.status_code == 401
        # 旧会话已被清除，重新登录后使用新版本
        dbo.execute(
            "UPDATE teabar_auth.WebAccount SET session_version = session_version - 1 "
            "WHERE login_name = ?",
            "guesta",
        )
        assert login("guesta").status_code == 302
    finally:
        dbo.execute(
            "UPDATE teabar_auth.WebAccount SET session_version = ("
            "SELECT MIN(session_version) FROM teabar_auth.WebAccount WHERE login_name = ?) "
            "WHERE login_name = ?",
            "guesta",
            "guesta",
        )


def test_protected_page_redirects_to_login(client):
    response = client.get("/my/orders", follow_redirects=False)
    assert response.status_code == 302
    assert "/login" in response.headers["Location"]
