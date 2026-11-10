"""Complete order history is available only to managers, never the work queue."""
from datetime import date, timedelta
import re

from ..dao import history_dao
from ..errors import AppError, translate_db_error
from ..security import service_roles

ID = re.compile(r"[A-Za-z0-9_-]{1,10}")
STATUSES = ("排队中", "制作中", "待取餐", "已完成", "已取消")


def _id(value):
    if not isinstance(value, str) or not ID.fullmatch(value):
        raise AppError("invalid_id", "编号格式不正确。", 400)
    return value


def _page(value, maximum):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9]{1,7}", value) or not 1 <= int(value) <= maximum:
        raise AppError("invalid_pagination", "页码须为 1–1000000，页大小须为 1–100 的整数。", 400)
    return int(value)


@service_roles("manager")
def list_orders(conn, params):
    if set(params) - {"order_id", "member_id", "status", "date_from", "date_to", "page", "page_size"}:
        raise AppError("invalid_filter", "历史订单查询包含未知筛选字段。", 400)
    filters = {}
    for field in ("order_id", "member_id"):
        if field in params:
            filters[field] = _id(params[field])
    if "status" in params:
        if params["status"] not in STATUSES:
            raise AppError("invalid_status", "订单状态不正确。", 400)
        filters["status"] = params["status"]
    for field in ("date_from", "date_to"):
        if field in params:
            try:
                raw = params[field]
                if not isinstance(raw, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", raw):
                    raise ValueError()
                filters[field] = date.fromisoformat(raw)
            except ValueError:
                raise AppError("invalid_date", "日期必须是有效的 YYYY-MM-DD。", 400)
    if "date_from" in filters and "date_to" in filters and filters["date_from"] > filters["date_to"]:
        raise AppError("invalid_date_range", "开始日期不能晚于结束日期。", 400)
    if "date_to" in filters:
        try:
            filters["date_to"] += timedelta(days=1)
        except OverflowError:
            raise AppError("invalid_date", "结束日期必须早于 9999-12-31。", 400)
    page = _page(params.get("page", "1"), 1000000)
    size = _page(params.get("page_size", "20"), 100)
    try:
        return history_dao.list_orders(conn, filters, page, size)
    except Exception as exc:
        raise translate_db_error(exc) from exc


@service_roles("manager")
def get_order(conn, order_id):
    _id(order_id)
    try:
        order = history_dao.get_order(conn, order_id)
    except Exception as exc:
        raise translate_db_error(exc) from exc
    if order is None:
        raise AppError("order_not_found", "订单不存在。", 404)
    return order
