/*
    v0.1 基线只读采集脚本
    适用：完整执行 db_creation.sql、seed_data.sql、constraint.sql、role.sql、view.sql 后的 TeabarDB
    作用：采集环境、持久对象、约束、权限、行数和关键业务结果
    安全性：不创建、修改或删除持久对象与业务数据；只使用会话内表变量整理结果

    注意：
    1. 本脚本不能替代 constraint.sql 的 44 项验证或 role.sql 的 84 项验证。
    2. 请在 SSMS 新查询窗口中完整执行，不要选中局部语句。
    3. 如需保留当前业务数据，绝对不要为了运行本脚本而重跑 db_creation.sql。
*/

USE TeabarDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

IF DB_NAME() <> N'TeabarDB'
    THROW 54000, N'当前数据库不是 TeabarDB，已停止基线采集。', 1;
IF @@TRANCOUNT <> 0
    THROW 54001, N'请在没有未结束事务的新查询窗口中执行基线采集。', 1;

PRINT N'BASELINE 01/12 环境信息';
SELECT
    N'<local-sql-server>' AS server_name,
    CONVERT(NVARCHAR(128), SERVERPROPERTY(N'ProductVersion')) AS product_version,
    CONVERT(NVARCHAR(128), SERVERPROPERTY(N'ProductLevel')) AS product_level,
    CONVERT(NVARCHAR(128), SERVERPROPERTY(N'Edition')) AS edition,
    CONVERT(NVARCHAR(128), SERVERPROPERTY(N'EngineEdition')) AS engine_edition,
    DB_NAME() AS database_name,
    d.compatibility_level,
    d.collation_name,
    d.recovery_model_desc,
    d.user_access_desc,
    d.state_desc,
    N'<windows-integrated-login>' AS original_login,
    N'<windows-integrated-login>' AS login_name,
    USER_NAME() AS database_user,
    SYSDATETIMEOFFSET() AS captured_at
FROM sys.databases AS d
WHERE d.database_id = DB_ID();

SELECT @@VERSION AS full_version_text;

DECLARE @RequiredObjects TABLE (
    schema_name SYSNAME NOT NULL,
    object_name SYSNAME NOT NULL,
    object_type VARCHAR(2) NOT NULL,
    object_group NVARCHAR(40) NOT NULL,
    PRIMARY KEY(schema_name, object_name)
);

INSERT @RequiredObjects(schema_name, object_name, object_type, object_group) VALUES
-- 15 张业务表
(N'dbo', N'Employee', 'U', N'业务表'),
(N'dbo', N'DutyRoster', 'U', N'业务表'),
(N'dbo', N'Member', 'U', N'业务表'),
(N'dbo', N'SalesOrder', 'U', N'业务表'),
(N'dbo', N'Product', 'U', N'业务表'),
(N'dbo', N'Specification', 'U', N'业务表'),
(N'dbo', N'Ingredient', 'U', N'业务表'),
(N'dbo', N'OrderItem', 'U', N'业务表'),
(N'dbo', N'ProductSpecification', 'U', N'业务表'),
(N'dbo', N'Recipe', 'U', N'业务表'),
(N'dbo', N'AddOn', 'U', N'业务表'),
(N'dbo', N'ItemSpec', 'U', N'业务表'),
(N'dbo', N'ItemAddOn', 'U', N'业务表'),
(N'dbo', N'OrderItemIngredient', 'U', N'业务表'),
(N'dbo', N'SpecificationIngredient', 'U', N'业务表'),
-- 授权辅助表
(N'teabar_auth', N'PrincipalBinding', 'U', N'授权辅助表'),
-- 13 个正式 dbo 视图
(N'dbo', N'vw_ProductCatalog', 'V', N'dbo正式视图'),
(N'dbo', N'vw_ProductSpecification', 'V', N'dbo正式视图'),
(N'dbo', N'vw_SpecificationIngredientRule', 'V', N'dbo正式视图'),
(N'dbo', N'vw_AddOnAvailability', 'V', N'dbo正式视图'),
(N'dbo', N'vw_IngredientStock', 'V', N'dbo正式视图'),
(N'dbo', N'vw_OrderSummary', 'V', N'dbo正式视图'),
(N'dbo', N'vw_OrderDetail', 'V', N'dbo正式视图'),
(N'dbo', N'vw_OrderIngredientUsage', 'V', N'dbo正式视图'),
(N'dbo', N'vw_MemberConsumptionStatistics', 'V', N'dbo正式视图'),
(N'dbo', N'vw_DutyRosterDetail', 'V', N'dbo正式视图'),
(N'dbo', N'vw_OrderDutyTeam', 'V', N'dbo正式视图'),
(N'dbo', N'vw_ProductSalesStatistics', 'V', N'dbo正式视图'),
(N'dbo', N'vw_DailySalesStatistics', 'V', N'dbo正式视图'),
-- 16 个接口视图
(N'teabar_api', N'vw_Menu', 'V', N'接口视图'),
(N'teabar_api', N'vw_AvailableSpecifications', 'V', N'接口视图'),
(N'teabar_api', N'vw_AvailableAddOns', 'V', N'接口视图'),
(N'teabar_api', N'vw_MyOrders', 'V', N'接口视图'),
(N'teabar_api', N'vw_MyOrderItems', 'V', N'接口视图'),
(N'teabar_api', N'vw_MyItemSpecs', 'V', N'接口视图'),
(N'teabar_api', N'vw_MyItemAddOns', 'V', N'接口视图'),
(N'teabar_api', N'vw_MyMember', 'V', N'接口视图'),
(N'teabar_api', N'vw_WorkOrders', 'V', N'接口视图'),
(N'teabar_api', N'vw_WorkOrderItems', 'V', N'接口视图'),
(N'teabar_api', N'vw_WorkItemSpecs', 'V', N'接口视图'),
(N'teabar_api', N'vw_WorkItemAddOns', 'V', N'接口视图'),
(N'teabar_api', N'vw_WorkConsumption', 'V', N'接口视图'),
(N'teabar_api', N'vw_WorkTeam', 'V', N'接口视图'),
(N'teabar_api', N'vw_DailySales', 'V', N'接口视图'),
(N'teabar_api', N'vw_ProductSales', 'V', N'接口视图'),
-- 15 个接口过程
(N'teabar_api', N'usp_PlacePaidOrder', 'P', N'接口过程'),
(N'teabar_api', N'usp_AdvanceOrder', 'P', N'接口过程'),
(N'teabar_api', N'usp_RefundOrder', 'P', N'接口过程'),
(N'teabar_api', N'usp_AdjustStock', 'P', N'接口过程'),
(N'teabar_api', N'usp_SaveMember', 'P', N'接口过程'),
(N'teabar_api', N'usp_FindMember', 'P', N'接口过程'),
(N'teabar_api', N'usp_SaveProduct', 'P', N'接口过程'),
(N'teabar_api', N'usp_SaveIngredient', 'P', N'接口过程'),
(N'teabar_api', N'usp_SaveEmployee', 'P', N'接口过程'),
(N'teabar_api', N'usp_SaveSpecification', 'P', N'接口过程'),
(N'teabar_api', N'usp_SaveProductSpecification', 'P', N'接口过程'),
(N'teabar_api', N'usp_SaveRecipe', 'P', N'接口过程'),
(N'teabar_api', N'usp_SaveSpecificationIngredient', 'P', N'接口过程'),
(N'teabar_api', N'usp_SaveAddOn', 'P', N'接口过程'),
(N'teabar_api', N'usp_SaveDutyRoster', 'P', N'接口过程'),
-- 身份函数
(N'teabar_auth', N'fn_CurrentIdentity', 'IF', N'内联表值函数');

PRINT N'BASELINE 02/12 必需对象存在性';
SELECT
    r.object_group,
    r.schema_name,
    r.object_name,
    r.object_type AS expected_type,
    o.type AS actual_type,
    o.type_desc,
    CASE WHEN o.object_id IS NOT NULL AND o.type COLLATE DATABASE_DEFAULT = r.object_type THEN N'通过' ELSE N'缺失或类型错误' END AS result
FROM @RequiredObjects AS r
LEFT JOIN sys.schemas AS s ON s.name COLLATE DATABASE_DEFAULT = r.schema_name
LEFT JOIN sys.objects AS o ON o.schema_id = s.schema_id AND o.name COLLATE DATABASE_DEFAULT = r.object_name
ORDER BY r.object_group, r.schema_name, r.object_name;

IF EXISTS (
    SELECT 1
    FROM @RequiredObjects AS r
    LEFT JOIN sys.schemas AS s ON s.name COLLATE DATABASE_DEFAULT = r.schema_name
    LEFT JOIN sys.objects AS o ON o.schema_id = s.schema_id AND o.name COLLATE DATABASE_DEFAULT = r.object_name AND o.type COLLATE DATABASE_DEFAULT = r.object_type
    WHERE r.object_group IN (N'业务表', N'授权辅助表') AND o.object_id IS NULL
)
    THROW 54002, N'缺少必需物理表，不能继续读取 v0.1 基线数据。请核对安装顺序。', 1;

PRINT N'BASELINE 03/12 对象数量摘要';
DECLARE @ObjectMetrics TABLE (
    metric NVARCHAR(80) PRIMARY KEY,
    expected_value INT NOT NULL,
    actual_value INT NOT NULL
);

INSERT @ObjectMetrics VALUES
(N'业务表', 15, (SELECT COUNT(*) FROM @RequiredObjects AS r WHERE r.object_group = N'业务表' AND OBJECT_ID(QUOTENAME(r.schema_name) + N'.' + QUOTENAME(r.object_name), N'U') IS NOT NULL)),
(N'授权辅助表', 1, (SELECT COUNT(*) FROM @RequiredObjects AS r WHERE r.object_group = N'授权辅助表' AND OBJECT_ID(QUOTENAME(r.schema_name) + N'.' + QUOTENAME(r.object_name), N'U') IS NOT NULL)),
(N'正式dbo视图', 13, (SELECT COUNT(*) FROM @RequiredObjects AS r WHERE r.object_group = N'dbo正式视图' AND OBJECT_ID(QUOTENAME(r.schema_name) + N'.' + QUOTENAME(r.object_name), N'V') IS NOT NULL)),
(N'接口视图', 16, (SELECT COUNT(*) FROM @RequiredObjects AS r WHERE r.object_group = N'接口视图' AND OBJECT_ID(QUOTENAME(r.schema_name) + N'.' + QUOTENAME(r.object_name), N'V') IS NOT NULL)),
(N'接口过程', 15, (SELECT COUNT(*) FROM @RequiredObjects AS r WHERE r.object_group = N'接口过程' AND OBJECT_ID(QUOTENAME(r.schema_name) + N'.' + QUOTENAME(r.object_name), N'P') IS NOT NULL)),
(N'身份函数', 1, (SELECT COUNT(*) FROM @RequiredObjects AS r WHERE r.object_group = N'内联表值函数' AND OBJECT_ID(QUOTENAME(r.schema_name) + N'.' + QUOTENAME(r.object_name), N'IF') IS NOT NULL)),
(N'表值类型', 3, (SELECT COUNT(*) FROM sys.table_types AS tt JOIN sys.schemas AS s ON s.schema_id = tt.schema_id WHERE s.name COLLATE DATABASE_DEFAULT = N'teabar_api' AND tt.name COLLATE DATABASE_DEFAULT IN (N'OrderLines', N'OrderSpecs', N'OrderAddOns'))),
(N'数据库角色', 4, (SELECT COUNT(*) FROM sys.database_principals WHERE type = 'R' AND name COLLATE DATABASE_DEFAULT IN (N'teabar_customer', N'teabar_member', N'teabar_clerk', N'teabar_manager'))),
(N'WITHOUT LOGIN演示用户', 6, (SELECT COUNT(*) FROM sys.database_principals WHERE type = 'S' AND authentication_type = 0 AND name COLLATE DATABASE_DEFAULT IN (N'demo_guest_a', N'demo_guest_b', N'demo_member_a', N'demo_member_b', N'demo_clerk', N'demo_manager'))),
(N'物理表字段', 74, (
    SELECT COUNT(*) FROM sys.columns AS c
    WHERE c.object_id IN (
        SELECT OBJECT_ID(QUOTENAME(r.schema_name) + N'.' + QUOTENAME(r.object_name))
        FROM @RequiredObjects AS r WHERE r.object_group IN (N'业务表', N'授权辅助表')
    )
)),
(N'外键', 19, (
    SELECT COUNT(*) FROM sys.foreign_keys AS fk
    WHERE fk.parent_object_id IN (
        SELECT OBJECT_ID(QUOTENAME(r.schema_name) + N'.' + QUOTENAME(r.object_name))
        FROM @RequiredObjects AS r WHERE r.object_group IN (N'业务表', N'授权辅助表')
    )
));

SELECT metric, expected_value, actual_value,
       CASE WHEN expected_value = actual_value THEN N'通过' ELSE N'不一致' END AS result
FROM @ObjectMetrics ORDER BY metric;

PRINT N'BASELINE 04/12 字段、主码、候选码、外键与约束明细';
SELECT
    s.name AS schema_name,
    t.name AS table_name,
    c.column_id,
    c.name AS column_name,
    TYPE_NAME(c.user_type_id) AS data_type,
    c.max_length,
    c.precision,
    c.scale,
    c.is_nullable,
    c.is_identity,
    c.is_computed,
    cc.definition AS computed_definition,
    cc.is_persisted
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.columns AS c ON c.object_id = t.object_id
LEFT JOIN sys.computed_columns AS cc ON cc.object_id = c.object_id AND cc.column_id = c.column_id
WHERE EXISTS (SELECT 1 FROM @RequiredObjects AS r WHERE r.schema_name = s.name COLLATE DATABASE_DEFAULT AND r.object_name = t.name COLLATE DATABASE_DEFAULT AND r.object_group IN (N'业务表', N'授权辅助表'))
ORDER BY s.name, t.name, c.column_id;

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    i.name AS key_name,
    i.is_primary_key,
    i.is_unique_constraint,
    STRING_AGG(QUOTENAME(c.name), N', ') WITHIN GROUP (ORDER BY ic.key_ordinal) AS key_columns
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.indexes AS i ON i.object_id = t.object_id AND (i.is_primary_key = 1 OR i.is_unique_constraint = 1)
JOIN sys.index_columns AS ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.key_ordinal > 0
JOIN sys.columns AS c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE EXISTS (SELECT 1 FROM @RequiredObjects AS r WHERE r.schema_name = s.name COLLATE DATABASE_DEFAULT AND r.object_name = t.name COLLATE DATABASE_DEFAULT AND r.object_group IN (N'业务表', N'授权辅助表'))
GROUP BY s.name, t.name, i.name, i.is_primary_key, i.is_unique_constraint
ORDER BY s.name, t.name, i.is_primary_key DESC, i.name;

SELECT
    OBJECT_SCHEMA_NAME(fk.parent_object_id) AS child_schema,
    OBJECT_NAME(fk.parent_object_id) AS child_table,
    fk.name AS foreign_key_name,
    STRING_AGG(QUOTENAME(pc.name), N', ') WITHIN GROUP (ORDER BY fkc.constraint_column_id) AS child_columns,
    OBJECT_SCHEMA_NAME(fk.referenced_object_id) AS parent_schema,
    OBJECT_NAME(fk.referenced_object_id) AS parent_table,
    STRING_AGG(QUOTENAME(rc.name), N', ') WITHIN GROUP (ORDER BY fkc.constraint_column_id) AS parent_columns,
    fk.delete_referential_action_desc,
    fk.update_referential_action_desc,
    fk.is_disabled,
    fk.is_not_trusted,
    CASE WHEN fk.is_disabled = 0 AND fk.is_not_trusted = 0 THEN N'通过' ELSE N'未启用或不受信任' END AS trust_result
FROM sys.foreign_keys AS fk
JOIN sys.foreign_key_columns AS fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns AS pc ON pc.object_id = fkc.parent_object_id AND pc.column_id = fkc.parent_column_id
JOIN sys.columns AS rc ON rc.object_id = fkc.referenced_object_id AND rc.column_id = fkc.referenced_column_id
WHERE fk.parent_object_id IN (
    SELECT OBJECT_ID(QUOTENAME(r.schema_name) + N'.' + QUOTENAME(r.object_name))
    FROM @RequiredObjects AS r WHERE r.object_group IN (N'业务表', N'授权辅助表')
)
GROUP BY fk.parent_object_id, fk.name, fk.referenced_object_id,
         fk.delete_referential_action_desc, fk.update_referential_action_desc,
         fk.is_disabled, fk.is_not_trusted
ORDER BY child_schema, child_table, foreign_key_name;

SELECT
    OBJECT_SCHEMA_NAME(parent_object_id) AS schema_name,
    OBJECT_NAME(parent_object_id) AS table_name,
    name AS check_name,
    definition,
    is_disabled,
    is_not_trusted,
    CASE WHEN is_disabled = 0 AND is_not_trusted = 0 THEN N'通过' ELSE N'未启用或不受信任' END AS trust_result
FROM sys.check_constraints
WHERE parent_object_id IN (
    SELECT OBJECT_ID(QUOTENAME(r.schema_name) + N'.' + QUOTENAME(r.object_name))
    FROM @RequiredObjects AS r WHERE r.object_group IN (N'业务表', N'授权辅助表')
)
ORDER BY schema_name, table_name, check_name;

SELECT
    OBJECT_SCHEMA_NAME(dc.parent_object_id) AS schema_name,
    OBJECT_NAME(dc.parent_object_id) AS table_name,
    c.name AS column_name,
    dc.name AS default_name,
    dc.definition
FROM sys.default_constraints AS dc
JOIN sys.columns AS c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
WHERE dc.parent_object_id IN (
    SELECT OBJECT_ID(QUOTENAME(r.schema_name) + N'.' + QUOTENAME(r.object_name))
    FROM @RequiredObjects AS r WHERE r.object_group IN (N'业务表', N'授权辅助表')
)
ORDER BY schema_name, table_name, column_name;

PRINT N'BASELINE 05/12 模块与表值类型';
SELECT
    s.name AS schema_name,
    o.name AS object_name,
    o.type,
    o.type_desc,
    sm.uses_ansi_nulls,
    sm.uses_quoted_identifier,
    sm.is_schema_bound
FROM sys.objects AS o
JOIN sys.schemas AS s ON s.schema_id = o.schema_id
LEFT JOIN sys.sql_modules AS sm ON sm.object_id = o.object_id
WHERE EXISTS (SELECT 1 FROM @RequiredObjects AS r WHERE r.schema_name = s.name COLLATE DATABASE_DEFAULT AND r.object_name = o.name COLLATE DATABASE_DEFAULT)
ORDER BY s.name, o.type, o.name;

SELECT
    s.name AS schema_name,
    tt.name AS type_name,
    c.column_id,
    c.name AS column_name,
    TYPE_NAME(c.user_type_id) AS data_type,
    c.max_length,
    c.precision,
    c.scale,
    c.is_nullable
FROM sys.table_types AS tt
JOIN sys.schemas AS s ON s.schema_id = tt.schema_id
JOIN sys.columns AS c ON c.object_id = tt.type_table_object_id
WHERE s.name COLLATE DATABASE_DEFAULT = N'teabar_api' AND tt.name COLLATE DATABASE_DEFAULT IN (N'OrderLines', N'OrderSpecs', N'OrderAddOns')
ORDER BY tt.name, c.column_id;

PRINT N'BASELINE 06/12 角色、用户、成员与显式权限';
SELECT name, type_desc, authentication_type_desc, default_schema_name, owning_principal_id
FROM sys.database_principals
WHERE name COLLATE DATABASE_DEFAULT IN (
    N'teabar_customer', N'teabar_member', N'teabar_clerk', N'teabar_manager',
    N'demo_guest_a', N'demo_guest_b', N'demo_member_a', N'demo_member_b', N'demo_clerk', N'demo_manager'
)
ORDER BY type_desc, name;

SELECT r.name AS role_name, u.name AS member_name
FROM sys.database_role_members AS rm
JOIN sys.database_principals AS r ON r.principal_id = rm.role_principal_id
JOIN sys.database_principals AS u ON u.principal_id = rm.member_principal_id
WHERE r.name COLLATE DATABASE_DEFAULT IN (N'teabar_customer', N'teabar_member', N'teabar_clerk', N'teabar_manager')
ORDER BY r.name, u.name;

SELECT
    pr.name AS principal_name,
    pe.state_desc,
    pe.permission_name,
    pe.class_desc,
    CASE pe.class
        WHEN 0 THEN DB_NAME()
        WHEN 1 THEN QUOTENAME(OBJECT_SCHEMA_NAME(pe.major_id)) + N'.' + QUOTENAME(OBJECT_NAME(pe.major_id))
        WHEN 3 THEN QUOTENAME(SCHEMA_NAME(pe.major_id))
        WHEN 6 THEN QUOTENAME(SCHEMA_NAME(ty.schema_id)) + N'.' + QUOTENAME(ty.name)
        ELSE CONVERT(NVARCHAR(128), pe.major_id)
    END AS securable
FROM sys.database_permissions AS pe
JOIN sys.database_principals AS pr ON pr.principal_id = pe.grantee_principal_id
LEFT JOIN sys.types AS ty ON pe.class = 6 AND ty.user_type_id = pe.major_id
WHERE pr.name COLLATE DATABASE_DEFAULT IN (N'teabar_customer', N'teabar_member', N'teabar_clerk', N'teabar_manager')
ORDER BY pr.name, pe.state_desc, pe.permission_name, pe.class_desc, securable;

PRINT N'BASELINE 07/12 表行数';
DECLARE @RowCounts TABLE (table_name SYSNAME PRIMARY KEY, row_count BIGINT NOT NULL);
INSERT @RowCounts VALUES
(N'Employee', (SELECT COUNT_BIG(*) FROM dbo.Employee)),
(N'DutyRoster', (SELECT COUNT_BIG(*) FROM dbo.DutyRoster)),
(N'Member', (SELECT COUNT_BIG(*) FROM dbo.Member)),
(N'SalesOrder', (SELECT COUNT_BIG(*) FROM dbo.SalesOrder)),
(N'Product', (SELECT COUNT_BIG(*) FROM dbo.Product)),
(N'Specification', (SELECT COUNT_BIG(*) FROM dbo.Specification)),
(N'Ingredient', (SELECT COUNT_BIG(*) FROM dbo.Ingredient)),
(N'OrderItem', (SELECT COUNT_BIG(*) FROM dbo.OrderItem)),
(N'ProductSpecification', (SELECT COUNT_BIG(*) FROM dbo.ProductSpecification)),
(N'Recipe', (SELECT COUNT_BIG(*) FROM dbo.Recipe)),
(N'AddOn', (SELECT COUNT_BIG(*) FROM dbo.AddOn)),
(N'ItemSpec', (SELECT COUNT_BIG(*) FROM dbo.ItemSpec)),
(N'ItemAddOn', (SELECT COUNT_BIG(*) FROM dbo.ItemAddOn)),
(N'OrderItemIngredient', (SELECT COUNT_BIG(*) FROM dbo.OrderItemIngredient)),
(N'SpecificationIngredient', (SELECT COUNT_BIG(*) FROM dbo.SpecificationIngredient));

SELECT table_name, row_count FROM @RowCounts ORDER BY table_name;
SELECT N'15张业务表总行数' AS metric, CONVERT(BIGINT, 232) AS expected_value,
       SUM(row_count) AS actual_value,
       CASE WHEN SUM(row_count) = 232 THEN N'通过' ELSE N'不一致' END AS result
FROM @RowCounts;

PRINT N'BASELINE 08/12 关键样例值';
DECLARE @Metrics TABLE (
    metric NVARCHAR(100) PRIMARY KEY,
    expected_value NVARCHAR(200) NOT NULL,
    actual_value NVARCHAR(200) NULL
);

INSERT @Metrics(metric, expected_value, actual_value) VALUES
(N'商品行数', N'4', CONVERT(NVARCHAR(200), (SELECT COUNT_BIG(*) FROM dbo.Product))),
(N'原料行数', N'9', CONVERT(NVARCHAR(200), (SELECT COUNT_BIG(*) FROM dbo.Ingredient))),
(N'订单行数', N'5', CONVERT(NVARCHAR(200), (SELECT COUNT_BIG(*) FROM dbo.SalesOrder))),
(N'明细行数', N'7', CONVERT(NVARCHAR(200), (SELECT COUNT_BIG(*) FROM dbo.OrderItem))),
(N'P001价格与状态', N'6.00|在售', (SELECT CONCAT(CONVERT(DECIMAL(10,2), base_price), N'|', status) FROM dbo.Product WHERE product_id = 'P001')),
(N'I001库存与单位', N'5000.00|g', (SELECT CONCAT(CONVERT(DECIMAL(10,2), stock), N'|', unit) FROM dbo.Ingredient WHERE ingredient_id = 'I001')),
(N'M001积分', N'120', (SELECT CONVERT(NVARCHAR(200), points) FROM dbo.Member WHERE member_id = 'M001')),
(N'CO001与CO002残留数', N'0', CONVERT(NVARCHAR(200), (SELECT COUNT_BIG(*) FROM dbo.SalesOrder WHERE order_id IN ('CO001', 'CO002'))));

SELECT metric, expected_value, actual_value,
       CASE WHEN expected_value = actual_value THEN N'通过' ELSE N'不一致' END AS result
FROM @Metrics ORDER BY metric;

PRINT N'BASELINE 09/12 订单金额一致性';
IF OBJECT_ID(N'dbo.vw_OrderSummary', N'V') IS NULL
    SELECT N'dbo.vw_OrderSummary 缺失' AS error_message;
ELSE
BEGIN
    SELECT order_id, total_amount, item_rows, total_cups, item_amount,
           missing_items, amount_matches_items
    FROM dbo.vw_OrderSummary
    ORDER BY order_id;

    SELECT N'订单金额全部匹配' AS metric, N'5|0' AS expected_value,
           CONCAT(COUNT_BIG(*), N'|', SUM(CASE WHEN amount_matches_items = 1 THEN 0 ELSE 1 END)) AS actual_value,
           CASE WHEN COUNT_BIG(*) = 5 AND SUM(CASE WHEN amount_matches_items = 1 THEN 0 ELSE 1 END) = 0
                THEN N'通过' ELSE N'不一致' END AS result
    FROM dbo.vw_OrderSummary;
END;

PRINT N'BASELINE 10/12 每日经营统计';
IF OBJECT_ID(N'dbo.vw_DailySalesStatistics', N'V') IS NULL
    SELECT N'dbo.vw_DailySalesStatistics 缺失' AS error_message;
ELSE
BEGIN
    SELECT business_date, completed_order_count, cups_sold, sales_amount,
           average_order_amount, member_order_count, nonmember_order_count
    FROM dbo.vw_DailySalesStatistics
    WHERE business_date = CONVERT(DATE, '2026-10-04');

    SELECT N'2026-10-04经营结果' AS metric,
           N'3|5|46.00|15.33' AS expected_value,
           CONCAT(completed_order_count, N'|', cups_sold, N'|',
                  CONVERT(DECIMAL(38,2), sales_amount), N'|',
                  CONVERT(DECIMAL(18,2), average_order_amount)) AS actual_value,
           CASE WHEN completed_order_count = 3 AND cups_sold = 5
                     AND sales_amount = 46.00 AND average_order_amount = 15.33
                THEN N'通过' ELSE N'不一致' END AS result
    FROM dbo.vw_DailySalesStatistics
    WHERE business_date = CONVERT(DATE, '2026-10-04');
END;

PRINT N'BASELINE 11/12 奶茶关键词经营统计';
IF OBJECT_ID(N'dbo.vw_ProductSalesStatistics', N'V') IS NULL
    SELECT N'dbo.vw_ProductSalesStatistics 缺失' AS error_message;
ELSE
BEGIN
    SELECT product_id, product_name,
           COUNT(DISTINCT order_id) AS order_count,
           SUM(cups_sold) AS cups_sold,
           SUM(sales_amount) AS sales_amount
    FROM dbo.vw_ProductSalesStatistics
    WHERE order_time >= CONVERT(DATETIME2(0), '2026-10-04')
      AND order_time <  CONVERT(DATETIME2(0), '2026-10-05')
      AND product_name LIKE N'%奶茶%'
    GROUP BY product_id, product_name
    ORDER BY product_id;

    SELECT N'奶茶关键词合计' AS metric,
           N'3|4|40.00' AS expected_value,
           CONCAT(COUNT(DISTINCT order_id), N'|', SUM(cups_sold), N'|', CONVERT(DECIMAL(38,2), SUM(sales_amount))) AS actual_value,
           CASE WHEN COUNT(DISTINCT order_id) = 3 AND SUM(cups_sold) = 4 AND SUM(sales_amount) = 40.00
                THEN N'通过' ELSE N'不一致' END AS result
    FROM dbo.vw_ProductSalesStatistics
    WHERE order_time >= CONVERT(DATETIME2(0), '2026-10-04')
      AND order_time <  CONVERT(DATETIME2(0), '2026-10-05')
      AND product_name LIKE N'%奶茶%';
END;

PRINT N'BASELINE 12/12 身份绑定与完成提示';
SELECT b.principal_name, b.member_id, b.guest_id, b.is_active,
       p.type_desc AS principal_type, p.authentication_type_desc
FROM teabar_auth.PrincipalBinding AS b
LEFT JOIN sys.database_principals AS p ON p.sid = b.principal_sid
ORDER BY b.principal_name;

SELECT
    CASE WHEN EXISTS (SELECT 1 FROM @ObjectMetrics WHERE expected_value <> actual_value)
              OR EXISTS (SELECT 1 FROM @Metrics WHERE expected_value <> actual_value OR actual_value IS NULL)
         THEN N'基线采集完成，但存在不一致；不要开始迁移。'
         ELSE N'静态对象和关键样例基准通过；仍需另行确认44项约束、84项角色验证及截图证据。'
    END AS completion_message;
GO
