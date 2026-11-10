"""店员/店长工作台服务。"""

from __future__ import annotations

import re

from ..security import service_roles

from ..dao import work_dao, order_dao
from ..errors import AppError, translate_db_error

ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{1,10}$")
PHONE_PATTERN = re.compile(r"1[0-9]{10}")
ALLOWED_STATUSES = ("排队中", "制作中", "待取餐", "已完成", "已取消")


@service_roles("clerk", "manager")
def list_orders(conn) -> list[dict]:
    try:
        return work_dao.list_work_orders(conn)
    except Exception as exc:
        raise translate_db_error(exc) from exc


@service_roles("clerk", "manager")
def get_order_detail(conn, order_id: str) -> dict:
    if not ID_PATTERN.fullmatch(order_id or ""):
        raise AppError("invalid_id", "订单编号格式不正确。", 400)
    order = work_dao.get_work_order(conn, order_id)
    if order is None:
        raise AppError("order_not_found", "订单不在当前工作范围内。", 404)
    detail = dict(order)
    detail["items"] = work_dao.list_work_items(conn, order_id)
    detail["specs"] = work_dao.list_work_item_specs(conn, order_id)
    detail["addons"] = work_dao.list_work_item_addons(conn, order_id)
    detail["consumption"] = work_dao.list_work_consumption(conn, order_id)
    return detail


@service_roles("clerk", "manager")
def list_team(conn) -> list[dict]:
    try:
        return work_dao.list_work_team(conn)
    except Exception as exc:
        raise translate_db_error(exc) from exc


@service_roles("clerk", "manager")
def advance(conn, order_id: str, next_status: str) -> dict:
    if not ID_PATTERN.fullmatch(order_id or ""):
        raise AppError("invalid_id", "订单编号格式不正确。", 400)
    if next_status not in ALLOWED_STATUSES:
        raise AppError("invalid_status", "目标状态不在允许范围内。", 400)
    try:
        return work_dao.advance_order(conn, order_id, next_status)
    except Exception as exc:
        raise translate_db_error(exc) from exc


@service_roles("clerk", "manager")
def find_member(conn, phone: str | None) -> dict | None:
    phone = phone.strip() if isinstance(phone, str) else ""
    if not PHONE_PATTERN.fullmatch(phone):
        raise AppError("invalid_phone", "请输入以 1 开头的 11 位 ASCII 数字手机号。", 400)
    try:
        return work_dao.find_member(conn, phone)
    except Exception as exc:
        raise translate_db_error(exc) from exc


@service_roles("clerk", "manager")
def save_member(conn, member_id: str, name: str, phone: str) -> None:
    if not isinstance(member_id, str) or not ID_PATTERN.fullmatch(member_id):
        raise AppError("invalid_id", "会员编号格式不正确。", 400)
    name = name.strip() if isinstance(name, str) else ""
    phone = phone.strip() if isinstance(phone, str) else ""
    try:
        name_length = len(name.encode("utf-16-le")) // 2
    except UnicodeEncodeError:
        name_length = 51
    if not name or name_length > 50:
        raise AppError("invalid_name", "会员姓名不能为空且不超过 50 个 UTF-16 单位。", 400)
    if not PHONE_PATTERN.fullmatch(phone):
        raise AppError("invalid_phone", "请输入以 1 开头的 11 位 ASCII 数字手机号。", 400)
    try:
        work_dao.save_member(conn, member_id, name, phone)
    except Exception as exc:
        raise translate_db_error(exc) from exc


@service_roles("clerk", "manager")
def refund(conn, order_id: str) -> dict:
    if not isinstance(order_id, str) or not ID_PATTERN.fullmatch(order_id):
        raise AppError("invalid_id", "订单编号格式不正确。", 400)
    try:
        return order_dao.refund_order(conn, order_id)
    except Exception as exc:
        raise translate_db_error(exc) from exc
