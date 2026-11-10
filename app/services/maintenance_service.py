"""Manager-only maintenance; database procedures own cross-record rules/transactions."""
from datetime import datetime
from decimal import Decimal, InvalidOperation
import re

from ..dao import maintenance_dao as dao
from ..errors import AppError, translate_db_error
from ..security import service_roles

ID = re.compile(r"[A-Za-z0-9_-]{1,10}")
TEXT_LENGTHS = {"product_name": 50, "ingredient_name": 50, "name": 50,
                "spec_name": 20, "addon_name": 50, "description": 200}
ENUMS = {
    "unit": ("g", "ml", "个"), "role": ("店员", "店长"),
    "spec_type": ("糖度", "温度", "杯型"),
}
STATUSES = {"products": ("在售", "下架"), "ingredients": ("可用", "缺货"),
            "employees": ("在职", "离职"), "product-specifications": ("可用", "停用"),
            "addons": ("可用", "缺货")}
DECIMALS = {"base_price", "salary", "price_delta", "base_amount", "factor", "price", "extra_amount"}


def _invalid(field):
    return AppError("invalid_field", f"字段 {field} 的类型、格式或取值不符合约定。", 400)


def _resource(resource):
    if resource not in dao.RESOURCES:
        raise AppError("resource_not_found", "管理资源不存在。", 404)
    return dao.RESOURCES[resource]


def _value(resource, field, value):
    if field == "remove":
        if type(value) is not bool:
            raise _invalid(field)
        return value
    if field in DECIMALS:
        if isinstance(value, bool) or not isinstance(value, (str, int, float, Decimal)):
            raise _invalid(field)
        try:
            number = Decimal(str(value))
        except InvalidOperation:
            raise _invalid(field)
        maximum = Decimal("999.99" if field == "factor" else "99999999.99")
        minimum = -maximum if field == "price_delta" else Decimal(0)
        if (not number.is_finite() or number.as_tuple().exponent < -2
                or not minimum <= number <= maximum
                or (field in {"base_amount", "extra_amount"} and number == 0)):
            raise _invalid(field)
        return number
    if field == "description" and value is None:
        return None
    if not isinstance(value, str):
        raise _invalid(field)
    value = value.strip()
    if field.endswith("_id"):
        if not ID.fullmatch(value):
            raise _invalid(field)
    elif field in TEXT_LENGTHS:
        # NVARCHAR length counts UTF-16 code units, including supplementary characters.
        try:
            length = len(value.encode("utf-16-le")) // 2
        except UnicodeEncodeError:
            raise _invalid(field)
        if length > TEXT_LENGTHS[field] or (not value and field != "description"):
            raise _invalid(field)
    elif field == "status" or field in ENUMS:
        allowed = STATUSES[resource] if field == "status" else ENUMS[field]
        if value not in allowed:
            raise _invalid(field)
    elif field in {"start_time", "end_time"}:
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}", value):
            raise _invalid(field)
        try:
            return datetime.fromisoformat(value)
        except ValueError:
            raise _invalid(field)
    return value


@service_roles("manager")
def list_records(conn, resource, filters=None):
    spec = _resource(resource)
    filters = filters or {}
    allowed = {f for f in spec.fields if f.endswith("_id") or f in {"status", "spec_type"}}
    if set(filters) - allowed:
        raise AppError("invalid_filter", "只支持编号、状态和规格类型过滤。", 400)
    values = {k: _value(resource, k, v) for k, v in filters.items()}
    try:
        return dao.list_records(conn, resource, values)
    except Exception as exc:
        raise translate_db_error(exc) from exc


@service_roles("manager")
def get_record(conn, resource, keys):
    spec = _resource(resource)
    if len(keys) != len(spec.keys):
        raise AppError("invalid_key", "主键数量不正确。", 400)
    filters = {k: _value(resource, k, v) for k, v in zip(spec.keys, keys)}
    try:
        rows = dao.list_records(conn, resource, filters)
    except Exception as exc:
        raise translate_db_error(exc) from exc
    if not rows:
        raise AppError("record_not_found", "记录不存在。", 404)
    return rows[0]


@service_roles("manager")
def save_record(conn, resource, payload):
    spec = _resource(resource)
    if not isinstance(payload, dict) or set(payload) - set(spec.fields):
        raise AppError("invalid_payload", "请求必须是 JSON 对象，且不能包含未知或只读字段。", 400)
    body = dict(payload)
    if "remove" in spec.fields:
        body.setdefault("remove", False)
        _value(resource, "remove", body["remove"])
    if "description" in spec.fields:
        body.setdefault("description", None)
    removing = body.get("remove", False)
    values = {}
    for field in spec.fields:
        if removing and field in {"base_amount", "factor"}:
            if body.get(field) is not None:
                raise _invalid(field)
            values[field] = None
        else:
            values[field] = _value(resource, field, body.get(field))
    if resource == "duty-rosters" and values["start_time"] >= values["end_time"]:
        raise AppError("invalid_time_range", "值班开始时间必须早于结束时间。", 400)
    try:
        dao.save_record(conn, resource, values)
    except Exception as exc:
        raise translate_db_error(exc) from exc
    result = {"saved": True, "key": {k: values[k] for k in spec.keys}}
    if "remove" in spec.fields:
        result["removed"] = removing
    if resource == "recipes":
        result["product_specifications_disabled"] = True
    return result
