"""The Web initialization patch preserves documented ASCII identifier semantics."""
import secrets
import pytest
import pyodbc
from app.dao import auth_dao, order_dao

@pytest.mark.parametrize("login", ["a_b", "a-b", "abc", "a" * 50])
def test_legal_login_names_pass_constraint_and_credential_query(dbo, login):
    cursor = dbo.cursor()
    cursor.execute("BEGIN TRANSACTION")
    try:
        cursor.execute("UPDATE teabar_auth.WebAccount SET login_name=? WHERE login_name='guesta'", login)
        credential = auth_dao.get_credential(dbo, login)
        assert credential and credential["account_id"]
    finally:
        cursor.execute("IF @@TRANCOUNT>0 ROLLBACK TRANSACTION")
        cursor.close()

def test_json_ids_allow_documented_underscore_and_hyphen(dbo):
    cursor = dbo.cursor()
    cursor.execute("BEGIN TRANSACTION")
    switched = False
    try:
        cursor.execute("EXECUTE AS USER='web_guest_a'")
        switched = True
        order_id = "O_-" + secrets.token_hex(3).upper()
        item_id = "I_-" + secrets.token_hex(3).upper()
        row = order_dao.place_paid_order(dbo, order_id,
            [{"item_id": item_id, "product_id":"P001", "quantity":1}],
            [{"item_id":item_id,"spec_id":s} for s in ["S007","S004","S001"]], [], True)
        assert row["order_id"] == order_id
    finally:
        if switched:
            cursor.execute("REVERT")
        cursor.execute("IF @@TRANCOUNT>0 ROLLBACK TRANSACTION")
        cursor.close()
