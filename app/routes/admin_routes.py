"""店长统计、库存、员工页面。"""

from __future__ import annotations

from flask import Blueprint, flash, redirect, render_template, request, url_for

from ..errors import AppError
from ..security import login_required, session_scope
from ..services import admin_service, work_service

bp = Blueprint("admin", __name__, url_prefix="/admin")

MANAGER_ROLES = ("manager",)


@bp.get("/stats")
@login_required
def stats():
    with session_scope(roles=MANAGER_ROLES) as (conn, _ctx):
        data = admin_service.stats(conn)
    return render_template("admin_stats.html", daily=data["daily"], products=data["products"])


@bp.get("/stock")
@login_required
def stock():
    with session_scope(roles=MANAGER_ROLES) as (conn, _ctx):
        ingredients = admin_service.ingredients(conn)
    return render_template("admin_stock.html", ingredients=ingredients)


@bp.post("/stock")
@login_required
def adjust_stock():
    ingredient_id = request.form.get("ingredient_id", "").strip()
    operation = request.form.get("operation", "").strip()
    amount = request.form.get("amount", "").strip()
    with session_scope(roles=MANAGER_ROLES) as (conn, _ctx):
        try:
            admin_service.adjust_stock(conn, ingredient_id, operation, amount)
        except AppError as exc:
            flash(exc.message, "danger")
            return render_template("admin_stock.html", ingredients=admin_service.ingredients(conn),
                                   form_values={"ingredient_id": ingredient_id, "operation": operation, "amount": amount}), exc.status
    flash("库存已更新。", "success")
    return redirect(url_for("admin.stock"))


@bp.get("/employees")
@login_required
def employees():
    with session_scope(roles=MANAGER_ROLES) as (conn, _ctx):
        rows = admin_service.employees(conn)
    return render_template("admin_employees.html", rows=rows)


@bp.get("/members")
@login_required
def members():
    phone = request.args.get("phone", "").strip()
    member = None
    with session_scope(roles=MANAGER_ROLES) as (conn, _ctx):
        if phone:
            try:
                member = work_service.find_member(conn, phone)
            except AppError as exc:
                flash(exc.message, "warning")
    return render_template("admin_members.html", member=member, phone=phone)


@bp.post("/members")
@login_required
def save_member():
    member_id = request.form.get("member_id", "").strip()
    name = request.form.get("name", "").strip()
    phone = request.form.get("phone", "").strip()
    with session_scope(roles=MANAGER_ROLES) as (conn, _ctx):
        try:
            work_service.save_member(conn, member_id, name, phone)
        except AppError as exc:
            flash(exc.message, "danger")
            return render_template("admin_members.html", member=None, phone=phone,
                                   form_values={"member_id":member_id,"name":name,"phone":phone}), exc.status
    flash(f"会员 {member_id} 已保存。", "success")
    return redirect(url_for("admin.members", phone=phone))
