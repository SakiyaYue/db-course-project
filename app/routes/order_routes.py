"""本人订单：下单、列表、详情、退款。"""

from __future__ import annotations

import json
import secrets

from flask import Blueprint, flash, jsonify, redirect, render_template, request, url_for

from ..errors import AppError
from ..security import login_required, session_scope
from ..services import menu_service, order_service

bp = Blueprint("orders", __name__)

BUYER_ROLES = ("customer", "member")


def _wants_json() -> bool:
    return request.path.startswith("/api/") or request.is_json


@bp.get("/my/orders")
@login_required
def my_orders():
    member = None
    with session_scope(roles=BUYER_ROLES) as (conn, ctx):
        orders = order_service.list_my_orders(conn)
        if ctx["app_role"] == "member":
            member = order_service.get_my_member(conn)
    return render_template("my_orders.html", orders=orders, member=member)


@bp.get("/my/orders/<order_id>")
@login_required
def order_detail(order_id: str):
    with session_scope(roles=BUYER_ROLES) as (conn, _ctx):
        detail = order_service.get_order_detail(conn, order_id)
    return render_template("order_detail.html", order=detail)


@bp.post("/orders")
@login_required
def create_order():
    payload = {}
    with session_scope(roles=BUYER_ROLES) as (conn, _ctx):
        try:
            if request.is_json:
                payload = request.get_json(silent=True) or {}
            else:
                payload = order_service.payload_from_form(request.form)
            result = order_service.place_paid_order(conn, payload)
        except AppError as exc:
            if _wants_json():
                return jsonify({"error": {"code": exc.code, "message": exc.message}}), exc.status
            # Re-render with safe basket fields, retaining the same idempotency token.
            if not payload:
                try:
                    raw_items = json.loads(request.form.get("items_json", "[]"))
                except (ValueError, TypeError):
                    raw_items = []
                payload = {"items": raw_items if isinstance(raw_items, list) else [],
                           "payment_succeeded": request.form.get("payment_succeeded", "true") == "true"}
            return render_template(
                "checkout.html", catalog=menu_service.load_catalog(conn), payload=payload,
                request_token=request.form.get("request_token") or secrets.token_urlsafe(32),
                error=exc.message,
            ), exc.status
    if _wants_json():
        return jsonify(result), 201
    flash(f"下单成功：{result['order_id']}，金额 {result['total_amount']} 元。", "success")
    return redirect(url_for("orders.my_orders"))


@bp.post("/my/orders/<order_id>/refund")
@login_required
def refund(order_id: str):
    with session_scope(roles=BUYER_ROLES) as (conn, _ctx):
        try:
            result = order_service.refund(conn, order_id)
        except AppError as exc:
            if _wants_json():
                return jsonify({"error": {"code": exc.code, "message": exc.message}}), exc.status
            return render_template("error.html", code=exc.code, message=exc.message, status=exc.status), exc.status
    if _wants_json():
        return jsonify(result)
    flash(f"订单 {result['order_id']} 已退款。", "success")
    return redirect(url_for("orders.my_orders"))
