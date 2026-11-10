"""给前端组员 C 的 JSON API；与 HTML 页面共用同一套 service。"""

from __future__ import annotations

from flask import Blueprint, jsonify, request

from ..security import catalog_scope, csrf_token, current_auth, login_required, session_scope
from ..services import admin_service, menu_service, order_service, work_service, history_service
from ..errors import AppError

bp = Blueprint("api", __name__, url_prefix="/api")

BUYER_ROLES = ("customer", "member")
STAFF_ROLES = ("clerk", "manager")
MANAGER_ROLES = ("manager",)


def _body() -> dict:
    payload = request.get_json(silent=True)
    return payload if isinstance(payload, dict) else {}


@bp.get("/csrf")
def csrf():
    return jsonify({"csrf_token": csrf_token()})


@bp.get("/me")
@login_required
def me():
    auth = current_auth() or {}
    with session_scope() as (conn, ctx):
        member = order_service.get_my_member(conn) if ctx["app_role"] == "member" else None
    return jsonify(
        {
            "login_name": auth.get("login_name"),
            "account_id": ctx["account_id"],
            "app_role": ctx["app_role"],
            "principal_name": ctx["principal_name"],
            "session_version": ctx["session_version"],
            "member": member,
        }
    )


@bp.get("/menu")
def menu():
    with catalog_scope() as (conn, _ctx):
        return jsonify(menu_service.load_catalog(conn))


@bp.get("/my/orders")
@login_required
def my_orders():
    with session_scope(roles=BUYER_ROLES) as (conn, _ctx):
        return jsonify({"orders": order_service.list_my_orders(conn)})


@bp.get("/my/orders/<order_id>")
@login_required
def my_order_detail(order_id: str):
    with session_scope(roles=BUYER_ROLES) as (conn, _ctx):
        return jsonify(order_service.get_order_detail(conn, order_id))


@bp.post("/orders")
@login_required
def create_order():
    with session_scope(roles=BUYER_ROLES) as (conn, _ctx):
        payload = _body()
        if request.headers.get("Idempotency-Key"):
            payload["request_token"] = request.headers["Idempotency-Key"]
        result = order_service.place_paid_order(conn, payload)
    return jsonify(result), 201


@bp.post("/my/orders/<order_id>/refund")
@login_required
def refund(order_id: str):
    with session_scope(roles=BUYER_ROLES) as (conn, _ctx):
        return jsonify(order_service.refund(conn, order_id))


@bp.get("/work/orders")
@login_required
def work_orders():
    with session_scope(roles=STAFF_ROLES) as (conn, _ctx):
        return jsonify({"orders": work_service.list_orders(conn)})


@bp.get("/work/orders/<order_id>")
@login_required
def work_order_detail(order_id: str):
    with session_scope(roles=STAFF_ROLES) as (conn, _ctx):
        return jsonify(work_service.get_order_detail(conn, order_id))


@bp.post("/work/orders/<order_id>/advance")
@login_required
def work_advance(order_id: str):
    next_status = str(_body().get("next_status") or "").strip()
    with session_scope(roles=STAFF_ROLES) as (conn, _ctx):
        return jsonify(work_service.advance(conn, order_id, next_status))


@bp.get("/work/team")
@login_required
def work_team():
    with session_scope(roles=STAFF_ROLES) as (conn, _ctx):
        return jsonify({"team": work_service.list_team(conn)})


@bp.get("/work/members")
@login_required
def find_member():
    phone = request.args.get("phone", "").strip()
    with session_scope(roles=STAFF_ROLES) as (conn, _ctx):
        member = work_service.find_member(conn, phone)
    if member is None:
        return jsonify({"error": {"code": "member_not_found", "message": "未找到会员。"}}), 404
    return jsonify(member)


@bp.post("/work/members")
@bp.post("/admin/members")
@login_required
def save_member():
    body = _body()
    roles = MANAGER_ROLES if request.path == "/api/admin/members" else STAFF_ROLES
    with session_scope(roles=roles) as (conn, _ctx):
        work_service.save_member(
            conn,
            body.get("member_id"),
            body.get("name"),
            body.get("phone"),
        )
    return jsonify({"saved": True})


@bp.post("/work/orders/<order_id>/refund")
@login_required
def work_refund(order_id):
    with session_scope(roles=STAFF_ROLES) as (conn, _ctx):
        return jsonify(work_service.refund(conn, order_id))


@bp.get("/admin/stats")
@login_required
def admin_stats():
    with session_scope(roles=MANAGER_ROLES) as (conn, _ctx):
        return jsonify(admin_service.stats(conn))


@bp.get("/admin/orders")
@login_required
def admin_orders():
    with session_scope(roles=MANAGER_ROLES) as (conn, _ctx):
        if any(len(request.args.getlist(k)) != 1 for k in request.args):
            raise AppError("invalid_filter", "查询参数不能重复。", 400)
        return jsonify(history_service.list_orders(conn, request.args.to_dict()))


@bp.get("/admin/orders/<order_id>")
@login_required
def admin_order_detail(order_id):
    with session_scope(roles=MANAGER_ROLES) as (conn, _ctx):
        return jsonify(history_service.get_order(conn, order_id))


@bp.get("/admin/stock")
@login_required
def admin_stock():
    with session_scope(roles=MANAGER_ROLES) as (conn, _ctx):
        return jsonify({"ingredients": admin_service.ingredients(conn)})


@bp.post("/admin/stock")
@login_required
def admin_adjust_stock():
    body = _body()
    with session_scope(roles=MANAGER_ROLES) as (conn, _ctx):
        return jsonify(
            admin_service.adjust_stock(
                conn,
                str(body.get("ingredient_id") or "").strip(),
                str(body.get("operation") or "").strip(),
                body.get("amount"),
            )
        )


@bp.get("/admin/members")
@login_required
def admin_find_member():
    phone = request.args.get("phone", "").strip()
    with session_scope(roles=MANAGER_ROLES) as (conn, _ctx):
        member = work_service.find_member(conn, phone)
    if member is None:
        return jsonify({"error": {"code": "member_not_found", "message": "未找到会员。"}}), 404
    return jsonify(member)
