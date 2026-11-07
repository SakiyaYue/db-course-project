"""应用配置：只从环境变量（或本地 .env）读取，不把连接串写死在代码里。"""

from __future__ import annotations

import os
import secrets
from dataclasses import dataclass
from pathlib import Path


def load_dotenv(path: Path) -> None:
    """极简 .env 加载器，避免为课程项目引入额外依赖。已存在的环境变量优先。"""
    if not path.is_file():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


@dataclass(frozen=True)
class Config:
    db_driver: str
    db_server: str
    db_name: str
    db_trusted: bool
    db_user: str | None
    db_password: str | None
    secret_key: str
    session_cookie_secure: bool
    connect_timeout: int = 5
    query_timeout: int = 30

    @classmethod
    def from_env(cls, env_file: Path | None = None) -> "Config":
        if env_file is not None:
            load_dotenv(env_file)
        trusted = os.environ.get("TEABAR_DB_TRUSTED", "yes").strip().lower() in {
            "1", "yes", "true", "y", "on",
        }
        secret = os.environ.get("TEABAR_SECRET_KEY", "").strip()
        if not secret:
            if os.environ.get("TEABAR_ENV", "development") != "development":
                raise RuntimeError("演示/部署环境必须设置 TEABAR_SECRET_KEY")
            secret = secrets.token_urlsafe(48)
        if secret in {"dev-only-insecure-key", "dev-only-change-me"}:
            raise RuntimeError("请设置随机 TEABAR_SECRET_KEY，不能使用示例密钥")
        return cls(
            db_driver=os.environ.get("TEABAR_DB_DRIVER", "ODBC Driver 18 for SQL Server"),
            db_server=os.environ.get("TEABAR_DB_SERVER", "localhost"),
            db_name=os.environ.get("TEABAR_DB_NAME", "TeabarDB_Phase2_Work"),
            db_trusted=trusted,
            db_user=os.environ.get("TEABAR_DB_USER") or None,
            db_password=os.environ.get("TEABAR_DB_PASSWORD") or None,
            secret_key=secret,
            session_cookie_secure=os.environ.get("TEABAR_SESSION_COOKIE_SECURE", "0") in {"1", "yes", "true"},
        )

    def connection_string(self, app_name: str = "teabar-web") -> str:
        def quote(value):
            return "{" + str(value).replace("}", "}}") + "}"
        parts = [
            f"DRIVER={quote(self.db_driver)}",
            f"SERVER={quote(self.db_server)}",
            f"DATABASE={quote(self.db_name)}",
            "TrustServerCertificate=yes",
            f"APP={quote(app_name)}",
            f"Connection Timeout={self.connect_timeout}",
        ]
        if self.db_trusted:
            parts.append("Trusted_Connection=yes")
        else:
            if not self.db_user or self.db_password is None:
                raise RuntimeError("非信任连接必须配置 TEABAR_DB_USER / TEABAR_DB_PASSWORD")
            parts.extend([f"UID={quote(self.db_user)}", f"PWD={quote(self.db_password)}"])
        return ";".join(parts)
