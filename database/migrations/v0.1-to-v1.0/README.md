# v0.1 → v1.0 迁移脚本

2026-11-07：**经用户授权，在独立副本TeabarDB_Phase2_Work完成回滚演练、52809故障回滚和迁移提交，184/184回归通过。** 冻结源库数据与模式指纹保持一致，见[实测结果](../../../docs/phase2/06-normalization/迁移前后结果与已知限制.md)。脚本默认保持回滚模式。

完整顺序、参数和恢复方式见[迁移与恢复说明](../../../docs/phase2/06-normalization/迁移与恢复说明.md)。目标依据为[对象变更](../../../docs/phase2/06-normalization/v1.0目标模式与对象变更.md)、[数据字典](../../../docs/phase2/06-normalization/v1.0数据字典.md)和[接口约定](../../../docs/phase2/06-normalization/v1.0数据库接口约定.md)。

## 文件与生成

| 文件 | 用途 |
| --- | --- |
| [migration.sql](migration.sql) | 独立运行的生成文件，包含清单、事务和完整模块定义；默认演练后回滚 |
| [migration-body.sql](migration-body.sql) | 可编辑的迁移主体与模式开关 |
| [modules/](modules/) | JSON、认证过程源；核心下单过程由冻结源码加一处校验生成 |
| [build-scripts.py](build-scripts.py) | 生成迁移、旧用例提取、完整回归和回滚核验；不连接 SQL Server |

仓库根目录运行，只生成和解析文件：

```powershell
python database\migrations\v0.1-to-v1.0\build-scripts.py
pwsh -File database\regression\validate-scripts.ps1
```

验证器需要 PowerShell 7.2+ 和 Microsoft ScriptDom DLL，可通过 `-ScriptDomPath` 指定位置。它解析顶层脚本、完整字面量 EXEC 批次及测试表中的语句；拼接产生的 SQL 和数据库对象绑定仍须实测。

## 迁移行为

1. 只接受明确的 `TeabarDB_Phase2_Work` 工作副本；拒绝冻结库、系统库、非 dbo 或已有外层事务。
2. 预检16表74列19FK、持久表22个主/唯一键和46个CHECK、模块、角色与样例；TVP内部约束单独保留，不计入持久表数量。锁定原表并保存全行哈希。
3. 同一事务内新建 WebAccount、三个索引和三个过程，升级核心逐明细正消耗检查；授权 JSON 给顾客和会员角色。
4. 核对目标 17 表、81 列、19 FK、18 个接口/认证过程，确认原 16 表行数和哈希不变，再提交或回滚。
5. 历史零消耗明细、金额错误和未知对象冲突一律拒绝，不按当前配方补造历史；不删除、重命名或重建原表。

主体中的开关：

| CommitMigration | InjectFailure | 结果 |
| --- | --- | --- |
| 0 | 0 | 默认验证后回滚，输出 `DRY_RUN_ROLLED_BACK_TO_V0.1` |
| 0 | 1 | DDL 完成后主动抛出 52809，走失败回滚 |
| 1 | 0 | 验证通过后提交，输出 `COMMITTED_V1.0` |

修改开关后重新生成，核对执行文件中的值。已提交的 v1.0 不能作为源；再次演练需干净 v0.1。结构迁移不创建真实 Web 登录、用户或密码哈希；管理员初始化与 B 的驱动联调另行验收。真实执行遵守[项目授权边界](../../../PHASE2-DECISIONS.md)。
