# v1.0 ER 目标设计

日期：2026-11-07。状态：**目标图已生成，数据库尚未迁移。** 模式及实施顺序见[目标模式](../../../docs/phase2/06-normalization/v1.0目标模式与对象变更.md)，字段细节见[目标字典](../../../docs/phase2/06-normalization/v1.0数据字典.md)。

| 图 | 可编辑源 | PNG |
| --- | --- | --- |
| 总图：17 表、81 字段、19 FK | [Mermaid](ER图_v1.0.mmd)、[DOT](ER图_v1.0.dot) | [总图](ER图_v1.0.png) |
| 交易与历史快照 | [DOT](ER图_v1.0_交易.dot) | [交易图](ER图_v1.0_交易.png) |
| 商品、规格、配方和原料 | [DOT](ER图_v1.0_配置.dot) | [配置图](ER图_v1.0_配置.png) |
| 账号、购买身份、会员及人员 | [DOT](ER图_v1.0_身份与人员.dot) | [身份与人员图](ER图_v1.0_身份与人员.png) |

## 图例与基数

深色表是保留对象，蓝色 WebAccount 是新增目标。实线表示 FK，对应完整安装后的19条约束；虚线表示SID匹配、订单归属或值班时间匹配，不能当成物理FK。图中 `?` 表示可空；PK/UK是键标记，复合键按表说明整体理解；`CK-derived` 是推导候选码，不表示 SQL CHECK。

`1..N` 的订单明细与原料消耗下限是目标业务规则，依赖下单过程和迁移预检，不由 FK 自动保证；D01 正消耗校验尚待实现。ItemSpec图中 `0..3` 表达存储结构允许的选择数，真实成交须为商品配置的每种类型选择恰好一个，至少一类、至多三类，由过程检查。加料选择可为空。

WebAccount 与 PrincipalBinding 的 SID 关联双方至多一个，购买者必须有活动绑定，工作账号不要求绑定；无 FK。与实际数据库用户的 SID 对应由安全对象初始化和上下文过程核验，系统目录不作为新增业务表计数。

订单-值班按 `start_time <= order_time < end_time` 匹配，可同时对应多人；订单与绑定通过购买身份匹配，不保证一订单只有一个 principal，因为现有会员可有多绑定。

## 重建与检查

[build-design.py](build-design.py) 从冻结建表SQL提取基础列，再补入 `guest_id`、PrincipalBinding 和目标 WebAccount；统一生成目标字典、Mermaid及四份DOT源。它不会连接数据库。命令从仓库根目录执行：

```powershell
python design/er/v1.0/build-design.py
node design/er/v1.0/render-er.cjs <bundled-node-modules-directory>
```

[render-er.cjs](render-er.cjs) 使用桌面运行时附带的 `@viz-js/viz` 与 `sharp` 将同源DOT渲染为PNG；运行时目录从桌面依赖工具取得，不将个人绝对路径写进项目。修改模型时同步更新构建源、字典和所有导出，避免只改图片。

本轮已核对生成字段/键/连线数量，检查四张导出图，图中均带 TARGET / NOT INSTALLED 标记。迁移成功后应另行更新状态并附上真实对象采集与回归证据。
