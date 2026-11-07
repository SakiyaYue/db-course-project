# 第二阶段 Web 应用验证证据（组员 B）

采集时间：2026-11-07。环境：Windows + SQL Server 2025（17.0.1000.7）、Python 3.12.16（conda 环境 `DatabaseLab`）、Flask 3.1.3、pyodbc 5.4.0、pytest 9.2.0。

| 文件 | 内容 | 结果 |
| --- | --- | --- |
| `pytest.txt` | `python -m pytest -q`，连接独立库 `TeabarDB_Phase2_Test` | `31 passed` |
| `migration.txt` | 工作库重置后，从 v0.1 备份还原并对 `TeabarDB_Phase2_Work` 执行 `@CommitMigration=1` 的 v1.0 迁移 | `COMMITTED_V1.0 TeabarDB_Phase2_Work 17 81 19`，16 张原表行数/哈希前后一致 |
| `regression.txt` | 迁移后对工作库执行 `database/regression/regression.sql` | `REGRESSION_PASSED_TEST_DATA_ROLLED_BACK 184`（baseline 1、cleanup 1、legacy-constraint 44、legacy-role 84、structure 1、v1.0-new 53，失败 0） |
| `init-web-accounts.txt` | 重跑 `database/admin/init_web_accounts.py --database TeabarDB_Phase2_Work` | 6 个演示账号校验 OK，`EXECUTE AS web_guest_a` 自检 OK，幂等提交 |
| `smoke-readonly.txt` | Flask `test_client` 只读冒烟：健康检查、匿名重定向、登录、菜单、`/api/me`、本人订单、退出 | `SMOKE_READONLY_PASSED` |

## 工作库重置记录

为清除联调阶段遗留的冒烟订单，工作库按以下步骤重置：

1. `DROP DATABASE TeabarDB_Phase2_Work`；
2. 从 `D:\SQLBackups\TeabarDB_v01_46B4EC180A924F11B8AED298E0278A33.bak` 还原（`MOVE` 到 `D:\SQLData\TeabarDB_Phase2_Work.mdf` / `D:\SQLLogs\TeabarDB_Phase2_Work.ldf`）；
3. 执行 `@CommitMigration=1` 的 `migration.sql`（`COMMITTED_V1.0`）；
4. 执行 `regression.sql`（184/184，测试数据已回滚）；
5. 执行 `init_web_accounts.py` 重建 Web 角色、用户、绑定与演示账号。

重置后：17 表 / 81 列 / 19 FK、样例 5 张订单（232 行业务数据）、`teabar_auth.WebAccount` 6 行（`account_id` 7–12，自增号随历史变化）。测试库 `TeabarDB_Phase2_Test` 保持独立，pytest 不写工作库。

## 复现命令

```powershell
# 测试（测试库）
python -m pytest -q

# 工作库 184 项回归
sqlcmd -S localhost -E -C -b -d TeabarDB_Phase2_Work -f 65001 `
  -i database\regression\regression.sql -o results\phase2\web\regression.txt

# 只读冒烟（需先启动应用或按 smoke-readonly 中的 test_client 方式运行）
python run.py
```
