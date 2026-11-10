"""C's server-rendered pages, using B's authorized services unchanged."""
from flask import Blueprint, flash, redirect, render_template, request, url_for

from ..dao.maintenance_dao import RESOURCES
from ..errors import AppError
from ..security import login_required, session_scope
from ..services import maintenance_service, history_service, order_service
from ..ui_fields import TITLES, LABELS, fields

bp = Blueprint("management_pages", __name__)


@bp.get("/admin/maintenance")
@login_required
def center():
    with session_scope(roles=("manager",)):
        pass
    return render_template("maintenance_center.html", titles=TITLES)


@bp.route("/admin/maintenance/<resource>", methods=["GET", "POST"])
@login_required
def maintain(resource):
    with session_scope(roles=("manager",)) as (conn, _ctx):
        if resource not in RESOURCES:
            raise AppError("resource_not_found", "管理项目不存在。", 404)
        spec = RESOURCES[resource]
        values, status, editing = {}, 200, False
        if resource == "products":
            values["status"] = "下架"
        elif resource == "product-specifications":
            values["status"] = "停用"
        if request.method == "POST":
            values = {f: request.form.get(f, "") for f in spec.fields if f != "remove"}
            editing = request.form.get("editing") == "1"
            for f in ("start_time", "end_time"):
                if f in values and len(values[f]) == 16:
                    values[f] += ":00"
            removing = request.form.get("operation") == "remove"
            payload = dict(values)
            if "remove" in spec.fields:
                payload["remove"] = removing
                if removing:
                    payload = {k: values[k] for k in spec.keys} | {"remove": True}
            try:
                result = maintenance_service.save_record(conn, resource, payload)
            except AppError as exc:
                flash(exc.message, "danger")
                status = exc.status
            else:
                message = "记录已移除。" if removing else "资料已保存。"
                if result.get("product_specifications_disabled"):
                    message += " 该商品的规格配置已停用，请复核原料规则后重新启用。"
                flash(message, "success")
                return redirect(url_for("management_pages.maintain", resource=resource))
        elif "key" in request.args:
            values = maintenance_service.get_record(conn, resource, request.args["key"].split("/"))
            editing = True
        rows = maintenance_service.list_records(conn, resource)
    return render_template("maintenance.html", resource=resource, title=TITLES[resource], fields=fields(resource),
                           labels=LABELS, keys=spec.keys, rows=rows, values=values, editing=editing,
                           removable="remove" in spec.fields, titles=TITLES), status


@bp.get("/admin/orders")
@login_required
def history():
    params = {k: v for k, v in request.args.items() if v}
    with session_scope(roles=("manager",)) as (conn, _ctx):
        if any(len(request.args.getlist(k)) > 1 for k in request.args):
            raise AppError("invalid_filter", "查询参数不能重复。", 400)
        result = history_service.list_orders(conn, params)
    prev = url_for("management_pages.history", **(params | {"page": result["page"] - 1}))
    next_page = url_for("management_pages.history", **(params | {"page": result["page"] + 1}))
    return render_template("history.html", result=result, filters=params, previous=prev, next_page=next_page)


@bp.get("/admin/orders/<order_id>")
@login_required
def history_detail(order_id):
    with session_scope(roles=("manager",)) as (conn, _ctx):
        order = history_service.get_order(conn, order_id)
    return render_template("history_detail.html", order=order)


@bp.get("/my/profile")
@login_required
def profile():
    with session_scope(roles=("member",)) as (conn, _ctx):
        member = order_service.get_my_member(conn)
    return render_template("profile.html", member=member)
