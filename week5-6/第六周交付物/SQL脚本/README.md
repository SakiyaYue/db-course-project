# 第六周 SQL 执行入口

所有文件可直接在 SSMS 中完整执行。`migration.sql` 内含完整模块定义，`regression.sql` 内含原有及新增测试，不需要另行执行模块、测试片段或构建脚本。

脚本按用途分为两个文件夹：`数据库迁移脚本/` 用于创建副本和升级结构，`数据库测试脚本/` 用于迁移前后的核验、回归及数据对照。回滚核验属于测试脚本，但需要在默认及故障演练后、正式提交前执行。

## 数据库迁移脚本

| 文件 | 执行数据库与初始状态 | 用途 |
| --- | --- | --- |
| [work-copy.sql](数据库迁移脚本/work-copy.sql) | 脚本切换到 master；TeabarDB 为完整 v0.1，工作库尚不存在 | COPY_ONLY 备份、校验并还原副本；Execute 默认 0，仅输出计划 |
| [migration.sql](数据库迁移脚本/migration.sql) | TeabarDB_Phase2_Work，完整 v0.1，dbo，无外层事务 | 三种模式的结构迁移；默认 0/0，演练后回滚 |

## 数据库测试脚本

| 文件 | 执行数据库与初始状态 | 用途 |
| --- | --- | --- |
| [verify-rollback.sql](数据库测试脚本/verify-rollback.sql) | 工作库，默认或故障演练已回滚 | 核验原结构、旧核心过程和基准行数，输出表哈希 |
| [regression.sql](数据库测试脚本/regression.sql) | 工作库，已正式提交 v1.0，dbo，无外层事务 | 184 项约束、业务、权限、新功能及清理检查 |
| [v1.0-object-capture.sql](数据库测试脚本/v1.0-object-capture.sql) | 工作库，已正式提交 v1.0 | 采集表、列、键、约束、索引、模块、参数和授权 |
| [key-query-compare.sql](数据库测试脚本/key-query-compare.sql) | 工作库，已正式提交 v1.0；源库存在 | 对照 10 项业务指标 |
| [business-query-compare.sql](数据库测试脚本/business-query-compare.sql) | 工作库，完整 v0.1 或迁移后 v1.0；源库存在 | 补充逐订单明细、逐商品销量与全部原料库存对照 |
| [source-integrity.sql](数据库测试脚本/source-integrity.sql) | TeabarDB，完整冻结 v0.1 | 只读采集源库数据和元数据指纹 |

## 三种迁移模式

| CommitMigration | InjectFailure | 预期结果 |
| --- | --- | --- |
| 0 | 0 | DRY_RUN_ROLLED_BACK_TO_V0.1 |
| 0 | 1 | 主动错误 52809，MIGRATION_FAILED_ROLLED_BACK |
| 1 | 0 | COMMITTED_V1.0 |

直接修改运行文件中的两个声明，每次完整执行。默认及故障演练后执行回滚核验，再进入下一阶段。正式提交后执行对象采集、完整回归和业务对照。

## 执行顺序

以下路径相对于本目录：

```text
数据库迁移脚本/work-copy.sql
→ 数据库迁移脚本/migration.sql：0/0 默认演练
→ 数据库测试脚本/verify-rollback.sql
→ 数据库迁移脚本/migration.sql：0/1 故障演练
→ 数据库测试脚本/verify-rollback.sql
→ 数据库迁移脚本/migration.sql：1/0 正式提交
→ 数据库测试脚本/v1.0-object-capture.sql
→ 数据库测试脚本/regression.sql
→ 数据库测试脚本/key-query-compare.sql
```

`数据库测试脚本/source-integrity.sql` 可在复制操作前后采集冻结源库指纹；`数据库测试脚本/business-query-compare.sql` 可在工作副本迁移前后保存详细业务对照。

提交版本将复制及迁移开关恢复为计划/演练默认值，业务 SQL 与本人实操版本一致。详细说明见[迁移与恢复说明](../迁移与恢复说明.md)，本次结果见[结果与截图索引](../迁移前后结果与已知限制.md)。
