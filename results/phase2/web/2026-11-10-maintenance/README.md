# 管理接口验证记录（2026-11-10）

- Python 环境：conda `db-crs-prj`。
- 本次新增：9 类管理资源的 GET 列表、GET 详情、POST 保存；列表包含全部状态，可按编号/状态/规格类型过滤。
- 单元回归：`test_maintenance_unit.py` 加原有三个无数据库测试文件，119 passed。
- 新增真实 SQL 集成测试：`test_maintenance_integration.py`，1 passed。覆盖 9 类新增与更新、列表与详情、配方修改停用规格、单位锁定、排班重叠、配方/系数移除。全部测试数据在外层事务回滚，最终检查商品记录不存在。
- 完整应用回归：`python -m pytest -q -p no:cacheprovider --junitxml=results/phase2/web/2026-11-10-maintenance/pytest.xml`，**175 passed in 18.61s**；机器可读结果见 `pytest.xml`。

## 测试库准备与影响

首次连接因沙箱 Windows 凭证限制失败；沙箱外连接确认独立测试库不可用。使用仓库已有 `prepare_test_database.py` 新建 `TeabarDB_Phase2_Test`，完成基础脚本、迁移、基线回归及 Web 初始化。该工具拒绝覆盖已有数据库。

创建前后冻结源库 `TeabarDB` 聚合指纹均为：

`054c1a50f6138e6c276389607e837cb7481f01cf73fc4f592a12de42e9e7e834`

完整回归包含原有下单/退款测试，会在独立测试库保留测试订单与快照；新增管理集成测试自身回滚。未修改工作库或源库。

## 验证边界

HTTP 路由测试保留真实 session_scope、Service 授权和 CSRF，模拟数据库传输和身份查询；真实 SQL 测试使用 Windows 集成连接后切换 `web_manager`。本轮不代表独立受限服务器登录已部署，也不代表 C 的浏览器页面已经验收。

接口及配置顺序见 [给 C 的契约](../../../../docs/phase2/07-web/管理维护接口-给C.md)。本轮未实现员工协助退款、店长完整历史订单查询。
