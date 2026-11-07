"""店长统计与库存服务。"""

from __future__ import annotations

import re
from decimal import Decimal, InvalidOperation

from ..security import service_roles

from ..dao import admin_dao
from ..errors import AppError, translate_db_error

ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{1,10}$")
OPERATIONS = ("补库", "盘点")


@service_roles("manager")
def stats(conn) -> dict:
    try:
        return {
            "daily": admin_dao.daily_sales(conn),
            "products": admin_dao.product_sales(conn),
        }
    except Exception as exc:
        raise translate_db_error(exc) from exc


@service_roles("manager")
def ingredients(conn) -> list[dict]:
    try:
        return admin_dao.list_ingredients(conn)
    except Exception as exc:
        raise translate_db_error(exc) from exc


@service_roles("manager")
def employees(conn) -> list[dict]:
    try:
        return admin_dao.list_employees(conn)
    except Exception as exc:
        raise translate_db_error(exc) from exc


@service_roles("manager")
def adjust_stock(conn, ingredient_id: str | None, operation: str | None, amount) -> dict:
    ingredient_id = (ingredient_id or "").strip()
    if not ID_PATTERN.fullmatch(ingredient_id):
        raise AppError("invalid_id", "原料编号格式不正确。", 400)
    if operation not in OPERATIONS:
        raise AppError("invalid_operation", "操作只能是「补库」或「盘点」。", 400)
    try:
        value = Decimal(str(amount).strip())
    except (InvalidOperation, AttributeError):
        raise AppError("invalid_amount", "数量必须是数字。", 400)
    if not value.is_finite() or value.as_tuple().exponent < -2 or value > Decimal("99999999.99"):
        raise AppError("invalid_amount", "数量必须是最多两位小数的有限非负数字。", 400)
    if value < 0 or (operation == "补库" and value <= 0):
        raise AppError("invalid_amount", "补库数量须大于 0；盘点实际库存须非负。", 400)
    try:
        return admin_dao.adjust_stock(conn, ingredient_id, operation, value)
    except Exception as exc:
        raise translate_db_error(exc) from exc
