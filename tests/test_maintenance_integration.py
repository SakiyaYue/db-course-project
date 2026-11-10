"""Real manager procedures in the dedicated test DB; all changes rolled back."""
import secrets

import pytest

from app.dao.common import query
from app.errors import AppError
from app.services import maintenance_service as service


def test_nine_management_resources_with_rollback(dbo):
    prefix = "T" + secrets.token_hex(3)
    p, i, e, s, a, d = [prefix + suffix for suffix in "PIESAD"]
    query(dbo, "BEGIN TRANSACTION")
    switched = False
    try:
        query(dbo, "EXECUTE AS USER = 'web_manager'")
        switched = True

        def save(resource, **body):
            assert service.save_record(dbo, resource, body)["saved"] is True

        save("ingredients", ingredient_id=i, ingredient_name=prefix, unit="ml", status="可用")
        save("products", product_id=p, product_name=prefix, base_price="8.50", status="下架")
        save("employees", employee_id=e, name=prefix, status="在职", salary="100", role="店员")
        save("specifications", spec_id=s, spec_type="杯型", spec_name=prefix)
        save("recipes", product_id=p, ingredient_id=i, base_amount="2")
        save("product-specifications", product_id=p, spec_id=s, price_delta="-0.50", status="停用")
        save("specification-ingredients", product_id=p, spec_id=s, ingredient_id=i, factor="1.50")
        save("addons", addon_id=a, addon_name=prefix, price="1", ingredient_id=i, extra_amount="1", status="缺货")
        save("duty-rosters", duty_id=d, employee_id=e, start_time="2099-01-01T08:00:00", end_time="2099-01-01T16:00:00")

        keys = {"products": [p], "ingredients": [i], "employees": [e], "specifications": [s],
                "product-specifications": [p, s], "recipes": [p, i],
                "specification-ingredients": [p, s, i], "addons": [a], "duty-rosters": [d]}
        for resource, ids in keys.items():
            assert service.get_record(dbo, resource, ids)
            assert service.list_records(dbo, resource)
        assert service.get_record(dbo, "ingredients", [i])["stock"] == "0.00"
        assert service.get_record(dbo, "products", [p])["status"] == "下架"

        # Exercise upsert/update branches, activation, locked units and overlap failure.
        save("ingredients", ingredient_id=i, ingredient_name=prefix + "改", unit="ml", status="缺货")
        save("employees", employee_id=e, name=prefix, status="在职", salary="200", role="店长")
        save("specifications", spec_id=s, spec_type="杯型", spec_name=prefix + "改")
        save("recipes", product_id=p, ingredient_id=i, base_amount="3")
        save("specification-ingredients", product_id=p, spec_id=s, ingredient_id=i, factor="2")
        save("addons", addon_id=a, addon_name=prefix, price="2", ingredient_id=i, extra_amount="2", status="可用")
        save("duty-rosters", duty_id=d, employee_id=e, start_time="2099-01-01T09:00:00", end_time="2099-01-01T17:00:00")
        save("product-specifications", product_id=p, spec_id=s, price_delta="-0.50", status="可用")
        save("products", product_id=p, product_name=prefix, base_price="9.50", status="在售")
        assert service.get_record(dbo, "products", [p])["base_price"] == "9.50"
        assert service.get_record(dbo, "employees", [e])["salary"] == "200.00"
        with pytest.raises(AppError) as error:
            save("ingredients", ingredient_id=i, ingredient_name=prefix, unit="g", status="可用")
        assert error.value.code == "ingredient_unit_locked"
        with pytest.raises(AppError) as error:
            save("duty-rosters", duty_id=prefix + "X", employee_id=e, start_time="2099-01-01T10:00:00", end_time="2099-01-01T18:00:00")
        assert error.value.code == "duty_overlap"
        assert service.get_record(dbo, "duty-rosters", [d])["start_time"] == "2099-01-01T09:00:00"

        save("recipes", product_id=p, ingredient_id=i, base_amount="4")
        assert service.get_record(dbo, "product-specifications", [p, s])["status"] == "停用"
        save("specification-ingredients", product_id=p, spec_id=s, ingredient_id=i, remove=True)
        save("recipes", product_id=p, ingredient_id=i, remove=True)
        for resource, ids in [("recipes", [p, i]), ("specification-ingredients", [p, s, i])]:
            with pytest.raises(AppError) as error:
                service.get_record(dbo, resource, ids)
            assert error.value.status == 404
    finally:
        try:
            query(dbo, "IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION")
        finally:
            if switched:
                query(dbo, "REVERT")
    assert query(dbo, "SELECT COUNT(*) AS count FROM dbo.Product WHERE product_id = ?", p)[0]["count"] == 0
