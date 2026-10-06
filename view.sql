-- 第四周视图：对应 docs/第四周查询.md 中选定的业务查询。
-- 可重复执行；CREATE OR ALTER 会创建新视图或更新已有视图。
-- 先执行 db_creation.sql 和 seed_data.sql，再执行本文件。
USE TeabarDB;
GO
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
-- 清理已从本次方案移除的旧配方库存视图。
DROP VIEW IF EXISTS dbo.vw_ProductRecipeStock;
GO

-- 商品与可选配置（V01—V04）

-- 1. 商品目录：一行一个商品。调用时再筛选在售和名称关键词。
CREATE OR ALTER VIEW dbo.vw_ProductCatalog
AS
SELECT p.product_id,
       p.product_name,
       p.base_price,
       p.description,
       p.status AS product_status
FROM dbo.Product AS p;
GO

-- 2. 商品规格配置：一行表示某商品的一项规格配置。
CREATE OR ALTER VIEW dbo.vw_ProductSpecification
AS
SELECT p.product_id,
       p.product_name,
       p.base_price,
       p.status AS product_status,
       s.spec_id,
       s.spec_type,
       s.spec_name,
       ps.price_delta,
       ps.status AS config_status
FROM dbo.Product AS p
JOIN dbo.ProductSpecification AS ps
  ON ps.product_id = p.product_id
JOIN dbo.Specification AS s
  ON s.spec_id = ps.spec_id;
GO

-- 3. 规格原料规则：一行表示某商品、某规格作用于一种基础原料。
-- 没有显式调整规则时 effective_factor 为 1，系数 0 会正常保留。
-- adjusted_amount 保留乘积精度，不压回基础用量字段的 DECIMAL(10,2)。
CREATE OR ALTER VIEW dbo.vw_SpecificationIngredientRule
AS
SELECT p.product_id,
       p.product_name,
       p.status AS product_status,
       s.spec_id,
       s.spec_type,
       s.spec_name,
       ps.price_delta,
       ps.status AS config_status,
       r.ingredient_id,
       g.ingredient_name,
       g.unit,
       r.base_amount,
       si.factor AS explicit_factor,
       CAST(COALESCE(si.factor, 1) AS DECIMAL(5,2)) AS effective_factor,
       r.base_amount * COALESCE(si.factor, 1) AS adjusted_amount,
       CASE WHEN si.ingredient_id IS NULL THEN N'无调整规则，按1'
            ELSE N'显式规则' END AS rule_source
FROM dbo.Product AS p
JOIN dbo.ProductSpecification AS ps
  ON ps.product_id = p.product_id
JOIN dbo.Specification AS s
  ON s.spec_id = ps.spec_id
JOIN dbo.Recipe AS r
  ON r.product_id = p.product_id
JOIN dbo.Ingredient AS g
  ON g.ingredient_id = r.ingredient_id
LEFT JOIN dbo.SpecificationIngredient AS si
  ON si.product_id = ps.product_id
 AND si.spec_id = ps.spec_id
 AND si.ingredient_id = r.ingredient_id;
GO

-- 4. 加料可用情况：一行一种加料，只判断购买一份。
CREATE OR ALTER VIEW dbo.vw_AddOnAvailability
AS
SELECT a.addon_id,
       a.addon_name,
       a.price,
       a.extra_amount,
       a.status AS addon_status,
       g.ingredient_id,
       g.ingredient_name,
       g.unit,
       g.stock,
       g.status AS ingredient_status,
       CAST(CASE WHEN a.status = N'可用'
                       AND g.status = N'可用'
                       AND g.stock >= a.extra_amount
                       AND (g.unit <> N'个'
                            OR (a.extra_amount = FLOOR(a.extra_amount)
                                AND g.stock = FLOOR(g.stock)))
                 THEN 1 ELSE 0 END AS BIT) AS can_choose_one,
       CASE WHEN a.status <> N'可用' THEN N'加料不可用'
            WHEN g.status <> N'可用' THEN N'对应原料不可用'
            WHEN g.stock < a.extra_amount THEN N'库存不足一份'
            WHEN g.unit = N'个'
             AND (a.extra_amount <> FLOOR(a.extra_amount)
                  OR g.stock <> FLOOR(g.stock)) THEN N'计件数量不是整数'
            ELSE N'可选择一份' END AS availability_reason
FROM dbo.AddOn AS a
JOIN dbo.Ingredient AS g
  ON g.ingredient_id = a.ingredient_id;
GO

-- 原料库存（V05）

-- 5. 原料库存：一行一种原料。
CREATE OR ALTER VIEW dbo.vw_IngredientStock
AS
SELECT g.ingredient_id,
       g.ingredient_name,
       g.unit,
       g.stock,
       g.status AS ingredient_status,
       CASE WHEN g.unit = N'个' AND g.stock <> FLOOR(g.stock)
            THEN N'计件库存异常' ELSE N'正常' END AS unit_check
FROM dbo.Ingredient AS g;
GO

-- 订单与退款依据（V06—V08）

-- 6. 订单概要：一行一笔订单，先汇总明细再连接。
CREATE OR ALTER VIEW dbo.vw_OrderSummary
AS
WITH ItemTotals AS (
    SELECT i.order_id,
           COUNT(*) AS item_rows,
           SUM(CONVERT(BIGINT, i.quantity)) AS total_cups,
           SUM(i.sub_amount) AS item_amount
    FROM dbo.OrderItem AS i
    GROUP BY i.order_id
)
SELECT o.order_id,
       o.order_time,
       o.member_id,
       COALESCE(m.name, N'非会员') AS member_name,
       o.status AS order_status,
       o.total_amount,
       COALESCE(t.item_rows, 0) AS item_rows,
       COALESCE(t.total_cups, 0) AS total_cups,
       COALESCE(t.item_amount, 0) AS item_amount,
       CAST(CASE WHEN t.order_id IS NULL THEN 1 ELSE 0 END AS BIT) AS missing_items,
       CAST(CASE WHEN t.order_id IS NOT NULL AND o.total_amount = t.item_amount
                 THEN 1 ELSE 0 END AS BIT) AS amount_matches_items
FROM dbo.SalesOrder AS o
LEFT JOIN dbo.Member AS m
  ON m.member_id = o.member_id
LEFT JOIN ItemTotals AS t
  ON t.order_id = o.order_id;
GO

-- 7. 订单详情：一行一条明细，规格和加料分别汇总，避免行数膨胀。
CREATE OR ALTER VIEW dbo.vw_OrderDetail
AS
WITH Specs AS (
    SELECT s.item_id,
           NULLIF(MAX(CASE WHEN s.spec_type = N'糖度'
                           THEN s.spec_name_snapshot ELSE N'' END), N'') AS sugar,
           NULLIF(MAX(CASE WHEN s.spec_type = N'温度'
                           THEN s.spec_name_snapshot ELSE N'' END), N'') AS temperature,
           NULLIF(MAX(CASE WHEN s.spec_type = N'杯型'
                           THEN s.spec_name_snapshot ELSE N'' END), N'') AS cup
    FROM dbo.ItemSpec AS s
    GROUP BY s.item_id
)
SELECT o.order_id,
       o.order_time,
       o.status AS order_status,
       i.item_id,
       i.product_id,
       i.product_name_snapshot,
       i.quantity,
       COALESCE(s.sugar, N'未记录') AS sugar,
       COALESCE(s.temperature, N'未记录') AS temperature,
       COALESCE(s.cup, N'未记录') AS cup,
       COALESCE(a.addons, N'无加料') AS addons,
       i.base_price_snapshot,
       i.unit_price,
       i.sub_amount
FROM dbo.SalesOrder AS o
JOIN dbo.OrderItem AS i
  ON i.order_id = o.order_id
LEFT JOIN Specs AS s
  ON s.item_id = i.item_id
OUTER APPLY (
    SELECT STUFF((
        SELECT N'、' + ia.addon_name_snapshot
        FROM dbo.ItemAddOn AS ia
        WHERE ia.item_id = i.item_id
        ORDER BY ia.addon_id
        FOR XML PATH(''), TYPE
    ).value('.', 'NVARCHAR(MAX)'), 1, 1, N'') AS addons
) AS a;
GO

-- 8. 订单原料快照：一行表示一笔订单的一种原料。
-- amount 已含明细全部杯数，不能再乘 quantity。
CREATE OR ALTER VIEW dbo.vw_OrderIngredientUsage
AS
SELECT o.order_id,
       o.order_time,
       o.status AS order_status,
       c.ingredient_id,
       g.ingredient_name,
       g.unit,
       SUM(c.amount) AS saved_amount,
       CASE WHEN o.status = N'排队中'
                 AND NOT EXISTS (
                     SELECT 1
                     FROM dbo.OrderItem AS missing_item
                     WHERE missing_item.order_id = o.order_id
                       AND NOT EXISTS (
                           SELECT 1
                           FROM dbo.OrderItemIngredient AS saved
                           WHERE saved.item_id = missing_item.item_id
                       )
                 )
            THEN SUM(c.amount)
            ELSE CAST(0 AS DECIMAL(38,2)) END AS refundable_amount,
       CASE WHEN o.status = N'排队中'
                 AND NOT EXISTS (
                     SELECT 1
                     FROM dbo.OrderItem AS missing_item
                     WHERE missing_item.order_id = o.order_id
                       AND NOT EXISTS (
                           SELECT 1
                           FROM dbo.OrderItemIngredient AS saved
                           WHERE saved.item_id = missing_item.item_id
                       )
                 ) THEN N'当前可按快照申请返库'
            WHEN o.status = N'排队中' THEN N'明细缺少消耗快照，暂不能确定完整返库数量'
            WHEN o.status = N'已取消' THEN N'仅查看历史依据，不能再次返库'
            ELSE N'当前状态不允许退款' END AS refund_eligibility
FROM dbo.SalesOrder AS o
JOIN dbo.OrderItem AS i
  ON i.order_id = o.order_id
JOIN dbo.OrderItemIngredient AS c
  ON c.item_id = i.item_id
JOIN dbo.Ingredient AS g
  ON g.ingredient_id = c.ingredient_id
GROUP BY o.order_id, o.order_time, o.status,
         c.ingredient_id, g.ingredient_name, g.unit;
GO

-- 会员消费（V09）

-- 9. 会员消费统计：一行一个会员，保留尚未完成订单或从未下单的会员。
CREATE OR ALTER VIEW dbo.vw_MemberConsumptionStatistics
AS
WITH OrderCups AS (
    SELECT i.order_id,
           SUM(CONVERT(BIGINT, i.quantity)) AS cups
    FROM dbo.OrderItem AS i
    GROUP BY i.order_id
), CompletedOrders AS (
    SELECT o.order_id,
           o.member_id,
           o.order_time,
           o.total_amount,
           COALESCE(c.cups, 0) AS cups
    FROM dbo.SalesOrder AS o
    LEFT JOIN OrderCups AS c
      ON c.order_id = o.order_id
    WHERE o.status = N'已完成'
      AND o.member_id IS NOT NULL
), MemberTotals AS (
    SELECT member_id,
           COUNT(*) AS completed_order_count,
           SUM(cups) AS cups_purchased,
           SUM(total_amount) AS total_spending,
           AVG(CAST(total_amount AS DECIMAL(18,2))) AS average_order_amount,
           MIN(order_time) AS first_purchase_time,
           MAX(order_time) AS last_purchase_time
    FROM CompletedOrders
    GROUP BY member_id
)
SELECT m.member_id,
       m.name AS member_name,
       m.phone,
       m.points AS current_points,
       COALESCE(t.completed_order_count, 0) AS completed_order_count,
       COALESCE(t.cups_purchased, 0) AS cups_purchased,
       CAST(COALESCE(t.total_spending, 0) AS DECIMAL(38,2)) AS total_spending,
       CAST(COALESCE(t.average_order_amount, 0) AS DECIMAL(18,2)) AS average_order_amount,
       t.first_purchase_time,
       t.last_purchase_time
FROM dbo.Member AS m
LEFT JOIN MemberTotals AS t
  ON t.member_id = m.member_id;
GO

-- 员工与值班安排（V10—V11）

-- 10. 员工排班：一行一条值班记录。月薪不放入通用排班视图。
CREATE OR ALTER VIEW dbo.vw_DutyRosterDetail
AS
SELECT d.duty_id,
       e.employee_id,
       e.name AS employee_name,
       e.role,
       e.status AS current_employee_status,
       d.start_time,
       d.end_time
FROM dbo.DutyRoster AS d
JOIN dbo.Employee AS e
  ON e.employee_id = d.employee_id;
GO

-- 11. 订单值班团队：一笔订单可以匹配多名员工。
CREATE OR ALTER VIEW dbo.vw_OrderDutyTeam
AS
SELECT o.order_id,
       o.order_time,
       o.status AS order_status,
       d.duty_id,
       e.employee_id,
       e.name AS employee_name,
       e.role,
       e.status AS current_employee_status,
       d.start_time,
       d.end_time,
       CASE WHEN d.duty_id IS NULL THEN N'未匹配排班'
            ELSE N'已匹配' END AS roster_match
FROM dbo.SalesOrder AS o
LEFT JOIN dbo.DutyRoster AS d
  ON d.start_time <= o.order_time
 AND o.order_time < d.end_time
LEFT JOIN dbo.Employee AS e
  ON e.employee_id = d.employee_id;
GO

-- 经营统计（V12—V13）

-- 12. 商品销量与营业额：一行表示一笔已完成订单中的一种商品。
-- 保留订单时间，调用时可按任意起止时间和商品名称关键词筛选。
CREATE OR ALTER VIEW dbo.vw_ProductSalesStatistics
AS
SELECT o.order_id,
       o.order_time,
       i.product_id,
       i.product_name_snapshot AS product_name,
       SUM(CONVERT(BIGINT, i.quantity)) AS cups_sold,
       CAST(SUM(i.sub_amount) AS DECIMAL(38,2)) AS sales_amount
FROM dbo.SalesOrder AS o
JOIN dbo.OrderItem AS i
  ON i.order_id = o.order_id
WHERE o.status = N'已完成'
GROUP BY o.order_id, o.order_time,
         i.product_id, i.product_name_snapshot;
GO

-- 13. 每日经营统计：一行一天，只汇总已完成订单。
-- 先按订单汇总杯数，避免订单金额因多条明细而重复。
CREATE OR ALTER VIEW dbo.vw_DailySalesStatistics
AS
WITH OrderCups AS (
    SELECT i.order_id,
           SUM(CONVERT(BIGINT, i.quantity)) AS cups
    FROM dbo.OrderItem AS i
    GROUP BY i.order_id
)
SELECT CAST(o.order_time AS DATE) AS business_date,
       COUNT_BIG(*) AS completed_order_count,
       SUM(COALESCE(c.cups, 0)) AS cups_sold,
       CAST(SUM(o.total_amount) AS DECIMAL(38,2)) AS sales_amount,
       CAST(AVG(CAST(o.total_amount AS DECIMAL(18,2))) AS DECIMAL(18,2)) AS average_order_amount,
       SUM(CASE WHEN o.member_id IS NOT NULL THEN CONVERT(BIGINT, 1) ELSE 0 END) AS member_order_count,
       SUM(CASE WHEN o.member_id IS NULL THEN CONVERT(BIGINT, 1) ELSE 0 END) AS nonmember_order_count
FROM dbo.SalesOrder AS o
LEFT JOIN OrderCups AS c
  ON c.order_id = o.order_id
WHERE o.status = N'已完成'
GROUP BY CAST(o.order_time AS DATE);
GO

-- 验证查询
-- 初始化样例的预期行数：4、36、153、3、9、5、7、29、4、5、10、4、1。

SELECT N'vw_ProductCatalog' AS view_name, COUNT(*) AS row_count FROM dbo.vw_ProductCatalog
UNION ALL SELECT N'vw_ProductSpecification', COUNT(*) FROM dbo.vw_ProductSpecification
UNION ALL SELECT N'vw_SpecificationIngredientRule', COUNT(*) FROM dbo.vw_SpecificationIngredientRule
UNION ALL SELECT N'vw_AddOnAvailability', COUNT(*) FROM dbo.vw_AddOnAvailability
UNION ALL SELECT N'vw_IngredientStock', COUNT(*) FROM dbo.vw_IngredientStock
UNION ALL SELECT N'vw_OrderSummary', COUNT(*) FROM dbo.vw_OrderSummary
UNION ALL SELECT N'vw_OrderDetail', COUNT(*) FROM dbo.vw_OrderDetail
UNION ALL SELECT N'vw_OrderIngredientUsage', COUNT(*) FROM dbo.vw_OrderIngredientUsage
UNION ALL SELECT N'vw_MemberConsumptionStatistics', COUNT(*) FROM dbo.vw_MemberConsumptionStatistics
UNION ALL SELECT N'vw_DutyRosterDetail', COUNT(*) FROM dbo.vw_DutyRosterDetail
UNION ALL SELECT N'vw_OrderDutyTeam', COUNT(*) FROM dbo.vw_OrderDutyTeam
UNION ALL SELECT N'vw_ProductSalesStatistics', COUNT(*) FROM dbo.vw_ProductSalesStatistics
UNION ALL SELECT N'vw_DailySalesStatistics', COUNT(*) FROM dbo.vw_DailySalesStatistics;

-- 商品目录与规格：预期奶茶 2 行，P001 可用规格 9 行。
SELECT product_id, product_name, base_price
FROM dbo.vw_ProductCatalog
WHERE product_status = N'在售' AND product_name LIKE N'%奶茶%'
ORDER BY base_price, product_id;

SELECT product_id, product_name, spec_type, spec_name, price_delta
FROM dbo.vw_ProductSpecification
WHERE product_id = 'P001'
  AND product_status = N'在售'
  AND config_status = N'可用'
ORDER BY spec_type, spec_id;

-- 订单概要：预期 5 行，所有金额核对通过。
SELECT order_id, order_time, member_name, order_status,
       total_amount, item_rows, total_cups, amount_matches_items
FROM dbo.vw_OrderSummary
ORDER BY order_time, order_id;

-- O001 制作详情：预期 2 行。
SELECT order_id, item_id, product_name_snapshot, quantity,
       sugar, temperature, cup, addons, unit_price, sub_amount
FROM dbo.vw_OrderDetail
WHERE order_id = 'O001'
ORDER BY item_id;

-- Q12 原料快照：O001 预期 8 行，可返量均为 0；O005 预期 7 行且可返。
SELECT order_id, order_status, ingredient_name, saved_amount,
       unit, refundable_amount, refund_eligibility
FROM dbo.vw_OrderIngredientUsage
WHERE order_id IN ('O001', 'O005')
ORDER BY order_id, ingredient_id;

-- 会员消费：预期 M001 为 1 单、3 杯、28 元，M004 无消费也会保留。
SELECT member_id, member_name, current_points,
       completed_order_count, cups_purchased,
       total_spending, average_order_amount,
       first_purchase_time, last_purchase_time
FROM dbo.vw_MemberConsumptionStatistics
ORDER BY total_spending DESC, member_id;

-- 订单团队：预期共 10 行；无匹配诊断为 0 行。
SELECT order_id, order_time, employee_id, employee_name,
       start_time, end_time, roster_match
FROM dbo.vw_OrderDutyTeam
ORDER BY order_id, employee_id;

SELECT order_id, order_time, order_status, roster_match
FROM dbo.vw_OrderDutyTeam
WHERE duty_id IS NULL
ORDER BY order_id;

-- “奶茶”在 10 月 4 日已完成订单中的销量／营业额。
-- 预期：P002 为 3 杯、31 元；P003 为 1 杯、9 元。
SELECT product_id, product_name,
       COUNT(DISTINCT order_id) AS completed_order_count,
       SUM(cups_sold) AS cups_sold,
       SUM(sales_amount) AS sales_amount
FROM dbo.vw_ProductSalesStatistics
WHERE order_time >= '2026-10-04T00:00:00'
  AND order_time < '2026-10-05T00:00:00'
  AND product_name LIKE N'%奶茶%'
GROUP BY product_id, product_name
ORDER BY sales_amount DESC, cups_sold DESC, product_id;

-- 每日经营：预期 2026-10-04 为 3 单、5 杯、46 元，平均客单价 15.33 元。
SELECT business_date, completed_order_count, cups_sold,
       sales_amount, average_order_amount,
       member_order_count, nonmember_order_count
FROM dbo.vw_DailySalesStatistics
ORDER BY business_date;
GO
