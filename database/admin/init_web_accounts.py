#!/usr/bin/env python
"""初始化 Web 演示账号与受限数据库边界（v1.0 工作库）。

本脚本只做"管理员初始化"这一件事，可重复执行（幂等）：

1. 创建应用角色 teabar_web_app，并只授予：
   - teabar_auth.usp_GetWebCredential / usp_GetWebContext 的 EXECUTE；
   - 对 6 个固定 web_* 用户和 4 个业务角色的最小逐对象元数据可见权限
     （VIEW DEFINITION），供 usp_GetWebContext 检查目录；
   - 对 6 个 web_* 用户的 IMPERSONATE（供受限应用登录切换购买身份）。
2. 创建 6 个 WITHOUT LOGIN 的 web_* 用户，并各自只加入一个业务角色：
   web_guest_a/b -> teabar_customer，web_member_a/b -> teabar_member，
   web_clerk -> teabar_clerk，web_manager -> teabar_manager。
3. 为 4 个购买者用户写入 teabar_auth.PrincipalBinding（复用演示会员/游客身份）。
4. 为 6 个账号写入 teabar_auth.WebAccount（ werkzeug 加盐哈希，不存明文）。

设计依据：docs/phase2/06-normalization/v1.0数据库接口约定.md 第 3 节。
本机实例为"仅 Windows 身份验证"，因此不创建 SQL 登录；应用以 Windows
集成身份连接，业务调用通过 EXECUTE AS USER 切换到 web_* 身份。

用法（本机 conda 环境 DatabaseLab）：
    D:\\DevEnvs\\DatabaseLab\\python.exe database\\admin\\init_web_accounts.py
    同上加 --dry-run 只演练后回滚。

已知数据库缺陷：v1.0 的 CK_WebAccount_LoginName 使用
`NOT like N'%[^a-z0-9._-]%'`，在 Latin1_General_100_BIN2 下短横线位于方括号
末尾会被当成范围符号，导致含 `_` 或 `-` 的登录名（如 guest_a）也被拒绝。
本脚本的演示登录名因此只用小写字母/数字；该缺陷应反馈给组员 A 修正约束
（把 `-` 放到方括号首位：`[^-a-z0-9._]`）并重新生成迁移。
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass, field

import pyodbc
from werkzeug.security import generate_password_hash

DEFAULT_DRIVER = "ODBC Driver 18 for SQL Server"
DEFAULT_SERVER = "localhost"
DEFAULT_DATABASE = "TeabarDB_Phase2_Work"
ALLOWED_DATABASES = {"TeabarDB_Phase2_Work", "TeabarDB_Phase2_Test"}

APP_ROLE = "teabar_web_app"
WEB_ROLES = ("teabar_customer", "teabar_member", "teabar_clerk", "teabar_manager")


@dataclass(frozen=True)
class DemoAccount:
    login_name: str
    password: str
    app_role: str          # customer / member / clerk / manager
    db_user: str           # web_guest_a ...
    db_role: str           # teabar_customer ...
    member_id: str | None = None
    guest_id: str | None = None


DEMO_ACCOUNTS: tuple[DemoAccount, ...] = (
    DemoAccount("guesta", "Guest#2026", "customer", "web_guest_a", "teabar_customer",
                guest_id="0D9AB0CB-4ABA-49E6-B46C-645EB5CAC9F6"),
    DemoAccount("guestb", "Guest#2026", "customer", "web_guest_b", "teabar_customer",
                guest_id="83F678A7-6C90-4BEF-BC46-74E733EA1D37"),
    DemoAccount("membera", "Member#2026", "member", "web_member_a", "teabar_member",
                member_id="M001"),
    DemoAccount("memberb", "Member#2026", "member", "web_member_b", "teabar_member",
                member_id="M002"),
    DemoAccount("clerk1", "Clerk#2026", "clerk", "web_clerk", "teabar_clerk"),
    DemoAccount("manager1", "Manager#2026", "manager", "web_manager", "teabar_manager"),
)


def build_connection_string(server: str, database: str, driver: str) -> str:
    parts = [
        f"DRIVER={{{driver}}}",
        f"SERVER={server}",
        f"DATABASE={database}",
        "Trusted_Connection=yes",
        "TrustServerCertificate=yes",
        "APP=teabar-init-web-accounts",
    ]
    return ";".join(parts)


def quote_name(name: str) -> str:
    """固定白名单标识符 → [name]；拒绝任何非预期字符。"""
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
        raise ValueError(f"非法标识符: {name!r}")
    return "[" + name + "]"


def fetch_principal_sid(cursor, user_name: str) -> bytes:
    cursor.execute("SELECT SID FROM sys.database_principals WHERE name = ?", user_name)
    row = cursor.fetchone()
    if row is None:
        raise RuntimeError(f"找不到数据库用户: {user_name}")
    return bytes(row[0])


def role_members_of(cursor, user_name: str) -> list[str]:
    cursor.execute(
        """
        SELECT role.name
        FROM sys.database_role_members AS rm
        JOIN sys.database_principals AS role ON role.principal_id = rm.role_principal_id
        JOIN sys.database_principals AS member ON member.principal_id = rm.member_principal_id
        WHERE member.name = ?
        ORDER BY role.name
        """,
        user_name,
    )
    return [row[0] for row in cursor.fetchall()]


def ensure_role(cursor, role_name: str) -> None:
    cursor.execute("SELECT 1 FROM sys.database_principals WHERE name = ? AND type = 'R'", role_name)
    if cursor.fetchone() is None:
        cursor.execute(f"CREATE ROLE {quote_name(role_name)};")
        print(f"[创建角色] {role_name}")


def ensure_web_user(cursor, user_name: str, role_name: str) -> None:
    cursor.execute("SELECT 1 FROM sys.database_principals WHERE name = ? AND type = 'S'", user_name)
    if cursor.fetchone() is None:
        # WITHOUT LOGIN：无服务器登录、无密码，仅用于 EXECUTE AS 实验。
        cursor.execute(f"CREATE USER {quote_name(user_name)} WITHOUT LOGIN;")
        print(f"[创建用户] {user_name} (WITHOUT LOGIN)")

    members = role_members_of(cursor, user_name)
    if role_name not in members:
        cursor.execute(f"ALTER ROLE {quote_name(role_name)} ADD MEMBER {quote_name(user_name)};")
        print(f"[加入角色] {user_name} -> {role_name}")
    if len(members) > 1 or (members and role_name not in members):
        raise RuntimeError(
            f"{user_name} 的角色成员关系必须恰好一个 {role_name}，实际为 {members}；"
            "请人工检查后再运行本脚本。"
        )


def ensure_grants(cursor) -> None:
    app_role = quote_name(APP_ROLE)
    for proc in ("teabar_auth.usp_GetWebCredential", "teabar_auth.usp_GetWebContext"):
        cursor.execute(f"GRANT EXECUTE ON OBJECT::{proc} TO {app_role};")
    for account in DEMO_ACCOUNTS:
        user = quote_name(account.db_user)
        cursor.execute(f"GRANT VIEW DEFINITION ON USER::{user} TO {app_role};")
        cursor.execute(f"GRANT IMPERSONATE ON USER::{user} TO {app_role};")
    for role in WEB_ROLES:
        cursor.execute(f"GRANT VIEW DEFINITION ON ROLE::{quote_name(role)} TO {app_role};")
    print("[授权] teabar_web_app: EXECUTE×2, VIEW DEFINITION×10, IMPERSONATE×6")


def ensure_binding(cursor, account: DemoAccount) -> None:
    if account.member_id is None and account.guest_id is None:
        return
    cursor.execute(
        "SELECT 1 FROM teabar_auth.PrincipalBinding WHERE principal_name = ?",
        account.db_user,
    )
    if cursor.fetchone() is not None:
        cursor.execute(
            "UPDATE teabar_auth.PrincipalBinding SET member_id = ?, guest_id = ?, is_active = 1 "
            "WHERE principal_name = ?",
            account.member_id,
            account.guest_id,
            account.db_user,
        )
        return
    sid = fetch_principal_sid(cursor, account.db_user)
    cursor.execute(
        "INSERT INTO teabar_auth.PrincipalBinding "
        "(principal_sid, principal_name, member_id, guest_id, is_active) VALUES (?, ?, ?, ?, 1)",
        sid,
        account.db_user,
        account.member_id,
        account.guest_id,
    )
    print(f"[绑定] {account.db_user} -> member={account.member_id} guest={account.guest_id}")


def ensure_account(cursor, account: DemoAccount, reset_password: bool) -> int:
    sid = fetch_principal_sid(cursor, account.db_user)
    cursor.execute(
        "SELECT account_id FROM teabar_auth.WebAccount WHERE login_name = ?",
        account.login_name,
    )
    row = cursor.fetchone()
    if row is None:
        password_hash = generate_password_hash(account.password)
        cursor.execute(
            "INSERT INTO teabar_auth.WebAccount "
            "(login_name, password_hash, app_role, principal_sid, is_active, session_version) "
            "VALUES (?, ?, ?, ?, 1, 1)",
            account.login_name,
            password_hash,
            account.app_role,
            sid,
        )
        cursor.execute("SELECT account_id FROM teabar_auth.WebAccount WHERE login_name = ?",
                       account.login_name)
        account_id = int(cursor.fetchone()[0])
        print(f"[账号] 新建 {account.login_name} (account_id={account_id}, role={account.app_role})")
        return account_id

    account_id = int(row[0])
    if reset_password:
        cursor.execute(
            "UPDATE teabar_auth.WebAccount SET password_hash = ?, principal_sid = ?, "
            "app_role = ?, is_active = 1, session_version = session_version + 1 WHERE account_id = ?",
            generate_password_hash(account.password),
            sid,
            account.app_role,
            account_id,
        )
        print(f"[账号] 重置密码并递增会话版本 {account.login_name} (account_id={account_id})")
    else:
        # 不覆盖已有哈希，只校正映射关系；版本变化需管理员显式重置。
        cursor.execute(
            "UPDATE teabar_auth.WebAccount SET principal_sid = ?, app_role = ?, is_active = 1 "
            "WHERE account_id = ?",
            sid,
            account.app_role,
            account_id,
        )
    return account_id


def verify_account(cursor, account: DemoAccount, account_id: int) -> None:
    cursor.execute("SELECT session_version FROM teabar_auth.WebAccount WHERE account_id = ?",
                   account_id)
    version = cursor.fetchone()[0]
    cursor.execute(
        "EXEC teabar_auth.usp_GetWebContext @account_id = ?, @session_version = ?",
        account_id,
        version,
    )
    row = cursor.fetchone()
    if row is None:
        raise RuntimeError(f"usp_GetWebContext 未返回 {account.login_name} 的上下文")
    app_role, principal_name = row[1], row[3]
    if app_role != account.app_role or principal_name != account.db_user:
        raise RuntimeError(
            f"上下文校验失败: 期望 {account.app_role}/{account.db_user}，"
            f"实际 {app_role}/{principal_name}"
        )
    print(f"[校验] {account.login_name}: app_role={app_role} principal={principal_name} OK")


def verify_impersonation(cursor) -> None:
    """在事务内切换一次身份并回退，确认 EXECUTE AS 可用。"""
    cursor.execute("EXECUTE AS USER = 'web_guest_a';")
    cursor.execute("SELECT USER_NAME(), SUSER_SNAME();")
    row = cursor.fetchone()
    cursor.execute("REVERT;")
    print(f"[校验] EXECUTE AS web_guest_a -> USER_NAME={row[0]}, 已 REVERT")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="初始化 TeabarDB v1.0 Web 演示账号")
    parser.add_argument("--server", default=os.environ.get("TEABAR_DB_SERVER", DEFAULT_SERVER))
    parser.add_argument("--database", default=os.environ.get("TEABAR_DB_NAME", DEFAULT_DATABASE))
    parser.add_argument("--driver", default=os.environ.get("TEABAR_DB_DRIVER", DEFAULT_DRIVER))
    parser.add_argument("--dry-run", action="store_true", help="完成后回滚，不写入数据库")
    parser.add_argument("--reset-passwords", action="store_true",
                        help="为已存在账号重置演示密码并递增 session_version")
    args = parser.parse_args(argv)

    if args.database not in ALLOWED_DATABASES:
        print(f"拒绝在数据库 {args.database!r} 上执行初始化；只允许 {sorted(ALLOWED_DATABASES)}",
              file=sys.stderr)
        return 2

    conn_str = build_connection_string(args.server, args.database, args.driver)
    conn = pyodbc.connect(conn_str, autocommit=False)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT DB_NAME(), SUSER_SNAME(), IS_MEMBER('db_owner')")
        db_name, login, is_owner = cursor.fetchone()
        if not is_owner:
            print("需要 db_owner 或 sysadmin 身份执行初始化。", file=sys.stderr)
            return 3
        print(f"[连接] {db_name} as {login}")

        ensure_role(cursor, APP_ROLE)
        for account in DEMO_ACCOUNTS:
            ensure_web_user(cursor, account.db_user, account.db_role)
        ensure_grants(cursor)
        for account in DEMO_ACCOUNTS:
            ensure_binding(cursor, account)
            account_id = ensure_account(cursor, account, args.reset_passwords)
            verify_account(cursor, account, account_id)
        verify_impersonation(cursor)

        if args.dry_run:
            conn.rollback()
            print("[dry-run] 已回滚，未写入数据库。")
        else:
            conn.commit()
            print("[完成] 初始化已提交。演示账号密码见 docs/phase2/07-web/演示账号与初始化.md。")
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
