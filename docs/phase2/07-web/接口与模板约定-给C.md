# 接口与模板约定（给组员 C）

> 2026-11-10 补充：9 类管理查询与写入使用[管理维护接口-给C](管理维护接口-给C.md)中的最新契约；原有 `/api/admin/employees` GET 返回格式保持兼容，并新增 POST 和详情查询。

> 2026-11-07补充优先于旧表：匿名GET /menu、/menu/<product_id>、/api/menu可用；下单仍需购买账号。HTML结算字段为items_json（多商品数组）、payment_succeeded（true/false）、request_token（20—100位URLsafe），保留旧单商品兼容输入。错误时同页回填，保持实际4xx/5xx状态。API可用Idempotency-Key请求头或request_token字段，网络重试必须复用同键；冲突request_conflict=409，繁忙request_busy=503。每个响应带X-Request-ID，healthz仅返回status。C最终合并仍待外部验收。


日期：2026-11-07。状态：HTML 路由与 `/api` JSON 已实现并通过 31 项 pytest；B 的模板是可运行的参考实现，C 可以在**不改字段名、不改角色规则、不改错误码**的前提下替换视觉层。数据库对象与字段以 [v1.0 接口约定](../06-normalization/v1.0数据库接口约定.md) 为准。

## 1. 角色与登录跳转

| app_role | 说明 | 登录后首页 |
| --- | --- | --- |
| customer | 游客 | `/menu` |
| member | 会员 | `/menu` |
| clerk | 店员 | `/work/orders` |
| manager | 店长 | `/admin/stats` |

未登录访问受保护页面 → 302 到 `/login?next=...`；未登录调用 `/api/*` → 401 JSON。角色不符：HTML 重定向回 `/menu` 或来源页并 flash 提示；`/api` → 403 JSON。前端隐藏按钮不能替代后端校验，直接请求同样被拒。

## 2. HTML 页面

| 方法 | 路径 | 允许角色 | 模板 | 模板上下文 |
| --- | --- | --- | --- | --- |
| GET | `/login` | 匿名 | `login.html` | `login_name`（回填） |
| POST | `/login` | 匿名 | 表单：`login_name, password, next?` | 失败 401 并 flash |
| POST | `/logout` | 已登录 | 表单：`csrf_token` | 302 到登录页 |
| GET | `/` | 已登录 | — | 按角色重定向 |
| GET | `/menu` | 已登录 | `menu.html` | `catalog`（见 §4）、`role` |
| GET | `/orders/new` | customer/member | `checkout.html` | `catalog` |
| POST | `/orders` | customer/member | 表单：`product_id, quantity, spec_id`（可重复）, `addon_id`（可重复）, `csrf_token` | 成功 flash + 302 到 `/my/orders`；失败 flash + 302 回 `/orders/new`（状态码为错误码） |
| GET | `/my/orders` | customer/member | `my_orders.html` | `orders`（列表）、`member`（会员资料或 None） |
| GET | `/my/orders/<order_id>` | customer/member | `order_detail.html` | `order`（含 `items/specs/addons`） |
| POST | `/my/orders/<order_id>/refund` | customer/member | 表单：`csrf_token` | 成功 flash + 302 回 `/my/orders` |
| GET | `/work/orders` | clerk/manager | `work_orders.html` | `orders`、`member`（按手机号查询结果或 None）、`role`、`phone` |
| GET | `/work/orders/<order_id>` | clerk/manager | `work_order_detail.html` | `order`（含 `items/specs/addons/consumption`） |
| POST | `/work/orders/<order_id>/advance` | clerk/manager | 表单：`next_status, csrf_token` | 成功/失败 flash + 302 回详情 |
| GET | `/work/team` | clerk/manager | `work_team.html` | `rows` |
| POST | `/work/members` | clerk/manager | 表单：`member_id, name, phone, csrf_token` | flash + 302 回 `/work/orders?phone=...` |
| GET | `/admin/stats` | manager | `admin_stats.html` | `daily`、`products` |
| GET | `/admin/stock` | manager | `admin_stock.html` | `ingredients` |
| POST | `/admin/stock` | manager | 表单：`ingredient_id, operation`（补库/盘点）, `amount, csrf_token` | flash + 302 回 `/admin/stock` |
| GET | `/admin/employees` | manager | `admin_employees.html` | `rows` |
| GET | `/admin/members` | manager | `admin_members.html` | `member`、`phone` |
| POST | `/admin/members` | manager | 表单：`member_id, name, phone, csrf_token` | flash + 302 回 `/admin/members?phone=...` |
| GET | `/healthz` | 匿名 | JSON | `{status,database,login}` |

所有 POST 必须带 `csrf_token`（表单字段）或 `X-CSRF-Token` 头，否则 400 `csrf_failed`。`base.html` 已提供 `csrf_token()` 与 `auth`（当前会话 `login_name/app_role/principal_name`）。

## 3. JSON API（`/api`）

统一错误响应：`{"error": {"code": "...", "message": "..."}}`，HTTP 状态见 §5。

| 方法 | 路径 | 角色 | 请求 | 响应 |
| --- | --- | --- | --- | --- |
| GET | `/api/csrf` | 任意 | — | `{"csrf_token"}` |
| GET | `/api/me` | 已登录 | — | `{login_name, account_id, app_role, principal_name, session_version, member}` |
| GET | `/api/menu` | 已登录 | — | `{products, addons}` |
| GET | `/api/my/orders` | customer/member | — | `{orders: [{order_id, order_time, total_amount, status}]}` |
| GET | `/api/my/orders/<id>` | customer/member | — | 订单详情：`order_id, order_time, total_amount, status, items, specs, addons` |
| POST | `/api/orders` | customer/member | 见 §4 | 201 `{order_id, total_amount, status}` |
| POST | `/api/my/orders/<id>/refund` | customer/member | — | `{order_id, status}`（`已取消`） |
| GET | `/api/work/orders` | clerk/manager | — | `{orders: [{order_id, member_id, order_time, total_amount, status}]}` |
| GET | `/api/work/orders/<id>` | clerk/manager | — | 工作详情 + `consumption` |
| POST | `/api/work/orders/<id>/advance` | clerk/manager | `{"next_status": "制作中"}` | `{order_id, status}` |
| GET | `/api/work/team` | clerk/manager | — | `{team: [...]}` |
| GET | `/api/work/members?phone=` | clerk/manager | — | `{member_id, name, phone, points}` 或 404 `member_not_found` |
| POST | `/api/work/members` | clerk/manager | `{member_id, name, phone}` | `{saved: true}` |
| GET | `/api/admin/stats` | manager | — | `{daily: [...], products: [...]}` |
| GET | `/api/admin/stock` | manager | — | `{ingredients: [...]}` |
| POST | `/api/admin/stock` | manager | `{ingredient_id, operation, amount}` | `{ingredient_id, stock, unit}` |
| GET | `/api/admin/employees` | manager | — | `{employees: [...]}` |
| GET | `/api/admin/members?phone=` | manager | — | 会员或 404 |
| GET | `/api/admin/members` + POST | manager | POST `{member_id, name, phone}` | `{saved: true}`（POST 同 `/api/work/members`，走同一 Service） |

## 4. 字段与格式

### 4.1 `catalog` / `GET /api/menu`

```json
{
  "products": [
    {
      "product_id": "P001",
      "product_name": "珍珠奶茶",
      "base_price": "6.00",
      "description": "...",
      "spec_types": {
        "杯型": [{"spec_id": "S007", "spec_name": "中杯", "price_delta": "0.00"}],
        "温度": [{"spec_id": "S004", "spec_name": "常温", "price_delta": "0.00"}],
        "糖度": [{"spec_id": "S001", "spec_name": "全糖", "price_delta": "0.00"}]
      }
    }
  ],
  "addons": [{"addon_id": "A001", "addon_name": "珍珠", "price": "2.00"}]
}
```

`spec_types` 的键是规格类型（杯型/温度/糖度），每类必须选一项；同一类型重复会被数据库拒绝（52008），漏选返回 `spec_missing`。

### 4.2 POST `/api/orders` 请求体

```json
{
  "items": [
    {"product_id": "P001", "quantity": 1, "specs": ["S007", "S004", "S001"], "addons": ["A001"]}
  ],
  "payment_succeeded": true
}
```

- 单笔最多 20 条明细，每件数量 1–99；`items` 非空；`specs/addons` 为数组且同一明细内不得重复。
- `payment_succeeded` 为 `false` 时数据库抛 52001，不创建订单（HTTP 402 `payment_failed`）。
- 应用生成 `O`/`I` 开头的 10 位业务编号，客户端不要自行拼号。

### 4.3 金额、时间与状态

- 金额统一为两位小数字符串（如 `"6.00"`），小数运算与总额以数据库为准。
- 时间统一为 `"YYYY-MM-DD HH:MM:SS"` 字符串。
- 订单状态：`排队中 → 制作中 → 待取餐 → 已完成`；`排队中` 可退款，退款后为 `已取消`。重复完成/退款被拒。
- `vw_DailySales.sale_date` 为 `"YYYY-MM-DD"`。

## 5. 错误码（前端提示建议）

| code | HTTP | 建议提示 |
| --- | --- | --- |
| `auth_required` | 401 | 请先登录 / 跳转登录页 |
| `forbidden` | 403 | 当前角色无权执行此操作 |
| `csrf_failed` | 400 | 页面已过期，请刷新后重试 |
| `invalid_items` / `invalid_quantity` / `invalid_selection` / `invalid_payment` | 400 | 表单校验提示，保留用户输入 |
| `product_unavailable` | 409 | 商品已下架，刷新菜单 |
| `spec_invalid` / `spec_duplicate` / `spec_missing` | 400 | 规格选择不完整或非法 |
| `stock_insufficient` | 409 | 库存不足，整单未提交 |
| `zero_consumption` | 409 | 该商品无原料消耗，无法下单 |
| `status_transition` | 409 | 订单状态已变化，刷新后重试 |
| `refund_other` | 403 | 只能退本人订单 |
| `refund_state` | 409 | 订单不是排队中或已退款 |
| `session_invalid` | 401 | 登录已失效，重新登录 |
| `order_not_found` | 404 | 订单不存在或不属于当前账号 |
| `member_not_found` | 404 | 未找到会员 |
| `invalid_phone` / `invalid_name` / `invalid_id` | 400 | 输入格式提示 |
| `duplicate_key` / `constraint_violation` | 409 | 数据冲突，刷新后重试 |
| `permission_denied` | 403 | 无权访问 |
| `database_error` | 503 | 数据库暂不可用，稍后重试 |
| `internal_error` | 500 | 服务器内部错误 |

实际响应中的 `message` 已是可直接展示的中文提示；前端不要显示 SQL、对象名或堆栈。

## 6. 模板变量契约

B 的模板已按上表实现，C 替换模板时请保留变量名与含义：

- `base.html`：`auth`（None 或会话字典）、`csrf_token()`、`get_flashed_messages()`、`url_for` 路由名（`menu.menu`、`orders.my_orders`、`work.orders`、`admin.stats`、`auth.logout` 等）。
- `menu.html`：`catalog.products[*].{product_id,product_name,base_price,description,spec_types}`、`catalog.addons`。
- `checkout.html`：`catalog` 同时以内嵌 JSON 交给 JS；表单提交字段见 §2。
- `my_orders.html`：`orders`、`member.points`；退款表单仅对 `status == '排队中'` 显示。
- `order_detail.html` / `work_order_detail.html`：`order` 及子数组；详情页的推进按钮目标状态映射固定。
- `admin_stats.html`：`daily`、`products`；`admin_stock.html`：`ingredients`；`admin_employees.html`：`rows`；`admin_members.html`：`member`、`phone`。

## 7. C 联调检查清单

1. 六种演示账号均可登录，按角色跳转正确；退出后受保护页面回到登录。
2. 游客 A/B 订单互不可见；退款只能退本人排队中订单。
3. 漏选规格、重复规格、库存不足都有友好提示且不产生订单。
4. 店员能推进三段状态，完成会员订单后积分增加；店员看不到店长统计。
5. 店长补库/盘点、查会员、看统计正常；顾客直接请求 `/api/admin/*` 返回 403。
6. 所有 POST 携带 CSRF；删除或伪造 token 返回 `csrf_failed`。
7. 会话版本被管理员递增后，旧页面下一次请求要求重新登录。
