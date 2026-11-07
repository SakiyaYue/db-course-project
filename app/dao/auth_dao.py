"""认证 DAO：只调用接口约定里的两个认证过程。"""

from __future__ import annotations

import pyodbc


from .common import first_result as _rows


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


def business_role(conn):
    from .common import query
    row = query(conn, "SELECT USER_NAME() AS principal_name, "
                "IS_ROLEMEMBER('teabar_customer') AS customer, "
                "IS_ROLEMEMBER('teabar_member') AS member, "
                "IS_ROLEMEMBER('teabar_clerk') AS clerk, "
                "IS_ROLEMEMBER('teabar_manager') AS manager")[0]
    return row
