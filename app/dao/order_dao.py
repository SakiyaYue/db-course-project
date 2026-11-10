"""订单 DAO：下单走 usp_PlacePaidOrderJson，查询走 teabar_api 视图。"""

from __future__ import annotations

import json

import pyodbc

from .common import transaction_count, procedure, query


def _iso(value) -> str | None:
    return value.isoformat(sep=" ", timespec="seconds") if value is not None else None


def _money(value) -> str | None:
    return f"{value:.2f}" if value is not None else None


from .common import first_result as _rows


def place_paid_order(
    conn: pyodbc.Connection,
    order_id: str,
    items: list[dict],
    specs: list[dict],
    addons: list[dict],
    payment_succeeded: bool,
) -> dict:
    """调用 JSON 下单入口；成功返回单行结果，失败由 THROW 抛出。"""
    cursor = conn.cursor()
    try:
        cursor.execute(
            "EXEC teabar_api.usp_PlacePaidOrderJson ?, ?, ?, ?, ?",
            order_id,
            json.dumps(items, ensure_ascii=False),
            json.dumps(specs, ensure_ascii=False),
            json.dumps(addons, ensure_ascii=False),
            1 if payment_succeeded else 0,
        )
        rows = _rows(cursor)
    finally:
        cursor.close()
    if not rows:
        raise pyodbc.Error("no_result", "(2601) 下单未返回结果。")
    row = rows[0]
    return {
        "order_id": row["order_id"],
        "total_amount": _money(row["total_amount"]),
        "status": row["status"],
    }


def list_my_orders(conn: pyodbc.Connection) -> list[dict]:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT order_id, order_time, total_amount, status "
            "FROM teabar_api.vw_MyOrders ORDER BY order_time DESC, order_id DESC"
        )
        rows = _rows(cursor)
    finally:
        cursor.close()
    for row in rows:
        row["order_time"] = _iso(row["order_time"])
        row["total_amount"] = _money(row["total_amount"])
    return rows


def get_my_order(conn: pyodbc.Connection, order_id: str) -> dict | None:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT order_id, order_time, total_amount, status "
            "FROM teabar_api.vw_MyOrders WHERE order_id = ?",
            order_id,
        )
        rows = _rows(cursor)
    finally:
        cursor.close()
    if not rows:
        return None
    row = rows[0]
    row["order_time"] = _iso(row["order_time"])
    row["total_amount"] = _money(row["total_amount"])
    return row


def list_my_items(conn: pyodbc.Connection, order_id: str) -> list[dict]:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT item_id, order_id, product_id, product_name_snapshot, quantity, "
            "base_price_snapshot, unit_price, sub_amount "
            "FROM teabar_api.vw_MyOrderItems WHERE order_id = ? ORDER BY item_id",
            order_id,
        )
        rows = _rows(cursor)
    finally:
        cursor.close()
    for row in rows:
        row["base_price_snapshot"] = _money(row["base_price_snapshot"])
        row["unit_price"] = _money(row["unit_price"])
        row["sub_amount"] = _money(row["sub_amount"])
    return rows


def list_my_item_specs(conn: pyodbc.Connection, order_id: str) -> list[dict]:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT item_id, spec_type, spec_id, spec_name_snapshot, price_delta_snapshot "
            "FROM teabar_api.vw_MyItemSpecs "
            "WHERE item_id IN (SELECT item_id FROM teabar_api.vw_MyOrderItems WHERE order_id = ?) "
            "ORDER BY item_id, spec_type",
            order_id,
        )
        rows = _rows(cursor)
    finally:
        cursor.close()
    for row in rows:
        row["price_delta_snapshot"] = _money(row["price_delta_snapshot"])
    return rows


def list_my_item_addons(conn: pyodbc.Connection, order_id: str) -> list[dict]:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT item_id, addon_id, addon_name_snapshot, price_snapshot "
            "FROM teabar_api.vw_MyItemAddOns "
            "WHERE item_id IN (SELECT item_id FROM teabar_api.vw_MyOrderItems WHERE order_id = ?) "
            "ORDER BY item_id, addon_id",
            order_id,
        )
        rows = _rows(cursor)
    finally:
        cursor.close()
    for row in rows:
        row["price_snapshot"] = _money(row["price_snapshot"])
    return rows


def refund_order(conn: pyodbc.Connection, order_id: str) -> dict:
    cursor = conn.cursor()
    try:
        cursor.execute("EXEC teabar_api.usp_RefundOrder ?", order_id)
        rows = _rows(cursor)
    finally:
        cursor.close()
    if not rows:
        raise pyodbc.Error("no_result", "(52106) 退款未返回结果。")
    return {"order_id": rows[0]["order_id"], "status": rows[0]["status"]}


def get_my_member(conn: pyodbc.Connection) -> dict | None:
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT member_id, name, phone, points FROM teabar_api.vw_MyMember")
        rows = _rows(cursor)
    finally:
        cursor.close()
    return rows[0] if rows else None


def list_my_consumption(conn, order_id):
    rows = query(conn, "SELECT item_id, ingredient_id, ingredient_name, unit, amount "
                 "FROM teabar_api.vw_MyConsumption WHERE order_id = ? ORDER BY item_id, ingredient_id", order_id)
    for row in rows:
        row["amount"] = _money(row["amount"])
    return rows


def place_web_order(conn, token, digest, order_id, items, specs, addons, payment_succeeded):
    rows = procedure(conn, "EXEC teabar_api.usp_PlaceWebOrder ?, ?, ?, ?, ?, ?, ?",
                     token, digest, order_id, json.dumps(items, ensure_ascii=False),
                     json.dumps(specs, ensure_ascii=False), json.dumps(addons, ensure_ascii=False),
                     int(payment_succeeded))
    if not rows:
        raise pyodbc.Error("no_result", "订单过程没有返回结果")
    return {"order_id": rows[0]["order_id"], "total_amount": _money(rows[0]["total_amount"]),
            "status": rows[0]["status"]}
