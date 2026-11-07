"""Build the v1.0 dictionary and editable diagrams from frozen SQL plus the target delta.

Run from any directory with Python 3. No database connection is made.
"""
from pathlib import Path
import html
import re

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
DOCS = ROOT / "docs/phase2/06-normalization"


def read_schema():
    sql = (ROOT / "db_creation.sql").read_text(encoding="utf-8-sig")
    tables = {}
    for name, body in re.findall(r"CREATE TABLE (\w+)\s*\((.*?)\n\);", sql, re.S):
        columns = []
        for line in body.splitlines():
            match = re.match(
                r"\s*(\w+)\s+(VARCHAR\(\d+\)|NVARCHAR\(\d+\)|DATETIME2\(\d+\)|"
                r"DECIMAL\(\d+,\s*\d+\)|INT|AS)\s+(.*)", line, re.I)
            if not match:
                continue
            col, typ, rest = match.groups()
            default = re.search(r"\bDEFAULT\s+(N?'[^']*'|SYSDATETIME\(\)|\d+)", rest)
            columns.append(dict(name=col, type=re.sub(r"\s+", "", typ.upper()),
                                nullable="NOT NULL" not in rest,
                                default=default.group(1) if default else "—",
                                computed=typ.upper() == "AS"))
        tables[name] = columns
    tables["SalesOrder"].insert(2, dict(name="guest_id", type="UNIQUEIDENTIFIER", nullable=True, default="—", computed=False))
    tables["PrincipalBinding"] = [
        dict(name=n, type=t, nullable=nu, default=d, computed=False)
        for n, t, nu, d in [
            ("principal_sid", "VARBINARY(85)", False, "—"),
            ("principal_name", "SYSNAME", False, "—"),
            ("member_id", "VARCHAR(10)", True, "—"),
            ("guest_id", "UNIQUEIDENTIFIER", True, "—"),
            ("is_active", "BIT", False, "1")]]
    tables["WebAccount"] = [
        dict(name=n, type=t, nullable=False, default=d, computed=False)
        for n, t, d in [
            ("account_id", "INT", "IDENTITY(1,1)"),
            ("login_name", "NVARCHAR(50)", "—"),
            ("password_hash", "NVARCHAR(512)", "—"),
            ("app_role", "VARCHAR(10)", "—"),
            ("principal_sid", "VARBINARY(85)", "—"),
            ("is_active", "BIT", "1"),
            ("session_version", "INT", "1")]]
    for column in tables["OrderItem"]:
        if column["computed"]:
            column.update(type="DECIMAL(10,2)", nullable=False, default="计算列")
    assert len(tables) == 17
    assert sum(map(len, tables.values())) == 81
    return tables


KEYS = {
    "Employee": [("employee_id",)], "DutyRoster": [("duty_id",), ("employee_id", "start_time")],
    "Member": [("member_id",), ("phone",)], "SalesOrder": [("order_id",)],
    "Product": [("product_id",)], "Specification": [("spec_id",), ("spec_type", "spec_name")],
    "Ingredient": [("ingredient_id",)], "OrderItem": [("item_id",)],
    "ProductSpecification": [("product_id", "spec_id")], "Recipe": [("product_id", "ingredient_id")],
    "AddOn": [("addon_id",), ("addon_name",)], "ItemSpec": [("item_id", "spec_type")],
    "ItemAddOn": [("item_id", "addon_id")], "OrderItemIngredient": [("item_id", "ingredient_id")],
    "SpecificationIngredient": [("product_id", "spec_id", "ingredient_id")],
    "PrincipalBinding": [("principal_sid",), ("principal_name",)],
    "WebAccount": [("account_id",), ("login_name",), ("principal_sid",)]}

FOREIGN_KEYS = [
    ("DutyRoster", "employee_id", "Employee", "employee_id", False),
    ("SalesOrder", "member_id", "Member", "member_id", True),
    ("OrderItem", "order_id", "SalesOrder", "order_id", False),
    ("OrderItem", "product_id", "Product", "product_id", False),
    ("ProductSpecification", "product_id", "Product", "product_id", False),
    ("ProductSpecification", "spec_id", "Specification", "spec_id", False),
    ("Recipe", "product_id", "Product", "product_id", False),
    ("Recipe", "ingredient_id", "Ingredient", "ingredient_id", False),
    ("AddOn", "ingredient_id", "Ingredient", "ingredient_id", False),
    ("ItemSpec", "item_id", "OrderItem", "item_id", False),
    ("ItemSpec", "spec_id, spec_type", "Specification", "spec_id, spec_type", False),
    ("ItemAddOn", "item_id", "OrderItem", "item_id", False),
    ("ItemAddOn", "addon_id", "AddOn", "addon_id", False),
    ("OrderItemIngredient", "item_id", "OrderItem", "item_id", False),
    ("OrderItemIngredient", "ingredient_id", "Ingredient", "ingredient_id", False),
    ("SpecificationIngredient", "product_id, spec_id", "ProductSpecification", "product_id, spec_id", False),
    ("SpecificationIngredient", "ingredient_id", "Ingredient", "ingredient_id", False),
    ("SpecificationIngredient", "product_id, ingredient_id", "Recipe", "product_id, ingredient_id", False),
    ("PrincipalBinding", "member_id", "Member", "member_id", True)]

TABLE_NOTES = {
    "Employee": "员工主档；status∈{在职,离职}，salary≥0（月薪），role∈{店员,店长}；岗位不自动授予数据库权限。",
    "DutyRoster": "单员工值班区间；start_time<end_time。另有过程保证同员工区间不重叠，因此业务候选码还包括(employee_id,end_time)，未声明 UNIQUE。",
    "Member": "会员当前资料与积分；手机号恰为11位数字、首位1且唯一，points≥0。",
    "SalesOrder": "正式订单；member_id/guest_id恰一非空，total_amount≥0；状态为排队中/制作中/待取餐/已完成/已取消。至少一条明细及金额合计由事务保证。",
    "Product": "当前商品；base_price≥0，status∈{在售,下架}；名称不唯一。",
    "Specification": "当前规格；spec_type∈{糖度,温度,杯型}；另保留UNIQUE(spec_id,spec_type)供复合FK引用，该组合不是最小候选码。",
    "Ingredient": "单门店原料与当前库存；unit∈{g,ml,个}，stock≥0，计件库存为整数；status∈{可用,缺货}，不由库存值自动推导。",
    "OrderItem": "成交明细；quantity>0，两种价格≥0。sub_amount为CAST(unit_price*quantity AS DECIMAL(10,2)) PERSISTED NOT NULL，不可单独写入。",
    "ProductSpecification": "商品规格当前差价与状态；差价允许为负，status∈{可用,停用}。",
    "Recipe": "每杯基础配方；base_amount>0，计件用量另由业务过程核验。",
    "AddOn": "加料定义；price≥0，extra_amount>0，status∈{可用,缺货}；一种加料对应一种原料。",
    "ItemSpec": "成交规格快照；由PK和复合FK可推得另一候选码(item_id,spec_id)，无单独UNIQUE。名称为非空白快照，差价可负；3NF非BCNF。",
    "ItemAddOn": "成交加料快照；price_snapshot≥0，同明细同加料最多一份，加料份数随明细杯数。",
    "OrderItemIngredient": "成交时全部杯数的原料消耗总量；amount>0。v1.0核心过程须额外保证每条明细至少一条正消耗，FK不能保证子行存在。",
    "SpecificationIngredient": "商品-规格-原料用量系数；factor≥0，未配置规则按1处理；须属于对应商品配方。",
    "PrincipalBinding": "管理员维护的购买身份；member_id/guest_id恰一非空，is_active默认1。身份字段没有唯一约束；无到系统目录的FK。",
    "WebAccount": "新增Web账号；每个账号一个独立数据库用户SID，无系统目录FK，也不强制引用购买身份绑定。明细约束见下一节。"}


def schema_name(name):
    return "teabar_auth" if name in ("PrincipalBinding", "WebAccount") else "dbo"


def column_marks(table, column):
    result = []
    if column in KEYS[table][0]: result.append("PK")
    if any(column in key for key in KEYS[table][1:]): result.append("UK")
    if any(child == table and column in cols.split(", ") for child, cols, *_ in FOREIGN_KEYS): result.append("FK")
    if table == "ItemSpec" and column in ("item_id", "spec_id"): result.append("CK-derived")
    return "/".join(result) or "—"


def dictionary(tables):
    lines = ["# v1.0 数据字典", "", "日期：2026-11-07。状态：**目标结构文档，未迁移安装。**", "",
             "依据冻结的 `db_creation.sql`、`constraint.sql`、`role.sql`，加上[目标模式](v1.0目标模式与对象变更.md)中的 WebAccount 增量。历史草稿和 v0.1 文档保留，不用它们代替本目标字典。", "",
             "## 1. 通用约定", "",
             "ID沿用VARCHAR(10)，金额/用量使用DECIMAL(10,2)，规格系数DECIMAL(5,2)。中文文本使用NVARCHAR；业务时间沿用DATETIME2(0)及现有门店时间语义，不因开发者机器时区改变冻结订单。", "",
             "PK为主码；UK为额外唯一约束的参与列，复合唯一性按候选码行解释；CK-derived表示约束推导候选码，不代表新增SQL CHECK或UNIQUE。所有现有PK/UK/FK/CHECK保留，FK/CHECK须启用且受信任，不新增级联删除。标识及已约束名称继续执行现有非空白检查。", "",
             "`dbo`下15表及PrincipalBinding保留74列；WebAccount增加7列，合计17表81列、19条FK。下表由可编辑构建脚本从冻结SQL提取并补入完整安装增量；它不会连接数据库。", "",
             "## 2. 逐表字段", ""]
    for i, (name, cols) in enumerate(tables.items(), 1):
        keys = "；".join("(" + ", ".join(k) + ")" for k in KEYS[name])
        lines += [f"### 2.{i} `{schema_name(name)}.{name}`", "", TABLE_NOTES[name], "",
                  "显式主码/其他候选码：" + keys + "。", "",
                  "| 字段 | SQL类型 | 可空 | 默认/生成 | 键标记 |", "| --- | --- | --- | --- | --- |"]
        for c in cols:
            lines.append(f"| `{c['name']}` | `{c['type']}` | {'是' if c['nullable'] else '否'} | {c['default']} | {column_marks(name,c['name'])} |")
        fk = [f"`({c}) → {schema_name(p)}.{p}({pc})`" for ch,c,p,pc,_ in FOREIGN_KEYS if ch == name]
        lines += ["", "外键：" + ("；".join(fk) if fk else "无") + "。", ""]
    lines += ["## 3. WebAccount 具体约束与字段语义", "",
              "| 约束/字段 | 目标规则 |", "| --- | --- |",
              "| PK_WebAccount | account_id主码，INT IDENTITY(1,1) |",
              "| UQ_WebAccount_LoginName / CK_WebAccount_LoginName | login_name唯一；3—50位小写ASCII字母/数字/点/下划线/短横线，不接受首尾空白；CHECK逐字符使用二进制排序语义 |",
              "| CK_WebAccount_PasswordHash | password_hash非空白且不超过512字符；带盐哈希在可信后端生成与验证，数据库不自行发明密码哈希算法 |",
              "| CK_WebAccount_Role | app_role精确为customer/member/clerk/manager之一；以二进制语义校验小写枚举 |",
              "| UQ_WebAccount_PrincipalSid / CK_WebAccount_Sid | SID唯一且DATALENGTH在1—85之间；管理员/上下文过程检查实际用户 |",
              "| DF_WebAccount_Active | is_active默认1；停用不删除历史订单 |",
              "| DF_WebAccount_SessionVersion / CK_WebAccount_SessionVersion | session_version默认1且>0；账号安全信息变化时递增，旧会话失效；溢出应拒绝而非重置旧版本 |", "",
              "WebAccount不保存明文密码、真实连接秘密、购买身份编号或重复数据库用户名。账号启用不等于数据库用户有效；两个认证过程必须核查跨对象映射。目标角色与SID的维护均为管理员操作，业务角色不得直接读取或修改账号表。", "",
              "## 4. 索引、接口与模型来源", "",
              "新增三个查询索引、三项新增过程、核心下单升级及安全主体详见[对象变更清单](v1.0目标模式与对象变更.md)和[接口约定](v1.0数据库接口约定.md)。既有6个额外UNIQUE加上WebAccount的2个，目标为8个；推导候选码不计作新UNIQUE。", "",
              "ER可编辑源和PNG见[ER目录](../../../design/er/v1.0/README.md)。本字典不把目标对象描述为已存在，不以新增演示账号行数覆盖232行业务基准。", ""]
    (DOCS / "v1.0数据字典.md").write_text("\n".join(lines), encoding="utf-8")


def diagrams(tables):
    mermaid = ["classDiagram", "direction LR", "%% v1.0 TARGET ONLY; not installed. Solid = FK; dotted = logical association."]
    for name, cols in tables.items():
        mermaid.append(f"class {name} {{")
        for c in cols:
            suffix = column_marks(name, c['name']).replace("/", "_")
            if c['nullable']: suffix += "_nullable"
            if c['computed']: suffix += "_computed"
            mermaid.append(f"  +{c['type'].split('(')[0].lower()} {c['name']} {suffix.replace('—','')}")
        mermaid.append("}")
    for child, cols, parent, _, nullable in FOREIGN_KEYS:
        minimum = "1..*" if (child,parent) in [("OrderItem","SalesOrder"),("OrderItemIngredient","OrderItem")] else "0..*"
        if child == "ItemSpec" and parent == "OrderItem": minimum="0..3"
        mermaid.append(f'{parent} "{ "0..1" if nullable else "1"}" --> "{minimum}" {child} : {cols.replace(", ", "_")} FK')
    mermaid += ['WebAccount "0..1" ..> "0..1" PrincipalBinding : SID match for buyers - not FK',
                'DutyRoster "0..*" ..> "0..*" SalesOrder : order_time in duty interval',
                'PrincipalBinding "0..*" ..> "0..*" SalesOrder : identity ownership - not FK',
                'note for WebAccount "TARGET: new auth table. SID resolved via sys.database_principals."',
                'note for OrderItemIngredient "TARGET D01: each official item has positive consumption; process enforced."',
                'note for ItemSpec "3NF, not BCNF. Derived key: item_id + spec_id."',
                'note for OrderItem "sub_amount is a persisted computed value; documented NF exception."']
    (OUT / "ER图_v1.0.mmd").write_text("\n".join(line.rstrip() for line in mermaid)+"\n", encoding="utf-8")
    groups = {
        "ER图_v1.0": set(tables),
        "ER图_v1.0_交易": {"SalesOrder","Member","OrderItem","ItemSpec","ItemAddOn","OrderItemIngredient","Product","Specification","AddOn","Ingredient"},
        "ER图_v1.0_配置": {"Product","Specification","ProductSpecification","Recipe","SpecificationIngredient","Ingredient","AddOn"},
        "ER图_v1.0_身份与人员": {"WebAccount","PrincipalBinding","Member","SalesOrder","Employee","DutyRoster"}}
    for filename, subset in groups.items():
        dot = ['digraph ER {', 'graph [rankdir=LR, bgcolor="#f8fafc", pad="0.4", nodesep="0.5", ranksep="1.1", splines=polyline, fontname="Arial", fontsize=21, labelloc=t, label="v1.0 TARGET DESIGN - NOT INSTALLED\\nSolid: existing FK | Dashed: logical association | Blue: new table"];',
               'node [shape=plain, fontname="Arial", fontsize=12];',
               'edge [fontname="Arial", fontsize=10, color="#64748b", arrowsize=0.7];']
        for name, cols in tables.items():
            if name not in subset: continue
            color = "#1d4ed8" if name == "WebAccount" else "#0f172a"
            rows = [f'<TR><TD COLSPAN="2" BGCOLOR="{color}"><FONT COLOR="white"><B>{schema_name(name)}.{name}</B></FONT></TD></TR>']
            for c in cols:
                marks=column_marks(name,c['name'])
                info=(" ["+marks+"]") if marks != "—" else ""
                if c['computed']: info += " [computed]"
                rows.append(f'<TR><TD ALIGN="LEFT">{html.escape(c["name"]+info)}</TD><TD ALIGN="LEFT">{c["type"]}{" ?" if c["nullable"] else ""}</TD></TR>')
            note={"ItemSpec":"3NF; derived key: item_id + spec_id", "OrderItem":"Computed subtotal: documented NF exception", "WebAccount":"SID unique; no FK to system catalogs", "DutyRoster":"UK(employee_id, start_time)", "Specification":"UK(spec_type, spec_name)"}.get(name)
            if note: rows.append(f'<TR><TD COLSPAN="2" BGCOLOR="#e2e8f0"><FONT POINT-SIZE="10">{note}</FONT></TD></TR>')
            dot.append(f'{name} [label=<<TABLE BORDER="1" COLOR="#cbd5e1" CELLBORDER="0" CELLSPACING="0" CELLPADDING="6">'+''.join(rows)+'</TABLE>>];')
        for child, cols, parent, _, nullable in FOREIGN_KEYS:
            if child not in subset or parent not in subset: continue
            many="0..N"
            extra=""
            if (child,parent) in [("OrderItem","SalesOrder"),("OrderItemIngredient","OrderItem")]: many="1..N"; extra="; minimum by process"
            if (child,parent)==("ItemSpec","OrderItem"): many="0..3"; extra="; required types by process"
            parentcard="0..1" if nullable else "1"
            dot.append(f'{parent} -> {child} [label="{cols}{extra}", taillabel="{parentcard}", headlabel="{many}", labeldistance=2];')
        for a,b,label in [("WebAccount","PrincipalBinding","SID match: 0..1 each; buyers only; NOT FK"),("DutyRoster","SalesOrder","0..N : 0..N; order_time within duty interval"),("PrincipalBinding","SalesOrder","0..N : 0..N; ownership check; NOT FK")]:
            if a in subset and b in subset: dot.append(f'{a} -> {b} [style=dashed, color="#0d9488", fontcolor="#0f766e", label="{label}", constraint=false];')
        dot.append('}')
        (OUT / (filename+".dot")).write_text("\n".join(dot)+"\n", encoding="utf-8")


if __name__ == "__main__":
    tables=read_schema()
    assert len(FOREIGN_KEYS)==19
    dictionary(tables)
    diagrams(tables)
    print("Generated target dictionary, Mermaid and 4 DOT sources: 17 tables, 81 columns, 19 FK. No SQL executed.")
