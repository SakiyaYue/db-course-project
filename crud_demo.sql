-- 第三周 CRUD：使用 seed_data.sql 中的样例，完整执行后回滚。
-- 执行顺序：db_creation.sql → seed_data.sql → query.sql → 本文件。
-- 示例固定为 P001、M001、五分糖／少冰／大杯及加芋圆，不是通用下单接口。
-- 同时演示商品上下架、待取餐订单完成后积分，以及按订单时间匹配值班团队。
USE TeabarDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;

IF DB_NAME() <> N'TeabarDB'
    THROW 51000, N'请在 TeabarDB 中运行。', 1;
IF @@TRANCOUNT <> 0
    THROW 51001, N'请在没有未结束事务的新查询窗口中运行。', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    IF EXISTS (SELECT 1 FROM dbo.Product WHERE product_id = 'CP001')
       OR EXISTS (SELECT 1 FROM dbo.Ingredient WHERE ingredient_id = 'CI001')
       OR EXISTS (SELECT 1 FROM dbo.SalesOrder WHERE order_id IN ('CO001', 'CO002'))
       OR EXISTS (SELECT 1 FROM dbo.OrderItem WHERE item_id IN ('CT001', 'CT002'))
        THROW 51002, N'CRUD 测试编号已被使用，请修改测试编号。', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Product WHERE product_id = 'P001' AND status = N'在售')
       OR NOT EXISTS (SELECT 1 FROM dbo.Ingredient WHERE ingredient_id = 'I001')
       OR NOT EXISTS (SELECT 1 FROM dbo.Member WHERE member_id = 'M001')
       OR NOT EXISTS (SELECT 1 FROM dbo.AddOn WHERE addon_id = 'A001' AND status = N'可用')
       OR NOT EXISTS (SELECT 1 FROM dbo.SalesOrder WHERE order_id = 'O001')
       OR NOT EXISTS (SELECT 1 FROM sys.computed_columns
                      WHERE object_id = OBJECT_ID(N'dbo.OrderItem') AND name = N'sub_amount')
        THROW 51003, N'缺少样例或小计计算列，请先执行最新建库及 seed_data.sql。', 1;

    DECLARE @selected_specs TABLE (spec_id VARCHAR(10) PRIMARY KEY);
    INSERT INTO @selected_specs VALUES ('S002'), ('S005'), ('S008');
    IF (SELECT COUNT(*) FROM @selected_specs AS chosen
        JOIN dbo.ProductSpecification AS ps ON ps.spec_id = chosen.spec_id
        JOIN dbo.Specification AS s ON s.spec_id = ps.spec_id
        WHERE ps.product_id = 'P001' AND ps.status = N'可用'
          AND ((s.spec_id = 'S002' AND s.spec_type = N'糖度')
            OR (s.spec_id = 'S005' AND s.spec_type = N'温度')
            OR (s.spec_id = 'S008' AND s.spec_type = N'杯型'))) <> 3
        THROW 51004, N'缺少 P001 的五分糖、少冰或大杯配置，请先装载样例。', 1;

    -- 1. 商品 C/R/U：新增记录参考样例，修改直接作用于原有 P001。
    SELECT N'商品新增前' AS stage, product_id, product_name, base_price, status
    FROM dbo.Product WHERE product_id = 'CP001';
    INSERT INTO dbo.Product (product_id, product_name, base_price, status, description)
    SELECT 'CP001', product_name + N'（测试新品）', base_price, N'下架', N'参考样例 P001 新增；未配置配方，不上架'
    FROM dbo.Product WHERE product_id = 'P001';
    SELECT N'商品新增后，参考 P001' AS stage, product_id, product_name, base_price, status
    FROM dbo.Product WHERE product_id = 'CP001';

    SELECT N'样例商品改价前' AS stage, product_id, product_name, base_price, status
    FROM dbo.Product WHERE product_id = 'P001';
    UPDATE dbo.Product SET base_price = base_price + 1.00 WHERE product_id = 'P001';
    SELECT N'样例商品改价后，初始化时 6 → 7 元' AS stage, product_id, product_name, base_price, status
    FROM dbo.Product WHERE product_id = 'P001';
    SELECT N'已有订单价格快照保持原值' AS stage, item_id, order_id,
           product_name_snapshot, base_price_snapshot, unit_price, sub_amount
    FROM dbo.OrderItem WHERE product_id = 'P001' ORDER BY item_id;

    -- 已有 P001 已配置配方和规格，演示人工下架及重新上架。
    SELECT N'商品下架前' AS stage, product_id, product_name, status
    FROM dbo.Product WHERE product_id = 'P001' AND status = N'在售';
    UPDATE dbo.Product SET status = N'下架'
    WHERE product_id = 'P001' AND status = N'在售';
    SELECT N'商品下架后' AS stage, product_id, product_name, status
    FROM dbo.Product WHERE product_id = 'P001';
    SELECT N'下架后在售查询，预期 0 行' AS stage, product_id, product_name, status
    FROM dbo.Product WHERE product_id = 'P001' AND status = N'在售';

    SELECT N'商品重新上架前' AS stage, product_id, product_name, status
    FROM dbo.Product WHERE product_id = 'P001' AND status = N'下架';
    UPDATE dbo.Product SET status = N'在售'
    WHERE product_id = 'P001' AND status = N'下架';
    SELECT N'商品重新上架后' AS stage, product_id, product_name, status
    FROM dbo.Product WHERE product_id = 'P001';

    -- 2. 库存 C/R/U：新增测试批次参考 I001，补货直接作用于原有柠檬库存。
    SELECT N'原料新增前' AS stage, ingredient_id, ingredient_name, stock, unit
    FROM dbo.Ingredient WHERE ingredient_id = 'CI001';
    INSERT INTO dbo.Ingredient (ingredient_id, ingredient_name, unit, stock, status)
    SELECT 'CI001', ingredient_name + N'（测试批次）', unit, 1000.00, N'可用'
    FROM dbo.Ingredient WHERE ingredient_id = 'I001';
    SELECT N'原料新增后，参考 I001' AS stage, ingredient_id, ingredient_name, stock, unit
    FROM dbo.Ingredient WHERE ingredient_id = 'CI001';

    SELECT N'样例柠檬补货前' AS stage, ingredient_id, ingredient_name, stock, unit
    FROM dbo.Ingredient WHERE ingredient_id = 'I001';
    UPDATE dbo.Ingredient SET stock = stock + 200.00 WHERE ingredient_id = 'I001';
    SELECT N'样例柠檬补货后，初始化时 5000 → 5200g' AS stage, ingredient_id, stock, unit
    FROM dbo.Ingredient WHERE ingredient_id = 'I001';

    -- 3. 订单 C/R：查询原样例，再让原有会员购买原有商品、规格及加料。
    SELECT N'已有柠檬水订单样例' AS stage, o.order_id, o.member_id, o.status,
           i.item_id, i.product_id, i.quantity, i.unit_price, i.sub_amount
    FROM dbo.SalesOrder AS o
    JOIN dbo.OrderItem AS i ON i.order_id = o.order_id
    WHERE i.product_id = 'P001' ORDER BY o.order_id, i.item_id;

    DECLARE @quantity INT = 2;
    DECLARE @base_price DECIMAL(10,2);
    DECLARE @spec_price DECIMAL(10,2);
    DECLARE @addon_price DECIMAL(10,2);
    DECLARE @unit_price DECIMAL(10,2);
    DECLARE @points_before INT = (SELECT points FROM dbo.Member WHERE member_id = 'M001');
    -- 借用 O001 的样例日期，确保新测试订单落在已装载的排班中。
    DECLARE @demo_order_time DATETIME2(0) = (SELECT order_time FROM dbo.SalesOrder WHERE order_id = 'O001');
    SELECT @base_price = base_price FROM dbo.Product WHERE product_id = 'P001';
    SELECT @spec_price = SUM(ps.price_delta)
    FROM dbo.ProductSpecification AS ps
    JOIN @selected_specs AS chosen ON chosen.spec_id = ps.spec_id
    WHERE ps.product_id = 'P001' AND ps.status = N'可用';
    SELECT @addon_price = price FROM dbo.AddOn WHERE addon_id = 'A001';
    SET @unit_price = @base_price + @spec_price + @addon_price;

    -- 同原料的糖度、温度、杯型系数相乘；缺少某类规则时系数为 1。
    -- 加料按每杯一份单独计算，与基础配方同原料时合并。
    DECLARE @consumption TABLE (ingredient_id VARCHAR(10) PRIMARY KEY, amount DECIMAL(10,2));
    ;WITH RequiredAmounts AS (
        SELECT r.ingredient_id,
               r.base_amount * COALESCE(sugar.factor, 1) * COALESCE(temperature.factor, 1)
               * COALESCE(cup.factor, 1) * @quantity AS amount
        FROM dbo.Recipe AS r
        LEFT JOIN dbo.SpecificationIngredient AS sugar
          ON sugar.product_id = r.product_id AND sugar.ingredient_id = r.ingredient_id AND sugar.spec_id = 'S002'
        LEFT JOIN dbo.SpecificationIngredient AS temperature
          ON temperature.product_id = r.product_id AND temperature.ingredient_id = r.ingredient_id AND temperature.spec_id = 'S005'
        LEFT JOIN dbo.SpecificationIngredient AS cup
          ON cup.product_id = r.product_id AND cup.ingredient_id = r.ingredient_id AND cup.spec_id = 'S008'
        WHERE r.product_id = 'P001'
        UNION ALL
        SELECT ingredient_id, extra_amount * @quantity FROM dbo.AddOn WHERE addon_id = 'A001'
    )
    INSERT INTO @consumption (ingredient_id, amount)
    SELECT ingredient_id, CAST(SUM(amount) AS DECIMAL(10,2))
    FROM RequiredAmounts GROUP BY ingredient_id
    HAVING CAST(SUM(amount) AS DECIMAL(10,2)) > 0;
    DECLARE @ingredient_count INT = (SELECT COUNT(*) FROM @consumption);
    IF @ingredient_count = 0
        THROW 51005, N'样例配方缺失，未生成原料消耗。', 1;

    DECLARE @stock_before TABLE (ingredient_id VARCHAR(10) PRIMARY KEY, stock DECIMAL(10,2));
    INSERT INTO @stock_before
    SELECT g.ingredient_id, g.stock FROM dbo.Ingredient AS g
    JOIN @consumption AS c ON c.ingredient_id = g.ingredient_id;

    SELECT N'订单新增前' AS stage, order_id, total_amount, status
    FROM dbo.SalesOrder WHERE order_id = 'CO001';
    SELECT N'样例原料扣库目标' AS stage, g.ingredient_id, g.ingredient_name, g.stock, g.unit,
           c.amount AS deduct_amount, g.stock - c.amount AS expected_stock
    FROM dbo.Ingredient AS g
    JOIN @consumption AS c ON c.ingredient_id = g.ingredient_id
    WHERE g.status = N'可用' AND g.stock >= c.amount;
    UPDATE g SET g.stock = g.stock - c.amount
    FROM dbo.Ingredient AS g
    JOIN @consumption AS c ON c.ingredient_id = g.ingredient_id
    WHERE g.status = N'可用' AND g.stock >= c.amount;
    IF @@ROWCOUNT <> @ingredient_count
        THROW 51006, N'样例原料缺失、不可用或库存不足，下单操作回滚。', 1;

    INSERT INTO dbo.SalesOrder (order_id, member_id, order_time, total_amount, status)
    VALUES ('CO001', 'M001', @demo_order_time, @unit_price * @quantity, N'排队中');
    INSERT INTO dbo.OrderItem
        (item_id, order_id, product_id, product_name_snapshot, quantity, base_price_snapshot, unit_price)
    SELECT 'CT001', 'CO001', product_id, product_name, @quantity, @base_price, @unit_price
    FROM dbo.Product WHERE product_id = 'P001';
    INSERT INTO dbo.ItemSpec (item_id, spec_type, spec_id, spec_name_snapshot, price_delta_snapshot)
    SELECT 'CT001', s.spec_type, s.spec_id, s.spec_name, ps.price_delta
    FROM dbo.ProductSpecification AS ps
    JOIN dbo.Specification AS s ON s.spec_id = ps.spec_id
    JOIN @selected_specs AS chosen ON chosen.spec_id = ps.spec_id
    WHERE ps.product_id = 'P001' AND ps.status = N'可用';
    INSERT INTO dbo.ItemAddOn (item_id, addon_id, addon_name_snapshot, price_snapshot)
    SELECT 'CT001', addon_id, addon_name, price FROM dbo.AddOn WHERE addon_id = 'A001';
    INSERT INTO dbo.OrderItemIngredient (item_id, ingredient_id, amount)
    SELECT 'CT001', ingredient_id, amount FROM @consumption;

    SELECT N'新订单关联原样例，初始化时总额 20 元' AS stage,
           o.order_id, o.member_id, m.name AS member_name, o.status, o.total_amount,
           i.item_id, i.product_id, i.product_name_snapshot, i.quantity, i.unit_price, i.sub_amount
    FROM dbo.SalesOrder AS o
    JOIN dbo.OrderItem AS i ON i.order_id = o.order_id
    JOIN dbo.Member AS m ON m.member_id = o.member_id
    WHERE o.order_id = 'CO001';
    SELECT N'新订单规格快照来自样例配置' AS stage, item_id, spec_type, spec_id, spec_name_snapshot, price_delta_snapshot
    FROM dbo.ItemSpec WHERE item_id = 'CT001';
    SELECT N'新订单加料快照来自样例 A001' AS stage, item_id, addon_id, addon_name_snapshot, price_snapshot
    FROM dbo.ItemAddOn WHERE item_id = 'CT001';
    SELECT N'下单扣库后' AS stage, g.ingredient_id, g.ingredient_name, g.stock, g.unit, c.amount
    FROM dbo.Ingredient AS g
    JOIN dbo.OrderItemIngredient AS c ON c.ingredient_id = g.ingredient_id
    WHERE c.item_id = 'CT001';
    IF (SELECT total_amount FROM dbo.SalesOrder WHERE order_id = 'CO001')
       <> (SELECT SUM(sub_amount) FROM dbo.OrderItem WHERE order_id = 'CO001')
       OR EXISTS (SELECT 1 FROM @stock_before AS b JOIN @consumption AS c ON c.ingredient_id = b.ingredient_id
                  JOIN dbo.Ingredient AS g ON g.ingredient_id = b.ingredient_id WHERE g.stock <> b.stock - c.amount)
        THROW 51007, N'订单金额或原料扣库不一致。', 1;

    -- 4. 订单 U：取消刚插入的排队订单，按保存的消耗快照返库。
    SELECT N'取消前' AS stage, order_id, total_amount, status
    FROM dbo.SalesOrder WHERE order_id = 'CO001' AND status = N'排队中';
    UPDATE dbo.SalesOrder SET status = N'已取消'
    WHERE order_id = 'CO001' AND status = N'排队中';
    IF @@ROWCOUNT <> 1
        THROW 51008, N'只有排队中的订单可以取消。', 1;
    SELECT N'样例原料返库目标' AS stage, g.ingredient_id, g.stock, g.unit,
           c.amount AS restore_amount, g.stock + c.amount AS expected_stock
    FROM dbo.Ingredient AS g
    JOIN (
        SELECT c.ingredient_id, SUM(c.amount) AS amount
        FROM dbo.OrderItemIngredient AS c
        JOIN dbo.OrderItem AS i ON i.item_id = c.item_id
        WHERE i.order_id = 'CO001' GROUP BY c.ingredient_id
    ) AS c ON c.ingredient_id = g.ingredient_id;
    UPDATE g SET g.stock = g.stock + c.amount
    FROM dbo.Ingredient AS g
    JOIN (
        SELECT c.ingredient_id, SUM(c.amount) AS amount
        FROM dbo.OrderItemIngredient AS c
        JOIN dbo.OrderItem AS i ON i.item_id = c.item_id
        WHERE i.order_id = 'CO001' GROUP BY c.ingredient_id
    ) AS c ON c.ingredient_id = g.ingredient_id;
    SELECT N'取消后' AS stage, order_id, total_amount, status
    FROM dbo.SalesOrder WHERE order_id = 'CO001';
    SELECT N'返库后，柠檬回到补货后的 5200g' AS stage, g.ingredient_id, g.stock, g.unit
    FROM dbo.Ingredient AS g
    JOIN @stock_before AS b ON b.ingredient_id = g.ingredient_id;
    IF EXISTS (SELECT 1 FROM @stock_before AS b JOIN dbo.Ingredient AS g ON g.ingredient_id = b.ingredient_id
               WHERE g.stock <> b.stock)
        THROW 51009, N'取消后的库存恢复结果不一致。', 1;

    SELECT N'取消订单不增加积分' AS stage, member_id, name, points, @points_before AS original_points
    FROM dbo.Member WHERE member_id = 'M001';
    IF (SELECT points FROM dbo.Member WHERE member_id = 'M001') <> @points_before
        THROW 51010, N'取消订单不应增加会员积分。', 1;

    -- 5. 正常完成及积分：直接准备一笔待取餐订单，不逐段演示制作状态。
    -- CO002／CT002 使用相同样例配置，已有付款和制作步骤在此省略展示。
    SELECT N'待取餐订单新增前' AS stage, order_id, member_id, status
    FROM dbo.SalesOrder WHERE order_id = 'CO002';
    SELECT N'正常订单扣库目标' AS stage, g.ingredient_id, g.stock, g.unit,
           c.amount AS deduct_amount, g.stock - c.amount AS expected_stock
    FROM dbo.Ingredient AS g
    JOIN @consumption AS c ON c.ingredient_id = g.ingredient_id
    WHERE g.status = N'可用' AND g.stock >= c.amount;
    UPDATE g SET g.stock = g.stock - c.amount
    FROM dbo.Ingredient AS g
    JOIN @consumption AS c ON c.ingredient_id = g.ingredient_id
    WHERE g.status = N'可用' AND g.stock >= c.amount;
    IF @@ROWCOUNT <> @ingredient_count
        THROW 51011, N'正常订单原料缺失、不可用或库存不足。', 1;

    INSERT INTO dbo.SalesOrder (order_id, member_id, order_time, total_amount, status)
    VALUES ('CO002', 'M001', DATEADD(MINUTE, 5, @demo_order_time), @unit_price * @quantity, N'待取餐');
    INSERT INTO dbo.OrderItem
        (item_id, order_id, product_id, product_name_snapshot, quantity, base_price_snapshot, unit_price)
    SELECT 'CT002', 'CO002', product_id, product_name, @quantity, @base_price, @unit_price
    FROM dbo.Product WHERE product_id = 'P001';
    INSERT INTO dbo.ItemSpec (item_id, spec_type, spec_id, spec_name_snapshot, price_delta_snapshot)
    SELECT 'CT002', s.spec_type, s.spec_id, s.spec_name, ps.price_delta
    FROM dbo.ProductSpecification AS ps
    JOIN dbo.Specification AS s ON s.spec_id = ps.spec_id
    JOIN @selected_specs AS chosen ON chosen.spec_id = ps.spec_id
    WHERE ps.product_id = 'P001' AND ps.status = N'可用';
    INSERT INTO dbo.ItemAddOn (item_id, addon_id, addon_name_snapshot, price_snapshot)
    SELECT 'CT002', addon_id, addon_name, price FROM dbo.AddOn WHERE addon_id = 'A001';
    INSERT INTO dbo.OrderItemIngredient (item_id, ingredient_id, amount)
    SELECT 'CT002', ingredient_id, amount FROM @consumption;

    -- 条件更新成功的订单通过 OUTPUT 进入本次积分集合，完成和加分在同一事务中。
    DECLARE @completed_orders TABLE (
        order_id VARCHAR(10) PRIMARY KEY, member_id VARCHAR(10), total_amount DECIMAL(10,2)
    );
    SELECT N'正常订单完成前' AS stage, order_id, member_id, total_amount, status
    FROM dbo.SalesOrder WHERE order_id = 'CO002' AND status = N'待取餐';
    UPDATE dbo.SalesOrder SET status = N'已完成'
    OUTPUT inserted.order_id, inserted.member_id, inserted.total_amount INTO @completed_orders
    WHERE order_id = 'CO002' AND status = N'待取餐';
    IF @@ROWCOUNT <> 1
        THROW 51012, N'只有待取餐订单能在本例完成并结算积分。', 1;

    -- 沿用数据字典的实现假设：完成订单金额向下取整，每 1 元积 1 分。
    SELECT N'会员积分结算前' AS stage, m.member_id, m.name, m.points,
           c.order_id, CAST(FLOOR(c.total_amount) AS INT) AS points_to_add
    FROM dbo.Member AS m
    JOIN @completed_orders AS c ON c.member_id = m.member_id;
    UPDATE m SET m.points = m.points + CAST(FLOOR(c.total_amount) AS INT)
    FROM dbo.Member AS m
    JOIN @completed_orders AS c ON c.member_id = m.member_id;
    SELECT N'正常订单完成后，初始化时积分 120 → 140' AS stage,
           o.order_id, o.status, o.total_amount, m.member_id, m.name, m.points
    FROM dbo.SalesOrder AS o
    JOIN dbo.Member AS m ON m.member_id = o.member_id
    WHERE o.order_id = 'CO002';
    IF (SELECT points FROM dbo.Member WHERE member_id = 'M001')
       <> @points_before + CAST(FLOOR(@unit_price * @quantity) AS INT)
        THROW 51013, N'正常订单完成后的积分不符合预期。', 1;

    -- 再尝试同一完成条件，应更新 0 行；没有首次完成的输出记录，不再次结算。
    DECLARE @repeat_completed TABLE (
        order_id VARCHAR(10) PRIMARY KEY, member_id VARCHAR(10), total_amount DECIMAL(10,2)
    );
    SELECT N'重复完成的目标，预期 0 行' AS stage, order_id, member_id, total_amount, status
    FROM dbo.SalesOrder WHERE order_id = 'CO002' AND status = N'待取餐';
    UPDATE dbo.SalesOrder SET status = N'已完成'
    OUTPUT inserted.order_id, inserted.member_id, inserted.total_amount INTO @repeat_completed
    WHERE order_id = 'CO002' AND status = N'待取餐';
    DECLARE @repeat_count INT = @@ROWCOUNT;
    SELECT N'重复完成未结算，积分仍为 140' AS stage,
           member_id, points, @repeat_count AS repeated_completion_rows
    FROM dbo.Member WHERE member_id = 'M001';
    IF @repeat_count <> 0 OR EXISTS (SELECT 1 FROM @repeat_completed)
       OR (SELECT points FROM dbo.Member WHERE member_id = 'M001')
          <> @points_before + CAST(FLOOR(@unit_price * @quantity) AS INT)
        THROW 51014, N'重复完成订单不能重复增加积分。', 1;

    SELECT N'完成订单保留库存消耗' AS stage, g.ingredient_id, g.stock, g.unit, c.amount
    FROM dbo.Ingredient AS g
    JOIN dbo.OrderItemIngredient AS c ON c.ingredient_id = g.ingredient_id
    WHERE c.item_id = 'CT002';

    -- 6. 团队归属：修改此编号即可查询其他订单；同时对照交接后的样例 O004。
    -- 一笔订单对应下单时全部值班员工，不保存单一负责人，也不按当前在职状态过滤。
    DECLARE @team_order_id VARCHAR(10) = 'CO002';
    SELECT N'订单按创建时间匹配值班团队' AS stage, o.order_id, o.order_time,
           d.duty_id, e.employee_id, e.name AS employee_name, e.role,
           d.start_time, d.end_time,
           CASE WHEN d.duty_id IS NULL THEN N'未匹配排班' ELSE N'已匹配' END AS roster_match
    FROM dbo.SalesOrder AS o
    LEFT JOIN dbo.DutyRoster AS d ON d.start_time <= o.order_time AND o.order_time < d.end_time
    LEFT JOIN dbo.Employee AS e ON e.employee_id = d.employee_id
    WHERE o.order_id IN (@team_order_id, 'O004')
    ORDER BY o.order_id, e.employee_id;

    -- 7. D：清理取消分支及测试基础资料；完成订单保留到最终回滚。
    SELECT N'明细规格删除前' AS stage, item_id, spec_type, spec_id, spec_name_snapshot, price_delta_snapshot
    FROM dbo.ItemSpec WHERE item_id = 'CT001';
    DELETE FROM dbo.ItemSpec WHERE item_id = 'CT001';
    SELECT N'明细加料删除前' AS stage, item_id, addon_id, addon_name_snapshot, price_snapshot
    FROM dbo.ItemAddOn WHERE item_id = 'CT001';
    DELETE FROM dbo.ItemAddOn WHERE item_id = 'CT001';
    SELECT N'原料消耗快照删除前' AS stage, item_id, ingredient_id, amount
    FROM dbo.OrderItemIngredient WHERE item_id = 'CT001';
    DELETE FROM dbo.OrderItemIngredient WHERE item_id = 'CT001';
    SELECT N'订单明细删除前' AS stage, item_id, order_id, product_id, quantity, unit_price, sub_amount
    FROM dbo.OrderItem WHERE item_id = 'CT001';
    DELETE FROM dbo.OrderItem WHERE item_id = 'CT001';
    SELECT N'订单删除前' AS stage, order_id, status
    FROM dbo.SalesOrder WHERE order_id = 'CO001' AND status = N'已取消';
    DELETE FROM dbo.SalesOrder WHERE order_id = 'CO001' AND status = N'已取消';
    SELECT N'订单删除后，预期 0 行' AS stage, order_id, status
    FROM dbo.SalesOrder WHERE order_id = 'CO001';

    SELECT N'商品删除前' AS stage, product_id, product_name
    FROM dbo.Product WHERE product_id = 'CP001';
    DELETE FROM dbo.Product WHERE product_id = 'CP001';
    SELECT N'商品删除后，预期 0 行' AS stage, product_id FROM dbo.Product WHERE product_id = 'CP001';
    SELECT N'原料删除前' AS stage, ingredient_id, ingredient_name, stock, unit
    FROM dbo.Ingredient WHERE ingredient_id = 'CI001';
    DELETE FROM dbo.Ingredient WHERE ingredient_id = 'CI001';
    SELECT N'原料删除后，预期 0 行' AS stage, ingredient_id FROM dbo.Ingredient WHERE ingredient_id = 'CI001';

    ROLLBACK TRANSACTION;
    SELECT N'回滚后的原样例商品，预期 6 元' AS stage, product_id, product_name, base_price
    FROM dbo.Product WHERE product_id = 'P001';
    SELECT N'回滚后的原样例柠檬，预期 5000g' AS stage, ingredient_id, ingredient_name, stock, unit
    FROM dbo.Ingredient WHERE ingredient_id = 'I001';
    SELECT N'回滚后的原会员积分，预期 120' AS stage, member_id, name, points
    FROM dbo.Member WHERE member_id = 'M001';
    SELECT N'回滚后的完成测试订单，预期 0 行' AS stage, order_id, status
    FROM dbo.SalesOrder WHERE order_id = 'CO002';
    PRINT N'CRUD 演示成功；事务已回滚，原样例价格、上下架状态、库存、会员积分及历史订单保持不变。';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
