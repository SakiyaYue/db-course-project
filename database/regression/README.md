# 数据库回归工作区

本目录用于第六周的 `regression.sql` 和预期结果说明。回归输入以 [关键查询基准](../../docs/phase2/00-baseline/关键查询基准.md) 为准。

2026-11-06 已通过 `sqlcmd` 完成当前库重建和完整 v0.1 验证。后续第六周迁移回归至少需要覆盖：

- 表行数和关键样例值；
- 订单金额、销量、库存和积分；
- 主外键、合法写入和非法写入；
- 四类角色的正常操作与越权拒绝；
- 退款返库、状态流转和逐明细消耗快照规则。

## 已准备脚本

- [`v0.1-baseline-capture.sql`](v0.1-baseline-capture.sql)：只读采集脚本，不修改持久表、对象或业务数据；用于完整安装后采集环境、对象、约束、行数、关键样例和经营查询结果。
- [`current-database-audit.sql`](current-database-audit.sql)：当前库不满足完整对象预检时使用的只读现状采集脚本；本次有效输出见 [`current-database-audit.txt`](../../results/phase2/baseline/current-database-audit.txt)。

约束 44 项和角色 84 项的自动验证仍需分别完整执行根目录 `constraint.sql`、`role.sql`，因为两份脚本的用例结果保存在执行会话中，不能由事后的只读查询还原。
