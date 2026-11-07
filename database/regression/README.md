# 数据库回归脚本

2026-11-07：**独立副本TeabarDB_Phase2_Work实测184/184通过，退出码0。** 本次[完整回归日志](../../results/phase2/migration/06-regression.txt)重新执行原44+84项和新增53项，不仅引用旧基线证据。

## 执行入口

| 文件 | 使用时机与作用 |
| --- | --- |
| [work-copy.sql](work-copy.sql) | 默认只打印计划；明确开启后 COPY_ONLY 备份、校验并还原为新工作库 |
| [verify-rollback.sql](verify-rollback.sql) | 演练/故障回滚后只读核验源对象、核心定义、行数并输出表哈希 |
| [regression.sql](regression.sql) | 工作副本提交 v1.0 后完整执行，已嵌入旧用例和新增测试 |
| [validate-scripts.ps1](validate-scripts.ps1) | 本地 ScriptDom 语法检查，不连接数据库 |

执行顺序、日志和失败处理见[迁移与恢复说明](../../docs/phase2/06-normalization/迁移与恢复说明.md)。回归只针对冻结样例的独立、无并发写入的工作库。

## 实测覆盖：184/184 项

| 套件 | 项数 | 内容 |
| --- | ---: | --- |
| legacy-constraint | 44 | 原主码、唯一、外键、CHECK、合法写入等正反例 |
| legacy-role | 84 | 原角色、本人隔离、状态、积分、退款返库和配置业务 |
| v1.0-new | 53 | JSON 正反例、逐明细零消耗、无部分写入、认证上下文及受限入口 |
| structure / baseline / cleanup | 3 | 目标对象、232 行和3单5杯46元、数据与安全配置恢复 |

四组均全部通过。新例含单条零消耗、正常与零消耗混单、原TVP同样拒绝、库存不足回滚、字段/类型/长度/重复/引用校验、停用账号、旧会话、额外角色、直接授权、架构所有权及身份切换。

52个新增用例与夹具在一个事务内执行，逐例保存点、最后整体回滚。禁止身份切换的最后一例会使外层事务失效，故在回滚后无显式事务执行；必要时临时创建角色为空的入口用户，用后删除。结果汇入临时表，完整入口比较17表行数/全行哈希及用户、角色、授权、架构哈希，均已恢复。WebAccount的IDENTITY可能留正常编号间隙，核验不含计数器。

新增只读证据入口：[source-integrity.sql](source-integrity.sql)检查冻结源库操作前后指纹，[key-query-compare.sql](key-query-compare.sql)比较源库/副本10项关键数值。它们不写持久表。

## 维护方式

1. 修改 [regression-body.sql](regression-body.sql) 或 [v1.0-new-tests.sql](v1.0-new-tests.sql)。
2. 仓库根目录运行 `python database\migrations\v0.1-to-v1.0\build-scripts.py`。
3. 运行 `pwsh -File database\regression\validate-scripts.ps1`，再经授权做副本实测。

[legacy-constraint-tests.sql](legacy-constraint-tests.sql) 和 [legacy-role-tests.sql](legacy-role-tests.sql) 只提取冻结原件的测试段，加入结果汇总钩子；完整入口自动嵌入。它们依赖入口创建的临时结果表，不单独执行。**不要在 v1.0 上重跑根目录 constraint.sql 或 role.sql：安装逻辑可能覆盖已升级过程。**

旧只读入口保留：[v0.1-baseline-capture.sql](v0.1-baseline-capture.sql)、[current-database-audit.sql](current-database-audit.sql)。前者仅适用于完整 v0.1，后者可采集不完整安装。提交 v1.0 后按目标清单验收，不能继续要求16表。
