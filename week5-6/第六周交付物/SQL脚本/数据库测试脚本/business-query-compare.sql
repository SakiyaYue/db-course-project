-- Read-only business comparison for the week 6 report.
-- Run on the v0.1 work copy before migration and again on v1.0 after regression.
SET NOCOUNT ON;
IF DB_NAME()<>N'TeabarDB_Phase2_Work' OR USER_NAME()<>N'dbo' OR @@TRANCOUNT<>0
    THROW 52900,N'请在工作副本中以 dbo、无外层事务运行业务对照。',1;
IF DB_ID(N'TeabarDB') IS NULL
    THROW 52900,N'冻结源库 TeabarDB 不存在。',1;

DECLARE @details TABLE(
    database_name SYSNAME,order_id VARCHAR(10),item_id VARCHAR(10),product_id VARCHAR(10),
    product_name_snapshot NVARCHAR(50),quantity INT,unit_price DECIMAL(10,2),sub_amount DECIMAL(10,2));
INSERT @details
SELECT N'TeabarDB',order_id,item_id,product_id,product_name_snapshot,quantity,unit_price,sub_amount
FROM TeabarDB.dbo.OrderItem
UNION ALL
SELECT N'TeabarDB_Phase2_Work',order_id,item_id,product_id,product_name_snapshot,quantity,unit_price,sub_amount
FROM dbo.OrderItem;
SELECT N'ORDER_DETAILS' AS stage,* FROM @details ORDER BY order_id,item_id,database_name;
IF EXISTS(
    SELECT order_id,item_id,product_id,product_name_snapshot,quantity,unit_price,sub_amount
    FROM @details WHERE database_name=N'TeabarDB'
    EXCEPT
    SELECT order_id,item_id,product_id,product_name_snapshot,quantity,unit_price,sub_amount
    FROM @details WHERE database_name=N'TeabarDB_Phase2_Work')
OR EXISTS(
    SELECT order_id,item_id,product_id,product_name_snapshot,quantity,unit_price,sub_amount
    FROM @details WHERE database_name=N'TeabarDB_Phase2_Work'
    EXCEPT
    SELECT order_id,item_id,product_id,product_name_snapshot,quantity,unit_price,sub_amount
    FROM @details WHERE database_name=N'TeabarDB')
    THROW 52901,N'订单明细前后不一致。',1;

DECLARE @sales TABLE(database_name SYSNAME,product_id VARCHAR(10),cups_sold BIGINT,sales_amount DECIMAL(38,2));
INSERT @sales
SELECT N'TeabarDB',i.product_id,SUM(CONVERT(BIGINT,i.quantity)),SUM(i.sub_amount)
FROM TeabarDB.dbo.OrderItem AS i JOIN TeabarDB.dbo.SalesOrder AS o ON o.order_id=i.order_id
WHERE o.status=N'已完成' AND o.order_time>='20261004' AND o.order_time<'20261005'
GROUP BY i.product_id
UNION ALL
SELECT N'TeabarDB_Phase2_Work',i.product_id,SUM(CONVERT(BIGINT,i.quantity)),SUM(i.sub_amount)
FROM dbo.OrderItem AS i JOIN dbo.SalesOrder AS o ON o.order_id=i.order_id
WHERE o.status=N'已完成' AND o.order_time>='20261004' AND o.order_time<'20261005'
GROUP BY i.product_id;
SELECT N'PRODUCT_SALES_2026_10_04_COMPLETED' AS stage,* FROM @sales ORDER BY product_id,database_name;
IF EXISTS(
    SELECT product_id,cups_sold,sales_amount FROM @sales WHERE database_name=N'TeabarDB'
    EXCEPT
    SELECT product_id,cups_sold,sales_amount FROM @sales WHERE database_name=N'TeabarDB_Phase2_Work')
OR EXISTS(
    SELECT product_id,cups_sold,sales_amount FROM @sales WHERE database_name=N'TeabarDB_Phase2_Work'
    EXCEPT
    SELECT product_id,cups_sold,sales_amount FROM @sales WHERE database_name=N'TeabarDB')
    THROW 52901,N'逐商品销量或销售额前后不一致。',1;

DECLARE @stock TABLE(database_name SYSNAME,ingredient_id VARCHAR(10),ingredient_name NVARCHAR(50),
    unit NVARCHAR(10),stock DECIMAL(10,2),status NVARCHAR(10));
INSERT @stock
SELECT N'TeabarDB',ingredient_id,ingredient_name,unit,stock,status FROM TeabarDB.dbo.Ingredient
UNION ALL
SELECT N'TeabarDB_Phase2_Work',ingredient_id,ingredient_name,unit,stock,status FROM dbo.Ingredient;
SELECT N'INGREDIENT_STOCK' AS stage,* FROM @stock ORDER BY ingredient_id,database_name;
IF EXISTS(
    SELECT ingredient_id,ingredient_name,unit,stock,status FROM @stock WHERE database_name=N'TeabarDB'
    EXCEPT
    SELECT ingredient_id,ingredient_name,unit,stock,status FROM @stock WHERE database_name=N'TeabarDB_Phase2_Work')
OR EXISTS(
    SELECT ingredient_id,ingredient_name,unit,stock,status FROM @stock WHERE database_name=N'TeabarDB_Phase2_Work'
    EXCEPT
    SELECT ingredient_id,ingredient_name,unit,stock,status FROM @stock WHERE database_name=N'TeabarDB')
    THROW 52901,N'原料资料或库存前后不一致。',1;

SELECT N'BUSINESS_DETAIL_COMPARE_PASSED' AS result,
       (SELECT COUNT(*) FROM @details WHERE database_name=N'TeabarDB_Phase2_Work') AS matched_order_items,
       (SELECT COUNT(*) FROM @sales WHERE database_name=N'TeabarDB_Phase2_Work') AS matched_products,
       (SELECT COUNT(*) FROM @stock WHERE database_name=N'TeabarDB_Phase2_Work') AS matched_ingredients;
