-- 初始化后可独立运行的只读查询。多对多子表先聚合，避免金额重复统计。
USE TeabarDB;
GO
SET NOCOUNT ON;
IF DB_NAME() <> N'TeabarDB' THROW 51100, N'请在 TeabarDB 中运行。', 1;

-- 1. 在售商品：商品状态不等于特定规格、加料下的库存充足。
SELECT product_id, product_name, base_price, status, description
FROM dbo.Product WHERE status = N'在售' ORDER BY product_id;

-- 2. 原料库存；库存单位不同，不能把全部库存数量直接相加。
SELECT ingredient_id, ingredient_name, stock, unit, status
FROM dbo.Ingredient ORDER BY ingredient_id;

-- 3. 商品配方。
SELECT p.product_id, p.product_name, g.ingredient_name, r.base_amount, g.unit
FROM dbo.Product AS p
JOIN dbo.Recipe AS r ON r.product_id = p.product_id
JOIN dbo.Ingredient AS g ON g.ingredient_id = r.ingredient_id
ORDER BY p.product_id, g.ingredient_id;

-- 4. 商品可用规格及每杯加价。
SELECT p.product_name, s.spec_type, s.spec_name, ps.price_delta
FROM dbo.ProductSpecification AS ps
JOIN dbo.Product AS p ON p.product_id = ps.product_id
JOIN dbo.Specification AS s ON s.spec_id = ps.spec_id
WHERE ps.status = N'可用' ORDER BY p.product_id, s.spec_type, s.spec_id;

-- 5. 订单与会员，包括非会员订单。
SELECT o.order_id, o.order_time, o.status, o.total_amount,
       o.member_id, COALESCE(m.name, N'非会员') AS member_name
FROM dbo.SalesOrder AS o
LEFT JOIN dbo.Member AS m ON m.member_id = o.member_id
ORDER BY o.order_time, o.order_id;

-- 6. 单笔订单详情，编号可改；规格、加料、消耗分开查，避免联接相乘。
DECLARE @order_id VARCHAR(10) = 'O001';
SELECT item_id, product_name_snapshot, quantity, base_price_snapshot, unit_price, sub_amount
FROM dbo.OrderItem WHERE order_id = @order_id ORDER BY item_id;
SELECT s.item_id, s.spec_type, s.spec_name_snapshot, s.price_delta_snapshot
FROM dbo.ItemSpec AS s JOIN dbo.OrderItem AS i ON i.item_id = s.item_id
WHERE i.order_id = @order_id ORDER BY s.item_id, s.spec_type;
SELECT a.item_id, a.addon_name_snapshot, a.price_snapshot
FROM dbo.ItemAddOn AS a JOIN dbo.OrderItem AS i ON i.item_id = a.item_id
WHERE i.order_id = @order_id ORDER BY a.item_id, a.addon_id;
SELECT c.item_id, g.ingredient_name, c.amount, g.unit
FROM dbo.OrderItemIngredient AS c
JOIN dbo.OrderItem AS i ON i.item_id = c.item_id
JOIN dbo.Ingredient AS g ON g.ingredient_id = c.ingredient_id
WHERE i.order_id = @order_id ORDER BY c.item_id, c.ingredient_id;

-- 7. 按订单时间匹配当时值班团队，保留没有排班匹配的订单。
-- 查询历史班次时不要加 Employee.status = 在职，离职员工也有历史值班。
SELECT o.order_id, o.order_time, e.employee_id, e.name AS employee_name,
       d.start_time, d.end_time
FROM dbo.SalesOrder AS o
LEFT JOIN dbo.DutyRoster AS d ON d.start_time <= o.order_time AND o.order_time < d.end_time
LEFT JOIN dbo.Employee AS e ON e.employee_id = d.employee_id
ORDER BY o.order_id, e.employee_id;

-- 8. 已完成订单的每日销售额；样例初始化后 2026-10-04 为 46 元、3 单。
SELECT CAST(order_time AS DATE) AS sales_date, COUNT(*) AS completed_orders,
       SUM(total_amount) AS sales_amount
FROM dbo.SalesOrder WHERE status = N'已完成'
GROUP BY CAST(order_time AS DATE) ORDER BY sales_date;

-- 9. 订单金额核对：正常结果为 0 行，同时发现没有明细的订单。
SELECT o.order_id, o.total_amount, COALESCE(SUM(i.sub_amount), 0) AS item_total
FROM dbo.SalesOrder AS o
LEFT JOIN dbo.OrderItem AS i ON i.order_id = o.order_id
GROUP BY o.order_id, o.total_amount
HAVING COUNT(i.item_id) = 0 OR o.total_amount <> COALESCE(SUM(i.sub_amount), 0);

-- 10. 明细成交单价核对：正常结果为 0 行，分别聚合规格和加料。
SELECT i.item_id, i.unit_price,
       i.base_price_snapshot + COALESCE(s.spec_price, 0) + COALESCE(a.addon_price, 0) AS expected_price
FROM dbo.OrderItem AS i
LEFT JOIN (SELECT item_id, SUM(price_delta_snapshot) AS spec_price FROM dbo.ItemSpec GROUP BY item_id) AS s
    ON s.item_id = i.item_id
LEFT JOIN (SELECT item_id, SUM(price_snapshot) AS addon_price FROM dbo.ItemAddOn GROUP BY item_id) AS a
    ON a.item_id = i.item_id
WHERE i.unit_price <> i.base_price_snapshot + COALESCE(s.spec_price, 0) + COALESCE(a.addon_price, 0);
