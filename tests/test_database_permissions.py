"""Direct SQL under real web_* business identities must retain database guards."""
import re
import pyodbc
import pytest


@pytest.mark.parametrize("principal,statement", [
    ("web_member_a", "UPDATE dbo.Member SET points = points WHERE member_id = 'M001'"),
    ("web_clerk", "EXEC teabar_api.usp_AdjustStock 'I001', N'补库', 1"),
    ("web_clerk", "SELECT salary FROM dbo.Employee"),
    ("web_clerk", "UPDATE dbo.Product SET base_price = base_price WHERE product_id = 'P001'"),
    ("web_manager", "UPDATE dbo.OrderItem SET product_name_snapshot = product_name_snapshot"),
    ("web_manager", "DELETE FROM dbo.SalesOrder WHERE 1 = 0"),
    ("web_guest_a", "SELECT password_hash FROM teabar_auth.WebAccount"),
    ("web_guest_a", "EXECUTE AS USER = 'web_manager'"),
])
def test_web_identity_direct_sql_is_denied(dbo, principal, statement):
    cursor = dbo.cursor()
    try:
        cursor.execute("BEGIN TRANSACTION;")
        # principal comes exclusively from this fixed test matrix.
        cursor.execute("EXECUTE AS USER = '" + principal + "'")
        try:
            with pytest.raises(pyodbc.Error) as error:
                cursor.execute(statement)
            numbers = {int(value) for value in re.findall(r"\((\d{3,6})\)", str(error.value))}
            expected = {15517, 15151} if statement.startswith("EXECUTE AS") else {229}
            assert numbers & expected, f"Expected permission error {expected}, got {error.value!r}"
        finally:
            cursor.execute("IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;")
            cursor.execute("REVERT;")
    finally:
        cursor.close()


def test_clerk_post_stock_write_is_denied(client, login, csrf):
    login("clerk1")
    response = client.post("/api/admin/stock", json={"ingredient_id": "I001", "operation": "补库", "amount": "1"}, headers={"X-CSRF-Token": csrf()})
    assert response.status_code == 403
