"""Fixed management object registry. SQL identifiers never come from request values."""
from dataclasses import dataclass
from datetime import date, datetime
from decimal import Decimal

from .common import query, procedure


@dataclass(frozen=True)
class Resource:
    table: str
    keys: tuple[str, ...]
    fields: tuple[str, ...]  # procedure parameter order
    procedure: str
    extra_columns: tuple[str, ...] = ()


RESOURCES = {
    "products": Resource("Product", ("product_id",), ("product_id", "product_name", "base_price", "status", "description"), "usp_SaveProduct"),
    "ingredients": Resource("Ingredient", ("ingredient_id",), ("ingredient_id", "ingredient_name", "unit", "status"), "usp_SaveIngredient", ("stock",)),
    "employees": Resource("Employee", ("employee_id",), ("employee_id", "name", "status", "salary", "role"), "usp_SaveEmployee"),
    "specifications": Resource("Specification", ("spec_id",), ("spec_id", "spec_type", "spec_name"), "usp_SaveSpecification"),
    "product-specifications": Resource("ProductSpecification", ("product_id", "spec_id"), ("product_id", "spec_id", "price_delta", "status"), "usp_SaveProductSpecification"),
    "recipes": Resource("Recipe", ("product_id", "ingredient_id"), ("product_id", "ingredient_id", "base_amount", "remove"), "usp_SaveRecipe"),
    "specification-ingredients": Resource("SpecificationIngredient", ("product_id", "spec_id", "ingredient_id"), ("product_id", "spec_id", "ingredient_id", "factor", "remove"), "usp_SaveSpecificationIngredient"),
    "addons": Resource("AddOn", ("addon_id",), ("addon_id", "addon_name", "price", "ingredient_id", "extra_amount", "status"), "usp_SaveAddOn"),
    "duty-rosters": Resource("DutyRoster", ("duty_id",), ("duty_id", "employee_id", "start_time", "end_time"), "usp_SaveDutyRoster"),
}


def list_records(conn, resource: str, filters: dict) -> list[dict]:
    spec = RESOURCES[resource]
    columns = tuple(f for f in spec.fields if f != "remove") + spec.extra_columns
    # Both projection and predicate columns are selected only from the fixed registry.
    filter_columns = tuple(f for f in columns if f in filters)
    sql = f"SELECT {', '.join(columns)} FROM dbo.{spec.table}"
    if filter_columns:
        sql += " WHERE " + " AND ".join(f"{field} = ?" for field in filter_columns)
    sql += " ORDER BY " + ", ".join(spec.keys)
    rows = query(conn, sql, *(filters[f] for f in filter_columns))
    for row in rows:
        for key, value in row.items():
            if isinstance(value, Decimal):
                row[key] = format(value, ".2f")
            elif isinstance(value, (datetime, date)):
                row[key] = value.isoformat()
    return rows


def save_record(conn, resource: str, values: dict) -> None:
    spec = RESOURCES[resource]
    sql = f"EXEC teabar_api.{spec.procedure} " + ", ".join("?" for _ in spec.fields)
    # Drain every result set: a deferred SQL error must not become a success response.
    procedure(conn, sql, *(values[f] for f in spec.fields))
