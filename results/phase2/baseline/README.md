# 第二阶段基线证据目录

本目录保存第 4 轮数据库重建和验证产生的可提交证据。2026-11-06 已在用户明确授权下通过 `sqlcmd` 删除旧 `TeabarDB`，并按仓库脚本完整重建 v0.1。

当前有效证据：

- `01-db-creation.txt`：删除旧库、重建数据库和 15 张基础表；
- `02-seed-data.txt`：15 张表、232 行样例装载成功；
- `03-constraint-validation.txt`：44/44 完整性用例通过；
- `04-role-validation.txt`：4 类角色、6 个演示用户、身份/API 安装及 84/84 用例通过；
- `05-view-installation.txt`：13 个正式视图安装和查询结果；
- `06-query-before-crud.txt`、`08-query-after-crud.txt`：Q01—Q18 输出完全相同；
- `07-crud-rollback.txt`：CRUD 演示成功并回滚；
- `v0.1-baseline-capture.txt`：完整对象、约束、权限、数据和查询基线；
- `current-database-audit.txt`：重建后的当前数据库审计；
- `当前数据库审计结论.md`：最终冻结结论；
- `SSMS执行说明.md`：如后续在安全副本安装完整 v0.1 时使用的执行说明。

本轮所有 `sqlcmd` 步骤退出码均为 0；44/44、84/84、对象数量和关键数据结果均有实际输出，不再仅引用第一阶段历史记录。

建议按以下结构命名：

```text
environment/       SQL Server版本、兼容级别、实例与执行信息
objects/           表、列、约束、视图、过程、类型、角色和用户
data/              表行数与关键样例值
constraint/        44项完整性验证明细与汇总
role/              84项角色/业务验证及代表性越权结果
queries/           订单金额、经营统计、库存、积分等基准
recovery/          CRUD回滚和演示恢复结果
```

每份证据应能对应到[关键查询基准](../../../docs/phase2/00-baseline/关键查询基准.md)中的检查项，并记录执行日期、执行人、脚本提交和实际结果。真实连接密码、服务器秘密和个人敏感信息不得进入仓库。

第六周迁移前请先阅读 [SSMS 执行说明](SSMS执行说明.md)，从当前冻结 v0.1 建立工作副本，并在[基线复现记录](../../../docs/phase2/00-baseline/基线复现记录.md)中追加迁移环境和回归结果。
