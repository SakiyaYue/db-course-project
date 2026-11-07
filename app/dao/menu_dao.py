"""菜单与商品/规格/加料查询 DAO。"""

from __future__ import annotations

import pyodbc


def _rows(cursor: pyodbc.Cursor) -> list[dict]:
    columns = [col[0] for col in cursor.description]
    result = []
    for row in cursor.fetchall():
        item = {}
        for name, value in zip(columns, row):
            if name.endswith("_price") or name in {"price", "base_price", "price_delta"}:
                item[name] = f"{value:.2f}" if value is not None else None
            else:
                item[name] = value
        result.append(item)
    return result


def list_menu(conn: pyodbc.Connection) -> list[dict]:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT product_id, product_name, base_price, description "
            "FROM teabar_api.vw_Menu ORDER BY product_id"
        )
        return _rows(cursor)
    finally:
        cursor.close()


def list_specifications(conn: pyodbc.Connection) -> list[dict]:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT product_id, spec_id, spec_type, spec_name, price_delta "
            "FROM teabar_api.vw_AvailableSpecifications ORDER BY product_id, spec_type, spec_id"
        )
        return _rows(cursor)
    finally:
        cursor.close()


def list_addons(conn: pyodbc.Connection) -> list[dict]:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT addon_id, addon_name, price FROM teabar_api.vw_AvailableAddOns ORDER BY addon_id"
        )
        return _rows(cursor)
    finally:
        cursor.close()
