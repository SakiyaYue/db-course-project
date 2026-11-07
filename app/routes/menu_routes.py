"""首页：公开菜单浏览与点单入口。"""

from __future__ import annotations

from flask import Blueprint, flash, redirect, render_template, request, url_for

from ..errors import AppError
from ..security import current_auth, login_required, session_scope
from ..services import menu_service

bp = Blueprint("menu", __name__)


@bp.get("/")
def index():
    auth = current_auth()
    if auth:
        if auth.get("app_role") == "clerk":
            return redirect(url_for("work.orders"))
        if auth.get("app_role") == "manager":
            return redirect(url_for("admin.stats"))
    return redirect(url_for("menu.menu"))


@bp.get("/menu")
@login_required
def menu():
    with session_scope() as (conn, ctx):
        catalog = menu_service.load_catalog(conn)
        role = ctx["app_role"]
    return render_template("menu.html", catalog=catalog, role=role)


@bp.get("/orders/new")
@login_required
def checkout():
    with session_scope() as (conn, ctx):
        if ctx["app_role"] not in {"customer", "member"}:
            raise AppError("role_forbidden", "当前角色不能点单。", 403)
        catalog = menu_service.load_catalog(conn)
    return render_template("checkout.html", catalog=catalog)
