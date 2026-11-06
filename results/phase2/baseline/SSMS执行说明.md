# v0.1 基线 SSMS 执行说明

## 安全前提

`db_creation.sql` 会删除并重建名为 `TeabarDB` 的数据库。如果当前数据库包含需要保留的数据，不要执行它。优先使用隔离 SQL Server 实例、虚拟机、容器，或已经确认可恢复的数据库副本。

## 推荐执行方式

1. 在 SSMS 中连接准备好的测试实例，以具备建库和数据库管理权限的账号操作。
2. 新建查询窗口，先确认服务器名称和目标环境，不要在生产或需要保留数据的实例上初始化。
3. 按根目录 README 顺序完整运行：`db_creation.sql`、`seed_data.sql`、`constraint.sql`、`role.sql`、`view.sql`、`query.sql`、`crud_demo.sql`、再次运行 `query.sql`。
4. `constraint.sql` 保存 44 项明细和汇总；`role.sql` 保存 84 项明细、角色成员关系和代表性越权行。
5. 最后完整运行 [`v0.1-baseline-capture.sql`](../../../database/regression/v0.1-baseline-capture.sql)。该脚本只采集持久状态，不修改业务数据。
6. 在 SSMS 中使用“结果另存为”分别保存关键结果集，截图必须包含脚本名、输入、结果列和消息。
7. 把实际值填写到[基线复现记录](../../../docs/phase2/00-baseline/基线复现记录.md)，差异不得只用截图掩盖。

## 请回传的最小信息

如果不方便导出全部结果，至少提供：

- 环境信息结果集；
- 对象数量摘要；
- 外键和 CHECK 中所有“不受信任/禁用”行；
- 表行数总计；
- 关键样例值结果；
- 订单金额、每日经营和奶茶关键词三个结果；
- `constraint.sql` 的 44 项汇总；
- `role.sql` 的 84 项汇总及四项代表性权限结果；
- 任意红色错误消息的完整文本。
