"""Backend regressions that run without SQL Server."""
import json
from copy import deepcopy
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import MagicMock

import pyodbc
import pytest

from app.db import Database
from app.dao import auth_dao, order_dao
from app.errors import AppError, translate_db_error
from app.services import order_service


def payload():
    return {"items": [{"product_id": "P001", "quantity": 1, "specs": ["S001"], "addons": ["A001"]}], "payment_succeeded": True}


def database():
    return Database(SimpleNamespace(query_timeout=5, connect_timeout=1, connection_string=lambda name: "unused"))


def test_driver_pool_is_disabled_before_connect():
    assert pyodbc.pooling is False


def test_connection_closes_when_business_code_raises(monkeypatch):
    conn = MagicMock()
    db = database()
    monkeypatch.setattr(db, "connect", lambda *args: conn)
    with pytest.raises(ValueError):
        with db.connection():
            raise ValueError("business failed")
    conn.close.assert_called_once()


def test_failed_impersonation_closes_cursor():
    conn = MagicMock()
    cursor = conn.cursor.return_value
    cursor.execute.side_effect = pyodbc.Error("42000", "permission denied (229)")
    with pytest.raises(Exception):
        with database().impersonate(conn, "web_guest_a"):
            pytest.fail("must not enter business code")
    cursor.close.assert_called_once()


def test_impersonation_reverts_after_business_failure():
    conn = MagicMock()
    cursor = conn.cursor.return_value
    with pytest.raises(ValueError):
        with database().impersonate(conn, "web_guest_a"):
            raise ValueError("failed")
    sqls = [str(c.args[0]).upper() for c in cursor.execute.call_args_list]
    assert "EXECUTE AS USER" in sqls[0]
    assert any("REVERT" in sql for sql in sqls[1:])
    # Pending transactions must be cleared before the security context is reverted.
    revert_index = next(i for i, sql in enumerate(sqls) if "REVERT" in sql)
    assert any("ROLLBACK" in sql for sql in sqls[1:revert_index + 1])
    cursor.close.assert_called_once()


def test_untrusted_principal_never_executes_sql():
    conn = MagicMock()
    with pytest.raises(AppError):
        with database().impersonate(conn, "web_guest_a'; REVERT;--"):
            pass
    conn.cursor.assert_not_called()


def test_connection_failure_becomes_friendly_503(monkeypatch):
    monkeypatch.setattr(pyodbc, "connect", MagicMock(side_effect=pyodbc.OperationalError("08001", "private server details")))
    with pytest.raises(AppError) as error:
        database().connect()
    assert error.value.status == 503
    assert "private server" not in error.value.message


def test_item_collision_regenerates_order_and_all_item_references(monkeypatch):
    calls = []
    monkeypatch.setattr(auth_dao, "business_role", lambda conn: {"customer": 1})
    monkeypatch.setattr(order_dao, "transaction_count", lambda conn: 0, raising=False)
    def place(conn, order_id, items, specs, addons, paid):
        calls.append(deepcopy((order_id, items, specs, addons)))
        if len(calls) == 1:
            raise pyodbc.IntegrityError("23000", "Violation of PRIMARY KEY constraint 'PK_OrderItem'. Cannot insert duplicate key in object 'dbo.OrderItem'. (2627)")
        return {"order_id": order_id}
    monkeypatch.setattr(order_dao, "place_paid_order", place)
    result = order_service.place_paid_order(MagicMock(), payload())
    assert len(calls) == 2
    assert result["order_id"] == calls[1][0]
    assert calls[0][0] != calls[1][0]
    assert calls[0][1][0]["item_id"] != calls[1][1][0]["item_id"]
    for _, items, specs, addons in calls:
        assert specs[0]["item_id"] == addons[0]["item_id"] == items[0]["item_id"]


def test_unrelated_unique_conflict_is_not_retried(monkeypatch):
    monkeypatch.setattr(auth_dao, "business_role", lambda conn: {"customer": 1})
    place = MagicMock(side_effect=pyodbc.IntegrityError("23000", "Violation of UNIQUE KEY constraint 'UQ_Member_Phone'. object 'dbo.Member'. (2627)"))
    monkeypatch.setattr(order_dao, "place_paid_order", place)
    with pytest.raises(AppError) as error:
        order_service.place_paid_order(MagicMock(), payload())
    assert error.value.code == "duplicate_key"
    place.assert_called_once()


def test_order_collision_retry_is_bounded(monkeypatch):
    monkeypatch.setattr(auth_dao, "business_role", lambda conn: {"customer": 1})
    monkeypatch.setattr(order_dao, "transaction_count", lambda conn: 0, raising=False)
    place = MagicMock(side_effect=pyodbc.IntegrityError("23000", "Violation of PRIMARY KEY constraint 'PK_SalesOrder'. object 'dbo.SalesOrder'. (2627)"))
    monkeypatch.setattr(order_dao, "place_paid_order", place)
    with pytest.raises(AppError) as error:
        order_service.place_paid_order(MagicMock(), payload())
    assert error.value.code == "id_collision"
    assert place.call_count == 3


@pytest.mark.parametrize("number,code,status", [(547,"constraint_violation",409),(229,"permission_denied",403),(52016,"stock_insufficient",409),(52105,"refund_other",403),(52700,"session_invalid",401)])
def test_database_errors_hide_sql_details(number, code, status):
    error = translate_db_error(pyodbc.Error("23000", f"private dbo.Table at C:/server/path ({number})"))
    assert (error.code, error.status) == (code, status)
    assert "dbo.Table" not in error.message
    assert "C:/server" not in error.message


def test_injection_string_is_bound_for_order_lookup():
    conn = MagicMock()
    cursor = conn.cursor.return_value
    cursor.nextset.return_value = False
    cursor.description = [("order_id",)]
    cursor.fetchall.return_value = []
    attack = "x'; DROP TABLE dbo.SalesOrder;--"
    assert order_dao.get_my_order(conn, attack) is None
    args = cursor.execute.call_args.args
    assert "?" in args[0] and attack not in args[0]
    assert attack in args[1:] or attack in args[1]
    cursor.close.assert_called_once()


def test_json_is_bound_instead_of_interpolated():
    conn = MagicMock()
    cursor = conn.cursor.return_value
    cursor.nextset.return_value = False
    cursor.description = [("order_id",),("total_amount",),("status",)]
    cursor.fetchall.return_value = [("O123456789", Decimal("6.00"), "排队中")]
    marker = "P001'; DROP TABLE dbo.Product;--"
    order_dao.place_paid_order(conn,"O123456789",[{"item_id":"I123456789","product_id":marker,"quantity":1}],[],[],True)
    args = cursor.execute.call_args.args
    assert args[0].count("?") == 5
    assert marker not in args[0]
    bound = args[1:] if len(args) > 2 else args[1]
    assert json.loads(bound[1])[0]["product_id"] == marker
    cursor.close.assert_called_once()


def test_dao_closes_cursor_when_driver_raises():
    conn = MagicMock()
    conn.cursor.return_value.execute.side_effect = pyodbc.Error("08S01", "network failed")
    with pytest.raises(pyodbc.Error):
        auth_dao.get_credential(conn,"guesta")
    conn.cursor.return_value.close.assert_called_once()



def test_service_rejects_direct_caller_with_wrong_sql_role(monkeypatch):
    monkeypatch.setattr(auth_dao, "business_role", lambda conn: {"clerk": 1})
    place = MagicMock()
    monkeypatch.setattr(order_dao, "place_paid_order", place)
    with pytest.raises(AppError) as error:
        order_service.place_paid_order(MagicMock(), payload())
    assert error.value.status == 403
    place.assert_not_called()


def test_revert_failure_discards_connection():
    conn = MagicMock()
    cursor = conn.cursor.return_value
    def execute(sql, *args):
        if sql.strip().upper() == "REVERT;":
            raise pyodbc.Error("08S01", "connection lost")
    cursor.execute.side_effect = execute
    with pytest.raises(AppError) as error:
        with database().impersonate(conn, "web_guest_a"):
            pass
    assert error.value.code == "identity_cleanup_failed"
    conn.close.assert_called_once()
    cursor.close.assert_called_once()


def test_pending_transaction_prevents_collision_retry(monkeypatch):
    monkeypatch.setattr(auth_dao, "business_role", lambda conn: {"customer": 1})
    monkeypatch.setattr(order_dao, "transaction_count", lambda conn: 1, raising=False)
    place = MagicMock(side_effect=pyodbc.IntegrityError("23000", "PRIMARY KEY constraint 'PK_OrderItem' object 'dbo.OrderItem' (2627)"))
    monkeypatch.setattr(order_dao, "place_paid_order", place)
    with pytest.raises(AppError):
        order_service.place_paid_order(MagicMock(), payload())
    place.assert_called_once()


def test_result_reader_skips_rowcount_and_drains_deferred_error():
    from app.dao.common import first_result
    cursor = MagicMock()
    descriptions = iter([None, [("value",)]])
    current = [next(descriptions)]
    type(cursor).description = property(lambda self: current[0])
    cursor.fetchall.return_value = [(1,)]
    def nextset():
        if current[0] is None:
            current[0] = next(descriptions)
            return True
        raise pyodbc.Error("42000", "deferred business error (52016)")
    cursor.nextset.side_effect = nextset
    with pytest.raises(pyodbc.Error):
        first_result(cursor)


def test_common_query_closes_cursor_after_deferred_sql_error():
    from app.dao.common import query
    conn = MagicMock()
    cursor = conn.cursor.return_value
    cursor.description = [("value",)]
    cursor.fetchall.return_value = [(1,)]
    cursor.nextset.side_effect = pyodbc.Error("42000", "deferred failure (547)")
    with pytest.raises(pyodbc.Error):
        query(conn, "EXEC fixed_proc ?", "bound")
    cursor.close.assert_called_once()



def test_second_close_error_does_not_mask_identity_cleanup_failure(monkeypatch):
    conn = MagicMock()
    conn.close.side_effect = [None, pyodbc.ProgrammingError("Attempt to use a closed connection.")]
    cursor = conn.cursor.return_value
    def execute(sql, *args):
        if sql.strip().upper() == "REVERT;":
            raise pyodbc.Error("08S01", "connection lost during revert")
    cursor.execute.side_effect = execute
    db = database()
    monkeypatch.setattr(db, "connect", lambda *args: conn)
    with pytest.raises(AppError) as error:
        with db.connection() as active:
            with db.impersonate(active, "web_guest_a"):
                pass
    assert error.value.code == "identity_cleanup_failed"
    assert error.value.status == 503
    assert conn.close.call_count == 2
