"""Explicitly registered management API routes for C's maintenance pages."""
from flask import Blueprint, jsonify, request

from ..dao.maintenance_dao import RESOURCES
from ..errors import AppError
from ..security import login_required, session_scope
from ..services import maintenance_service as service

bp = Blueprint("maintenance", __name__, url_prefix="/api/admin")


@login_required
def records(resource):
    with session_scope(roles=("manager",)) as (conn, _ctx):
        if request.method == "POST":
            return jsonify(service.save_record(conn, resource, request.get_json(silent=True)))
        if any(len(request.args.getlist(k)) != 1 for k in request.args):
            raise AppError("invalid_filter", "查询参数不能重复。", 400)
        return jsonify({resource.replace("-", "_"): service.list_records(conn, resource, request.args.to_dict())})


@login_required
def detail(resource, keys):
    with session_scope(roles=("manager",)) as (conn, _ctx):
        return jsonify(service.get_record(conn, resource, keys.split("/")))


for resource in RESOURCES:
    bp.add_url_rule(f"/{resource}", endpoint=f"{resource}_records", view_func=records,
                    defaults={"resource": resource}, methods=["GET", "POST"])
    bp.add_url_rule(f"/{resource}/<path:keys>", endpoint=f"{resource}_detail", view_func=detail,
                    defaults={"resource": resource}, methods=["GET"])
