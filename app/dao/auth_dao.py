"""认证 DAO：只调用接口约定里的两个认证过程。"""

from __future__ import annotations

import pyodbc


def _rows(cursor: pyodbc.Cursor) -> list[dict]:
    columns = [col[0] for col in cursor.description]
    return [dict(zip(columns, row)) for row in cursor.fetchall()]


def get_credential(conn: pyodbc.Connection, login_name: str) -> dict | None:
    cursor = conn.cursor()
    try:
        cursor.execute("EXEC teabar_auth.usp_GetWebCredential ?", login_name)
        rows = _rows(cursor)
        return rows[0] if rows else None
    finally:
        cursor.close()


def get_context(conn: pyodbc.Connection, account_id: int, session_version: int) -> dict:
    cursor = conn.cursor()
    try:
        cursor.execute("EXEC teabar_auth.usp_GetWebContext ?, ?", account_id, session_version)
        rows = _rows(cursor)
    finally:
        cursor.close()
    if not rows:
        raise pyodbc.Error("context", "(52700) 账号或会话已失效。")
    return rows[0]
