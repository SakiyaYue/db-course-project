"""统一错误类型与 SQL Server 错误号 → 用户可读错误的映射。

原则：
- 数据库堆栈、对象名、参数值只进服务端日志，不返回浏览器；
- 业务错误号用接口约定里的 5 位编号识别，映射为稳定的应用错误码；
- 未知异常一律 500，对外只给通用提示。
"""

from __future__ import annotations

import re

# 接口约定（docs/phase2/06-normalization/v1.0数据库接口约定.md）第 2.3 节
DB_ERROR_MAP: dict[int, tuple[str, str, int]] = {
    52102: ("order_out_of_scope", "订单不在当前工作查询范围。", 403),
    52107: ("consumption_snapshot_missing", "订单缺少原料消耗快照，无法退款。", 409),
    52108: ("refund_ingredient_missing", "退款涉及的原料记录不完整。", 409),
    52100: ("manager_required", "仅店长可以执行此管理操作。", 403),
    52112: ("product_configuration_incomplete", "上架前须配置基础配方及各类型的可用规格。", 409),
    52113: ("ingredient_unit_locked", "非零库存或已被引用的原料不能修改单位。", 409),
    52114: ("specification_type_locked", "已使用的规格不能修改类型。", 409),
    52115: ("recipe_required", "启用商品规格前须配置基础配方。", 409),
    52116: ("fractional_piece_consumption", "计件原料的用量或规格组合会产生非整数消耗。", 409),
    52117: ("remove_required", "是否移除必须明确指定。", 400),
    52118: ("specification_must_be_disabled", "修改原料系数前须停用对应商品规格。", 409),
    52119: ("invalid_time_range", "值班开始时间必须早于结束时间。", 400),
    52120: ("employee_inactive", "只能为在职员工新增或修改排班。", 409),
    52121: ("duty_overlap", "同一员工的值班区间不能重叠。", 409),
    52122: ("product_not_found", "商品不存在，不能维护商品规格。", 409),
    52000: ("purchase_identity", "当前账号的购买身份不符合要求。", 403),
    52001: ("payment_failed", "模拟付款失败，未创建订单。", 402),
    52005: ("product_unavailable", "商品当前不可售，请刷新菜单后重试。", 409),
    52007: ("spec_invalid", "所选规格不存在或已停用，请重新选择。", 400),
    52008: ("spec_duplicate", "同一类型规格只能选择一项。", 400),
    52009: ("spec_missing", "还有规格类型未选择，请补全。", 400),
    52016: ("stock_insufficient", "原料库存不足，请调整数量或稍后再试。", 409),
    52018: ("zero_consumption", "存在没有任何原料消耗的明细，整单已拒绝。", 409),
    52103: ("status_transition", "订单状态流转不合法，请刷新后重试。", 409),
    52105: ("refund_other", "只能退本人的订单。", 403),
    52106: ("refund_state", "订单不是排队中或已重复退款。", 409),
    52600: ("json_invalid", "订单参数不是合法的 JSON 数组。", 400),
    52601: ("json_shape", "订单参数的元素或字段不符合约定。", 400),
    52602: ("json_value", "订单编号或数量的类型、格式不正确。", 400),
    52603: ("json_duplicate", "订单内存在重复的明细或选择。", 400),
    52604: ("json_reference", "规格或加料引用了本次订单之外的明细。", 400),
    52820: ("request_conflict", "同一请求标识不能用于不同的购物篮。", 409),
    52821: ("request_busy", "订单请求处理中，请稍后使用相同标识重试。", 503),
    52700: ("session_invalid", "登录状态已失效，请重新登录。", 401),
}

SQL_NUMBER_PATTERN = re.compile(r"\((\d{3,6})\)")


class AppError(Exception):
    """面向浏览器的应用错误：code 稳定、message 可直接展示、status 为 HTTP 状态码。"""

    def __init__(self, code: str, message: str, status: int = 400, detail: str | None = None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status
        self.detail = detail
        # Store structured diagnostics, never raw SQL/parameters/passwords in audit logs.
        from flask import g, has_request_context
        if has_request_context():
            g.error_code = code
            g.sql_number = extract_sql_number(Exception(detail or ""))
            match = re.search(r"\b(?:08[A-Z0-9]{3}|HY[A-Z0-9]{3}|23000|28000|42000)\b", detail or "")
            g.sql_state = match.group(0) if match else None


class AuthRequired(AppError):
    def __init__(self, message: str = "请先登录。"):
        super().__init__("auth_required", message, 401)


class Forbidden(AppError):
    def __init__(self, message: str = "当前角色无权执行此操作。"):
        super().__init__("forbidden", message, 403)


def extract_sql_number(exc: Exception) -> int | None:
    """从 pyodbc 异常文本中提取 SQL Server 错误号（形如 (52018)）。"""
    for arg in getattr(exc, "args", ()):
        text = str(arg)
        for match in SQL_NUMBER_PATTERN.finditer(text):
            number = int(match.group(1))
            if 50000 <= number <= 59999 or number in (2601, 2627, 229, 547, 1205, 1222):
                return number
    return None


def translate_db_error(exc: Exception) -> AppError:
    """把 pyodbc/数据库异常翻译成 AppError；未知错误返回 500 且隐藏细节。"""
    if isinstance(exc, AppError):
        return exc
    number = extract_sql_number(exc)
    if number in DB_ERROR_MAP:
        code, message, status = DB_ERROR_MAP[number]
        return AppError(code, message, status, detail=str(exc))
    if number in (1205, 1222):
        return AppError("transaction_failed", "事务冲突或超时，请稍后重试。", 503, detail=str(exc))
    if number in (2601, 2627):
        return AppError("duplicate_key", "数据已存在，不能重复创建。", 409, detail=str(exc))
    if number == 547:
        return AppError("constraint_violation", "数据不满足业务约束，操作已回滚。", 409, detail=str(exc))
    if number == 229:
        return AppError("permission_denied", "当前角色无权访问该数据。", 403, detail=str(exc))
    if number is not None:
        return AppError("database_business_error", "数据库拒绝了本次操作，请检查输入。", 409, detail=str(exc))
    # 连接类错误（驱动/网络）与未知错误分开处理
    text = " ".join(str(arg) for arg in getattr(exc, "args", ()))
    if any(state in text for state in ("HYT00", "HYT01")):
        return AppError("transaction_timeout", "数据库操作超时，请稍后重试。", 503, detail=text)
    if "SQL Server" in text or "ODBC" in text:
        return AppError("database_error", "数据库暂时不可用，请稍后重试。", 503, detail=text)
    return AppError("internal_error", "服务器内部错误，请稍后重试。", 500, detail=text)
