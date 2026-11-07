"""登录、退出。"""

from __future__ import annotations

from urllib.parse import urlsplit

from flask import Blueprint, flash, redirect, render_template, request, url_for

from ..errors import AppError
from ..security import clear_session, current_auth, get_database, set_session
from ..services import auth_service

bp = Blueprint("auth", __name__)

ROLE_HOME = {
    "customer": "menu.menu",
    "member": "menu.menu",
    "clerk": "work.orders",
    "manager": "admin.stats",
}


@bp.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "GET":
        if current_auth():
            return redirect(url_for("menu.index"))
        return render_template("login.html")

    login_name = request.form.get("login_name")
    password = request.form.get("password")
    try:
        with get_database().connection("teabar-web-login") as conn:
            payload = auth_service.authenticate(conn, login_name, password)
    except AppError as exc:
        if exc.code in {"login_invalid", "password_required"}:
            flash(exc.message, "warning")
        else:
            flash("登录名或密码不正确。", "danger")
        return render_template("login.html", login_name=login_name or ""), 401

    set_session(payload)
    next_url = request.form.get("next") or request.args.get("next")
    if next_url:
        parsed = urlsplit(next_url)
        if not parsed.netloc and next_url.startswith("/") and not next_url.startswith("//"):
            return redirect(next_url)
    return redirect(url_for(ROLE_HOME.get(payload["app_role"], "menu.menu")))


@bp.post("/logout")
def logout():
    clear_session()
    flash("已退出登录。", "success")
    return redirect(url_for("auth.login"))
