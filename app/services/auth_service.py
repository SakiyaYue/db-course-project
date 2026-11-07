"""认证服务：登录名规范化、加盐哈希校验、上下文获取。"""

from __future__ import annotations

import re

from werkzeug.security import check_password_hash, generate_password_hash

from ..dao import auth_dao
from ..errors import AppError, translate_db_error

# 接口约定：登录名 3–50 位小写 ASCII 字母、数字、点、下划线或短横线
LOGIN_PATTERN = re.compile(r"^[a-z0-9._-]{3,50}$")
# 未找到账号时也执行一次哈希校验，避免通过响应时间枚举账号
DUMMY_HASH = generate_password_hash("teabar-dummy-password")


def normalize_login_name(raw: str | None) -> str:
    login = (raw or "").strip().lower()
    if not LOGIN_PATTERN.fullmatch(login):
        raise AppError("login_invalid", "登录名格式不正确。", 400)
    return login


def authenticate(conn, login_name: str | None, password: str | None) -> dict:
    login = normalize_login_name(login_name)
    if not password:
        raise AppError("password_required", "请输入密码。", 400)
    try:
        credential = auth_dao.get_credential(conn, login)
    except Exception as exc:  # pyodbc.Error
        raise translate_db_error(exc) from exc
    password_hash = credential["password_hash"] if credential else DUMMY_HASH
    verified = check_password_hash(password_hash, password) and credential is not None
    if not verified:
        raise AppError("login_failed", "登录名或密码不正确。", 401)
    try:
        ctx = auth_dao.get_context(conn, int(credential["account_id"]), int(credential["session_version"]))
    except Exception as exc:  # pyodbc.Error
        error = translate_db_error(exc)
        if error.code == "session_invalid":
            raise AppError("login_failed", "登录名或密码不正确。", 401) from exc
        raise error from exc
    return {
        "account_id": int(ctx["account_id"]),
        "session_version": int(ctx["session_version"]),
        "app_role": ctx["app_role"],
        "principal_name": ctx["principal_name"],
        "login_name": login,
    }
