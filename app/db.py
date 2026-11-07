"""pyodbc 连接管理与 EXECUTE AS USER 身份切换。

安全边界：
- 应用以 Windows 集成身份（演示环境）或受限 SQL 登录连接，**不**用 dbo 直连业务表；
- 业务调用前切换到接口约定允许的固定 web_* 用户，调用结束立即 REVERT；
- IMPERSONATE 的目标名来自固定白名单，绝不接受任意字符串拼接。
"""

from __future__ import annotations

import contextlib
import logging
from collections.abc import Iterator

import pyodbc

from .config import Config
from .errors import AppError

# Must be set before the first connection is created.
pyodbc.pooling = False

# 接口约定第 3.2 节固定的六个 Web 数据库用户
ALLOWED_PRINCIPALS = frozenset(
    {"web_guest_a", "web_guest_b", "web_member_a", "web_member_b", "web_clerk", "web_manager", "web_public"}
)


def _safe_close(resource):
    try:
        resource.close()
    except pyodbc.Error as exc:
        # Closing an already-discarded ODBC handle must not mask the business/cleanup error.
        logging.getLogger(__name__).warning("ODBC handle disposal: %s", type(exc).__name__)


class Database:
    def __init__(self, config: Config):
        self.config = config

    def connect(self, app_name: str = "teabar-web") -> pyodbc.Connection:
        try:
            conn = pyodbc.connect(
                self.config.connection_string(app_name),
                autocommit=True,
                timeout=self.config.connect_timeout,
            )
        except pyodbc.Error as exc:
            raise AppError("database_unavailable", "无法连接数据库，请确认 SQL Server 已启动。", 503,
                           detail=str(exc)) from exc
        try:
            conn.timeout = self.config.query_timeout
        except Exception:
            _safe_close(conn)
            raise
        return conn

    @contextlib.contextmanager
    def connection(self, app_name: str = "teabar-web") -> Iterator[pyodbc.Connection]:
        conn = self.connect(app_name)
        try:
            yield conn
        finally:
            _safe_close(conn)

    @contextlib.contextmanager
    def impersonate(self, conn: pyodbc.Connection, principal_name: str) -> Iterator[None]:
        """切换到 web_* 业务身份；退出时 REVERT。"""
        if principal_name not in ALLOWED_PRINCIPALS:
            raise AppError("invalid_principal", "数据库身份不在允许名单内。", 500)
        cursor = conn.cursor()
        switched = False
        try:
            cursor.execute(f"EXECUTE AS USER = '{principal_name}';")
            switched = True
            yield
        finally:
            try:
                if switched:
                    cursor.execute("IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;")
                    cursor.execute("REVERT;")
            except pyodbc.Error as exc:
                _safe_close(conn)  # Never reuse a connection whose identity is uncertain.
                raise AppError("identity_cleanup_failed", "数据库会话清理失败，请重试。", 503,
                               detail=type(exc).__name__) from exc
            finally:
                _safe_close(cursor)
