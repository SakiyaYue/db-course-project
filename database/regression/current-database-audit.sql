/*
    当前 TeabarDB 只读状态审计
    适用于尚未完整安装 constraint.sql / role.sql / view.sql 的数据库。
    不创建、修改或删除持久对象和业务数据。
*/

USE TeabarDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

IF DB_NAME() <> N'TeabarDB'
    THROW 54100, N'当前数据库不是 TeabarDB，停止审计。', 1;

PRINT N'AUDIT 01/10 环境';
SELECT
    N'<local-sql-server>' AS server_name,
    CONVERT(NVARCHAR(128), SERVERPROPERTY(N'ProductVersion')) AS product_version,
    CONVERT(NVARCHAR(128), SERVERPROPERTY(N'ProductLevel')) AS product_level,
    CONVERT(NVARCHAR(128), SERVERPROPERTY(N'Edition')) AS edition,
    DB_NAME() AS database_name,
    d.compatibility_level,
    d.collation_name,
    d.recovery_model_desc,
    d.state_desc,
    N'<windows-integrated-login>' AS original_login,
    USER_NAME() AS database_user,
    SYSDATETIMEOFFSET() AS captured_at
FROM sys.databases AS d
WHERE d.database_id = DB_ID();

PRINT N'AUDIT 02/10 对象与安全模块摘要';
SELECT N'dbo业务表' AS metric, 15 AS full_v01_expected,
       COUNT(*) AS actual_value
FROM sys.tables AS t JOIN sys.schemas AS s ON s.schema_id = t.schema_id
WHERE s.name COLLATE DATABASE_DEFAULT = N'dbo'
  AND t.name COLLATE DATABASE_DEFAULT IN (
      N'Employee', N'DutyRoster', N'Member', N'SalesOrder', N'Product',
      N'Specification', N'Ingredient', N'OrderItem', N'ProductSpecification',
      N'Recipe', N'AddOn', N'ItemSpec', N'ItemAddOn',
      N'OrderItemIngredient', N'SpecificationIngredient')
UNION ALL
SELECT N'物理表总数', 16, COUNT(*) FROM sys.tables
UNION ALL
SELECT N'物理字段总数', 74, COUNT(*)
FROM sys.columns AS c JOIN sys.tables AS t ON t.object_id = c.object_id
UNION ALL
SELECT N'外键', 19, COUNT(*) FROM sys.foreign_keys
UNION ALL
SELECT N'CHECK约束', NULL, COUNT(*) FROM sys.check_constraints
UNION ALL
SELECT N'默认约束', 12, COUNT(*) FROM sys.default_constraints
UNION ALL
SELECT N'dbo正式视图', 13, COUNT(*)
FROM sys.views AS v JOIN sys.schemas AS s ON s.schema_id = v.schema_id
WHERE s.name COLLATE DATABASE_DEFAULT = N'dbo'
UNION ALL
SELECT N'teabar_api接口视图', 16, COUNT(*)
FROM sys.views AS v JOIN sys.schemas AS s ON s.schema_id = v.schema_id
WHERE s.name COLLATE DATABASE_DEFAULT = N'teabar_api'
UNION ALL
SELECT N'teabar_api接口过程', 15, COUNT(*)
FROM sys.procedures AS p JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name COLLATE DATABASE_DEFAULT = N'teabar_api'
UNION ALL
SELECT N'teabar_api表值类型', 3, COUNT(*)
FROM sys.table_types AS tt JOIN sys.schemas AS s ON s.schema_id = tt.schema_id
WHERE s.name COLLATE DATABASE_DEFAULT = N'teabar_api'
UNION ALL
SELECT N'业务数据库角色', 4, COUNT(*)
FROM sys.database_principals
WHERE type = 'R' AND name COLLATE DATABASE_DEFAULT IN
      (N'teabar_customer', N'teabar_member', N'teabar_clerk', N'teabar_manager')
UNION ALL
SELECT N'WITHOUT LOGIN演示用户', 6, COUNT(*)
FROM sys.database_principals
WHERE type = 'S' AND authentication_type = 0
  AND name COLLATE DATABASE_DEFAULT IN
      (N'demo_guest_a', N'demo_guest_b', N'demo_member_a', N'demo_member_b', N'demo_clerk', N'demo_manager');

PRINT N'AUDIT 03/10 关键升级标记';
SELECT
    CASE WHEN COL_LENGTH(N'dbo.SalesOrder', N'guest_id') IS NOT NULL THEN 1 ELSE 0 END AS has_salesorder_guest_id,
    CASE WHEN OBJECT_ID(N'dbo.CK_SalesOrder_Owner', N'C') IS NOT NULL THEN 1 ELSE 0 END AS has_order_owner_check,
    CASE WHEN OBJECT_ID(N'dbo.FK_SpecificationIngredient_Recipe', N'F') IS NOT NULL THEN 1 ELSE 0 END AS has_recipe_composite_fk,
    CASE WHEN OBJECT_ID(N'teabar_auth.PrincipalBinding', N'U') IS NOT NULL THEN 1 ELSE 0 END AS has_principal_binding,
    CASE WHEN SCHEMA_ID(N'teabar_auth') IS NOT NULL THEN 1 ELSE 0 END AS has_auth_schema,
    CASE WHEN SCHEMA_ID(N'teabar_api') IS NOT NULL THEN 1 ELSE 0 END AS has_api_schema,
    CASE WHEN OBJECT_ID(N'dbo.vw_OrderSummary', N'V') IS NOT NULL THEN 1 ELSE 0 END AS has_order_summary_view,
    CASE WHEN OBJECT_ID(N'teabar_api.usp_PlacePaidOrder', N'P') IS NOT NULL THEN 1 ELSE 0 END AS has_place_order_api;

SELECT
    c.name AS orderitem_sub_amount_column,
    c.is_computed,
    cc.is_persisted,
    cc.definition
FROM sys.columns AS c
LEFT JOIN sys.computed_columns AS cc ON cc.object_id = c.object_id AND cc.column_id = c.column_id
WHERE c.object_id = OBJECT_ID(N'dbo.OrderItem') AND c.name COLLATE DATABASE_DEFAULT = N'sub_amount';

PRINT N'AUDIT 04/10 当前对象名称';
SELECT s.name AS schema_name, o.name AS object_name, o.type_desc
FROM sys.objects AS o JOIN sys.schemas AS s ON s.schema_id = o.schema_id
WHERE o.is_ms_shipped = 0
  AND o.type IN ('U', 'V', 'P', 'FN', 'IF', 'TF')
ORDER BY s.name, o.type, o.name;

PRINT N'AUDIT 05/10 外键与CHECK信任状态';
SELECT
    OBJECT_SCHEMA_NAME(parent_object_id) AS schema_name,
    OBJECT_NAME(parent_object_id) AS table_name,
    name AS foreign_key_name,
    is_disabled,
    is_not_trusted
FROM sys.foreign_keys
ORDER BY schema_name, table_name, foreign_key_name;

SELECT
    OBJECT_SCHEMA_NAME(parent_object_id) AS schema_name,
    OBJECT_NAME(parent_object_id) AS table_name,
    name AS check_name,
    is_disabled,
    is_not_trusted,
    definition
FROM sys.check_constraints
ORDER BY schema_name, table_name, check_name;

PRINT N'AUDIT 06/10 业务表行数';
SELECT N'Employee' AS table_name, COUNT_BIG(*) AS row_count FROM dbo.Employee
UNION ALL SELECT N'DutyRoster', COUNT_BIG(*) FROM dbo.DutyRoster
UNION ALL SELECT N'Member', COUNT_BIG(*) FROM dbo.Member
UNION ALL SELECT N'SalesOrder', COUNT_BIG(*) FROM dbo.SalesOrder
UNION ALL SELECT N'Product', COUNT_BIG(*) FROM dbo.Product
UNION ALL SELECT N'Specification', COUNT_BIG(*) FROM dbo.Specification
UNION ALL SELECT N'Ingredient', COUNT_BIG(*) FROM dbo.Ingredient
UNION ALL SELECT N'OrderItem', COUNT_BIG(*) FROM dbo.OrderItem
UNION ALL SELECT N'ProductSpecification', COUNT_BIG(*) FROM dbo.ProductSpecification
UNION ALL SELECT N'Recipe', COUNT_BIG(*) FROM dbo.Recipe
UNION ALL SELECT N'AddOn', COUNT_BIG(*) FROM dbo.AddOn
UNION ALL SELECT N'ItemSpec', COUNT_BIG(*) FROM dbo.ItemSpec
UNION ALL SELECT N'ItemAddOn', COUNT_BIG(*) FROM dbo.ItemAddOn
UNION ALL SELECT N'OrderItemIngredient', COUNT_BIG(*) FROM dbo.OrderItemIngredient
UNION ALL SELECT N'SpecificationIngredient', COUNT_BIG(*) FROM dbo.SpecificationIngredient;

SELECT SUM(row_count) AS total_business_rows
FROM (
    SELECT COUNT_BIG(*) AS row_count FROM dbo.Employee
    UNION ALL SELECT COUNT_BIG(*) FROM dbo.DutyRoster
    UNION ALL SELECT COUNT_BIG(*) FROM dbo.Member
    UNION ALL SELECT COUNT_BIG(*) FROM dbo.SalesOrder
    UNION ALL SELECT COUNT_BIG(*) FROM dbo.Product
    UNION ALL SELECT COUNT_BIG(*) FROM dbo.Specification
    UNION ALL SELECT COUNT_BIG(*) FROM dbo.Ingredient
    UNION ALL SELECT COUNT_BIG(*) FROM dbo.OrderItem
    UNION ALL SELECT COUNT_BIG(*) FROM dbo.ProductSpecification
    UNION ALL SELECT COUNT_BIG(*) FROM dbo.Recipe
    UNION ALL SELECT COUNT_BIG(*) FROM dbo.AddOn
    UNION ALL SELECT COUNT_BIG(*) FROM dbo.ItemSpec
    UNION ALL SELECT COUNT_BIG(*) FROM dbo.ItemAddOn
    UNION ALL SELECT COUNT_BIG(*) FROM dbo.OrderItemIngredient
    UNION ALL SELECT COUNT_BIG(*) FROM dbo.SpecificationIngredient
) AS x;

PRINT N'AUDIT 07/10 关键样例';
SELECT COUNT_BIG(*) AS product_count FROM dbo.Product;
SELECT COUNT_BIG(*) AS ingredient_count FROM dbo.Ingredient;
SELECT COUNT_BIG(*) AS order_count FROM dbo.SalesOrder;
SELECT COUNT_BIG(*) AS item_count FROM dbo.OrderItem;
SELECT product_id, base_price, status FROM dbo.Product WHERE product_id = 'P001';
SELECT ingredient_id, stock, unit, status FROM dbo.Ingredient WHERE ingredient_id = 'I001';
SELECT member_id, points FROM dbo.Member WHERE member_id = 'M001';
SELECT order_id FROM dbo.SalesOrder WHERE order_id IN ('CO001', 'CO002') ORDER BY order_id;

PRINT N'AUDIT 08/10 订单金额一致性';
WITH ItemTotals AS (
    SELECT order_id, COUNT_BIG(*) AS item_rows,
           SUM(CONVERT(BIGINT, quantity)) AS total_cups,
           SUM(sub_amount) AS item_amount
    FROM dbo.OrderItem
    GROUP BY order_id
)
SELECT o.order_id, o.total_amount, COALESCE(i.item_rows, 0) AS item_rows,
       COALESCE(i.total_cups, 0) AS total_cups,
       COALESCE(i.item_amount, 0) AS item_amount,
       CASE WHEN i.order_id IS NOT NULL AND o.total_amount = i.item_amount THEN 1 ELSE 0 END AS amount_matches_items
FROM dbo.SalesOrder AS o
LEFT JOIN ItemTotals AS i ON i.order_id = o.order_id
ORDER BY o.order_id;

PRINT N'AUDIT 09/10 每日经营与奶茶关键词';
WITH OrderCups AS (
    SELECT order_id, SUM(CONVERT(BIGINT, quantity)) AS cups
    FROM dbo.OrderItem GROUP BY order_id
)
SELECT CONVERT(DATE, o.order_time) AS business_date,
       COUNT_BIG(*) AS completed_order_count,
       SUM(COALESCE(c.cups, 0)) AS cups_sold,
       CAST(SUM(o.total_amount) AS DECIMAL(38,2)) AS sales_amount,
       CAST(AVG(CAST(o.total_amount AS DECIMAL(18,2))) AS DECIMAL(18,2)) AS average_order_amount
FROM dbo.SalesOrder AS o
LEFT JOIN OrderCups AS c ON c.order_id = o.order_id
WHERE o.status = N'已完成' AND CONVERT(DATE, o.order_time) = CONVERT(DATE, '2026-10-04')
GROUP BY CONVERT(DATE, o.order_time);

SELECT i.product_id, i.product_name_snapshot AS product_name,
       COUNT(DISTINCT o.order_id) AS order_count,
       SUM(CONVERT(BIGINT, i.quantity)) AS cups_sold,
       CAST(SUM(i.sub_amount) AS DECIMAL(38,2)) AS sales_amount
FROM dbo.SalesOrder AS o
JOIN dbo.OrderItem AS i ON i.order_id = o.order_id
WHERE o.status = N'已完成'
  AND o.order_time >= CONVERT(DATETIME2(0), '2026-10-04')
  AND o.order_time < CONVERT(DATETIME2(0), '2026-10-05')
  AND i.product_name_snapshot LIKE N'%奶茶%'
GROUP BY i.product_id, i.product_name_snapshot
ORDER BY i.product_id;

SELECT COUNT(DISTINCT o.order_id) AS order_count,
       SUM(CONVERT(BIGINT, i.quantity)) AS cups_sold,
       CAST(SUM(i.sub_amount) AS DECIMAL(38,2)) AS sales_amount
FROM dbo.SalesOrder AS o
JOIN dbo.OrderItem AS i ON i.order_id = o.order_id
WHERE o.status = N'已完成'
  AND o.order_time >= CONVERT(DATETIME2(0), '2026-10-04')
  AND o.order_time < CONVERT(DATETIME2(0), '2026-10-05')
  AND i.product_name_snapshot LIKE N'%奶茶%';

PRINT N'AUDIT 10/10 最终诊断标志';
SELECT
    CASE
        WHEN OBJECT_ID(N'teabar_auth.PrincipalBinding', N'U') IS NULL
          OR OBJECT_ID(N'teabar_api.usp_PlacePaidOrder', N'P') IS NULL
          OR OBJECT_ID(N'dbo.vw_OrderSummary', N'V') IS NULL
          OR COL_LENGTH(N'dbo.SalesOrder', N'guest_id') IS NULL
        THEN N'当前数据库不是完整安装后的v0.1，禁止作为迁移源。'
        ELSE N'完整v0.1关键对象存在，仍需核对全部基准与测试。'
    END AS final_diagnosis;
GO
