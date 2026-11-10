# 订单与会员补充接口（2026-11-10）

本契约补齐 C 清单中的员工退款、店长历史订单、会员写入及本人消耗查询。与[管理维护接口](管理维护接口-给C.md)一起使用。后端接口完成不等于 C 最终页面已验收。

## 1. 员工协助退款

- `POST /api/work/orders/<order_id>/refund`：clerk/manager；无需请求体，必须携带 `X-CSRF-Token`。
- `POST /work/orders/<order_id>/refund`：同样的角色和规则，支持表单 `csrf_token`；成功 302 跳转工作订单详情。参考页面已增加“协助退款”按钮。
- API 成功 HTTP 200：`{"order_id":"...","status":"已取消"}`。
- 仅排队中的订单允许退款；数据库按付款时消耗快照返库。已取消、制作中、待取餐及已完成均拒绝，不会重复返库。
- 原有顾客本人退款入口仍仅允许 customer/member。员工入口不会放宽购买者权限。
- 错误：`invalid_id` 400、`forbidden` 403、`order_out_of_scope` 403、`refund_state` 409、`consumption_snapshot_missing` 409、`refund_ingredient_missing` 409。CSRF、会话和数据库错误沿用原契约。

## 2. 店长完整历史订单

`GET /api/admin/orders` 和 `GET /api/admin/orders/<order_id>` 仅 manager 可访问。与员工工作台独立，支持任意日期及所有五种状态，不改变员工“当天或未完成订单”的范围。

列表可选参数：

| 参数 | 约定 |
| --- | --- |
| `order_id`、`member_id` | 精确匹配，1–10 位 ASCII 字母、数字、下划线、短横线 |
| `status` | 排队中、制作中、待取餐、已完成、已取消 |
| `date_from`、`date_to` | `YYYY-MM-DD`，包含开始和结束当天；数据库本地时间，不做时区转换；结束日期早于 9999-12-31 |
| `page` | 默认 1，范围 1–1000000 |
| `page_size` | 默认 20，范围 1–100 |

多个条件按 AND 组合，未知、重复或非法参数返回 400。未选择的筛选项应省略，不发送空字符串。开始日期不得晚于结束日期。

```text
GET /api/admin/orders?date_from=2026-10-01&date_to=2026-10-31&status=已完成&page=1&page_size=20
```

响应：

```json
{"orders":[],"page":1,"page_size":20,"has_more":false}
```

每行字段为 `order_id, member_id, order_time, total_amount, status`。按 `order_time DESC, order_id DESC` 排序，取额外一行计算 `has_more`；无总数。并发新增订单期间，翻页不是固定时间点的数据快照，可刷新第一页重新查询。

详情返回同样的主单字段，并包含：

- `items`：`item_id, order_id, product_id, product_name_snapshot, quantity, base_price_snapshot, unit_price, sub_amount`。
- `specs`：`item_id, spec_type, spec_id, spec_name_snapshot, price_delta_snapshot`。
- `addons`：`item_id, addon_id, addon_name_snapshot, price_snapshot`。
- `consumption`：`item_id, ingredient_id, ingredient_name, unit, amount`。

金额和数量用两位小数字符串，时间为 `YYYY-MM-DDTHH:MM:SS`。价格、商品/规格/加料名称及消耗数量读取成交快照，不按现价、现配方重算。原料名称是当前基础资料标签；单位由既有引用锁定规则保护，数据库没有独立的原料名称快照列。

不存在的订单返回 404 `order_not_found`。新校验错误为 `invalid_filter / invalid_id / invalid_status / invalid_date / invalid_date_range / invalid_pagination`，均 HTTP 400。接口只读，不提供历史订单修改或物理删除。C 可用 API 构建历史列表/详情页面，本轮未新增独立历史 HTML 页面。

## 3. 会员管理写入及校验

补齐 `POST /api/admin/members`（manager），复用 `POST /api/work/members`（clerk/manager）的 Service。两者都要求 CSRF，成功返回 `{"saved":true}`；clerk 不能借管理侧入口操作。

请求：`{"member_id":"M001","name":"姓名","phone":"13800000001"}`。三个字段均应为字符串；编号规则同上，姓名去首尾空白后非空且最多 50 个 UTF-16 单位（常用汉字/ASCII 为一个，补充平面字符通常为两个），手机号去首尾空白后必须匹配 `1[0-9]{10}`。API 不再把数字手机号或对象强制转成字符串。

姓名过长、类型不正确或手机号格式不正确在调用数据库前返回 400 `invalid_name/invalid_phone`。数据库唯一冲突返回 409 `duplicate_key`。保存过程会读完所有结果集后才返回成功，避免漏掉延迟抛出的数据库异常。参考会员表单已同步 maxlength 和手机号 pattern。

## 4. 顾客本人原料消耗

原 `GET /api/my/orders/<order_id>` 响应新增 `consumption`，字段同上；本人 HTML 订单详情已增加展示。仅 customer/member，跨购买者读取仍为 404。

新增数据库视图 `teabar_api.vw_MyConsumption`，通过 `vw_MyOrderItems` 按当前数据库身份绑定过滤，再关联原料消耗快照。购买者只获该视图 SELECT 权限，没有获得原料、订单或快照基表读取权限。即使绕过 Web 直接查询视图，也看不到其他购买者订单。

## 5. 安装和测试

使用 `conda activate db-crs-prj`。已有 v1.0 Work/Test 库运行：

```powershell
python database/admin/init_web_accounts.py --database TeabarDB_Phase2_Test
python database/admin/init_web_accounts.py --database TeabarDB_Phase2_Work
```

初始化现在在同一事务中安装 `order_read_extensions.sql`，支持重复执行；不重置密码。`--dry-run` 回滚包括新增视图及授权在内的全部变更。新建库工具也自动安装此扩展，无须修改冻结的 v0.1 或 A 迁移脚本。新视图是本次代码运行的前置条件。

```powershell
python -m pytest -q tests/test_handoff_gaps_unit.py
python -m pytest -q tests/test_handoff_gaps.py
python -m pytest -q
```

集成测试仅针对固定独立 Test 库；会保留下单/退款等测试订单。测试临时修改的商品价格、订单日期、会员资料会恢复。C 仍需完成最终页面、浏览器交互和截图证据。
