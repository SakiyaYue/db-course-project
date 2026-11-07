"""店员/店长工作台页面。"""

from __future__ import annotations

from flask import Blueprint, flash, redirect, render_template, request, url_for

from ..errors import AppError
from ..security import login_required, session_scope
from ..services import work_service

bp = Blueprint("work", __name__, url_prefix="/work")

STAFF_ROLES = ("clerk", "manager")


@bp.get("/orders")
@login_required
def orders():
    with session_scope(roles=STAFF_ROLES) as (conn, ctx):
        orders = work_service.list_orders(conn)
        member = None
        phone = request.args.get("phone", "").strip()
        if phone:
            try:
                member = work_service.find_member(conn, phone)
            except AppError as exc:
                flash(exc.message, "warning")
    return render_template("work_orders.html", orders=orders, member=member, role=ctx["app_role"],
                           phone=phone)


@bp.get("/orders/<order_id>")
@login_required
def order_detail(order_id: str):
    with session_scope(roles=STAFF_ROLES) as (conn, _ctx):
        detail = work_service.get_order_detail(conn, order_id)
    return render_template("work_order_detail.html", order=detail)


@bp.post("/orders/<order_id>/advance")
@login_required
def advance(order_id: str):
    next_status = request.form.get("next_status", "").strip()
    with session_scope(roles=STAFF_ROLES) as (conn, _ctx):
        try:
            result = work_service.advance(conn, order_id, next_status)
        except AppError as exc:
            flash(exc.message, "danger")
            return redirect(url_for("work.order_detail", order_id=order_id)), exc.status
    flash(f"订单 {result['order_id']} 已流转到 {result['status']}。", "success")
    return redirect(url_for("work.order_detail", order_id=order_id))


@bp.get("/team")
@login_required
def team():
    with session_scope(roles=STAFF_ROLES) as (conn, _ctx):
        rows = work_service.list_team(conn)
    return render_template("work_team.html", rows=rows)


@bp.post("/members")
@login_required
def save_member():
    member_id = request.form.get("member_id", "").strip()
    name = request.form.get("name", "").strip()
    phone = request.form.get("phone", "").strip()
    with session_scope(roles=STAFF_ROLES) as (conn, _ctx):
        try:
            work_service.save_member(conn, member_id, name, phone)
        except AppError as exc:
            flash(exc.message, "danger")
            return redirect(url_for("work.orders", phone=phone)), exc.status
    flash(f"会员 {member_id} 已保存。", "success")
    return redirect(url_for("work.orders", phone=phone))
