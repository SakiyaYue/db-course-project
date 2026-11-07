# 第二阶段 Web 应用（组员 B）

2026-11-07。状态：**应用已可运行并完成 31 项 pytest 与端到端冒烟验证；真实受限 SQL 登录受本机实例仅 Windows 身份验证的限制，见[已知限制](已知限制与后续.md)。** 数据库侧沿用 [v1.0 接口约定](../06-normalization/v1.0数据库接口约定.md)，本地工作库已验证 184/184 回归。

## 快速开始

```powershell
# 1. 激活带 Flask/pyodbc/pytest 的环境（本机示例）
D:\DevTools\Miniconda3\condabin\conda.bat activate DatabaseLab
Set-Location D:\00_study_file_desktop\grade_3\grade_3_1\01 Principles of Database Systems\lab\db-course-project

# 2. 初始化 Web 角色、无登录用户、身份绑定和演示账号（幂等，可 --dry-run）
python database\admin\init_web_accounts.py --database TeabarDB_Phase2_Work

# 3. 配置连接（复制模板后按本机修改；真实 .env 不提交）
Copy-Item .env.example .env

# 4. 启动
python run.py          # http://127.0.0.1:5000
```

演示账号见[演示账号与初始化](演示账号与初始化.md)。测试使用独立库 `TeabarDB_Phase2_Test`：

```powershell
python -m pytest -q    # 31 passed
```

`TeabarDB_Phase2_Test` 由 v0.1 备份还原并对副本执行 v1.0 迁移得到，初始化方式见[演示账号与初始化](演示账号与初始化.md)。

## 应用结构

```text
run.py                     Flask 入口
app/
├─ __init__.py             应用工厂、蓝图、CSRF、错误处理和 /healthz
├─ config.py               环境变量与 ODBC 连接串
├─ db.py                   连接生命周期与受限身份切换（EXECUTE AS/REVERT）
├─ security.py             会话、CSRF、登录复核、角色门禁
├─ errors.py               统一错误类型与 SQL 错误号映射
├─ dao/                    唯一直接执行 SQL 的层（auth/menu/order/work/admin）
├─ services/               业务规则、输入校验、错误翻译（auth/menu/order/work/admin）
├─ routes/                 HTML 页面 + /api JSON（auth/menu/order/work/admin/api）
├─ templates/              Jinja2 模板（B 的可运行参考实现，供 C 替换）
└─ static/style.css
database/admin/init_web_accounts.py   管理员初始化脚本（不进日常请求路径）
tests/                    pytest：认证、菜单、下单、退款、工作台、统计、库存、积分
requirements.txt、.env.example、pytest.ini
```

分层固定为 Browser → Route → Service → DAO → `teabar_api` 视图/过程 → SQL Server；Route、Service 和模板中不出现 SQL 文本。

## 页面与接口

- 顾客/会员：`/menu`、`/orders/new`、`/my/orders`、`/my/orders/<id>`，以及下单、退款 POST。
- 店员/店长：`/work/orders`、`/work/orders/<id>`、`/work/team`，状态推进与会员登记 POST。
- 店长：`/admin/stats`、`/admin/stock`、`/admin/employees`、`/admin/members`。
- JSON API：`/api/menu`、`/api/me`、`/api/orders`、`/api/my/orders`、`/api/work/*`、`/api/admin/*`，字段与错误码见[接口与模板约定（给 C）](接口与模板约定-给C.md)。

## 关键设计

- **身份**：会话只保存 `account_id/session_version/app_role/principal_name/login_name`；每次请求用 `teabar_auth.usp_GetWebContext` 复核，再 `EXECUTE AS USER web_*` 调用业务对象，`finally REVERT` 并关闭连接。购买者身份由数据库 `PrincipalBinding` 解析，应用不向下单过程传会员/游客编号、单价或角色。
- **参数化**：DAO 全部使用 `?` 占位符；三个 JSON 数组由 `json.dumps` 后绑定到 `teabar_api.usp_PlacePaidOrderJson`，不拼 SQL。
- **事务**：应用连接 `autocommit=True`，下单、退款、状态推进、补库的事务边界在数据库过程内；库存不足等失败整单回滚（测试覆盖）。
- **错误**：`52000/52001/52005/52007/52008/52009/52016/52018/52103/52105/52106/52600–52604/52700` 映射为稳定应用错误码；未知异常统一 500，SQL 堆栈只进日志。
- **Web 安全**：所有修改请求校验 CSRF；会话 Cookie `HttpOnly`、`SameSite=Lax`；会话版本变化立即失效；服务端按角色拒绝越权，不依赖前端隐藏按钮。

## 文档导航

- [后端技术说明](后端技术说明.md)：技术栈、分层、连接与事务、参数化、错误与日志、安全与测试。
- [登录与身份映射](登录与身份映射.md)：WebAccount、哈希、会话复核、`EXECUTE AS` 与角色映射。
- [演示账号与初始化](演示账号与初始化.md)：`init_web_accounts.py` 行为、账号表、测试库准备。
- [接口与模板约定（给 C）](接口与模板约定-给C.md)：页面、JSON API、字段、错误码与模板变量。
- [已知限制与后续](已知限制与后续.md)：A 的约束缺陷、仅 Windows 认证、测试库与清理。
- [给 A 的缺陷反馈](给A的缺陷反馈.md)：`CK_WebAccount_LoginName` 与登录名长度不一致的可复现说明。

验证证据在 `results/phase2/web/`（pytest 输出、迁移到测试库的记录、回归结果）。
