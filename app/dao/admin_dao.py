"""店长统计、库存与员工 DAO。"""

from __future__ import annotations

import datetime as _dt
from decimal import Decimal

import pyodbc


def _money(value) -> str | None:
    return f"{value:.2f}" if value is not None else None


def _iso(value) -> str | None:
    if value is None:
        return None
    if isinstance(value, _dt.datetime):
        return value.isoformat(sep=" ", timespec="seconds")
    return value.isoformat()  # date 等只需要日期部分


from .common import first_result as _rows


def daily_sales(conn: pyodbc.Connection) -> list[dict]:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT sale_date, order_count, sales_amount FROM teabar_api.vw_DailySales "
            "ORDER BY sale_date DESC"
        )
        rows = _rows(cursor)
    finally:
        cursor.close()
    for row in rows:
        row["sale_date"] = _iso(row["sale_date"])
        row["sales_amount"] = _money(row["sales_amount"])
    return rows


def product_sales(conn: pyodbc.Connection) -> list[dict]:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT product_id, product_name, cups_sold, sales_amount "
            "FROM teabar_api.vw_ProductSales ORDER BY product_id"
        )
        rows = _rows(cursor)
    finally:
        cursor.close()
    for row in rows:
        row["sales_amount"] = _money(row["sales_amount"])
    return rows


def list_ingredients(conn: pyodbc.Connection) -> list[dict]:
    """接口约定允许店长通过固定的、角色获准的 dbo 表 SELECT 读取原料。"""
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT ingredient_id, ingredient_name, unit, stock, status "
            "FROM dbo.Ingredient ORDER BY ingredient_id"
        )
        rows = _rows(cursor)
    finally:
        cursor.close()
    for row in rows:
        stock = row.get("stock")
        row["stock"] = f"{stock:.2f}" if isinstance(stock, Decimal) else stock
    return rows


def list_employees(conn: pyodbc.Connection) -> list[dict]:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT employee_id, name, role, status, salary FROM dbo.Employee ORDER BY employee_id"
        )
        rows = _rows(cursor)
    finally:
        cursor.close()
    for row in rows:
        salary = row.get("salary")
        row["salary"] = f"{salary:.2f}" if isinstance(salary, Decimal) else salary
    return rows


def adjust_stock(conn: pyodbc.Connection, ingredient_id: str, operation: str, amount: Decimal) -> dict:
    cursor = conn.cursor()
    try:
        cursor.execute("EXEC teabar_api.usp_AdjustStock ?, ?, ?", ingredient_id, operation, amount)
        rows = _rows(cursor)
    finally:
        cursor.close()
    if not rows:
        raise pyodbc.Error("no_result", "(52109) 库存调整未返回结果。")
    row = rows[0]
    return {
        "ingredient_id": row["ingredient_id"],
        "stock": f"{row['stock']:.2f}",
        "unit": row["unit"],
    }
