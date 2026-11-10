# 管理维护接口（2026-11-10）

本文为新增 9 类管理资源的有效契约。旧统计、补库、会员接口继续使用原约定。全部接口仅允许已登录店长；每次请求复核会话并切换到 `web_manager`，Service 同时验证可信角色。数据库结构及过程未修改。

## 路由和字段

所有路径以 `/api/admin/` 开头，每种资源均有 GET 列表、GET 主键详情和 POST 保存。POST 为按主键新增或完整更新，不是局部 PATCH；调用已有 `teabar_api.usp_Save*` 过程。除说明的可选字段外，表中字段均必填。

| 资源路径 | 详情路径主键顺序 | POST 字段（也是过程参数顺序） |
| --- | --- | --- |
| `products` | `product_id` | `product_id, product_name, base_price, status, description` |
| `ingredients` | `ingredient_id` | `ingredient_id, ingredient_name, unit, status` |
| `employees` | `employee_id` | `employee_id, name, status, salary, role` |
| `specifications` | `spec_id` | `spec_id, spec_type, spec_name` |
| `product-specifications` | `product_id/spec_id` | `product_id, spec_id, price_delta, status` |
| `recipes` | `product_id/ingredient_id` | `product_id, ingredient_id, base_amount, remove` |
| `specification-ingredients` | `product_id/spec_id/ingredient_id` | `product_id, spec_id, ingredient_id, factor, remove` |
| `addons` | `addon_id` | `addon_id, addon_name, price, ingredient_id, extra_amount, status` |
| `duty-rosters` | `duty_id` | `duty_id, employee_id, start_time, end_time` |

示例：`GET /api/admin/product-specifications/P001/S001`；不存在返回 404 `record_not_found`。主键段数不符返回 400 `invalid_key`。

列表返回 `{ "products": [...] }` 等；复合资源名用下划线作为 JSON 键，例如 `product_specifications`、`specification_ingredients`、`duty_rosters`。列表按主键排序，包含全部状态；没有分页，适用于当前课程数据规模。每条记录包含表中保存字段（不含 `remove`），原料额外返回只读 `stock`。金额、数量和系数以两位小数字符串返回；时间以 `YYYY-MM-DDTHH:MM:SS` 返回。员工列表保留原来的 `employees` 包装和字段。

列表支持该资源的所有 `*_id` 字段、`status`（存在时）、`spec_type`（存在时）等值过滤，多个条件按 AND 组合。例如：

```text
GET /api/admin/products?status=下架
GET /api/admin/recipes?product_id=P001
GET /api/admin/specification-ingredients?product_id=P001&spec_id=S001
GET /api/admin/duty-rosters?employee_id=E001
```

未知过滤字段或重复参数返回 400 `invalid_filter`。不传过滤条件返回全部记录，C 可以使用各列表构建名称下拉框和关联编辑表单。

## 写入约定

请求必须为 JSON 对象，携带 `Content-Type: application/json` 和 `X-CSRF-Token`（先 GET `/api/csrf`）。未知字段、只读字段（例如 `stock`）和错误类型被拒绝；不能通过此接口写历史订单或库存快照。

```json
{
  "product_id": "PNEW",
  "product_name": "新品",
  "base_price": "12.50",
  "status": "下架",
  "description": "新品说明"
}
```

保存成功统一 HTTP 200：`{"saved":true,"key":{"product_id":"PNEW"}}`，不区分新增和修改。保存后重新 GET 列表或详情读取数据库状态。

- 编号：1–10 位 ASCII 字母、数字、下划线或短横线。
- 名称：商品、原料、员工、加料最多 50 个 UTF-16 单位，规格名称最多 20；不得为空。描述可省略或为 null，最多 200；省略表示清空，不表示保留旧值。
- 金额/用量：建议以十进制字符串传入，最多两位小数，必须有限；DECIMAL(10,2) 最大 `99999999.99`。价格、工资非负；配方基础量和加料用量严格大于零；规格差价可为负。`factor` 范围 `0`–`999.99`。布尔值不能充当数字。
- 商品状态：`在售/下架`；原料及加料：`可用/缺货`；员工：`在职/离职`；商品规格配置：`可用/停用`。
- 原料单位：`g/ml/个`；员工岗位：`店员/店长`；规格类型：`糖度/温度/杯型`。
- 排班时间必须为无时区、精确到秒的本地日期时间，如 `2099-01-01T08:00:00`，也接受日期和时间间使用空格。开始早于结束；同一员工重叠检查由数据库完成。前端 datetime-local 若只返回分钟，提交前补 `:00`。
- 配方和系数的 `remove` 可省略（默认 false），必须是 JSON 布尔值。移除时传主键和 `remove:true`，用量/系数省略或为 null；响应附加 `removed:true`。其他资源不提供物理删除接口；排班当前只支持新增/修改。

## 配置流程和副作用

1. 新商品先以“下架”保存，准备原料与规格字典。
2. 配置基础配方，然后建立“停用”的商品规格关联。
3. 配置规格原料系数，完成后逐项启用商品规格，再上架商品。
4. 修改基础配方会停用该商品全部规格配置，响应附加 `product_specifications_disabled:true`；页面应提示重新审查并启用。移除配方原料还会删除对应系数规则。
5. 修改/移除原料系数前，须先停用对应商品规格。涉及计件原料的组合必须产生整数用量，数据库会拒绝不合法组合。
6. 原料库存继续用原有 `/api/admin/stock` 补库/盘点接口。修改员工岗位或离职状态仅维护业务资料，不会自动修改 Web 账号或数据库授权。

## 错误

沿用 `{"error":{"code":"...","message":"..."}}`；不会向浏览器暴露 SQL 或连接细节。

| HTTP | code | 含义 |
| --- | --- | --- |
| 400 | `invalid_payload / invalid_field / invalid_filter / invalid_key` | 输入对象、字段、过滤或主键错误 |
| 400 | `csrf_failed / invalid_time_range` | CSRF 或时间区间错误 |
| 401 / 403 | `auth_required / forbidden` | 未登录或非店长 |
| 404 | `record_not_found` | 查询对象不存在 |
| 409 | `product_configuration_incomplete / recipe_required` | 上架或规格启用条件不足 |
| 409 | `ingredient_unit_locked / specification_type_locked` | 已引用对象不能更改单位/规格类型 |
| 409 | `specification_must_be_disabled / fractional_piece_consumption` | 先停用规格或修正计件用量 |
| 409 | `employee_inactive / duty_overlap / product_not_found` | 员工、排班或商品关联冲突 |
| 409 | `constraint_violation / duplicate_key` | 外键、CHECK 或唯一约束拒绝 |
| 503 | `transaction_failed` | 事务冲突/锁超时，可刷新后重试 |

本批范围是 9 类管理查询/写入。员工协助退款、店长历史订单等已在后续补齐，见[订单与会员补充接口](订单与会员补充接口-给C.md)。C 的最终管理页面仍待联调。

## 验证命令

使用 `conda activate db-crs-prj` 后运行：

```powershell
python -m pytest -q tests/test_maintenance_unit.py tests/test_backend_unit.py tests/test_checkout_unit.py tests/test_observability_unit.py -p no:cacheprovider
python -m pytest -q tests/test_maintenance_integration.py -p no:cacheprovider
```

集成测试仅连接固定 `TeabarDB_Phase2_Test`，在外层事务中以 `web_manager` 身份执行 9 类新增/更新、查询、配置移除、约束失败和副作用检查，最终回滚并确认测试商品不存在。
