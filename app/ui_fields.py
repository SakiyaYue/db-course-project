"""Presentation metadata for the existing maintenance contract, no SQL."""
TITLES = {"products": "商品", "ingredients": "原料资料", "employees": "员工", "specifications": "规格字典",
          "product-specifications": "商品规格", "recipes": "基础配方", "specification-ingredients": "规格原料系数",
          "addons": "加料", "duty-rosters": "值班排班"}
LABELS = dict(product_id="商品编号", product_name="商品名称", base_price="基础价格", status="状态", description="描述",
              ingredient_id="原料编号", ingredient_name="原料名称", unit="单位", stock="库存", employee_id="员工编号",
              name="姓名", salary="工资", role="岗位", spec_id="规格编号", spec_type="规格类型", spec_name="规格名称",
              price_delta="规格差价", base_amount="基础用量", factor="原料系数", addon_id="加料编号", addon_name="加料名称",
              price="加料价格", extra_amount="每份用量", duty_id="班次编号", start_time="开始时间", end_time="结束时间")


def fields(resource):
    from .dao.maintenance_dao import RESOURCES
    from .services.maintenance_service import TEXT_LENGTHS, ENUMS, STATUSES, DECIMALS
    result = []
    for name in RESOURCES[resource].fields:
        if name == "remove":
            continue
        field = {"name": name, "label": LABELS[name], "type": "text", "required": name != "description",
                 "maxlength": TEXT_LENGTHS.get(name, 10), "options": None, "pattern": None}
        if name == "status" or name in ENUMS:
            field["options"] = STATUSES[resource] if name == "status" else ENUMS[name]
        elif name in DECIMALS:
            field.update(type="number", step="0.01", min="-99999999.99" if name == "price_delta" else
                         ("0.01" if name in {"base_amount", "extra_amount"} else "0"),
                         max="999.99" if name == "factor" else "99999999.99")
        elif name in {"start_time", "end_time"}:
            field.update(type="datetime-local", step="1")
        elif name.endswith("_id"):
            field["pattern"] = "[A-Za-z0-9_-]{1,10}"
        result.append(field)
    return result
