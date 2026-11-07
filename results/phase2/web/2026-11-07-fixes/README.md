# B 修复最终证据

本目录是2026-11-07本轮实际验证，旧results/phase2/web根目录为上一版本历史证据。

- pytest-final.txt：89 passed，真实独立测试库，退出0。
- web-permissions.txt：26项模拟受限入口/业务角色/公开菜单权限通过；探针临时用户和事务已回滚。
- web-permissions-final.txt：最终权限命令的退出码与结果。
- database-setup-continued.txt：Test从零准备完成，184项A回归通过，源聚合指纹不变；database-setup.txt保留首次seed守卫失败尝试，不覆盖为成功。
- work-database-setup.txt：全新Work从零完成建表、232样例、v1.0迁移、184项回归与B初始化；源聚合指纹不变。
- work-init-idempotent.txt：Work初始化重复执行成功。
- init-dry-run.txt：Test初始化和扩展已回滚，退出0。
- work-readonly-smoke.txt：匿名菜单/商品详情/登录/结算/本人订单/退出；Work保持5单、232业务行、6账号、0回执。
- independent-review.md：独立subagent发现项、修复及复审结果。

A原184回归要求干净17表/19FK，实际执行顺序为迁移后、B扩展前。B扩展后为18表/20FK，后续应用行为由89项测试覆盖。权限探针使用EXECUTE AS USER，不等同于真实服务器登录。测试库保留测试订单；Work保持演示样例。没有删除或覆盖冻结TeabarDB。
