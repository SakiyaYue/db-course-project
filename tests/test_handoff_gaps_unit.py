"""Boundary checks for the five C handoff gaps, without database access."""
from datetime import date
from unittest.mock import MagicMock

import pyodbc
import pytest

from app.dao import auth_dao, history_dao, work_dao
from app.errors import AppError
from app.services import history_service, work_service


@pytest.fixture
def manager(monkeypatch):
    monkeypatch.setattr(auth_dao, "business_role", lambda conn: {"manager": 1})
    return MagicMock()


@pytest.mark.parametrize("field,value", [("name", "字" * 51), ("name", "😀" * 26),
    ("name", []), ("phone", "1234567"), ("phone", "23800000000"),
    ("phone", "１3800000000"), ("phone", 13800000000), ("phone", "138000000000")])
def test_member_invalid_fields_do_not_reach_dao(manager, monkeypatch, field, value):
    save = MagicMock()
    monkeypatch.setattr(work_dao, "save_member", save)
    body = {"member_id": "MTEST", "name": "测试", "phone": "13800000000"}
    body[field] = value
    with pytest.raises(AppError) as error:
        work_service.save_member(manager, **body)
    assert error.value.status == 400
    save.assert_not_called()


def test_member_exact_name_boundary_and_trim(manager, monkeypatch):
    save = MagicMock()
    monkeypatch.setattr(work_dao, "save_member", save)
    work_service.save_member(manager, "MTEST", "  " + "😀" * 25 + "  ", " 13800000000 ")
    assert save.call_args.args[2:] == ("😀" * 25, "13800000000")


@pytest.mark.parametrize("params", [{"page": "0"}, {"page_size": "101"}, {"page": "1.0"},
    {"page": "-1"}, {"page": "1000001"}, {"date_from": "2026-02-30"},
    {"date_to": "9999-12-31"}, {"date_from": "2026-11-10", "date_to": "2026-11-09"},
    {"order_id": "x';--"}, {"status": "退款"}, {"sql": "anything"}])
def test_history_rejects_bad_filters(manager, monkeypatch, params):
    read = MagicMock()
    monkeypatch.setattr(history_dao, "list_orders", read)
    with pytest.raises(AppError) as error:
        history_service.list_orders(manager, params)
    assert error.value.status == 400
    read.assert_not_called()


def test_history_date_end_is_inclusive_and_pagination_bounded(manager, monkeypatch):
    read = MagicMock(return_value={"orders": []})
    monkeypatch.setattr(history_dao, "list_orders", read)
    history_service.list_orders(manager, {"date_from": "2026-11-01", "date_to": "2026-11-10", "page_size": "5"})
    assert read.call_args.args[1:] == ({"date_from": date(2026, 11, 1), "date_to": date(2026, 11, 11)}, 1, 5)


def test_history_filter_values_are_parameters(manager):
    cursor = manager.cursor.return_value
    cursor.description = None
    cursor.nextset.return_value = False
    history_dao.list_orders(manager, {"order_id": "PTEST", "status": "已取消"}, 2, 10)
    sql, *params = cursor.execute.call_args.args
    assert "PTEST" not in sql and "已取消" not in sql
    assert params == ["PTEST", "已取消", 10, 11]
    assert "order_time DESC, order_id DESC" in sql


@pytest.mark.parametrize("role", ["customer", "member", "clerk"])
def test_history_service_is_manager_only(manager, monkeypatch, role):
    monkeypatch.setattr(auth_dao, "business_role", lambda conn: {role: 1})
    for call in (lambda: history_service.list_orders(manager, {}), lambda: history_service.get_order(manager, "O1")):
        with pytest.raises(AppError) as error:
            call()
        assert error.value.status == 403


def test_member_save_drains_deferred_errors(manager):
    cursor = manager.cursor.return_value
    cursor.description = None
    cursor.nextset.side_effect = pyodbc.Error("23000", "duplicate (2627)")
    with pytest.raises(AppError) as error:
        work_service.save_member(manager, "MTEST", "测试", "13800000000")
    assert error.value.code == "duplicate_key"
    cursor.close.assert_called_once()
