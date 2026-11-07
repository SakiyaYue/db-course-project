# 给组员 A 的 v1.0 缺陷反馈

日期：2026-11-07。反馈人：组员 B。涉及版本：`migration.sql` / `migration-body.sql` 生成的 `teabar_auth` 对象（v1.0 已提交到 `TeabarDB_Phase2_Work`）。B 在实现 Web 登录初始化时实测发现，未修改任何 A 的脚本或数据库对象。

## 1. 缺陷：`CK_WebAccount_LoginName` 在 Latin1_General_100_BIN2 下拒绝合法登录名

### 1.1 现象

`database\admin\init_web_accounts.py` 首次插入演示账号 `guest_a` 时失败并回滚：

```text
pyodbc.IntegrityError: ('23000', '[23000] [Microsoft][ODBC Driver 18 for SQL Server][SQL Server]
与 CHECK 约束"CK_WebAccount_LoginName"冲突。该冲突发生于数据库"TeabarDB_Phase2_Work"，表"teabar_auth.WebAccount"。
[SQL Server]语句已终止。 (547) (SQLExecDirectW)')
```

### 1.2 根因

约束定义为（见 `v1.0目标模式与对象变更.md`、`migration-body.sql` 中 `WebAccount` 段）：

```sql
CONSTRAINT CK_WebAccount_LoginName CHECK (
    datalength(login_name) BETWEEN 6 AND 100
    AND NOT (login_name COLLATE Latin1_General_100_BIN2 LIKE N'%[^a-z0-9._-]%')
)
```

在 `Latin1_General_100_BIN2` 下，字符类 `[^a-z0-9._-]` 末尾的短横线被当作范围连接符而不是字面量，字符类实际含义改变，导致 `_` 与 `-` 也被判为非法字符，`guest_a`、`member_a`、`user-name` 等合法登录名全部被拒绝。

### 1.3 最小复现（可直接在任意库执行）

```sql
SELECT
  'a_b' AS v,
  CASE WHEN N'a_b' COLLATE Latin1_General_100_BIN2 LIKE N'%[^a-z0-9._-]%'
       THEN 'LIKE_BAD(被误判)' ELSE 'PASS' END AS result
UNION ALL SELECT 'a-b',
  CASE WHEN N'a-b' COLLATE Latin1_General_100_BIN2 LIKE N'%[^a-z0-9._-]%'
       THEN 'LIKE_BAD' ELSE 'PASS' END
UNION ALL SELECT 'guest_a',
  CASE WHEN N'guest_a' COLLATE Latin1_General_100_BIN2 LIKE N'%[^a-z0-9._-]%'
       THEN 'LIKE_BAD' ELSE 'PASS' END;
```

实测结果：`a_b` → `LIKE_BAD`，`a-b` → `LIKE_BAD`，`guest_a` → `LIKE_BAD`。

对照：同样的表达式在 `Chinese_PRC_CI_AS` 下返回 `PASS`（`guest_a` / `a-b` 不被匹配），说明这与库排序规则相关，不是数据问题。

把短横线移到字符类首位后恢复正常：

```sql
SELECT CASE WHEN N'guest_a' COLLATE Latin1_General_100_BIN2 LIKE N'%[^-a-z0-9._]%'
            THEN 'LIKE_BAD' ELSE 'PASS' END;  -- PASS
SELECT CASE WHEN N'a-b' COLLATE Latin1_General_100_BIN2 LIKE N'%[^-a-z0-9._]%'
            THEN 'LIKE_BAD' ELSE 'PASS' END;  -- PASS
```

### 1.4 影响范围

1. `teabar_auth.WebAccount` 的 `CK_WebAccount_LoginName`：合法登录名（含 `_` 或 `-`）无法插入。
2. `teabar_auth.usp_GetWebCredential` 使用同一条模式做输入过滤：

```sql
AND @login_name COLLATE Latin1_General_100_BIN2 NOT LIKE N'%[^a-z0-9._-]%'
```

即使约束被修正，含 `_`/`-` 的登录名在凭据查询处仍会被判为非法并返回零行，登录失败。两个位置必须一起改。

3. 文档不一致：接口约定 §3.1 写登录名 3—50 位，约束与过程写 6—100 字节，应用层按 3—50 校验。建议统一为"3—50 位小写 ASCII 字母/数字/点/下划线/短横线，存储为小写"，并同步修改约束、过程与文档。

### 1.5 建议修复

方案 A（推荐，最小改动，保持语义直观）：把短横线放在字符类开头，`]` 与 `^` 位置不变：

```sql
login_name COLLATE Latin1_General_100_BIN2 NOT LIKE N'%[^-a-z0-9._]%'
```

方案 B：对 `-`、`]` 显式转义（T-SQL LIKE 的转义需配合 `ESCAPE`）：

```sql
login_name COLLATE Latin1_General_100_BIN2 NOT LIKE N'%[^a-z0-9._\-]%' ESCAPE '\'
```

方案 C：改用 `PATINDEX`/`TRANSLATE` 或逐字符检查，避免 LIKE 字符类语义差异。

修复时需同时改：`migration-body.sql`（`WebAccount` 表定义与 `usp_GetWebCredential` 模块）、重新生成 `migration.sql`，并对已提交的 `TeabarDB_Phase2_Work` 出一份增量修正脚本（`ALTER TABLE ... DROP CONSTRAINT` + `ADD CONSTRAINT`，以及 `ALTER PROCEDURE`）。修复后请用 `guest_a`、`a-b`、`member_a` 三类登录名各跑一条正例，并保留失败反例（大写、空格、超长、`@`）。

## 2. 附：JSON 包装过程订单号长度与文档不一致

接口约定 §2.1 写 `@order_id` "1—10 位 ASCII 字母/数字/下划线/短横线"，`usp_PlacePaidOrderJson` 实现实际校验为 2—20 字节。B 的应用层按 1—10 位校验并只生成 10 位编号（`O`/`I` + 9 位十六进制），正常路径不受影响，但文档与实现应统一（建议改文档为 2—20，或收窄过程校验；两者需与 B 的应用校验口径一致）。

## 3. B 侧临时规避（不修改 A 的对象）

B 的演示登录名改为不含 `_`/`-` 的 `guesta`、`guestb`、`membera`、`memberb`、`clerk1`、`manager1`（用户显示名仍为 `web_guest_a` 等）；`init_web_accounts.py` 的 docstring 已记录本缺陷与临时规避方式。待 A 修复后，B 会用含 `_`/`-` 的登录名补一条回归，验证约束与凭据查询同时恢复。

## 4. 复现与验证记录

- 环境：SQL Server 2025（17.0.1000.7），`TeabarDB_Phase2_Work`，库排序规则 `Chinese_PRC_CI_AS`，但约束列显式 `COLLATE Latin1_General_100_BIN2`。
- 初始化脚本：`database\admin\init_web_accounts.py`（313 行），失败后事务回滚，未留下用户或账号；改为无 `_`/`-` 登录名后 `--database TeabarDB_Phase2_Work` 与 `--database TeabarDB_Phase2_Test` 均执行成功（exit 0）。
- 相关文档：[v1.0 目标模式与对象变更](../06-normalization/v1.0目标模式与对象变更.md)、[v1.0 数据库接口约定](../06-normalization/v1.0数据库接口约定.md)、[迁移与恢复说明](../06-normalization/迁移与恢复说明.md)。
