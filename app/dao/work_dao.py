"""店员/店长工作台 DAO：工作订单、消耗、值班团队、会员查询与保存、状态推进。"""

from __future__ import annotations

import pyodbc


def _money(value) -> str | None:
    return f"{value:.2f}" if value is not None else None


def _iso(value) -> str | None:
    return value.isoformat(sep=" ", timespec="seconds") if value is not None else None


from .common import first_result as _rows


def list_work_orders(conn: pyodbc.Connection) -> list[dict]:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT order_id, member_id, order_time, total_amount, status "
            "FROM teabar_api.vw_WorkOrders ORDER BY order_time DESC, order_id DESC"
        )
        rows = _rows(cursor)
    finally:
        cursor.close()
    for row in rows:
        row["order_time"] = _iso(row["order_time"])
        row["total_amount"] = _money(row["total_amount"])
    return rows


def get_work_order(conn: pyodbc.Connection, order_id: str) -> dict | None:
    orders = [row for row in list_work_orders(conn) if row["order_id"] == order_id]
    return orders[0] if orders else None


def list_work_items(conn: pyodbc.Connection, order_id: str) -> list[dict]:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT item_id, order_id, product_id, product_name_snapshot, quantity, "
            "base_price_snapshot, unit_price, sub_amount "
            "FROM teabar_api.vw_WorkOrderItems WHERE order_id = ? ORDER BY item_id",
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


def list_work_item_specs(conn: pyodbc.Connection, order_id: str) -> list[dict]:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT item_id, spec_type, spec_id, spec_name_snapshot, price_delta_snapshot "
            "FROM teabar_api.vw_WorkItemSpecs "
            "WHERE item_id IN (SELECT item_id FROM teabar_api.vw_WorkOrderItems WHERE order_id = ?) "
            "ORDER BY item_id, spec_type",
            order_id,
        )
        rows = _rows(cursor)
    finally:
        cursor.close()
    for row in rows:
        row["price_delta_snapshot"] = _money(row["price_delta_snapshot"])
    return rows


def list_work_item_addons(conn: pyodbc.Connection, order_id: str) -> list[dict]:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT item_id, addon_id, addon_name_snapshot, price_snapshot "
            "FROM teabar_api.vw_WorkItemAddOns "
            "WHERE item_id IN (SELECT item_id FROM teabar_api.vw_WorkOrderItems WHERE order_id = ?) "
            "ORDER BY item_id, addon_id",
            order_id,
        )
        rows = _rows(cursor)
    finally:
        cursor.close()
    for row in rows:
        row["price_snapshot"] = _money(row["price_snapshot"])
    return rows


def list_work_consumption(conn: pyodbc.Connection, order_id: str) -> list[dict]:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT item_id, ingredient_id, ingredient_name, unit, amount "
            "FROM teabar_api.vw_WorkConsumption "
            "WHERE item_id IN (SELECT item_id FROM teabar_api.vw_WorkOrderItems WHERE order_id = ?) "
            "ORDER BY item_id, ingredient_id",
            order_id,
        )
        rows = _rows(cursor)
    finally:
        cursor.close()
    for row in rows:
        row["amount"] = _money(row["amount"])
    return rows


def list_work_team(conn: pyodbc.Connection) -> list[dict]:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT order_id, employee_id, name, role, start_time, end_time "
            "FROM teabar_api.vw_WorkTeam ORDER BY start_time DESC"
        )
        rows = _rows(cursor)
    finally:
        cursor.close()
    for row in rows:
        row["start_time"] = _iso(row["start_time"])
        row["end_time"] = _iso(row["end_time"])
    return rows


def advance_order(conn: pyodbc.Connection, order_id: str, next_status: str) -> dict:
    cursor = conn.cursor()
    try:
        cursor.execute("EXEC teabar_api.usp_AdvanceOrder ?, ?", order_id, next_status)
        rows = _rows(cursor)
    finally:
        cursor.close()
    if not rows:
        raise pyodbc.Error("no_result", "(52104) 状态推进未返回结果。")
    return {"order_id": rows[0]["order_id"], "status": rows[0]["status"]}


def find_member(conn: pyodbc.Connection, phone: str) -> dict | None:
    cursor = conn.cursor()
    try:
        cursor.execute("EXEC teabar_api.usp_FindMember ?", phone)
        rows = _rows(cursor)
    finally:
        cursor.close()
    return rows[0] if rows else None


def save_member(conn: pyodbc.Connection, member_id: str, name: str, phone: str) -> None:
    cursor = conn.cursor()
    try:
        cursor.execute("EXEC teabar_api.usp_SaveMember ?, ?, ?", member_id, name, phone)
        _rows(cursor)
    finally:
        cursor.close()
