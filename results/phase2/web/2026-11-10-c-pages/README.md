# C 第一至第七部分页面验收（2026-11-10）

## 完成范围

角色/页面操作矩阵、公共布局、登录角色导航、顾客会员页面、店员页面、店长维护/历史页面、前端校验及错误体验。矩阵及交接见 [C 页面与角色操作矩阵](../../../../docs/phase2/07-web/C页面与角色操作矩阵.md)。不表示 C 第八至第十六部分已完成。

## 自动验证

- 项目运行与 pytest：conda `db-crs-prj`。
- `python -m pytest -q tests/test_c_pages.py -p no:cacheprovider`：**19 passed in 3.94s**。
- `python -m pytest -q -p no:cacheprovider`：最终 **234 passed in 19.84s**。
- 模板编译全部通过；`git diff --check` 无空白错误。
- 新增用例覆盖全部 9 类维护表单、商品新增/修改与成功重定向、失败回填、跨角色 GET/POST 拒绝、会员资料、历史页面及空结果、会话失效、503/超时友好显示、不泄露诊断详情。

第一次全量回归为 226 passed、5 failed、3 errors，失败均来自多轮测试累积导致的原料库存不足（52016）。仅在独立 Test 库通过已有 `usp_AdjustStock` 对低于 100000 的 9 项原料分别补库 100000，随后全量重跑通过。未重建数据库、未绕过约束、未修改工作库或源库。

## 真实浏览器

当前 Browser 插件缺少可调用执行工具，使用应用自带 Playwright/Node 驱动本机无头 Edge。Flask 测试服务由 `db-crs-prj` 启动，固定连接 `TeabarDB_Phase2_Test`，仅监听 127.0.0.1:5051。Python 环境另外安装了可选 Playwright，不是应用运行依赖。

可复现步骤（另装 Node Playwright 时无需设置 PLAYWRIGHT_MODULE；使用应用自带包则用该环境实际路径）：

```powershell
conda activate db-crs-prj
python tests/c_browser_server.py
# 另一个终端：
node tests/c_browser_check.cjs
```

浏览器检查脚本仅用于本地演示测试，使用仓库既有演示账号，不是生产凭据。成功证据：[browser.txt](browser.txt)。

覆盖：必选规格校验；数量改变后价格预览更新；双商品模拟付款失败并保留购物篮，再成功提交；9 类管理页面渲染；主键锁定；负价前端拒绝；历史只读详情；会员资料；390px 移动端页面不横向溢出。全程零 pageerror。

截图已目视检查：

- [多商品结算](checkout.png)
- [维护中心](maintenance-center.png)
- [商品编辑与负价校验场景](maintenance-product.png)
- [历史订单](history.png)
- [移动端维护表单](mobile-maintenance.png)

## 数据与限制

页面测试的临时商品及会话版本恢复；完整回归与浏览器成功下单会在独立 Test 库保留测试订单。截图只含课程演示数据，不含密码、连接信息或本机账号。工作库没有本轮测试写入。

本轮不替代另一台电脑复现、人工课堂演练、完整证据编目和最终报告；这些仍属于第八部分以后。管理列表使用小数据量全量列表与横向滚动，历史订单使用后端分页。业务登录部署仍沿用既有集成身份/EXECUTE AS 验证边界。
