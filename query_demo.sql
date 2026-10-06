-- 第四周查询演示：对应 Q01、Q17、Q18。
-- 前置：TeabarDB 已有样例数据，且已执行 view.sql。
-- 只修改输入参数并读取结果，不修改业务数据。
USE TeabarDB;
GO
SET NOCOUNT ON;
GO

-- 1. 商品关键词查询：改成空字符串，可查看全部在售商品。
-- 默认“奶茶”：2 行，椰果奶茶 7 元、珍珠奶茶 8 元。
DECLARE @keyword NVARCHAR(50) = N'奶茶';

SELECT product_id, product_name, base_price
FROM dbo.vw_ProductCatalog
WHERE product_status = N'在售'
  AND product_name LIKE N'%' + @keyword + N'%'
ORDER BY base_price, product_id;
GO

-- 2. 指定关键词和时间范围的销量、营业额。
-- 开始时间包含，结束时间不包含；视图只统计已完成订单。
DECLARE @keyword NVARCHAR(50) = N'奶茶';
DECLARE @start_time DATETIME2(0) = '2026-10-04T00:00:00';
DECLARE @end_time DATETIME2(0) = '2026-10-05T00:00:00';

-- 各商品：珍珠奶茶 3 杯、31 元；椰果奶茶 1 杯、9 元。
SELECT product_id, product_name,
       COUNT(DISTINCT order_id) AS completed_order_count,
       SUM(cups_sold) AS cups_sold,
       SUM(sales_amount) AS sales_amount
FROM dbo.vw_ProductSalesStatistics
WHERE order_time >= @start_time
  AND order_time < @end_time
  AND product_name LIKE N'%' + @keyword + N'%'
GROUP BY product_id, product_name
ORDER BY sales_amount DESC, product_id;

-- 品类合计：3 笔订单、4 杯、40 元。
SELECT @keyword AS product_keyword,
       COUNT(DISTINCT order_id) AS completed_order_count,
       COALESCE(SUM(cups_sold), 0) AS cups_sold,
       COALESCE(SUM(sales_amount), 0) AS sales_amount
FROM dbo.vw_ProductSalesStatistics
WHERE order_time >= @start_time
  AND order_time < @end_time
  AND product_name LIKE N'%' + @keyword + N'%';
GO

-- 3. 当日经营统计：只修改一个日期。
-- 2026-10-04：3 单、5 杯、46 元，平均客单价 15.33 元。
-- 改为 2026-10-05：仍返回一行，各统计值为 0。
DECLARE @business_date DATE = '2026-10-04';

SELECT d.business_date,
       COALESCE(s.completed_order_count, 0) AS completed_order_count,
       COALESCE(s.cups_sold, 0) AS cups_sold,
       COALESCE(s.sales_amount, 0) AS sales_amount,
       COALESCE(s.average_order_amount, 0) AS average_order_amount,
       COALESCE(s.member_order_count, 0) AS member_order_count,
       COALESCE(s.nonmember_order_count, 0) AS nonmember_order_count
FROM (SELECT @business_date AS business_date) AS d
LEFT JOIN dbo.vw_DailySalesStatistics AS s
  ON s.business_date = d.business_date;
GO
