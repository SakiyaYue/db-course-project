"""点单与本人订单服务：应用层只做格式/类型校验与错误翻译，业务规则交给数据库过程。"""

from __future__ import annotations

import re
import secrets
from decimal import Decimal

from ..dao import order_dao
from ..errors import AppError, translate_db_error

ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{1,10}$")
MAX_ITEMS = 20
MAX_QUANTITY = 99


def _new_id(prefix: str) -> str:
    return prefix + secrets.token_hex(5)[:9].upper()


def new_order_id() -> str:
    return _new_id("O")


def new_item_id() -> str:
    return _new_id("I")


def _require_id(value, field: str) -> str:
    text = str(value or "").strip()
    if not ID_PATTERN.fullmatch(text):
        raise AppError("invalid_id", f"{field} 不是合法的业务编号。", 400)
    return text


def _require_quantity(value) -> int:
    if isinstance(value, bool):
        raise AppError("invalid_quantity", "购买数量必须是正整数。", 400)
    if isinstance(value, str):
        if not value.strip().isdigit():
            raise AppError("invalid_quantity", "购买数量必须是正整数。", 400)
        value = int(value.strip())
    if isinstance(value, Decimal):
        value = int(value)
    if not isinstance(value, int) or not 1 <= value <= MAX_QUANTITY:
        raise AppError("invalid_quantity", f"购买数量必须在 1–{MAX_QUANTITY} 之间。", 400)
    return value


def _require_id_list(value, field: str) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, (list, tuple)):
        raise AppError("invalid_selection", f"{field} 必须是数组。", 400)
    return [_require_id(item, field) for item in value]


def normalize_payload(payload: dict) -> dict:
    """把 API/表单输入规范成 {items, specs, addons, payment_succeeded, basket}。"""
    if not isinstance(payload, dict):
        raise AppError("invalid_payload", "请求体必须是 JSON 对象。", 400)
    raw_items = payload.get("items")
    if not isinstance(raw_items, list) or not raw_items:
        raise AppError("invalid_items", "订单至少需要一件商品。", 400)
    if len(raw_items) > MAX_ITEMS:
        raise AppError("invalid_items", f"单笔订单最多 {MAX_ITEMS} 条明细。", 400)

    items_json: list[dict] = []
    specs_json: list[dict] = []
    addons_json: list[dict] = []
    basket: list[dict] = []
    for raw in raw_items:
        if not isinstance(raw, dict):
            raise AppError("invalid_items", "每条明细必须是对象。", 400)
        product_id = _require_id(raw.get("product_id"), "product_id")
        quantity = _require_quantity(raw.get("quantity", 1))
        item_id = new_item_id()
        spec_ids = _require_id_list(raw.get("specs"), "specs")
        addon_ids = _require_id_list(raw.get("addons"), "addons")
        if len(set(spec_ids)) != len(spec_ids):
            raise AppError("invalid_selection", "同一明细的规格不能重复。", 400)
        if len(set(addon_ids)) != len(addon_ids):
            raise AppError("invalid_selection", "同一明细的加料不能重复。", 400)
        items_json.append({"item_id": item_id, "product_id": product_id, "quantity": quantity})
        specs_json.extend({"item_id": item_id, "spec_id": spec_id} for spec_id in spec_ids)
        addons_json.extend({"item_id": item_id, "addon_id": addon_id} for addon_id in addon_ids)
        basket.append(
            {
                "item_id": item_id,
                "product_id": product_id,
                "quantity": quantity,
                "specs": spec_ids,
                "addons": addon_ids,
            }
        )

    payment_succeeded = payload.get("payment_succeeded", True)
    if not isinstance(payment_succeeded, bool):
        raise AppError("invalid_payment", "payment_succeeded 必须是布尔值。", 400)
    return {
        "items": items_json,
        "specs": specs_json,
        "addons": addons_json,
        "payment_succeeded": payment_succeeded,
        "basket": basket,
    }


def place_paid_order(conn, payload: dict) -> dict:
    normalized = normalize_payload(payload)
    # 订单/明细主键冲突时重试整组编号（接口约定：最多 3 次）
    last_error: Exception | None = None
    for _attempt in range(3):
        order_id = new_order_id()
        try:
            return order_dao.place_paid_order(
                conn,
                order_id,
                normalized["items"],
                normalized["specs"],
                normalized["addons"],
                normalized["payment_succeeded"],
            )
        except Exception as exc:  # pyodbc.Error
            error = translate_db_error(exc)
            if error.code == "duplicate_key":
                last_error = exc
                continue
            raise error from exc
    raise AppError("id_collision", "订单编号连续冲突，请重试。", 503, detail=str(last_error))


def payload_from_form(form) -> dict:
    """HTML 表单 → 订单载荷（单商品，多规格选择，多加料）。"""
    product_id = form.get("product_id")
    quantity = form.get("quantity", "1")
    spec_ids = form.getlist("spec_id")
    addon_ids = form.getlist("addon_id")
    return {
        "items": [
            {
                "product_id": product_id,
                "quantity": quantity,
                "specs": spec_ids,
                "addons": addon_ids,
            }
        ],
        "payment_succeeded": True,
    }


def list_my_orders(conn) -> list[dict]:
    try:
        return order_dao.list_my_orders(conn)
    except Exception as exc:
        raise translate_db_error(exc) from exc


def get_order_detail(conn, order_id: str) -> dict:
    order = order_dao.get_my_order(conn, order_id)
    if order is None:
        raise AppError("order_not_found", "订单不存在或不属于当前账号。", 404)
    detail = dict(order)
    detail["items"] = order_dao.list_my_items(conn, order_id)
    detail["specs"] = order_dao.list_my_item_specs(conn, order_id)
    detail["addons"] = order_dao.list_my_item_addons(conn, order_id)
    return detail


def refund(conn, order_id: str) -> dict:
    if not ID_PATTERN.fullmatch(str(order_id or "")):
        raise AppError("invalid_id", "订单编号格式不正确。", 400)
    try:
        return order_dao.refund_order(conn, order_id)
    except Exception as exc:
        raise translate_db_error(exc) from exc


def get_my_member(conn) -> dict | None:
    try:
        return order_dao.get_my_member(conn)
    except Exception as exc:
        raise translate_db_error(exc) from exc
