"""首页：公开菜单浏览与点单入口。"""

from __future__ import annotations

import secrets

from flask import Blueprint, flash, redirect, render_template, request, url_for

from ..errors import AppError
from ..security import catalog_scope, current_auth, login_required, session_scope
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
def menu():
    with catalog_scope() as (conn, ctx):
        catalog = menu_service.load_catalog(conn)
        role = ctx["app_role"] if ctx else None
    return render_template("menu.html", catalog=catalog, role=role)


@bp.get("/orders/new")
@login_required
def checkout():
    with session_scope() as (conn, ctx):
        if ctx["app_role"] not in {"customer", "member"}:
            raise AppError("role_forbidden", "当前角色不能点单。", 403)
        catalog = menu_service.load_catalog(conn)
    return render_template("checkout.html", catalog=catalog, payload={"items": [], "payment_succeeded": True}, request_token=secrets.token_urlsafe(32))


@bp.get("/menu/<product_id>")
def product_detail(product_id: str):
    with catalog_scope() as (conn, ctx):
        detail = menu_service.get_product_detail(conn, product_id)
    return render_template("product_detail.html", product=detail["product"], addons=detail["addons"])
