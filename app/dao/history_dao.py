"""Manager-only history reads using fixed projections and bound filters."""
from datetime import datetime
from decimal import Decimal

from .common import query


def _read(conn, sql, *parameters):
    rows = query(conn, sql, *parameters)
    for row in rows:
        for key, value in row.items():
            if isinstance(value, Decimal):
                row[key] = format(value, ".2f")
            elif isinstance(value, datetime):
                row[key] = value.isoformat(timespec="seconds")
    return rows


def list_orders(conn, filters, page, page_size):
    conditions, parameters = [], []
    for field in ("order_id", "member_id", "status"):
        if field in filters:
            conditions.append(field + " = ?")
            parameters.append(filters[field])
    if "date_from" in filters:
        conditions.append("order_time >= ?")
        parameters.append(filters["date_from"])
    if "date_to" in filters:
        conditions.append("order_time < ?")
        parameters.append(filters["date_to"])
    where = " WHERE " + " AND ".join(conditions) if conditions else ""
    # Fetch one extra row for has_more; avoids a count/page race between two queries.
    rows = _read(conn, "SELECT order_id, member_id, order_time, total_amount, status "
                 "FROM dbo.SalesOrder" + where + " ORDER BY order_time DESC, order_id DESC "
                 "OFFSET ? ROWS FETCH NEXT ? ROWS ONLY", *parameters, (page - 1) * page_size, page_size + 1)
    return {"orders": rows[:page_size], "page": page, "page_size": page_size, "has_more": len(rows) > page_size}


def get_order(conn, order_id):
    rows = _read(conn, "SELECT order_id, member_id, order_time, total_amount, status "
                 "FROM dbo.SalesOrder WHERE order_id = ?", order_id)
    if not rows:
        return None
    order = rows[0]
    order["items"] = _read(conn, "SELECT item_id, order_id, product_id, product_name_snapshot, quantity, "
                           "base_price_snapshot, unit_price, sub_amount FROM dbo.OrderItem "
                           "WHERE order_id = ? ORDER BY item_id", order_id)
    order["specs"] = _read(conn, "SELECT s.item_id, s.spec_type, s.spec_id, s.spec_name_snapshot, s.price_delta_snapshot "
                           "FROM dbo.ItemSpec AS s JOIN dbo.OrderItem AS i ON i.item_id=s.item_id "
                           "WHERE i.order_id = ? ORDER BY s.item_id, s.spec_type", order_id)
    order["addons"] = _read(conn, "SELECT a.item_id, a.addon_id, a.addon_name_snapshot, a.price_snapshot "
                            "FROM dbo.ItemAddOn AS a JOIN dbo.OrderItem AS i ON i.item_id=a.item_id "
                            "WHERE i.order_id = ? ORDER BY a.item_id, a.addon_id", order_id)
    order["consumption"] = _read(conn, "SELECT c.item_id, c.ingredient_id, g.ingredient_name, g.unit, c.amount "
                                 "FROM dbo.OrderItemIngredient AS c JOIN dbo.OrderItem AS i ON i.item_id=c.item_id "
                                 "JOIN dbo.Ingredient AS g ON g.ingredient_id=c.ingredient_id "
                                 "WHERE i.order_id = ? ORDER BY c.item_id, c.ingredient_id", order_id)
    return order
