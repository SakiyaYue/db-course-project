-- Generated test-only extraction from constraint.sql; no installation DDL.
SET XACT_ABORT OFF;

DECLARE @prefix VARCHAR(8) = 'VC' + LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 6);
DECLARE @employee VARCHAR(10) = @prefix + 'E1', @duty VARCHAR(10) = @prefix + 'D1';
DECLARE @member VARCHAR(10) = @prefix + 'M1', @member2 VARCHAR(10) = @prefix + 'M2';
DECLARE @product VARCHAR(10) = @prefix + 'P1';
DECLARE @spec VARCHAR(10) = @prefix + 'S1', @spec2 VARCHAR(10) = @prefix + 'S2';
DECLARE @ingredient VARCHAR(10) = @prefix + 'I1', @outside VARCHAR(10) = @prefix + 'I2';
DECLARE @tea VARCHAR(10) = @prefix + 'I3', @piece VARCHAR(10) = @prefix + 'I4';
DECLARE @addon VARCHAR(10) = @prefix + 'A1', @order VARCHAR(10) = @prefix + 'O1';
DECLARE @guest_order VARCHAR(10) = @prefix + 'O2', @guest_order2 VARCHAR(10) = @prefix + 'O3';
DECLARE @item VARCHAR(10) = @prefix + 'T1', @item2 VARCHAR(10) = @prefix + 'T2';
DECLARE @missing VARCHAR(10) = @prefix + 'XX', @guest UNIQUEIDENTIFIER = NEWID();
DECLARE @phone VARCHAR(20);
WHILE @phone IS NULL OR EXISTS (SELECT 1 FROM dbo.Member WHERE phone = @phone)
    SET @phone = '199' + RIGHT('00000000' + CONVERT(VARCHAR(8),
        ABS(CONVERT(BIGINT, CHECKSUM(NEWID()))) % 100000000), 8);
DECLARE @start DATETIME2(0) = '2099-01-01T08:00:00';

DECLARE @negative_cases TABLE (
    seq INT IDENTITY PRIMARY KEY,
    case_name NVARCHAR(100), statement NVARCHAR(MAX),
    expected_error INT, expected_object NVARCHAR(128)
);
INSERT INTO @negative_cases (case_name, statement, expected_error, expected_object) VALUES
    (N'主键：重复商品编号', N'INSERT dbo.Product(product_id, product_name, base_price) VALUES(@product, N''重复商品'', 0);', 2627, N'PK_Product'),
    (N'联合主键：重复配方', N'INSERT dbo.Recipe(product_id, ingredient_id, base_amount) VALUES(@product, @ingredient, 1);', 2627, N'PK_Recipe'),
    (N'UNIQUE：重复会员手机号', N'INSERT dbo.Member(member_id, name, phone) VALUES(@member2, N''重复手机号'', @phone);', 2627, N'UK_Member_Phone'),
    (N'UNIQUE：同员工相同值班开始时间', N'INSERT dbo.DutyRoster(duty_id, employee_id, start_time, end_time) VALUES(@missing, @employee, @start, DATEADD(HOUR, 9, @start));', 2627, N'UQ_DutyRoster_Employee_StartTime'),
    (N'外键：配方引用不存在的原料', N'INSERT dbo.Recipe(product_id, ingredient_id, base_amount) VALUES(@product, @missing, 1);', 547, N'FK_Recipe_Ingredient'),
    (N'外键：明细引用不存在的订单', N'INSERT dbo.OrderItem(item_id, order_id, product_id, product_name_snapshot, base_price_snapshot, unit_price) VALUES(@item2, @missing, @product, N''测试商品'', 0, 0);', 547, N'FK_OrderItem_Order'),
    (N'复合外键：规格规则原料不在商品配方中', N'INSERT dbo.SpecificationIngredient(product_id, spec_id, ingredient_id, factor) VALUES(@product, @spec, @outside, 1);', 547, N'FK_SpecificationIngredient_Recipe'),
    (N'复合外键：商品没有配置该规格', N'INSERT dbo.SpecificationIngredient(product_id, spec_id, ingredient_id, factor) VALUES(@product, @spec2, @ingredient, 1);', 547, N'FK_SpecificationIngredient_ProductSpec'),
    (N'复合外键：规格编号与类型不匹配', N'INSERT dbo.ItemSpec(item_id, spec_type, spec_id, spec_name_snapshot, price_delta_snapshot) VALUES(@item, N''杯型'', @spec, N''测试选项'', 0);', 547, N'FK_ItemSpec_Spec_id'),
    (N'联合主键：同明细同类型选择两个规格', N'INSERT dbo.ItemSpec(item_id, spec_type, spec_id, spec_name_snapshot, price_delta_snapshot) VALUES(@item, N''糖度'', @spec2, N''第二选项'', 0);', 2627, N'PK_ItemSpec'),
    (N'联合主键：同明细重复选择一种加料', N'INSERT dbo.ItemAddOn(item_id, addon_id, addon_name_snapshot, price_snapshot) VALUES(@item, @addon, N''测试加料'', 1);', 2627, N'PK_ItemAddOn'),
    (N'CHECK：库存不能为负', N'UPDATE dbo.Ingredient SET stock = -1 WHERE ingredient_id = @ingredient;', 547, N'CK_Ingredient_Stock'),
    (N'CHECK：计件库存不能有小数', N'UPDATE dbo.Ingredient SET stock = 1.5 WHERE ingredient_id = @piece;', 547, N'CK_Ingredient_PieceStock'),
    (N'CHECK：购买数量必须大于零', N'UPDATE dbo.OrderItem SET quantity = 0 WHERE item_id = @item;', 547, N'CK_OrderItem_Quantity'),
    (N'CHECK：商品基础价格不能为负', N'UPDATE dbo.Product SET base_price = -1 WHERE product_id = @product;', 547, N'CK_Product_Price'),
    (N'CHECK：明细基础价格不能为负', N'UPDATE dbo.OrderItem SET base_price_snapshot = -1 WHERE item_id = @item;', 547, N'CK_OrderItem_BasePrice'),
    (N'CHECK：成交单价不能为负', N'UPDATE dbo.OrderItem SET unit_price = -1 WHERE item_id = @item;', 547, N'CK_OrderItem_UnitPrice'),
    (N'CHECK：订单金额不能为负', N'UPDATE dbo.SalesOrder SET total_amount = -1 WHERE order_id = @order;', 547, N'CK_SalesOrder_Amount'),
    (N'CHECK：会员积分不能为负', N'UPDATE dbo.Member SET points = -1 WHERE member_id = @member;', 547, N'CK_Member_Points'),
    (N'CHECK：员工月薪不能为负', N'UPDATE dbo.Employee SET salary = -1 WHERE employee_id = @employee;', 547, N'CK_Employee_Salary'),
    (N'CHECK：员工岗位只能为店员或店长', N'UPDATE dbo.Employee SET role = N''配送员'' WHERE employee_id = @employee;', 547, N'CK_Employee_Role'),
    (N'CHECK：订单状态枚举', N'UPDATE dbo.SalesOrder SET status = N''配送中'' WHERE order_id = @order;', 547, N'CK_SalesOrder_status'),
    (N'CHECK：商品状态枚举', N'UPDATE dbo.Product SET status = N''未知'' WHERE product_id = @product;', 547, N'CK_Product_Status'),
    (N'CHECK：商品名称不能是空白', N'UPDATE dbo.Product SET product_name = N''   '' WHERE product_id = @product;', 547, N'CK_Product_Name_NotBlank'),
    (N'NOT NULL：商品名称不能为NULL', N'UPDATE dbo.Product SET product_name = NULL WHERE product_id = @product;', 515, N'product_name'),
    (N'CHECK：会员手机号格式', N'UPDATE dbo.Member SET phone = ''1990000ABCD'' WHERE member_id = @member;', 547, N'CK_Member_Phone_Format'),
    (N'CHECK：值班结束必须晚于开始', N'UPDATE dbo.DutyRoster SET end_time = start_time WHERE duty_id = @duty;', 547, N'CK_DutyRoster_Time'),
    (N'CHECK：配方用量必须大于零', N'UPDATE dbo.Recipe SET base_amount = 0 WHERE product_id = @product AND ingredient_id = @ingredient;', 547, N'CK_Recipe_BaseAmount'),
    (N'CHECK：规格系数不能为负', N'UPDATE dbo.SpecificationIngredient SET factor = -1 WHERE product_id = @product AND spec_id = @spec AND ingredient_id = @ingredient;', 547, N'CK_SpecificationIngredient_Factor'),
    (N'CHECK：加料用量必须大于零', N'UPDATE dbo.AddOn SET extra_amount = 0 WHERE addon_id = @addon;', 547, N'CK_AddOn_ExtraAmount'),
    (N'CHECK：加料价格不能为负', N'UPDATE dbo.AddOn SET price = -1 WHERE addon_id = @addon;', 547, N'CK_AddOn_Price'),
    (N'CHECK：原料消耗快照必须大于零', N'UPDATE dbo.OrderItemIngredient SET amount = 0 WHERE item_id = @item AND ingredient_id = @ingredient;', 547, N'CK_OrderItemIngredient_Amount'),
    (N'CHECK：会员和游客归属不能同时为空', N'UPDATE dbo.SalesOrder SET member_id = NULL, guest_id = NULL WHERE order_id = @order;', 547, N'CK_SalesOrder_Owner'),
    (N'CHECK：会员和游客归属不能同时填写', N'UPDATE dbo.SalesOrder SET guest_id = @guest WHERE order_id = @order;', 547, N'CK_SalesOrder_Owner'),
    (N'删除保护：不能删除被规格规则引用的配方', N'DELETE dbo.Recipe WHERE product_id = @product AND ingredient_id = @ingredient;', 547, N'FK_SpecificationIngredient_Recipe'),
    (N'删除保护：不能删除被订单引用的会员', N'DELETE dbo.Member WHERE member_id = @member;', 547, N'FK_SalesOrder_Member'),
    (N'计算列：不能直接修改明细小计', N'UPDATE dbo.OrderItem SET sub_amount = 1 WHERE item_id = @item;', 271, N'sub_amount'),
    (N'CHECK：值班编号不能是空白', N'INSERT dbo.DutyRoster(duty_id, employee_id, start_time, end_time) VALUES('' '', @employee, DATEADD(DAY, 1, @start), DATEADD(DAY, 2, @start));', 547, N'CK_DutyRoster_Id_NotBlank'),
    (N'CHECK：明细编号不能是空白', N'INSERT dbo.OrderItem(item_id, order_id, product_id, product_name_snapshot, base_price_snapshot, unit_price) VALUES('' '', @order, @product, N''测试商品'', 0, 0);', 547, N'CK_OrderItem_Id_NotBlank');

DECLARE @results TABLE (
    seq INT IDENTITY PRIMARY KEY, case_name NVARCHAR(100),
    expected_error INT NULL, actual_error INT NULL, passed BIT, detail NVARCHAR(4000)
);

BEGIN TRY
    BEGIN TRANSACTION;

    -- 测试数据只服务于独立约束验证，不代替支付及完整下单过程。
    INSERT dbo.Employee(employee_id, name, salary, role)
        VALUES(@employee, N'约束测试员工', 0, N'店员');
    INSERT dbo.DutyRoster(duty_id, employee_id, start_time, end_time)
        VALUES(@duty, @employee, @start, DATEADD(HOUR, 8, @start));
    INSERT dbo.Member(member_id, name, phone)
        VALUES(@member, N'约束测试会员', @phone);
    INSERT dbo.Product(product_id, product_name, base_price)
        VALUES(@product, N'约束测试商品', 0);
    INSERT dbo.Specification(spec_id, spec_type, spec_name)
        VALUES(@spec, N'糖度', CONVERT(NVARCHAR(10), @spec)),
              (@spec2, N'糖度', CONVERT(NVARCHAR(10), @spec2));
    INSERT dbo.Ingredient(ingredient_id, ingredient_name, unit)
        VALUES(@ingredient, N'约束测试糖浆', N'ml'),
              (@outside, N'约束测试配方外原料', N'g'),
              (@tea, N'约束测试茶汤', N'ml'),
              (@piece, N'约束测试杯子', N'个');
    INSERT dbo.ProductSpecification(product_id, spec_id)
        VALUES(@product, @spec);
    INSERT dbo.Recipe(product_id, ingredient_id, base_amount)
        VALUES(@product, @ingredient, 10), (@product, @tea, 10), (@product, @piece, 1);
    INSERT dbo.SpecificationIngredient(product_id, spec_id, ingredient_id, factor)
        VALUES(@product, @spec, @ingredient, 0), (@product, @spec, @tea, 1.5);
    INSERT dbo.AddOn(addon_id, addon_name, price, ingredient_id, extra_amount)
        VALUES(@addon, CONVERT(NVARCHAR(10), @addon), 1, @ingredient, 1);
    INSERT dbo.SalesOrder(order_id, member_id, total_amount)
        VALUES(@order, @member, 0);
    INSERT dbo.OrderItem(item_id, order_id, product_id, product_name_snapshot, base_price_snapshot, unit_price)
        VALUES(@item, @order, @product, N'约束测试商品', 0, 0);
    INSERT dbo.ItemSpec(item_id, spec_type, spec_id, spec_name_snapshot, price_delta_snapshot)
        VALUES(@item, N'糖度', @spec, CONVERT(NVARCHAR(10), @spec), -1);
    INSERT dbo.ItemAddOn(item_id, addon_id, addon_name_snapshot, price_snapshot)
        VALUES(@item, @addon, CONVERT(NVARCHAR(10), @addon), 1);
    INSERT dbo.OrderItemIngredient(item_id, ingredient_id, amount)
        VALUES(@item, @ingredient, 1), (@item, @tea, 15), (@item, @piece, 1);

    -- DEFAULT 正例：省略字段后检查数据库实际写入值，而非只检查约束存在。
    IF NOT EXISTS (SELECT 1 FROM dbo.Employee WHERE employee_id = @employee AND status = N'在职')
       OR NOT EXISTS (SELECT 1 FROM dbo.Member WHERE member_id = @member AND points = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.Product WHERE product_id = @product AND status = N'下架')
       OR NOT EXISTS (SELECT 1 FROM dbo.Ingredient WHERE ingredient_id = @piece AND stock = 0 AND status = N'可用')
       OR NOT EXISTS (SELECT 1 FROM dbo.ProductSpecification WHERE product_id = @product AND spec_id = @spec AND price_delta = 0 AND status = N'停用')
       OR NOT EXISTS (SELECT 1 FROM dbo.OrderItem WHERE item_id = @item AND quantity = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.SalesOrder WHERE order_id = @order AND status = N'排队中' AND order_time IS NOT NULL)
        THROW 51306, N'默认值验证失败。', 1;
    INSERT @results(case_name, passed, detail)
        VALUES(N'正例：数据库默认值', 1, N'在职、积分0、下架、库存0、可用、规格停用及差价0、数量1、排队中及下单时间');

    UPDATE dbo.Ingredient SET stock = 1.25 WHERE ingredient_id = @ingredient;
    IF NOT EXISTS (SELECT 1 FROM dbo.Ingredient WHERE ingredient_id = @ingredient AND stock = 1.25)
        THROW 51307, N'非计件原料的小数库存验证失败。', 1;
    INSERT @results(case_name, passed, detail)
        VALUES(N'正例：零金额、零系数、大于1系数、小数原料库存', 1, N'商品与订单金额可为0；系数0及1.5合法；ml原料库存可为1.25');

    UPDATE dbo.ProductSpecification SET price_delta = -1
        WHERE product_id = @product AND spec_id = @spec;
    IF NOT EXISTS (SELECT 1 FROM dbo.ProductSpecification WHERE product_id = @product AND spec_id = @spec AND price_delta = -1)
        THROW 51308, N'规格差价允许负数的验证失败。', 1;
    INSERT @results(case_name, passed, detail)
        VALUES(N'正例：规格差价及快照允许负数', 1, N'price_delta和price_delta_snapshot均接受-1，最终成交单价仍须非负');

    -- 同一游客会话的两笔订单共享 guest_id，故不能为该字段创建唯一约束。
    EXEC sys.sp_executesql
        N'INSERT dbo.SalesOrder(order_id, guest_id, total_amount)
          VALUES(@o1, @g, 0), (@o2, @g, 0);
          IF (SELECT COUNT(*) FROM dbo.SalesOrder WHERE order_id IN (@o1, @o2)
              AND guest_id = @g AND member_id IS NULL) <> 2
              THROW 51309, N''同一游客会话的订单归属验证失败。'', 1;',
        N'@o1 VARCHAR(10), @o2 VARCHAR(10), @g UNIQUEIDENTIFIER',
        @o1 = @guest_order, @o2 = @guest_order2, @g = @guest;
    INSERT @results(case_name, passed, detail)
        VALUES(N'正例：同一游客会话可以下多笔订单', 1, N'两笔非会员订单共享同一个guest_id；会员订单不填写guest_id');

    SAVE TRANSACTION PositiveComputedColumn;
    UPDATE dbo.OrderItem SET quantity = 2, unit_price = 3.5 WHERE item_id = @item;
    IF NOT EXISTS (SELECT 1 FROM dbo.OrderItem WHERE item_id = @item AND sub_amount = 7)
        THROW 51310, N'明细小计自动计算验证失败。', 1;
    ROLLBACK TRANSACTION PositiveComputedColumn;
    INSERT @results(case_name, passed, detail)
        VALUES(N'正例：明细小计自动重算', 1, N'单价3.50、数量2时，计算列小计自动变为7.00');

    DECLARE @test_seq INT = 1, @test_count INT = (SELECT COUNT(*) FROM @negative_cases);
    DECLARE @case_name NVARCHAR(100), @statement NVARCHAR(MAX), @expected_error INT;
    DECLARE @expected_object NVARCHAR(128), @actual_error INT, @error_message NVARCHAR(4000);
    DECLARE @parameters NVARCHAR(MAX) =
        N'@employee VARCHAR(10), @duty VARCHAR(10), @member VARCHAR(10), @member2 VARCHAR(10),
          @product VARCHAR(10), @spec VARCHAR(10), @spec2 VARCHAR(10), @ingredient VARCHAR(10),
          @outside VARCHAR(10), @piece VARCHAR(10), @addon VARCHAR(10), @order VARCHAR(10),
          @item VARCHAR(10), @item2 VARCHAR(10), @missing VARCHAR(10), @phone VARCHAR(20),
          @start DATETIME2(0), @guest UNIQUEIDENTIFIER';

    WHILE @test_seq <= @test_count
    BEGIN
        SELECT @case_name = case_name, @statement = statement,
               @expected_error = expected_error, @expected_object = expected_object
        FROM @negative_cases WHERE seq = @test_seq;
        SET @actual_error = NULL;
        SET @error_message = NULL;
        SAVE TRANSACTION NegativeCase;
        BEGIN TRY
            EXEC sys.sp_executesql @statement, @parameters,
                @employee = @employee, @duty = @duty, @member = @member, @member2 = @member2,
                @product = @product, @spec = @spec, @spec2 = @spec2, @ingredient = @ingredient,
                @outside = @outside, @piece = @piece, @addon = @addon, @order = @order,
                @item = @item, @item2 = @item2, @missing = @missing, @phone = @phone,
                @start = @start, @guest = @guest;
        END TRY
        BEGIN CATCH
            SET @actual_error = ERROR_NUMBER();
            SET @error_message = ERROR_MESSAGE();
            IF XACT_STATE() <> 1 THROW;
        END CATCH;
        ROLLBACK TRANSACTION NegativeCase;
        INSERT @results(case_name, expected_error, actual_error, passed, detail)
        VALUES(@case_name, @expected_error, @actual_error,
            CASE WHEN @actual_error = @expected_error
                   AND CHARINDEX(@expected_object, @error_message) > 0 THEN 1 ELSE 0 END,
            COALESCE(@error_message, N'非法操作被接受，约束验证失败。'));
        SET @test_seq += 1;
    END;

    -- 所有测试 INSERT/UPDATE/DELETE 回滚；安装好的约束和旧样例ID补齐继续保留。
    ROLLBACK TRANSACTION;
    IF (SELECT COUNT(*) FROM @results)<>44 THROW 52901,N'提取的约束用例数量不是44。',1;
    INSERT #RegressionResults(suite,case_name,expected_error,actual_error,passed,detail)
        SELECT N'legacy-constraint',case_name,expected_error,actual_error,passed,detail FROM @results;
    SET XACT_ABORT ON;
    SELECT seq, case_name, expected_error, actual_error,
           CASE passed WHEN 1 THEN N'通过' ELSE N'失败' END AS result, detail
    FROM @results ORDER BY seq;
    IF EXISTS (SELECT 1 FROM @results WHERE passed = 0)
        THROW 51311, N'存在未通过的约束验证，请根据结果中的实际错误定位。', 1;
    SELECT N'约束验证全部通过，测试数据已回滚' AS stage, COUNT(*) AS passed_cases
    FROM @results;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    SET XACT_ABORT ON;
    THROW;
END CATCH;
