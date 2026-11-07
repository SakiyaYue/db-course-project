"""菜单服务：把视图行组装成渲染/JSON 均可用的目录结构。"""

from __future__ import annotations

from ..dao import menu_dao


def load_catalog(conn) -> dict:
    products = menu_dao.list_menu(conn)
    specs = menu_dao.list_specifications(conn)
    addons = menu_dao.list_addons(conn)

    spec_map: dict[str, dict[str, list[dict]]] = {}
    for spec in specs:
        spec_map.setdefault(spec["product_id"], {}).setdefault(spec["spec_type"], []).append(
            {
                "spec_id": spec["spec_id"],
                "spec_name": spec["spec_name"],
                "price_delta": spec["price_delta"],
            }
        )

    catalog = []
    for product in products:
        catalog.append(
            {
                "product_id": product["product_id"],
                "product_name": product["product_name"],
                "base_price": product["base_price"],
                "description": product["description"],
                "spec_types": spec_map.get(product["product_id"], {}),
            }
        )
    return {"products": catalog, "addons": addons}
