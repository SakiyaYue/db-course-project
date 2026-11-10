# 给 A 的接口修正交接

2026-11-10 增补：为落实 C 的“本人原料消耗快照”要求，B 新增 `database/admin/order_read_extensions.sql`，由账号初始化在同一事务中安装 `teabar_api.vw_MyConsumption`。列为 `order_id,item_id,ingredient_id,ingredient_name,unit,amount`，通过既有 `vw_MyOrderItems` 过滤当前购买者，再关联消耗快照；仅向 customer/member 授该视图 SELECT，未增加基表读取权限。原料名称仍为当前资料，消耗数量为历史快照。Test/Work 已安装，跨购买者 HTTP 和 SQL 隔离已验证；A 后续版本可整合此新增视图，不需修改原下单/退款过程。

2026-11-07 本轮已用 SQL Server 只读表达式重现：BIN2 字符类 `[^a-z0-9._-]` 将 `guest_a`、`a-b` 判为非法；原 JSON 包装的ID字符类也有同样位置风险。

B 的管理员初始化已在 `database/admin/web_backend_extensions.sql` 提供后置兼容补丁：

- 重建 CK_WebAccount_LoginName，只把短横线移到字符类开头。
- CREATE OR ALTER 凭据过程，同步合法登录名过滤。
- 对原 JSON 过程定义作精确模式替换，使其允许已约定的下划线/短横线；不复制原下单业务，不改变参数与授权。
- 安装在同一管理员事务内，失败回滚，重复安装安全；不改冻结源 TeabarDB 或 A 原迁移源文件。

**撤回原长度缺陷结论**：NVARCHAR 的6—100字节就是3—50个ASCII字符；订单号2—20字节就是1—10个ASCII字符。原长度无需放宽；应用和数据库长度口径保持原约定。

交接 A：下一版本迁移可整合上述三个字符类修复，保持现有错误码和业务规则。交接 C：匿名菜单、多商品表单和幂等字段变更见接口契约补充。此文件为仓库内交接记录，没有向外部成员自动发送消息。
