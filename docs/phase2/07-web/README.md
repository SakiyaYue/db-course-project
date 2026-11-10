# Phase2 B Web 后端

2026-11-10 已补齐员工退款、店长历史订单、管理侧会员写入、会员校验和本人消耗快照，见[订单与会员补充接口](订单与会员补充接口-给C.md)。已有数据库须重新运行账号初始化以安装新视图，不需重置密码。

2026-11-10 新增 9 类管理列表、详情和保存接口，契约见[管理维护接口-给C](管理维护接口-给C.md)。此补充不表示 C 页面或最终联调已经完成。

Flask + Jinja2 + pyodbc；登录、会话校验、匿名菜单与商品详情、多商品下单、本人订单/退款、店员状态推进、首次完成积分、店长统计/补库及会员资料维护已实现。

本轮验收入口：[B 后端修复与验收](B后端修复与验收-2026-11-07.md)。当前限制见[已知限制](已知限制与后续.md)，给 C 的接口见[接口与模板约定](接口与模板约定-给C.md)。不将参考模板交付等同于 C 最终页面验收。

## 空环境复现

使用已安装 ODBC Driver 18 的 Python 环境：

```powershell
python -m pip install -r requirements.txt
# 管理员仅在目标库尚不存在时运行；脚本拒绝覆盖，不删除源库。
python database/admin/prepare_test_database.py --database TeabarDB_Phase2_Test
python database/admin/prepare_test_database.py --database TeabarDB_Phase2_Work
Copy-Item .env.example .env
# 在 .env 中填写随机 TEABAR_SECRET_KEY；演示建议 TEABAR_ENV=demo
python run.py
```

如果独立库已经完成 v1.0 迁移，只需运行 `python database/admin/init_web_accounts.py --database TeabarDB_Phase2_Work`。初始化自动安装 `web_backend_extensions.sql`，包含匿名只读身份、幂等请求回执和字符类兼容修复；`--dry-run` 回滚全部初始化与扩展，`--reset-passwords` 才重置已有演示密码。

`prepare_test_database.py` 仅接收固定 Work/Test 库名，先建新库，从根脚本截取建表部分，适配目标库守卫并装载数据，执行 A 的 v1.0 迁移及 184 回归，随后安装 B 对象。新库存在时直接拒绝，不运行 DROP。冻结 `TeabarDB` 仅采集只读聚合指纹。

## 配置与启动

环境变量为 `TEABAR_DB_DRIVER/SERVER/NAME/TRUSTED/USER/PASSWORD`、`TEABAR_SECRET_KEY`、`TEABAR_SESSION_COOKIE_SECURE`、`TEABAR_ENV`。不提交真实 `.env`；示例无固定密钥，开发模式缺失密钥时仅生成本进程随机密钥（重启后会话失效）；demo/production 缺密钥直接拒绝。默认关闭 debug。

默认地址 `http://127.0.0.1:5000`；匿名可看 `/menu`、`/menu/<product_id>` 与 `/api/menu`，下单需要购买账号。`/healthz` 只返回健康状态。演示账号见[初始化说明](演示账号与初始化.md)。

## 测试

```powershell
python -m pytest -q
python database/admin/verify_web_permissions.py --database TeabarDB_Phase2_Test
```

pytest 默认且仅针对固定独立测试库；即使设置 `TEABAR_TEST_DB` 也仅允许该固定库名，其他目标直接拒绝。测试会保留测试订单、快照与幂等回执，测试库不可当作干净演示数据。当前配置原生 SQL Server 只支持 Windows 认证：应用演示仍以开发者集成身份连接；26 项权限探针是模拟受限入口与业务身份，不能当作真实受限登录的连接证据。

目录：`app/routes` HTTP、`app/services` 输入/授权、`app/dao` SQL 与结果、`app/db.py` 身份连接生命周期、`app/templates` 可替换参考界面；管理员脚本在 `database/admin`，新结果在 `results/phase2/web/2026-11-07-fixes`。
