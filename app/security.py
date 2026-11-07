"""会话、CSRF 与登录校验。

会话里只保存 account_id、session_version、app_role、principal_name 等标识；
每次请求都回数据库调用 usp_GetWebContext 复核（账号禁用、会话版本变化、
角色/绑定变化都会立刻失效）。
"""

from __future__ import annotations

import secrets
from contextlib import contextmanager
from collections.abc import Iterator
from functools import wraps

import pyodbc
from flask import current_app, flash, jsonify, redirect, request, session, url_for

from .dao import auth_dao
from .db import Database
from .errors import AppError, AuthRequired, Forbidden, translate_db_error

SESSION_KEY = "auth"
CSRF_KEY = "csrf_token"
ALLOWED_APP_ROLES = {"customer", "member", "clerk", "manager"}


def get_database() -> Database:
    return current_app.extensions["teabar_db"]


def csrf_token() -> str:
    token = session.get(CSRF_KEY)
    if not token:
        token = secrets.token_urlsafe(32)
        session[CSRF_KEY] = token
    return token


def validate_csrf() -> None:
    """对所有修改请求校验 CSRF（表单字段或 X-CSRF-Token 头）。"""
    if request.method not in {"POST", "PUT", "PATCH", "DELETE"}:
        return
    expected = session.get(CSRF_KEY)
    supplied = request.headers.get("X-CSRF-Token") or request.form.get("csrf_token")
    if not expected or not supplied or not secrets.compare_digest(str(expected), str(supplied)):
        raise AppError("csrf_failed", "请求校验失败，请刷新页面后重试。", 400)


def set_session(payload: dict) -> None:
    session.clear()
    session[SESSION_KEY] = payload
    csrf_token()


def clear_session() -> None:
    session.clear()


def current_auth() -> dict | None:
    return session.get(SESSION_KEY)


@contextmanager
def session_scope(*, roles: tuple[str, ...] | None = None) -> Iterator[tuple[pyodbc.Connection, dict]]:
    """打开连接 → 复核会话 → 切换业务身份 → 用完 REVERT 并关闭连接。"""
    auth = current_auth()
    if not auth:
        raise AuthRequired()
    if auth.get("app_role") not in ALLOWED_APP_ROLES:
        clear_session()
        raise AuthRequired()
    db = get_database()
    with db.connection() as conn:
        try:
            ctx = auth_dao.get_context(conn, int(auth["account_id"]), int(auth["session_version"]))
        except pyodbc.Error as exc:
            error = translate_db_error(exc)
            if error.code == "session_invalid":
                clear_session()
                raise AuthRequired() from exc
            raise error from exc
        if (
            ctx["principal_name"] != auth.get("principal_name")
            or ctx["app_role"] != auth.get("app_role")
            or ctx["session_version"] != auth.get("session_version")
        ):
            clear_session()
            raise AuthRequired()
        if roles is not None and ctx["app_role"] not in roles:
            raise Forbidden()
        with db.impersonate(conn, ctx["principal_name"]):
            yield conn, ctx


def login_required(view):
    """未登录时：HTML 重定向到登录页，/api 返回 401 JSON。"""

    @wraps(view)
    def wrapper(*args, **kwargs):
        try:
            return view(*args, **kwargs)
        except AuthRequired:
            if request.path.startswith("/api/"):
                return jsonify({"error": {"code": "auth_required", "message": "请先登录。"}}), 401
            flash("请先登录。", "warning")
            return redirect(url_for("auth.login", next=request.full_path.rstrip("?")))
        except Forbidden:
            if request.path.startswith("/api/"):
                return jsonify({"error": {"code": "forbidden", "message": "当前角色无权执行此操作。"}}), 403
            return redirect(url_for("menu.index"))

    return wrapper
