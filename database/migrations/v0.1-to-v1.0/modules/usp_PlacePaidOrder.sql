ALTER PROCEDURE teabar_api.usp_PlacePaidOrder
    @order_id VARCHAR(10),
    @items teabar_api.OrderLines READONLY,
    @specs teabar_api.OrderSpecs READONLY,
    @addons teabar_api.OrderAddOns READONLY,
    @payment_succeeded BIT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    DECLARE @own_transaction BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    IF @own_transaction = 1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION role_operation;
    BEGIN TRY
        -- 课程模拟支付成功；金额在数据库重新计算，不接受客户端报价或订单归属。
        DECLARE @member_id VARCHAR(10), @guest_id UNIQUEIDENTIFIER;
        SELECT @member_id = member_id, @guest_id = guest_id FROM teabar_auth.fn_CurrentIdentity();
        IF (@member_id IS NULL AND @guest_id IS NULL)
           OR (COALESCE(IS_ROLEMEMBER(N'teabar_customer'), 0) = 0
               AND COALESCE(IS_ROLEMEMBER(N'teabar_member'), 0) = 0)
            THROW 52000, N'当前购买身份未绑定或无下单权限。', 1;
        IF @payment_succeeded IS NULL OR @payment_succeeded <> 1
            THROW 52001, N'模拟支付未成功，不创建正式订单。', 1;
        IF @order_id IS NULL OR LEN(LTRIM(RTRIM(@order_id))) = 0 OR NOT EXISTS (SELECT 1 FROM @items)
            THROW 52002, N'订单编号及至少一条明细必须提供。', 1;
        IF EXISTS (SELECT 1 FROM @items WHERE quantity <= 0 OR LEN(LTRIM(RTRIM(item_id))) = 0)
            THROW 52003, N'明细编号不能为空白，数量必须大于0。', 1;
        IF EXISTS (SELECT 1 FROM @specs AS x WHERE NOT EXISTS (SELECT 1 FROM @items AS i WHERE i.item_id = x.item_id))
           OR EXISTS (SELECT 1 FROM @addons AS x WHERE NOT EXISTS (SELECT 1 FROM @items AS i WHERE i.item_id = x.item_id))
            THROW 52004, N'规格或加料引用了本次订单之外的明细。', 1;

        DECLARE @prices TABLE (
            item_id VARCHAR(10) PRIMARY KEY, product_id VARCHAR(10), product_name NVARCHAR(50),
            quantity INT, base_price DECIMAL(10,2), unit_price DECIMAL(10,2)
        );
        INSERT @prices(item_id, product_id, product_name, quantity, base_price)
        SELECT i.item_id, i.product_id, p.product_name, i.quantity, p.base_price
        FROM @items AS i JOIN dbo.Product AS p WITH (UPDLOCK, HOLDLOCK) ON p.product_id = i.product_id
        WHERE p.status = N'在售';
        IF (SELECT COUNT(*) FROM @prices) <> (SELECT COUNT(*) FROM @items)
            THROW 52005, N'商品不存在或未在售。', 1;

        DECLARE @configuration TABLE (
            product_id VARCHAR(10), spec_id VARCHAR(10), spec_type NVARCHAR(20),
            spec_name NVARCHAR(20), price_delta DECIMAL(10,2), status NVARCHAR(10),
            PRIMARY KEY(product_id, spec_id)
        );
        INSERT @configuration
        SELECT ps.product_id, ps.spec_id, s.spec_type, s.spec_name, ps.price_delta, ps.status
        FROM dbo.ProductSpecification AS ps WITH (UPDLOCK, HOLDLOCK)
        JOIN dbo.Specification AS s WITH (HOLDLOCK) ON s.spec_id = ps.spec_id
        WHERE ps.product_id IN (SELECT product_id FROM @prices);
        IF EXISTS (SELECT 1 FROM @prices AS i WHERE NOT EXISTS (SELECT 1 FROM @configuration AS c WHERE c.product_id = i.product_id))
            THROW 52006, N'商品尚未配置规格，不能直接按默认系数下单。', 1;
        IF EXISTS (
            SELECT 1 FROM @specs AS x JOIN @prices AS i ON i.item_id = x.item_id
            WHERE NOT EXISTS (SELECT 1 FROM @configuration AS c WHERE c.product_id = i.product_id AND c.spec_id = x.spec_id AND c.status = N'可用')
        )
            THROW 52007, N'所选规格不适用于该商品或已停用。', 1;
        DECLARE @chosen TABLE (
            item_id VARCHAR(10), spec_type NVARCHAR(20), spec_id VARCHAR(10),
            spec_name NVARCHAR(20), price_delta DECIMAL(10,2)
        );
        INSERT @chosen
        SELECT x.item_id, c.spec_type, c.spec_id, c.spec_name, c.price_delta
        FROM @specs AS x JOIN @prices AS i ON i.item_id = x.item_id
        JOIN @configuration AS c ON c.product_id = i.product_id AND c.spec_id = x.spec_id;
        IF EXISTS (SELECT item_id, spec_type FROM @chosen GROUP BY item_id, spec_type HAVING COUNT(*) > 1)
            THROW 52008, N'同一明细同一规格类型只能选择一个选项。', 1;
        IF EXISTS (
            SELECT i.item_id, c.spec_type FROM @prices AS i JOIN @configuration AS c ON c.product_id = i.product_id
            EXCEPT SELECT item_id, spec_type FROM @chosen
        )
            THROW 52009, N'每种已配置的规格类型必须明确选择一个，默认选项也必须传入。', 1;

        DECLARE @extras TABLE (
            item_id VARCHAR(10), addon_id VARCHAR(10), addon_name NVARCHAR(50),
            price DECIMAL(10,2), ingredient_id VARCHAR(10), extra_amount DECIMAL(10,2)
        );
        INSERT @extras
        SELECT x.item_id, a.addon_id, a.addon_name, a.price, a.ingredient_id, a.extra_amount
        FROM @addons AS x JOIN dbo.AddOn AS a WITH (UPDLOCK, HOLDLOCK) ON a.addon_id = x.addon_id
        WHERE a.status = N'可用';
        IF (SELECT COUNT(*) FROM @extras) <> (SELECT COUNT(*) FROM @addons)
            THROW 52010, N'加料不存在或缺货。', 1;
        UPDATE i SET unit_price = i.base_price
            + COALESCE((SELECT SUM(c.price_delta) FROM @chosen AS c WHERE c.item_id = i.item_id), 0)
            + COALESCE((SELECT SUM(a.price) FROM @extras AS a WHERE a.item_id = i.item_id), 0)
        FROM @prices AS i;
        IF EXISTS (SELECT 1 FROM @prices WHERE unit_price < 0)
            THROW 52011, N'规格差价可以为负，但最终成交单价不能为负。', 1;

        DECLARE @recipe TABLE (
            product_id VARCHAR(10), ingredient_id VARCHAR(10), base_amount DECIMAL(10,2),
            PRIMARY KEY(product_id, ingredient_id)
        );
        INSERT @recipe
        SELECT r.product_id, r.ingredient_id, r.base_amount
        FROM dbo.Recipe AS r WITH (UPDLOCK, HOLDLOCK) WHERE r.product_id IN (SELECT product_id FROM @prices);
        IF EXISTS (SELECT 1 FROM @prices AS i WHERE NOT EXISTS (SELECT 1 FROM @recipe AS r WHERE r.product_id = i.product_id))
            THROW 52012, N'商品缺少基础配方。', 1;
        DECLARE @rules TABLE (
            product_id VARCHAR(10), spec_id VARCHAR(10), ingredient_id VARCHAR(10), factor DECIMAL(5,2),
            PRIMARY KEY(product_id, spec_id, ingredient_id)
        );
        INSERT @rules
        SELECT r.product_id, r.spec_id, r.ingredient_id, r.factor
        FROM dbo.SpecificationIngredient AS r WITH (HOLDLOCK)
        WHERE r.product_id IN (SELECT product_id FROM @prices);
        IF EXISTS (
            SELECT 1 FROM @rules AS r WHERE NOT EXISTS (
                SELECT 1 FROM @recipe AS b WHERE b.product_id = r.product_id AND b.ingredient_id = r.ingredient_id)
        )
            THROW 52013, N'规格规则引用了配方外原料。', 1;

        DECLARE @raw TABLE (
            item_id VARCHAR(10), ingredient_id VARCHAR(10), per_cup DECIMAL(27,8), quantity INT
        );
        ;WITH Choices AS (
            SELECT i.item_id,
                (SELECT spec_id FROM @chosen WHERE item_id = i.item_id AND spec_type = N'糖度') AS sugar,
                (SELECT spec_id FROM @chosen WHERE item_id = i.item_id AND spec_type = N'温度') AS temperature,
                (SELECT spec_id FROM @chosen WHERE item_id = i.item_id AND spec_type = N'杯型') AS cup
            FROM @prices AS i
        )
        INSERT @raw
        SELECT i.item_id, r.ingredient_id,
               r.base_amount * COALESCE(s.factor, 1) * COALESCE(t.factor, 1) * COALESCE(c.factor, 1), i.quantity
        FROM @prices AS i JOIN @recipe AS r ON r.product_id = i.product_id
        JOIN Choices AS x ON x.item_id = i.item_id
        LEFT JOIN @rules AS s ON s.product_id = i.product_id AND s.spec_id = x.sugar AND s.ingredient_id = r.ingredient_id
        LEFT JOIN @rules AS t ON t.product_id = i.product_id AND t.spec_id = x.temperature AND t.ingredient_id = r.ingredient_id
        LEFT JOIN @rules AS c ON c.product_id = i.product_id AND c.spec_id = x.cup AND c.ingredient_id = r.ingredient_id
        UNION ALL
        SELECT a.item_id, a.ingredient_id, a.extra_amount, i.quantity FROM @extras AS a JOIN @prices AS i ON i.item_id = a.item_id;

        IF EXISTS (
            SELECT 1 FROM @raw AS r JOIN dbo.Ingredient AS g WITH (HOLDLOCK) ON g.ingredient_id = r.ingredient_id
            WHERE g.unit = N'个' AND r.per_cup <> FLOOR(r.per_cup)
        ) OR EXISTS (
            SELECT 1 FROM @recipe AS r JOIN dbo.Ingredient AS g WITH (HOLDLOCK) ON g.ingredient_id = r.ingredient_id
            WHERE g.unit = N'个' AND r.base_amount <> FLOOR(r.base_amount)
        )
            THROW 52014, N'计件原料每杯用量必须为整数，不能靠杯数或四舍五入掩盖。', 1;
        DECLARE @consumption TABLE (
            item_id VARCHAR(10), ingredient_id VARCHAR(10), amount DECIMAL(10,2),
            PRIMARY KEY(item_id, ingredient_id)
        );
        INSERT @consumption
        SELECT item_id, ingredient_id, CAST(ROUND(SUM(per_cup * quantity), 2) AS DECIMAL(10,2))
        FROM @raw GROUP BY item_id, ingredient_id
        HAVING ROUND(SUM(per_cup * quantity), 2) > 0;
        -- v1.0 D01: check EVERY input item before stock deduction or persistent inserts.
        IF EXISTS(SELECT 1 FROM @items AS i WHERE NOT EXISTS(
            SELECT 1 FROM @consumption AS c WHERE c.item_id=i.item_id AND c.amount>0))
            THROW 52018, N'订单包含未产生正原料消耗的明细，整单拒绝。', 1;
        DECLARE @needed TABLE (ingredient_id VARCHAR(10) PRIMARY KEY, amount DECIMAL(10,2));
        INSERT @needed SELECT ingredient_id, SUM(amount) FROM @consumption GROUP BY ingredient_id;
        IF NOT EXISTS (SELECT 1 FROM @needed)
            THROW 52015, N'配方未产生有效原料需求。', 1;
        DECLARE @needed_count INT = (SELECT COUNT(*) FROM @needed);
        UPDATE g WITH (UPDLOCK, HOLDLOCK) SET stock = g.stock - n.amount
        FROM dbo.Ingredient AS g JOIN @needed AS n ON n.ingredient_id = g.ingredient_id
        WHERE g.status = N'可用' AND g.stock >= n.amount;
        IF @@ROWCOUNT <> @needed_count
            THROW 52016, N'整笔订单库存不足或原料缺货，下单全部回滚。', 1;

        DECLARE @total DECIMAL(10,2);
        SELECT @total = SUM(CAST(unit_price * quantity AS DECIMAL(10,2))) FROM @prices;
        INSERT dbo.SalesOrder(order_id, member_id, guest_id, total_amount)
            VALUES(@order_id, @member_id, @guest_id, @total);
        INSERT dbo.OrderItem(item_id, order_id, product_id, product_name_snapshot, quantity, base_price_snapshot, unit_price)
            SELECT item_id, @order_id, product_id, product_name, quantity, base_price, unit_price FROM @prices;
        INSERT dbo.ItemSpec(item_id, spec_type, spec_id, spec_name_snapshot, price_delta_snapshot)
            SELECT item_id, spec_type, spec_id, spec_name, price_delta FROM @chosen;
        INSERT dbo.ItemAddOn(item_id, addon_id, addon_name_snapshot, price_snapshot)
            SELECT item_id, addon_id, addon_name, price FROM @extras;
        INSERT dbo.OrderItemIngredient(item_id, ingredient_id, amount)
            SELECT item_id, ingredient_id, amount FROM @consumption;
        IF @total <> (SELECT SUM(sub_amount) FROM dbo.OrderItem WHERE order_id = @order_id)
            THROW 52017, N'订单总额与明细不一致。', 1;
        SELECT @order_id AS order_id, @total AS total_amount, N'排队中' AS status;
        IF @own_transaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_transaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @own_transaction = 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION role_operation;
        THROW;
    END CATCH;
END;
