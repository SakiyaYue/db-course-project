-- Week 6 standalone regression; all legacy and v1.0 tests are embedded.
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
SET XACT_ABORT ON;
DECLARE @ExpectedDatabase SYSNAME=N'TeabarDB_Phase2_Work';
IF DB_NAME()<>@ExpectedDatabase OR DB_NAME() IN(N'TeabarDB',N'master',N'model',N'msdb',N'tempdb')
    THROW 52900,N'仅在指定的独立迁移工作库中执行回归。',1;
IF @@TRANCOUNT<>0 OR USER_NAME()<>N'dbo'
    THROW 52900,N'回归要求dbo管理员和无未结束事务的新窗口。',1;
IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'TeabarDB.SchemaVersion' AND CONVERT(NVARCHAR(20),value)=N'1.0')
    THROW 52900,N'先在独立工作库成功提交v1.0迁移，再执行回归。',1;
CREATE TABLE #RegressionResults(suite NVARCHAR(40),case_name NVARCHAR(150),expected_error INT NULL,
    actual_error INT NULL,passed BIT NOT NULL,detail NVARCHAR(4000));
DECLARE @snapshot_before TABLE(name SYSNAME PRIMARY KEY,row_count BIGINT,data_hash VARBINARY(32));
DECLARE @snapshot_after TABLE(name SYSNAME PRIMARY KEY,row_count BIGINT,data_hash VARBINARY(32));
DECLARE @table SYSNAME,@schema SYSNAME,@ordering NVARCHAR(MAX),@sql NVARCHAR(MAX),@rows BIGINT,@hash VARBINARY(32);
DECLARE @tables TABLE(name SYSNAME PRIMARY KEY,schema_name SYSNAME,order_columns NVARCHAR(300));
INSERT @tables VALUES
(N'Employee',N'dbo',N'[employee_id]'),
(N'DutyRoster',N'dbo',N'[duty_id]'),
(N'Member',N'dbo',N'[member_id]'),
(N'SalesOrder',N'dbo',N'[order_id]'),
(N'Product',N'dbo',N'[product_id]'),
(N'Specification',N'dbo',N'[spec_id]'),
(N'Ingredient',N'dbo',N'[ingredient_id]'),
(N'OrderItem',N'dbo',N'[item_id]'),
(N'ProductSpecification',N'dbo',N'[product_id],[spec_id]'),
(N'Recipe',N'dbo',N'[product_id],[ingredient_id]'),
(N'AddOn',N'dbo',N'[addon_id]'),
(N'ItemSpec',N'dbo',N'[item_id],[spec_type]'),
(N'ItemAddOn',N'dbo',N'[item_id],[addon_id]'),
(N'OrderItemIngredient',N'dbo',N'[item_id],[ingredient_id]'),
(N'SpecificationIngredient',N'dbo',N'[product_id],[spec_id],[ingredient_id]'),
(N'PrincipalBinding',N'teabar_auth',N'[principal_sid]'),
(N'WebAccount',N'teabar_auth',N'[account_id]');
DECLARE @security_before VARBINARY(32),@security_after VARBINARY(32);
DECLARE @security_fingerprint NVARCHAR(MAX)=N'SELECT @h=HASHBYTES(''SHA2_256'',
    (SELECT principal_id,name,type,sid,owning_principal_id,authentication_type,default_schema_name
       FROM sys.database_principals ORDER BY principal_id FOR XML RAW,BINARY BASE64)
   +(SELECT * FROM sys.database_role_members ORDER BY role_principal_id,member_principal_id FOR XML RAW)
   +(SELECT * FROM sys.database_permissions ORDER BY class,major_id,minor_id,grantee_principal_id,grantor_principal_id,type FOR XML RAW)
   +(SELECT schema_id,name,principal_id FROM sys.schemas ORDER BY schema_id FOR XML RAW));';
BEGIN TRY
    EXEC sys.sp_executesql @security_fingerprint,N'@h VARBINARY(32) OUTPUT',@h=@security_before OUTPUT;
    IF (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0)<>17
       OR (SELECT COUNT(*) FROM sys.columns AS c JOIN sys.tables AS t ON t.object_id=c.object_id WHERE t.is_ms_shipped=0)<>81
       OR (SELECT COUNT(*) FROM sys.foreign_keys)<>19
       OR (SELECT COUNT(*) FROM sys.key_constraints WHERE type='PK' AND parent_object_id IN(SELECT object_id FROM sys.tables WHERE is_ms_shipped=0))<>17
       OR (SELECT COUNT(*) FROM sys.key_constraints WHERE type='UQ' AND parent_object_id IN(SELECT object_id FROM sys.tables WHERE is_ms_shipped=0))<>8
       OR (SELECT COUNT(*) FROM sys.views WHERE schema_id=SCHEMA_ID(N'dbo'))<>13
       OR (SELECT COUNT(*) FROM sys.views WHERE schema_id=SCHEMA_ID(N'teabar_api'))<>16
       OR (SELECT COUNT(*) FROM sys.procedures WHERE schema_id IN(SCHEMA_ID(N'teabar_api'),SCHEMA_ID(N'teabar_auth')))<>18
       OR EXISTS(SELECT 1 FROM sys.foreign_keys WHERE is_disabled=1 OR is_not_trusted=1)
       OR EXISTS(SELECT 1 FROM sys.check_constraints WHERE is_disabled=1 OR is_not_trusted=1)
       OR NOT EXISTS(SELECT 1 FROM sys.computed_columns WHERE object_id=OBJECT_ID(N'dbo.OrderItem') AND name=N'sub_amount' AND is_persisted=1)
       OR (SELECT COUNT(*) FROM sys.indexes WHERE (object_id=OBJECT_ID(N'dbo.SalesOrder') AND name IN(N'IX_SalesOrder_Member_Time',N'IX_SalesOrder_Guest_Time'))
              OR (object_id=OBJECT_ID(N'dbo.OrderItem') AND name=N'IX_OrderItem_Order'))<>3
        THROW 52901,N'v1.0对象/键/视图/索引/约束状态检查失败。',1;
    INSERT #RegressionResults VALUES(N'structure',N'17表81列19FK、键、视图、过程、计算列与索引',NULL,NULL,1,N'目录状态符合目标数量；行为继续由后续用例检查。');

    DECLARE snapshot_tables CURSOR LOCAL FAST_FORWARD FOR SELECT name,schema_name,order_columns FROM @tables ORDER BY name;
    OPEN snapshot_tables; FETCH NEXT FROM snapshot_tables INTO @table,@schema,@ordering;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @sql=N'SELECT @n=COUNT_BIG(*) FROM '+QUOTENAME(@schema)+N'.'+QUOTENAME(@table)+N';'
          +N'SELECT @h=HASHBYTES(''SHA2_256'',(SELECT * FROM '+QUOTENAME(@schema)+N'.'+QUOTENAME(@table)
          +N' ORDER BY '+@ordering+N' FOR XML RAW,BINARY BASE64));';
        EXEC sys.sp_executesql @sql,N'@n BIGINT OUTPUT,@h VARBINARY(32) OUTPUT',@n=@rows OUTPUT,@h=@hash OUTPUT;
        INSERT @snapshot_before VALUES(@table,@rows,@hash);
        FETCH NEXT FROM snapshot_tables INTO @table,@schema,@ordering;
    END;
    CLOSE snapshot_tables; DEALLOCATE snapshot_tables;
    IF EXISTS(SELECT 1 FROM dbo.OrderItem AS i WHERE NOT EXISTS(SELECT 1 FROM dbo.OrderItemIngredient AS c WHERE c.item_id=i.item_id AND c.amount>0))
       OR EXISTS(SELECT 1 FROM dbo.SalesOrder AS o OUTER APPLY(SELECT COUNT(*) AS n,SUM(sub_amount) AS amount
           FROM dbo.OrderItem AS i WHERE i.order_id=o.order_id) AS x WHERE x.n=0 OR x.amount<>o.total_amount)
        THROW 52901,N'历史订单缺明细、金额不一致或存在逐明细零消耗。',1;
    IF (SELECT SUM(row_count) FROM @snapshot_before WHERE name NOT IN(N'PrincipalBinding',N'WebAccount'))<>232
       OR NOT EXISTS(SELECT 1 FROM dbo.Product WHERE product_id='P001' AND base_price=6)
       OR NOT EXISTS(SELECT 1 FROM dbo.Ingredient WHERE ingredient_id='I001' AND stock=5000 AND unit=N'g')
       OR NOT EXISTS(SELECT 1 FROM dbo.Member WHERE member_id='M001' AND points=120)
       OR (SELECT COUNT(*) FROM dbo.SalesOrder WHERE status=N'已完成' AND order_time>='20261004' AND order_time<'20261005')<>3
       OR (SELECT SUM(total_amount) FROM dbo.SalesOrder WHERE status=N'已完成' AND order_time>='20261004' AND order_time<'20261005')<>46
       OR (SELECT SUM(i.quantity) FROM dbo.OrderItem AS i JOIN dbo.SalesOrder AS o ON o.order_id=i.order_id
           WHERE o.status=N'已完成' AND o.order_time>='20261004' AND o.order_time<'20261005')<>5
        THROW 52901,N'冻结业务基准与经营统计不符合预期。',1;
    INSERT #RegressionResults VALUES(N'baseline',N'232行、金额、库存、积分和3单5杯46元',NULL,NULL,1,N'在新增测试前核对冻结基准；完整表哈希另在末尾比较。');
    EXEC(N'SET XACT_ABORT OFF;

DECLARE @prefix VARCHAR(8) = ''VC'' + LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), ''-'', ''''), 6);
DECLARE @employee VARCHAR(10) = @prefix + ''E1'', @duty VARCHAR(10) = @prefix + ''D1'';
DECLARE @member VARCHAR(10) = @prefix + ''M1'', @member2 VARCHAR(10) = @prefix + ''M2'';
DECLARE @product VARCHAR(10) = @prefix + ''P1'';
DECLARE @spec VARCHAR(10) = @prefix + ''S1'', @spec2 VARCHAR(10) = @prefix + ''S2'';
DECLARE @ingredient VARCHAR(10) = @prefix + ''I1'', @outside VARCHAR(10) = @prefix + ''I2'';
DECLARE @tea VARCHAR(10) = @prefix + ''I3'', @piece VARCHAR(10) = @prefix + ''I4'';
DECLARE @addon VARCHAR(10) = @prefix + ''A1'', @order VARCHAR(10) = @prefix + ''O1'';
DECLARE @guest_order VARCHAR(10) = @prefix + ''O2'', @guest_order2 VARCHAR(10) = @prefix + ''O3'';
DECLARE @item VARCHAR(10) = @prefix + ''T1'', @item2 VARCHAR(10) = @prefix + ''T2'';
DECLARE @missing VARCHAR(10) = @prefix + ''XX'', @guest UNIQUEIDENTIFIER = NEWID();
DECLARE @phone VARCHAR(20);
WHILE @phone IS NULL OR EXISTS (SELECT 1 FROM dbo.Member WHERE phone = @phone)
    SET @phone = ''199'' + RIGHT(''00000000'' + CONVERT(VARCHAR(8),
        ABS(CONVERT(BIGINT, CHECKSUM(NEWID()))) % 100000000), 8);
DECLARE @start DATETIME2(0) = ''2099-01-01T08:00:00'';

DECLARE @negative_cases TABLE (
    seq INT IDENTITY PRIMARY KEY,
    case_name NVARCHAR(100), statement NVARCHAR(MAX),
    expected_error INT, expected_object NVARCHAR(128)
);
INSERT INTO @negative_cases (case_name, statement, expected_error, expected_object) VALUES
    (N''主键：重复商品编号'', N''INSERT dbo.Product(product_id, product_name, base_price) VALUES(@product, N''''重复商品'''', 0);'', 2627, N''PK_Product''),
    (N''联合主键：重复配方'', N''INSERT dbo.Recipe(product_id, ingredient_id, base_amount) VALUES(@product, @ingredient, 1);'', 2627, N''PK_Recipe''),
    (N''UNIQUE：重复会员手机号'', N''INSERT dbo.Member(member_id, name, phone) VALUES(@member2, N''''重复手机号'''', @phone);'', 2627, N''UK_Member_Phone''),
    (N''UNIQUE：同员工相同值班开始时间'', N''INSERT dbo.DutyRoster(duty_id, employee_id, start_time, end_time) VALUES(@missing, @employee, @start, DATEADD(HOUR, 9, @start));'', 2627, N''UQ_DutyRoster_Employee_StartTime''),
    (N''外键：配方引用不存在的原料'', N''INSERT dbo.Recipe(product_id, ingredient_id, base_amount) VALUES(@product, @missing, 1);'', 547, N''FK_Recipe_Ingredient''),
    (N''外键：明细引用不存在的订单'', N''INSERT dbo.OrderItem(item_id, order_id, product_id, product_name_snapshot, base_price_snapshot, unit_price) VALUES(@item2, @missing, @product, N''''测试商品'''', 0, 0);'', 547, N''FK_OrderItem_Order''),
    (N''复合外键：规格规则原料不在商品配方中'', N''INSERT dbo.SpecificationIngredient(product_id, spec_id, ingredient_id, factor) VALUES(@product, @spec, @outside, 1);'', 547, N''FK_SpecificationIngredient_Recipe''),
    (N''复合外键：商品没有配置该规格'', N''INSERT dbo.SpecificationIngredient(product_id, spec_id, ingredient_id, factor) VALUES(@product, @spec2, @ingredient, 1);'', 547, N''FK_SpecificationIngredient_ProductSpec''),
    (N''复合外键：规格编号与类型不匹配'', N''INSERT dbo.ItemSpec(item_id, spec_type, spec_id, spec_name_snapshot, price_delta_snapshot) VALUES(@item, N''''杯型'''', @spec, N''''测试选项'''', 0);'', 547, N''FK_ItemSpec_Spec_id''),
    (N''联合主键：同明细同类型选择两个规格'', N''INSERT dbo.ItemSpec(item_id, spec_type, spec_id, spec_name_snapshot, price_delta_snapshot) VALUES(@item, N''''糖度'''', @spec2, N''''第二选项'''', 0);'', 2627, N''PK_ItemSpec''),
    (N''联合主键：同明细重复选择一种加料'', N''INSERT dbo.ItemAddOn(item_id, addon_id, addon_name_snapshot, price_snapshot) VALUES(@item, @addon, N''''测试加料'''', 1);'', 2627, N''PK_ItemAddOn''),
    (N''CHECK：库存不能为负'', N''UPDATE dbo.Ingredient SET stock = -1 WHERE ingredient_id = @ingredient;'', 547, N''CK_Ingredient_Stock''),
    (N''CHECK：计件库存不能有小数'', N''UPDATE dbo.Ingredient SET stock = 1.5 WHERE ingredient_id = @piece;'', 547, N''CK_Ingredient_PieceStock''),
    (N''CHECK：购买数量必须大于零'', N''UPDATE dbo.OrderItem SET quantity = 0 WHERE item_id = @item;'', 547, N''CK_OrderItem_Quantity''),
    (N''CHECK：商品基础价格不能为负'', N''UPDATE dbo.Product SET base_price = -1 WHERE product_id = @product;'', 547, N''CK_Product_Price''),
    (N''CHECK：明细基础价格不能为负'', N''UPDATE dbo.OrderItem SET base_price_snapshot = -1 WHERE item_id = @item;'', 547, N''CK_OrderItem_BasePrice''),
    (N''CHECK：成交单价不能为负'', N''UPDATE dbo.OrderItem SET unit_price = -1 WHERE item_id = @item;'', 547, N''CK_OrderItem_UnitPrice''),
    (N''CHECK：订单金额不能为负'', N''UPDATE dbo.SalesOrder SET total_amount = -1 WHERE order_id = @order;'', 547, N''CK_SalesOrder_Amount''),
    (N''CHECK：会员积分不能为负'', N''UPDATE dbo.Member SET points = -1 WHERE member_id = @member;'', 547, N''CK_Member_Points''),
    (N''CHECK：员工月薪不能为负'', N''UPDATE dbo.Employee SET salary = -1 WHERE employee_id = @employee;'', 547, N''CK_Employee_Salary''),
    (N''CHECK：员工岗位只能为店员或店长'', N''UPDATE dbo.Employee SET role = N''''配送员'''' WHERE employee_id = @employee;'', 547, N''CK_Employee_Role''),
    (N''CHECK：订单状态枚举'', N''UPDATE dbo.SalesOrder SET status = N''''配送中'''' WHERE order_id = @order;'', 547, N''CK_SalesOrder_status''),
    (N''CHECK：商品状态枚举'', N''UPDATE dbo.Product SET status = N''''未知'''' WHERE product_id = @product;'', 547, N''CK_Product_Status''),
    (N''CHECK：商品名称不能是空白'', N''UPDATE dbo.Product SET product_name = N''''   '''' WHERE product_id = @product;'', 547, N''CK_Product_Name_NotBlank''),
    (N''NOT NULL：商品名称不能为NULL'', N''UPDATE dbo.Product SET product_name = NULL WHERE product_id = @product;'', 515, N''product_name''),
    (N''CHECK：会员手机号格式'', N''UPDATE dbo.Member SET phone = ''''1990000ABCD'''' WHERE member_id = @member;'', 547, N''CK_Member_Phone_Format''),
    (N''CHECK：值班结束必须晚于开始'', N''UPDATE dbo.DutyRoster SET end_time = start_time WHERE duty_id = @duty;'', 547, N''CK_DutyRoster_Time''),
    (N''CHECK：配方用量必须大于零'', N''UPDATE dbo.Recipe SET base_amount = 0 WHERE product_id = @product AND ingredient_id = @ingredient;'', 547, N''CK_Recipe_BaseAmount''),
    (N''CHECK：规格系数不能为负'', N''UPDATE dbo.SpecificationIngredient SET factor = -1 WHERE product_id = @product AND spec_id = @spec AND ingredient_id = @ingredient;'', 547, N''CK_SpecificationIngredient_Factor''),
    (N''CHECK：加料用量必须大于零'', N''UPDATE dbo.AddOn SET extra_amount = 0 WHERE addon_id = @addon;'', 547, N''CK_AddOn_ExtraAmount''),
    (N''CHECK：加料价格不能为负'', N''UPDATE dbo.AddOn SET price = -1 WHERE addon_id = @addon;'', 547, N''CK_AddOn_Price''),
    (N''CHECK：原料消耗快照必须大于零'', N''UPDATE dbo.OrderItemIngredient SET amount = 0 WHERE item_id = @item AND ingredient_id = @ingredient;'', 547, N''CK_OrderItemIngredient_Amount''),
    (N''CHECK：会员和游客归属不能同时为空'', N''UPDATE dbo.SalesOrder SET member_id = NULL, guest_id = NULL WHERE order_id = @order;'', 547, N''CK_SalesOrder_Owner''),
    (N''CHECK：会员和游客归属不能同时填写'', N''UPDATE dbo.SalesOrder SET guest_id = @guest WHERE order_id = @order;'', 547, N''CK_SalesOrder_Owner''),
    (N''删除保护：不能删除被规格规则引用的配方'', N''DELETE dbo.Recipe WHERE product_id = @product AND ingredient_id = @ingredient;'', 547, N''FK_SpecificationIngredient_Recipe''),
    (N''删除保护：不能删除被订单引用的会员'', N''DELETE dbo.Member WHERE member_id = @member;'', 547, N''FK_SalesOrder_Member''),
    (N''计算列：不能直接修改明细小计'', N''UPDATE dbo.OrderItem SET sub_amount = 1 WHERE item_id = @item;'', 271, N''sub_amount''),
    (N''CHECK：值班编号不能是空白'', N''INSERT dbo.DutyRoster(duty_id, employee_id, start_time, end_time) VALUES('''' '''', @employee, DATEADD(DAY, 1, @start), DATEADD(DAY, 2, @start));'', 547, N''CK_DutyRoster_Id_NotBlank''),
    (N''CHECK：明细编号不能是空白'', N''INSERT dbo.OrderItem(item_id, order_id, product_id, product_name_snapshot, base_price_snapshot, unit_price) VALUES('''' '''', @order, @product, N''''测试商品'''', 0, 0);'', 547, N''CK_OrderItem_Id_NotBlank'');

DECLARE @results TABLE (
    seq INT IDENTITY PRIMARY KEY, case_name NVARCHAR(100),
    expected_error INT NULL, actual_error INT NULL, passed BIT, detail NVARCHAR(4000)
);

BEGIN TRY
    BEGIN TRANSACTION;

    -- 测试数据只服务于独立约束验证，不代替支付及完整下单过程。
    INSERT dbo.Employee(employee_id, name, salary, role)
        VALUES(@employee, N''约束测试员工'', 0, N''店员'');
    INSERT dbo.DutyRoster(duty_id, employee_id, start_time, end_time)
        VALUES(@duty, @employee, @start, DATEADD(HOUR, 8, @start));
    INSERT dbo.Member(member_id, name, phone)
        VALUES(@member, N''约束测试会员'', @phone);
    INSERT dbo.Product(product_id, product_name, base_price)
        VALUES(@product, N''约束测试商品'', 0);
    INSERT dbo.Specification(spec_id, spec_type, spec_name)
        VALUES(@spec, N''糖度'', CONVERT(NVARCHAR(10), @spec)),
              (@spec2, N''糖度'', CONVERT(NVARCHAR(10), @spec2));
    INSERT dbo.Ingredient(ingredient_id, ingredient_name, unit)
        VALUES(@ingredient, N''约束测试糖浆'', N''ml''),
              (@outside, N''约束测试配方外原料'', N''g''),
              (@tea, N''约束测试茶汤'', N''ml''),
              (@piece, N''约束测试杯子'', N''个'');
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
        VALUES(@item, @order, @product, N''约束测试商品'', 0, 0);
    INSERT dbo.ItemSpec(item_id, spec_type, spec_id, spec_name_snapshot, price_delta_snapshot)
        VALUES(@item, N''糖度'', @spec, CONVERT(NVARCHAR(10), @spec), -1);
    INSERT dbo.ItemAddOn(item_id, addon_id, addon_name_snapshot, price_snapshot)
        VALUES(@item, @addon, CONVERT(NVARCHAR(10), @addon), 1);
    INSERT dbo.OrderItemIngredient(item_id, ingredient_id, amount)
        VALUES(@item, @ingredient, 1), (@item, @tea, 15), (@item, @piece, 1);

    -- DEFAULT 正例：省略字段后检查数据库实际写入值，而非只检查约束存在。
    IF NOT EXISTS (SELECT 1 FROM dbo.Employee WHERE employee_id = @employee AND status = N''在职'')
       OR NOT EXISTS (SELECT 1 FROM dbo.Member WHERE member_id = @member AND points = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.Product WHERE product_id = @product AND status = N''下架'')
       OR NOT EXISTS (SELECT 1 FROM dbo.Ingredient WHERE ingredient_id = @piece AND stock = 0 AND status = N''可用'')
       OR NOT EXISTS (SELECT 1 FROM dbo.ProductSpecification WHERE product_id = @product AND spec_id = @spec AND price_delta = 0 AND status = N''停用'')
       OR NOT EXISTS (SELECT 1 FROM dbo.OrderItem WHERE item_id = @item AND quantity = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.SalesOrder WHERE order_id = @order AND status = N''排队中'' AND order_time IS NOT NULL)
        THROW 51306, N''默认值验证失败。'', 1;
    INSERT @results(case_name, passed, detail)
        VALUES(N''正例：数据库默认值'', 1, N''在职、积分0、下架、库存0、可用、规格停用及差价0、数量1、排队中及下单时间'');

    UPDATE dbo.Ingredient SET stock = 1.25 WHERE ingredient_id = @ingredient;
    IF NOT EXISTS (SELECT 1 FROM dbo.Ingredient WHERE ingredient_id = @ingredient AND stock = 1.25)
        THROW 51307, N''非计件原料的小数库存验证失败。'', 1;
    INSERT @results(case_name, passed, detail)
        VALUES(N''正例：零金额、零系数、大于1系数、小数原料库存'', 1, N''商品与订单金额可为0；系数0及1.5合法；ml原料库存可为1.25'');

    UPDATE dbo.ProductSpecification SET price_delta = -1
        WHERE product_id = @product AND spec_id = @spec;
    IF NOT EXISTS (SELECT 1 FROM dbo.ProductSpecification WHERE product_id = @product AND spec_id = @spec AND price_delta = -1)
        THROW 51308, N''规格差价允许负数的验证失败。'', 1;
    INSERT @results(case_name, passed, detail)
        VALUES(N''正例：规格差价及快照允许负数'', 1, N''price_delta和price_delta_snapshot均接受-1，最终成交单价仍须非负'');

    -- 同一游客会话的两笔订单共享 guest_id，故不能为该字段创建唯一约束。
    EXEC sys.sp_executesql
        N''INSERT dbo.SalesOrder(order_id, guest_id, total_amount)
          VALUES(@o1, @g, 0), (@o2, @g, 0);
          IF (SELECT COUNT(*) FROM dbo.SalesOrder WHERE order_id IN (@o1, @o2)
              AND guest_id = @g AND member_id IS NULL) <> 2
              THROW 51309, N''''同一游客会话的订单归属验证失败。'''', 1;'',
        N''@o1 VARCHAR(10), @o2 VARCHAR(10), @g UNIQUEIDENTIFIER'',
        @o1 = @guest_order, @o2 = @guest_order2, @g = @guest;
    INSERT @results(case_name, passed, detail)
        VALUES(N''正例：同一游客会话可以下多笔订单'', 1, N''两笔非会员订单共享同一个guest_id；会员订单不填写guest_id'');

    SAVE TRANSACTION PositiveComputedColumn;
    UPDATE dbo.OrderItem SET quantity = 2, unit_price = 3.5 WHERE item_id = @item;
    IF NOT EXISTS (SELECT 1 FROM dbo.OrderItem WHERE item_id = @item AND sub_amount = 7)
        THROW 51310, N''明细小计自动计算验证失败。'', 1;
    ROLLBACK TRANSACTION PositiveComputedColumn;
    INSERT @results(case_name, passed, detail)
        VALUES(N''正例：明细小计自动重算'', 1, N''单价3.50、数量2时，计算列小计自动变为7.00'');

    DECLARE @test_seq INT = 1, @test_count INT = (SELECT COUNT(*) FROM @negative_cases);
    DECLARE @case_name NVARCHAR(100), @statement NVARCHAR(MAX), @expected_error INT;
    DECLARE @expected_object NVARCHAR(128), @actual_error INT, @error_message NVARCHAR(4000);
    DECLARE @parameters NVARCHAR(MAX) =
        N''@employee VARCHAR(10), @duty VARCHAR(10), @member VARCHAR(10), @member2 VARCHAR(10),
          @product VARCHAR(10), @spec VARCHAR(10), @spec2 VARCHAR(10), @ingredient VARCHAR(10),
          @outside VARCHAR(10), @piece VARCHAR(10), @addon VARCHAR(10), @order VARCHAR(10),
          @item VARCHAR(10), @item2 VARCHAR(10), @missing VARCHAR(10), @phone VARCHAR(20),
          @start DATETIME2(0), @guest UNIQUEIDENTIFIER'';

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
            COALESCE(@error_message, N''非法操作被接受，约束验证失败。''));
        SET @test_seq += 1;
    END;

    -- 所有测试 INSERT/UPDATE/DELETE 回滚；安装好的约束和旧样例ID补齐继续保留。
    ROLLBACK TRANSACTION;
    IF (SELECT COUNT(*) FROM @results)<>44 THROW 52901,N''提取的约束用例数量不是44。'',1;
    INSERT #RegressionResults(suite,case_name,expected_error,actual_error,passed,detail)
        SELECT N''legacy-constraint'',case_name,expected_error,actual_error,passed,detail FROM @results;
    SET XACT_ABORT ON;
    SELECT seq, case_name, expected_error, actual_error,
           CASE passed WHEN 1 THEN N''通过'' ELSE N''失败'' END AS result, detail
    FROM @results ORDER BY seq;
    IF EXISTS (SELECT 1 FROM @results WHERE passed = 0)
        THROW 51311, N''存在未通过的约束验证，请根据结果中的实际错误定位。'', 1;
    SELECT N''约束验证全部通过，测试数据已回滚'' AS stage, COUNT(*) AS passed_cases
    FROM @results;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    SET XACT_ABORT ON;
    THROW;
END CATCH;

');
EXEC(N'SET NOCOUNT ON;
SET XACT_ABORT OFF;
DECLARE @administrator SYSNAME=USER_NAME(), @impersonating BIT=0;
DECLARE @prefix VARCHAR(8)=''VT''+LEFT(REPLACE(CONVERT(VARCHAR(36),NEWID()),''-'',''''),6);
DECLARE @P VARCHAR(10)=@prefix+''P1'',@P2 VARCHAR(10)=@prefix+''P2'',
 @S1 VARCHAR(10)=@prefix+''S1'',@S2 VARCHAR(10)=@prefix+''S2'',@S3 VARCHAR(10)=@prefix+''S3'',
 @S4 VARCHAR(10)=@prefix+''S4'',@S5 VARCHAR(10)=@prefix+''S5'',
 @I1 VARCHAR(10)=@prefix+''I1'',@I2 VARCHAR(10)=@prefix+''I2'',@I3 VARCHAR(10)=@prefix+''I3'',
 @I4 VARCHAR(10)=@prefix+''I4'',@A VARCHAR(10)=@prefix+''A1'',@A2 VARCHAR(10)=@prefix+''A2'',
 @MA VARCHAR(10)=@prefix+''M1'',@MB VARCHAR(10)=@prefix+''M2'',@MC VARCHAR(10)=@prefix+''M3'',
 @E VARCHAR(10)=@prefix+''E1'',@D1 VARCHAR(10)=@prefix+''D1'',@D2 VARCHAR(10)=@prefix+''D2'',@D3 VARCHAR(10)=@prefix+''D3'',
 @OG VARCHAR(10)=@prefix+''O1'',@OG2 VARCHAR(10)=@prefix+''O2'',@OGB VARCHAR(10)=@prefix+''O3'',
 @OM VARCHAR(10)=@prefix+''O4'',@OMB VARCHAR(10)=@prefix+''O5'',@OD VARCHAR(10)=@prefix+''O6'',
 @OP VARCHAR(10)=@prefix+''O7'',@OX VARCHAR(10)=@prefix+''OX'',
 @TG VARCHAR(10)=@prefix+''T1'',@TG2 VARCHAR(10)=@prefix+''T2'',@TGB VARCHAR(10)=@prefix+''T3'',
 @TM VARCHAR(10)=@prefix+''T4'',@TMB VARCHAR(10)=@prefix+''T5'',@TX VARCHAR(10)=@prefix+''TX'',@TY VARCHAR(10)=@prefix+''TY'';
DECLARE @PA VARCHAR(20),@PB VARCHAR(20),@PC VARCHAR(20),@GA UNIQUEIDENTIFIER,@GB UNIQUEIDENTIFIER;
WHILE @PA IS NULL OR EXISTS(SELECT 1 FROM dbo.Member WHERE phone=@PA)
 SET @PA=''199''+RIGHT(''00000000''+CONVERT(VARCHAR(8),ABS(CONVERT(BIGINT,CHECKSUM(NEWID())))%100000000),8);
WHILE @PB IS NULL OR @PB=@PA OR EXISTS(SELECT 1 FROM dbo.Member WHERE phone=@PB)
 SET @PB=''199''+RIGHT(''00000000''+CONVERT(VARCHAR(8),ABS(CONVERT(BIGINT,CHECKSUM(NEWID())))%100000000),8);
WHILE @PC IS NULL OR @PC IN(@PA,@PB) OR EXISTS(SELECT 1 FROM dbo.Member WHERE phone=@PC)
 SET @PC=''199''+RIGHT(''00000000''+CONVERT(VARCHAR(8),ABS(CONVERT(BIGINT,CHECKSUM(NEWID())))%100000000),8);
SELECT @GA=guest_id FROM teabar_auth.PrincipalBinding WHERE principal_name=N''demo_guest_a'';
SELECT @GB=guest_id FROM teabar_auth.PrincipalBinding WHERE principal_name=N''demo_guest_b'';

DECLARE @cases TABLE(
 seq INT IDENTITY PRIMARY KEY, user_name SYSNAME, case_name NVARCHAR(100),
 statement NVARCHAR(MAX), expected_error INT NULL, setup NVARCHAR(MAX), teardown NVARCHAR(MAX));
INSERT @cases(user_name,case_name,statement,expected_error,setup,teardown) VALUES
    (N''demo_guest_a'', N''顾客浏览可售商品及选项'', N''IF NOT EXISTS (SELECT 1 FROM teabar_api.vw_Menu WHERE product_id=@P) THROW 52500,N''''商品未显示'''',1; SELECT product_id,product_name,base_price FROM teabar_api.vw_Menu WHERE product_id=@P;'', NULL, NULL, NULL),
    (N''demo_guest_a'', N''顾客付款下单：两杯、规格及加料'', N''DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TG, @P, 2);
INSERT @s VALUES(@TG, @S1), (@TG, @S2), (@TG, @S3);
INSERT @addon_selection VALUES(@TG, @A);
EXEC teabar_api.usp_PlacePaidOrder @OG, @l, @s, @addon_selection, 1;'', NULL, NULL, N''IF NOT EXISTS(SELECT 1 FROM dbo.SalesOrder WHERE order_id=@OG AND total_amount=19.6)
 OR NOT EXISTS(SELECT 1 FROM dbo.OrderItemIngredient WHERE item_id=@TG AND ingredient_id=@I1 AND amount=26)
 OR NOT EXISTS(SELECT 1 FROM dbo.OrderItemIngredient WHERE item_id=@TG AND ingredient_id=@I2 AND amount=200)
 OR NOT EXISTS(SELECT 1 FROM dbo.OrderItemIngredient WHERE item_id=@TG AND ingredient_id=@I3 AND amount=2)
 THROW 52500,N''''价格或多规格、同原料加料计算不正确'''',1;''),
    (N''demo_guest_a'', N''同一顾客会话再次下单'', N''DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TG2, @P, 1);
INSERT @s VALUES(@TG2, @S1), (@TG2, @S2), (@TG2, @S3);

EXEC teabar_api.usp_PlacePaidOrder @OG2, @l, @s, @addon_selection, 1;'', NULL, NULL, NULL),
    (N''demo_guest_b'', N''第二名顾客独立下单'', N''DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TGB, @P, 1);
INSERT @s VALUES(@TGB, @S1), (@TGB, @S2), (@TGB, @S3);

EXEC teabar_api.usp_PlacePaidOrder @OGB, @l, @s, @addon_selection, 1;'', NULL, NULL, NULL),
    (N''demo_member_a'', N''会员付款下单并绑定本人身份'', N''DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TM, @P, 2);
INSERT @s VALUES(@TM, @S1), (@TM, @S2), (@TM, @S3);
INSERT @addon_selection VALUES(@TM, @A);
EXEC teabar_api.usp_PlacePaidOrder @OM, @l, @s, @addon_selection, 1;'', NULL, NULL, NULL),
    (N''demo_member_b'', N''第二名会员独立下单'', N''DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TMB, @P, 1);
INSERT @s VALUES(@TMB, @S1), (@TMB, @S2), (@TMB, @S3);

EXEC teabar_api.usp_PlacePaidOrder @OMB, @l, @s, @addon_selection, 1;'', NULL, NULL, NULL),
    (N''demo_guest_a'', N''顾客仅能查询本人订单'', N''IF NOT EXISTS(SELECT 1 FROM teabar_api.vw_MyOrders WHERE order_id=@OG)
 OR EXISTS(SELECT 1 FROM teabar_api.vw_MyOrders WHERE order_id IN(@OGB,@OM,@OMB))
 THROW 52500,N''''游客订单未隔离'''',1;
 SELECT * FROM teabar_api.vw_MyOrderItems WHERE order_id=@OG;'', NULL, NULL, NULL),
    (N''demo_member_a'', N''会员资料和消费记录仅限本人'', N''IF NOT EXISTS(SELECT 1 FROM teabar_api.vw_MyMember WHERE member_id=@MA)
 OR EXISTS(SELECT 1 FROM teabar_api.vw_MyMember WHERE member_id=@MB)
 OR EXISTS(SELECT 1 FROM teabar_api.vw_MyOrders WHERE order_id IN(@OG,@OMB,@OD))
 THROW 52500,N''''会员数据未隔离'''',1; SELECT * FROM teabar_api.vw_MyMember;'', NULL, NULL, NULL),
    (N''demo_guest_a'', N''伪造SESSION_CONTEXT不能改订单身份'', N''DECLARE @previous SQL_VARIANT=SESSION_CONTEXT(N''''guest_id'''');
EXEC sys.sp_set_session_context @key=N''''guest_id'''',@value=@GB;
BEGIN TRY
 IF EXISTS(SELECT 1 FROM teabar_api.vw_MyOrders WHERE order_id=@OGB) THROW 52500,N''''会话变量绕过了身份绑定'''',1;
 EXEC sys.sp_set_session_context @key=N''''guest_id'''',@value=@previous;
END TRY
BEGIN CATCH
 EXEC sys.sp_set_session_context @key=N''''guest_id'''',@value=@previous; THROW;
END CATCH;'', NULL, NULL, NULL),
    (N''demo_clerk'', N''店员仅查当天及全部未完成订单'', N''IF EXISTS(SELECT 1 FROM teabar_api.vw_WorkOrders WHERE order_id=@OD)
 OR NOT EXISTS(SELECT 1 FROM teabar_api.vw_WorkOrders WHERE order_id=@OP)
 OR NOT EXISTS(SELECT 1 FROM teabar_api.vw_WorkOrders WHERE order_id=@OM)
 THROW 52500,N''''店员订单时间范围不正确'''',1; SELECT * FROM teabar_api.vw_WorkOrders WHERE order_id IN(@OM,@OP);'', NULL, NULL, NULL),
    (N''demo_manager'', N''店长可查看历史订单和经营统计'', N''IF NOT EXISTS(SELECT 1 FROM dbo.SalesOrder WHERE order_id=@OD) THROW 52500,N''''店长不能查历史'''',1; SELECT * FROM teabar_api.vw_DailySales WHERE sale_date=CONVERT(DATE,DATEADD(DAY,-2,SYSDATETIME()));'', NULL, NULL, NULL),
    (N''demo_guest_a'', N''重复订单编号不能造成重复扣库'', N''DECLARE @l teabar_api.OrderLines,@s teabar_api.OrderSpecs,@addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TX,@P,2); INSERT @s VALUES(@TX,@S1),(@TX,@S2),(@TX,@S3);
INSERT @addon_selection VALUES(@TX,@A);
EXEC teabar_api.usp_PlacePaidOrder @OG,@l,@s,@addon_selection,1;'', 2627, NULL, NULL),
    (N''demo_guest_a'', N''顾客不能直接插入他人归属的订单'', N''INSERT dbo.SalesOrder(order_id,guest_id,total_amount) VALUES(@OX,@GB,0);'', 229, NULL, NULL),
    (N''demo_guest_a'', N''顾客不能直接读取全部订单'', N''SELECT * FROM dbo.SalesOrder;'', 229, NULL, NULL),
    (N''demo_member_a'', N''会员不能直接读取会员名单'', N''SELECT * FROM dbo.Member;'', 229, NULL, NULL),
    (N''demo_clerk'', N''店员不能读取员工工资'', N''SELECT salary FROM dbo.Employee;'', 229, NULL, NULL),
    (N''demo_guest_a'', N''顾客不能读取会员专属资料视图'', N''SELECT * FROM teabar_api.vw_MyMember;'', 229, NULL, NULL),
    (N''demo_clerk'', N''店员不能读取历史销售统计'', N''SELECT * FROM teabar_api.vw_DailySales;'', 229, NULL, NULL),
    (N''demo_guest_a'', N''顾客不能退款他人游客订单'', N''EXEC teabar_api.usp_RefundOrder @OGB;'', 52105, NULL, NULL),
    (N''demo_member_a'', N''会员不能退款其他会员订单'', N''EXEC teabar_api.usp_RefundOrder @OMB;'', 52105, NULL, NULL),
    (N''demo_guest_a'', N''顾客不能直接篡改订单金额'', N''UPDATE dbo.SalesOrder SET total_amount=0 WHERE order_id=@OG;'', 229, NULL, NULL),
    (N''demo_member_a'', N''会员不能自行修改积分'', N''UPDATE dbo.Member SET points=9999 WHERE member_id=@MA;'', 229, NULL, NULL),
    (N''demo_guest_a'', N''顾客不能推进制作状态'', N''EXEC teabar_api.usp_AdvanceOrder @OG,N''''制作中'''';'', 229, NULL, NULL),
    (N''demo_clerk'', N''店员没有代替顾客下单权限'', N''EXEC teabar_api.usp_PlacePaidOrder;'', 229, NULL, NULL),
    (N''demo_guest_a'', N''支付失败不产生订单'', N''DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TX, @P, 2);
INSERT @s VALUES(@TX, @S1), (@TX, @S2), (@TX, @S3);
INSERT @addon_selection VALUES(@TX, @A);
EXEC teabar_api.usp_PlacePaidOrder @OX, @l, @s, @addon_selection, 0;'', 52001, NULL, NULL),
    (N''demo_guest_a'', N''漏选已配置规格类型被拒绝'', N''DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TX, @P, 2);
INSERT @s VALUES(@TX, @S1), (@TX, @S2);
INSERT @addon_selection VALUES(@TX, @A);
EXEC teabar_api.usp_PlacePaidOrder @OX, @l, @s, @addon_selection, 1;'', 52009, NULL, NULL),
    (N''demo_guest_a'', N''同类型选择两个规格被拒绝'', N''DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TX, @P, 2);
INSERT @s VALUES(@TX, @S1), (@TX, @S4), (@TX, @S2), (@TX, @S3);
INSERT @addon_selection VALUES(@TX, @A);
EXEC teabar_api.usp_PlacePaidOrder @OX, @l, @s, @addon_selection, 1;'', 52008, NULL, NULL),
    (N''demo_guest_a'', N''不适用于商品的规格被拒绝'', N''DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TX, @P, 2);
INSERT @s VALUES(@TX, @S1), (@TX, @S2), (@TX, @S5);
INSERT @addon_selection VALUES(@TX, @A);
EXEC teabar_api.usp_PlacePaidOrder @OX, @l, @s, @addon_selection, 1;'', 52007, NULL, NULL),
    (N''demo_guest_a'', N''下单接口没有可伪造的归属或金额参数'', N''IF EXISTS (
 SELECT 1 FROM sys.parameters WHERE object_id=OBJECT_ID(N''''teabar_api.usp_PlacePaidOrder'''')
 AND name IN(N''''@member_id'''',N''''@guest_id'''',N''''@total_amount''''))
 THROW 52500,N''''接口暴露了不应由调用者指定的参数'''',1;'', NULL, NULL, NULL),
    (N''demo_clerk'', N''不能从排队中直接完成'', N''EXEC teabar_api.usp_AdvanceOrder @OM,N''''已完成'''';'', 52103, NULL, NULL),
    (N''demo_clerk'', N''店员接单进入制作中'', N''EXEC teabar_api.usp_AdvanceOrder @OM,N''''制作中'''';'', NULL, NULL, NULL),
    (N''demo_member_a'', N''制作中不允许退款'', N''EXEC teabar_api.usp_RefundOrder @OM;'', 52106, NULL, NULL),
    (N''demo_clerk'', N''制作完成进入待取餐'', N''EXEC teabar_api.usp_AdvanceOrder @OM,N''''待取餐'''';'', NULL, NULL, NULL),
    (N''demo_clerk'', N''交付完成并自动结算积分'', N''EXEC teabar_api.usp_AdvanceOrder @OM,N''''已完成'''';'', NULL, NULL, NULL),
    (N''demo_member_a'', N''19.60元整单首次完成积19分'', N''IF NOT EXISTS(SELECT 1 FROM teabar_api.vw_MyMember WHERE member_id=@MA AND points=19) THROW 52500,N''''积分算法错误'''',1;'', NULL, NULL, NULL),
    (N''demo_clerk'', N''重复完成不得再次加分'', N''EXEC teabar_api.usp_AdvanceOrder @OM,N''''已完成'''';'', 52103, NULL, NULL),
    (N''demo_member_a'', N''已完成订单不允许退款'', N''EXEC teabar_api.usp_RefundOrder @OM;'', 52106, NULL, NULL),
    (N''demo_guest_a'', N''配方变更后本人退款仍按付款快照返库'', N''EXEC teabar_api.usp_RefundOrder @OG;'', NULL, N''UPDATE dbo.Recipe SET base_amount=123 WHERE product_id=@P AND ingredient_id=@I1;'', N''IF NOT EXISTS(SELECT 1 FROM dbo.Ingredient WHERE ingredient_id=@I1 AND stock=944)
 THROW 52500,N''''退款重算了当前配方，未按原快照返库'''',1;
UPDATE dbo.Recipe SET base_amount=10 WHERE product_id=@P AND ingredient_id=@I1;''),
    (N''demo_guest_a'', N''重复退款不得重复返库'', N''EXEC teabar_api.usp_RefundOrder @OG;'', 52106, NULL, NULL),
    (N''demo_clerk'', N''店员协助顾客退款'', N''EXEC teabar_api.usp_RefundOrder @OGB;'', NULL, NULL, NULL),
    (N''demo_manager'', N''店长协助会员退款'', N''EXEC teabar_api.usp_RefundOrder @OMB;'', NULL, NULL, NULL),
    (N''demo_clerk'', N''店员登记会员且积分初始为0'', N''EXEC teabar_api.usp_SaveMember @MC,N''''新会员'''',@PC;'', NULL, NULL, NULL),
    (N''demo_clerk'', N''店员更正会员资料但不改积分'', N''EXEC teabar_api.usp_SaveMember @MA,N''''修改后的本人姓名'''',@PA; EXEC teabar_api.usp_FindMember @PA;'', NULL, NULL, NULL),
    (N''demo_manager'', N''店长通过补库增加原料'', N''EXEC teabar_api.usp_AdjustStock @I1,N''''补库'''',5;'', NULL, NULL, NULL),
    (N''demo_clerk'', N''店员不能补库'', N''EXEC teabar_api.usp_AdjustStock @I1,N''''补库'''',5;'', 229, NULL, NULL),
    (N''demo_manager'', N''补库数量不能为0'', N''EXEC teabar_api.usp_AdjustStock @I1,N''''补库'''',0;'', 52110, NULL, NULL),
    (N''demo_manager'', N''计件补库不能使用小数'', N''EXEC teabar_api.usp_AdjustStock @I3,N''''补库'''',0.5;'', 52111, NULL, NULL),
    (N''demo_manager'', N''盘点实际库存允许为0'', N''EXEC teabar_api.usp_AdjustStock @I3,N''''盘点'''',0;'', NULL, NULL, NULL),
    (N''demo_manager'', N''盘点库存不能为负'', N''EXEC teabar_api.usp_AdjustStock @I3,N''''盘点'''',-1;'', 52110, NULL, NULL),
    (N''demo_manager'', N''店长也不能直接更新库存'', N''UPDATE dbo.Ingredient SET stock=999 WHERE ingredient_id=@I1;'', 229, NULL, NULL),
    (N''demo_manager'', N''店长也不能直接改历史成交快照'', N''UPDATE dbo.OrderItem SET unit_price=0 WHERE item_id=@TM;'', 229, NULL, NULL),
    (N''demo_manager'', N''店长没有物理删除商品权限'', N''DELETE dbo.Product WHERE product_id=@P;'', 229, NULL, NULL),
    (N''demo_manager'', N''店长没有物理删除订单权限'', N''DELETE dbo.SalesOrder WHERE order_id=@OM;'', 229, NULL, NULL),
    (N''demo_manager'', N''店长不能修改身份绑定'', N''UPDATE teabar_auth.PrincipalBinding SET member_id=@MB WHERE principal_name=N''''demo_member_a'''';'', 229, NULL, NULL),
    (N''demo_manager'', N''店长不能授予数据库角色'', N''ALTER ROLE teabar_manager ADD MEMBER demo_guest_a;'', 15151, NULL, NULL),
    (N''demo_manager'', N''店长改价不改历史金额和快照'', N''EXEC teabar_api.usp_SaveProduct @P,N''''改名后的商品'''',7.8,N''''在售'''';'', NULL, NULL, NULL),
    (N''demo_manager'', N''已使用原料不能变更单位'', N''EXEC teabar_api.usp_SaveIngredient @I1,N''''糖浆'''',N''''g'''',N''''可用'''';'', 52113, NULL, NULL),
    (N''demo_manager'', N''停用商品规格配置'', N''EXEC teabar_api.usp_SaveProductSpecification @P,@S3,2,N''''停用'''';'', NULL, NULL, NULL),
    (N''demo_guest_a'', N''停用规格不能购买'', N''DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TX, @P, 2);
INSERT @s VALUES(@TX, @S1), (@TX, @S2), (@TX, @S3);
INSERT @addon_selection VALUES(@TX, @A);
EXEC teabar_api.usp_PlacePaidOrder @OX, @l, @s, @addon_selection, 1;'', 52007, NULL, NULL),
    (N''demo_manager'', N''计件规格规则拒绝1.5个'', N''EXEC teabar_api.usp_SaveSpecificationIngredient @P,@S3,@I3,1.5;'', 52116, NULL, NULL),
    (N''demo_manager'', N''重新启用已完成的规格配置'', N''EXEC teabar_api.usp_SaveProductSpecification @P,@S3,2,N''''可用'''';'', NULL, NULL, NULL),
    (N''demo_manager'', N''模拟库存不足的盘点'', N''EXEC teabar_api.usp_AdjustStock @I1,N''''盘点'''',1;'', NULL, NULL, NULL),
    (N''demo_guest_a'', N''库存不足整单回滚不留下半张订单'', N''DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TX, @P, 2);
INSERT @s VALUES(@TX, @S1), (@TX, @S2), (@TX, @S3);
INSERT @addon_selection VALUES(@TX, @A);
EXEC teabar_api.usp_PlacePaidOrder @OX, @l, @s, @addon_selection, 1;'', 52016, NULL, NULL),
    (N''demo_manager'', N''补齐可用库存供后续测试'', N''EXEC teabar_api.usp_AdjustStock @I1,N''''盘点'''',1000; EXEC teabar_api.usp_AdjustStock @I3,N''''盘点'''',100;'', NULL, NULL, NULL),
    (N''demo_guest_a'', N''多条明细需求先汇总防止各自足够但整单不足'', N''DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TX, @P, 1),(@TY,@P,1);
INSERT @s VALUES(@TX,@S1),(@TX,@S2),(@TX,@S3),(@TY,@S1),(@TY,@S2),(@TY,@S3);

EXEC teabar_api.usp_PlacePaidOrder @OX, @l, @s, @addon_selection, 1;'', 52016, N''UPDATE dbo.Ingredient SET stock=15 WHERE ingredient_id=@I1;'', N''UPDATE dbo.Ingredient SET stock=1000 WHERE ingredient_id=@I1;''),
    (N''demo_guest_a'', N''每杯1.5个即使买两杯也拒绝'', N''DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TX, @P, 2);
INSERT @s VALUES(@TX, @S1), (@TX, @S2), (@TX, @S3);
INSERT @addon_selection VALUES(@TX, @A);
EXEC teabar_api.usp_PlacePaidOrder @OX, @l, @s, @addon_selection, 1;'', 52014, N''INSERT dbo.SpecificationIngredient(product_id,spec_id,ingredient_id,factor) VALUES(@P,@S3,@I3,1.5);'', N''DELETE dbo.SpecificationIngredient WHERE product_id=@P AND spec_id=@S3 AND ingredient_id=@I3;''),
    (N''demo_manager'', N''店长创建新原料、商品和配方'', N''EXEC teabar_api.usp_SaveIngredient @I4,N''''新原料'''',N''''ml'''',N''''可用'''';
 EXEC teabar_api.usp_SaveProduct @P2,N''''新商品'''',1,N''''下架'''';
 EXEC teabar_api.usp_SaveRecipe @P2,@I4,0.5;'', NULL, NULL, NULL),
    (N''demo_manager'', N''店长创建规格、规则并启用配置'', N''EXEC teabar_api.usp_SaveSpecification @S5,N''''杯型'''',@S5;
 EXEC teabar_api.usp_SaveProductSpecification @P2,@S5,-0.5,N''''停用'''';
 EXEC teabar_api.usp_SaveSpecificationIngredient @P2,@S5,@I4,2;
 EXEC teabar_api.usp_SaveProductSpecification @P2,@S5,-0.5,N''''可用'''';
 EXEC teabar_api.usp_SaveProduct @P2,N''''新商品'''',1,N''''在售'''';'', NULL, NULL, NULL),
    (N''demo_manager'', N''店长创建独立加料'', N''EXEC teabar_api.usp_SaveAddOn @A2,@A2,1,@I4,2,N''''可用'''';'', NULL, NULL, NULL),
    (N''demo_manager'', N''店长登记员工及相邻班次'', N''EXEC teabar_api.usp_SaveEmployee @E,N''''测试员工'''',N''''在职'''',0,N''''店员'''';
 EXEC teabar_api.usp_SaveDutyRoster @D1,@E,''''2099-01-01T08:00:00'''',''''2099-01-01T16:00:00'''';
 EXEC teabar_api.usp_SaveDutyRoster @D2,@E,''''2099-01-01T16:00:00'''',''''2099-01-01T23:00:00'''';'', NULL, NULL, NULL),
    (N''demo_manager'', N''同一员工不同开始时间仍不允许排班重叠'', N''EXEC teabar_api.usp_SaveDutyRoster @D3,@E,''''2099-01-01T12:00:00'''',''''2099-01-01T18:00:00'''';'', 52121, NULL, NULL),
    (N''demo_manager'', N''员工岗位和离职资料不自动修改数据库角色'', N''EXEC teabar_api.usp_SaveEmployee @E,N''''测试员工'''',N''''离职'''',0,N''''店长'''';'', NULL, NULL, NULL),
    (N''demo_manager'', N''不能为离职员工新排班'', N''EXEC teabar_api.usp_SaveDutyRoster @D3,@E,''''2099-01-02T08:00:00'''',''''2099-01-02T16:00:00'''';'', 52120, NULL, NULL),
    (N''demo_guest_a'', N''零糖系数不取消独立加料且加料不乘杯型系数'', N''DECLARE @zo VARCHAR(10)=LEFT(@P,8)+''''OZ'''',@zi VARCHAR(10)=LEFT(@P,8)+''''TZ'''';
DECLARE @zl teabar_api.OrderLines,@zs teabar_api.OrderSpecs,@za teabar_api.OrderAddOns;
INSERT @zl VALUES(@zi,@P,2); INSERT @zs VALUES(@zi,@S4),(@zi,@S2),(@zi,@S3); INSERT @za VALUES(@zi,@A);
EXEC teabar_api.usp_PlacePaidOrder @zo,@zl,@zs,@za,1;'', NULL, NULL,
N''IF NOT EXISTS(SELECT 1 FROM dbo.OrderItemIngredient WHERE item_id=LEFT(@P,8)+''''TZ'''' AND ingredient_id=@I1 AND amount=6)
 OR NOT EXISTS(SELECT 1 FROM dbo.OrderItemIngredient WHERE item_id=LEFT(@P,8)+''''TZ'''' AND ingredient_id=@I2 AND amount=200)
 OR NOT EXISTS(SELECT 1 FROM dbo.OrderItemIngredient WHERE item_id=LEFT(@P,8)+''''TZ'''' AND ingredient_id=@I3 AND amount=2)
  THROW 52500,N''''零系数或独立加料计算错误'''',1;''),
    (N''demo_manager'', N''准备两类型和三类型计件组合配置'', N''DECLARE @pz VARCHAR(10)=LEFT(@P,8)+''''PZ'''',@py VARCHAR(10)=LEFT(@P,8)+''''PY'''',@iz VARCHAR(10)=LEFT(@P,8)+''''IZ'''';
 EXEC teabar_api.usp_SaveIngredient @iz,N''''组合测试原料'''',N''''个'''',N''''可用'''';
 EXEC teabar_api.usp_AdjustStock @iz,N''''补库'''',1000;
 EXEC teabar_api.usp_SaveProduct @pz,N''''两类型组合测试'''',1,N''''下架'''';
 EXEC teabar_api.usp_SaveProduct @py,N''''三类型组合测试'''',1,N''''下架'''';
 EXEC teabar_api.usp_SaveRecipe @pz,@iz,2;
 EXEC teabar_api.usp_SaveRecipe @py,@iz,4;
 EXEC teabar_api.usp_SaveProductSpecification @pz,@S1,0,N''''停用'''';
 EXEC teabar_api.usp_SaveProductSpecification @pz,@S4,0,N''''停用'''';
 EXEC teabar_api.usp_SaveProductSpecification @pz,@S3,0,N''''停用'''';
 EXEC teabar_api.usp_SaveSpecificationIngredient @pz,@S1,@iz,1.5;
 EXEC teabar_api.usp_SaveSpecificationIngredient @pz,@S4,@iz,1.5;
 EXEC teabar_api.usp_SaveSpecificationIngredient @pz,@S3,@iz,1.5;
 EXEC teabar_api.usp_SaveProductSpecification @py,@S1,0,N''''停用'''';
 EXEC teabar_api.usp_SaveProductSpecification @py,@S2,0,N''''停用'''';
 EXEC teabar_api.usp_SaveProductSpecification @py,@S3,0,N''''停用'''';
 EXEC teabar_api.usp_SaveSpecificationIngredient @py,@S1,@iz,1.5;
 EXEC teabar_api.usp_SaveSpecificationIngredient @py,@S2,@iz,1.5;
 EXEC teabar_api.usp_SaveSpecificationIngredient @py,@S3,@iz,1.5;'', NULL, NULL, NULL),
    (N''demo_manager'', N''同类型备选不相乘且停用类型不参与组合'', N''DECLARE @pz VARCHAR(10)=LEFT(@P,8)+''''PZ'''';
 EXEC teabar_api.usp_SaveProductSpecification @pz,@S1,0,N''''可用'''';
 EXEC teabar_api.usp_SaveProductSpecification @pz,@S4,0,N''''可用'''';'', NULL, NULL, NULL),
    (N''demo_manager'', N''两个单项整数但组合4.5个时拒绝启用'', N''DECLARE @pz VARCHAR(10)=LEFT(@P,8)+''''PZ'''';
 EXEC teabar_api.usp_SaveProductSpecification @pz,@S3,9,N''''可用'''';'', 52116, NULL, NULL),
    (N''demo_manager'', N''修正规则后合法两类型组合可以启用'', N''DECLARE @pz VARCHAR(10)=LEFT(@P,8)+''''PZ'''',@iz VARCHAR(10)=LEFT(@P,8)+''''IZ'''';
 EXEC teabar_api.usp_SaveSpecificationIngredient @pz,@S3,@iz,2;
 EXEC teabar_api.usp_SaveProductSpecification @pz,@S3,0,N''''可用'''';'', NULL, NULL, NULL),
    (N''demo_manager'', N''三类型配置先启用合法的两类型组合'', N''DECLARE @py VARCHAR(10)=LEFT(@P,8)+''''PY'''';
 EXEC teabar_api.usp_SaveProductSpecification @py,@S1,0,N''''可用'''';
 EXEC teabar_api.usp_SaveProductSpecification @py,@S2,0,N''''可用'''';'', NULL, NULL, NULL),
    (N''demo_manager'', N''任意两项整数但三类型组合13.5个时拒绝启用'', N''DECLARE @py VARCHAR(10)=LEFT(@P,8)+''''PY'''';
 EXEC teabar_api.usp_SaveProductSpecification @py,@S3,9,N''''可用'''';'', 52116, NULL, NULL),
    (N''demo_manager'', N''修正规则后合法三类型组合可以启用上架'', N''DECLARE @py VARCHAR(10)=LEFT(@P,8)+''''PY'''',@iz VARCHAR(10)=LEFT(@P,8)+''''IZ'''';
 EXEC teabar_api.usp_SaveSpecificationIngredient @py,@S3,@iz,2;
 EXEC teabar_api.usp_SaveProductSpecification @py,@S3,0,N''''可用'''';
 EXEC teabar_api.usp_SaveProduct @py,N''''三类型组合测试'''',1,N''''在售'''';'', NULL, NULL, NULL),
    (N''demo_manager'', N''计件组合允许同类型的零系数备选'', N''DECLARE @pz VARCHAR(10)=LEFT(@P,8)+''''PZ'''',@iz VARCHAR(10)=LEFT(@P,8)+''''IZ'''';
 EXEC teabar_api.usp_SaveProductSpecification @pz,@S4,0,N''''停用'''';
 EXEC teabar_api.usp_SaveSpecificationIngredient @pz,@S4,@iz,0;
 EXEC teabar_api.usp_SaveProductSpecification @pz,@S4,0,N''''可用'''';
 EXEC teabar_api.usp_SaveProduct @pz,N''''两类型组合测试'''',1,N''''在售'''';'', NULL, NULL, NULL),
    (N''demo_manager'', N''零系数备选不能掩盖另一个备选的非法组合'', N''DECLARE @pz VARCHAR(10)=LEFT(@P,8)+''''PZ'''';
 EXEC teabar_api.usp_SaveProductSpecification @pz,@S3,9,N''''可用'''';'', 52116,
 N''UPDATE dbo.ProductSpecification SET status=N''''停用'''' WHERE product_id=LEFT(@P,8)+''''PZ'''' AND spec_id=@S3;
 UPDATE dbo.SpecificationIngredient SET factor=1.5 WHERE product_id=LEFT(@P,8)+''''PZ'''' AND spec_id=@S3 AND ingredient_id=LEFT(@P,8)+''''IZ'''';'',
 N''UPDATE dbo.SpecificationIngredient SET factor=2 WHERE product_id=LEFT(@P,8)+''''PZ'''' AND spec_id=@S3 AND ingredient_id=LEFT(@P,8)+''''IZ'''';
 UPDATE dbo.ProductSpecification SET status=N''''可用'''' WHERE product_id=LEFT(@P,8)+''''PZ'''' AND spec_id=@S3;''),
    (N''demo_guest_a'', N''合法两类型及三类型组合下单正确扣减计件库存'', N''DECLARE @pz VARCHAR(10)=LEFT(@P,8)+''''PZ'''',@py VARCHAR(10)=LEFT(@P,8)+''''PY'''',
 @oz VARCHAR(10)=LEFT(@P,8)+''''OY'''',@combo_item_a VARCHAR(10)=LEFT(@P,8)+''''TT'''',@combo_item_b VARCHAR(10)=LEFT(@P,8)+''''TU'''';
 DECLARE @l teabar_api.OrderLines,@s teabar_api.OrderSpecs,@combo_addons teabar_api.OrderAddOns;
 INSERT @l VALUES(@combo_item_a,@pz,1),(@combo_item_b,@py,1);
 INSERT @s VALUES(@combo_item_a,@S1),(@combo_item_a,@S3),(@combo_item_b,@S1),(@combo_item_b,@S2),(@combo_item_b,@S3);
 EXEC teabar_api.usp_PlacePaidOrder @oz,@l,@s,@combo_addons,1;'', NULL, NULL,
 N''IF NOT EXISTS(SELECT 1 FROM dbo.OrderItemIngredient WHERE item_id=LEFT(@P,8)+''''TT'''' AND ingredient_id=LEFT(@P,8)+''''IZ'''' AND amount=6)
 OR NOT EXISTS(SELECT 1 FROM dbo.OrderItemIngredient WHERE item_id=LEFT(@P,8)+''''TU'''' AND ingredient_id=LEFT(@P,8)+''''IZ'''' AND amount=18)
 OR NOT EXISTS(SELECT 1 FROM dbo.Ingredient WHERE ingredient_id=LEFT(@P,8)+''''IZ'''' AND stock=976)
 THROW 52500,N''''合法组合的计件扣库或快照错误'''',1;'');

DECLARE @results TABLE(
 seq INT PRIMARY KEY, user_name SYSNAME, case_name NVARCHAR(100),
 expected_error INT NULL, actual_error INT NULL, passed BIT, detail NVARCHAR(1000));
DECLARE @params NVARCHAR(MAX)=N''
 @P VARCHAR(10),@P2 VARCHAR(10),@S1 VARCHAR(10),@S2 VARCHAR(10),@S3 VARCHAR(10),@S4 VARCHAR(10),@S5 VARCHAR(10),
 @I1 VARCHAR(10),@I2 VARCHAR(10),@I3 VARCHAR(10),@I4 VARCHAR(10),@A VARCHAR(10),@A2 VARCHAR(10),
 @MA VARCHAR(10),@MB VARCHAR(10),@MC VARCHAR(10),@PA VARCHAR(20),@PB VARCHAR(20),@PC VARCHAR(20),
 @E VARCHAR(10),@D1 VARCHAR(10),@D2 VARCHAR(10),@D3 VARCHAR(10),
 @OG VARCHAR(10),@OG2 VARCHAR(10),@OGB VARCHAR(10),@OM VARCHAR(10),@OMB VARCHAR(10),
 @OD VARCHAR(10),@OP VARCHAR(10),@OX VARCHAR(10),
 @TG VARCHAR(10),@TG2 VARCHAR(10),@TGB VARCHAR(10),@TM VARCHAR(10),@TMB VARCHAR(10),@TX VARCHAR(10),@TY VARCHAR(10),
 @GB UNIQUEIDENTIFIER'';

BEGIN TRY
 BEGIN TRANSACTION;
 -- 管理员建立独立随机测试数据，临时把两个示例会员映射至测试会员；最后一并回滚。
 INSERT dbo.Member(member_id,name,phone,points) VALUES(@MA,N''测试会员甲'',@PA,0),(@MB,N''测试会员乙'',@PB,0);
 UPDATE teabar_auth.PrincipalBinding SET member_id=@MA WHERE principal_name=N''demo_member_a'';
 UPDATE teabar_auth.PrincipalBinding SET member_id=@MB WHERE principal_name=N''demo_member_b'';
 INSERT dbo.Product(product_id,product_name,base_price,status) VALUES(@P,N''角色测试商品'',6.8,N''在售'');
 INSERT dbo.Ingredient(ingredient_id,ingredient_name,unit,stock,status)
 VALUES(@I1,N''角色测试糖浆'',N''ml'',1000,N''可用''),(@I2,N''角色测试茶汤'',N''ml'',1000,N''可用''),
       (@I3,N''角色测试杯子'',N''个'',100,N''可用'');
 INSERT dbo.Specification(spec_id,spec_type,spec_name)
 VALUES(@S1,N''糖度'',@S1),(@S2,N''温度'',@S2),(@S3,N''杯型'',@S3),(@S4,N''糖度'',@S4);
 INSERT dbo.ProductSpecification(product_id,spec_id,price_delta,status)
 VALUES(@P,@S1,0,N''可用''),(@P,@S2,0,N''可用''),(@P,@S3,2,N''可用''),(@P,@S4,0,N''可用'');
 INSERT dbo.Recipe(product_id,ingredient_id,base_amount) VALUES(@P,@I1,10),(@P,@I2,100),(@P,@I3,1);
 INSERT dbo.SpecificationIngredient(product_id,spec_id,ingredient_id,factor)
 VALUES(@P,@S1,@I1,0.5),(@P,@S2,@I2,0.5),(@P,@S3,@I1,2),(@P,@S3,@I2,2),(@P,@S4,@I1,0);
 INSERT dbo.AddOn(addon_id,addon_name,price,ingredient_id,extra_amount,status)
 VALUES(@A,@A,1,@I1,3,N''可用'');
 -- 两条历史测试记录仅服务于查询范围验证，不演示完整下单流程。
 INSERT dbo.SalesOrder(order_id,member_id,order_time,total_amount,status)
 VALUES(@OD,@MB,DATEADD(DAY,-2,SYSDATETIME()),0,N''已完成''),
       (@OP,@MB,DATEADD(DAY,-2,SYSDATETIME()),0,N''排队中'');

 DECLARE @seq INT=1,@count INT=(SELECT COUNT(*) FROM @cases),@user SYSNAME,@label NVARCHAR(100);
 DECLARE @sql NVARCHAR(MAX),@setup NVARCHAR(MAX),@teardown NVARCHAR(MAX),@expected INT,@actual INT,@message NVARCHAR(4000);
 DECLARE @before VARBINARY(32),@after VARBINARY(32),@passed BIT;
 WHILE @seq<=@count
 BEGIN
  SELECT @user=user_name,@label=case_name,@sql=statement,@expected=expected_error,@setup=setup,@teardown=teardown
  FROM @cases WHERE seq=@seq;
  IF @setup IS NOT NULL
   EXEC sys.sp_executesql @setup,@params,
    @P=@P,@P2=@P2,@S1=@S1,@S2=@S2,@S3=@S3,@S4=@S4,@S5=@S5,
    @I1=@I1,@I2=@I2,@I3=@I3,@I4=@I4,@A=@A,@A2=@A2,
    @MA=@MA,@MB=@MB,@MC=@MC,@PA=@PA,@PB=@PB,@PC=@PC,
    @E=@E,@D1=@D1,@D2=@D2,@D3=@D3,
    @OG=@OG,@OG2=@OG2,@OGB=@OGB,@OM=@OM,@OMB=@OMB,@OD=@OD,@OP=@OP,@OX=@OX,
    @TG=@TG,@TG2=@TG2,@TGB=@TGB,@TM=@TM,@TMB=@TMB,@TX=@TX,@TY=@TY,@GB=@GB;
  SET @actual=NULL; SET @message=NULL;
  SAVE TRANSACTION role_test_case;
  SELECT @before=HASHBYTES(''SHA2_256'',
        (SELECT * FROM dbo.Employee ORDER BY employee_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.DutyRoster ORDER BY duty_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.Member ORDER BY member_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.SalesOrder ORDER BY order_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.Product ORDER BY product_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.Specification ORDER BY spec_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.Ingredient ORDER BY ingredient_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.OrderItem ORDER BY item_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.ProductSpecification ORDER BY product_id,spec_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.Recipe ORDER BY product_id,ingredient_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.AddOn ORDER BY addon_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.ItemSpec ORDER BY item_id,spec_type FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.ItemAddOn ORDER BY item_id,addon_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.OrderItemIngredient ORDER BY item_id,ingredient_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.SpecificationIngredient ORDER BY product_id,spec_id,ingredient_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM teabar_auth.PrincipalBinding ORDER BY principal_sid FOR XML RAW, BINARY BASE64));
  BEGIN TRY
   EXECUTE AS USER=@user;
   SET @impersonating=1;
   EXEC sys.sp_executesql @sql,@params,
    @P=@P,@P2=@P2,@S1=@S1,@S2=@S2,@S3=@S3,@S4=@S4,@S5=@S5,
    @I1=@I1,@I2=@I2,@I3=@I3,@I4=@I4,@A=@A,@A2=@A2,
    @MA=@MA,@MB=@MB,@MC=@MC,@PA=@PA,@PB=@PB,@PC=@PC,
    @E=@E,@D1=@D1,@D2=@D2,@D3=@D3,
    @OG=@OG,@OG2=@OG2,@OGB=@OGB,@OM=@OM,@OMB=@OMB,@OD=@OD,@OP=@OP,@OX=@OX,
    @TG=@TG,@TG2=@TG2,@TGB=@TGB,@TM=@TM,@TMB=@TMB,@TX=@TX,@TY=@TY,@GB=@GB;
   REVERT; SET @impersonating=0;
  END TRY
  BEGIN CATCH
   SET @actual=ERROR_NUMBER(); SET @message=ERROR_MESSAGE();
   IF XACT_STATE()<>1
   BEGIN
    SELECT @seq AS case_number,@label AS case_name,@actual AS actual_error,@message AS detail,
           XACT_STATE() AS transaction_state;
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    IF @impersonating=1 BEGIN REVERT; SET @impersonating=0; END;
    THROW;
   END;
   IF @impersonating=1 BEGIN REVERT; SET @impersonating=0; END;
  END CATCH;
  SELECT @after=HASHBYTES(''SHA2_256'',
        (SELECT * FROM dbo.Employee ORDER BY employee_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.DutyRoster ORDER BY duty_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.Member ORDER BY member_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.SalesOrder ORDER BY order_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.Product ORDER BY product_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.Specification ORDER BY spec_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.Ingredient ORDER BY ingredient_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.OrderItem ORDER BY item_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.ProductSpecification ORDER BY product_id,spec_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.Recipe ORDER BY product_id,ingredient_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.AddOn ORDER BY addon_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.ItemSpec ORDER BY item_id,spec_type FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.ItemAddOn ORDER BY item_id,addon_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.OrderItemIngredient ORDER BY item_id,ingredient_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.SpecificationIngredient ORDER BY product_id,spec_id,ingredient_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM teabar_auth.PrincipalBinding ORDER BY principal_sid FOR XML RAW, BINARY BASE64));
  SET @passed=CASE WHEN @expected IS NULL AND @actual IS NULL THEN 1
    WHEN @expected IS NOT NULL AND @actual=@expected AND @before=@after THEN 1 ELSE 0 END;
  IF @expected IS NOT NULL OR @actual IS NOT NULL ROLLBACK TRANSACTION role_test_case;
  IF @passed=0
  BEGIN
   SELECT @seq AS case_number,@user AS user_name,@label AS case_name,
          @expected AS expected_error,@actual AS actual_error,@message AS detail;
   THROW 52503,N''当前权限或业务验证未通过，已回滚测试事务。'',1;
  END;
  IF @teardown IS NOT NULL
   EXEC sys.sp_executesql @teardown,@params,
    @P=@P,@P2=@P2,@S1=@S1,@S2=@S2,@S3=@S3,@S4=@S4,@S5=@S5,
    @I1=@I1,@I2=@I2,@I3=@I3,@I4=@I4,@A=@A,@A2=@A2,
    @MA=@MA,@MB=@MB,@MC=@MC,@PA=@PA,@PB=@PB,@PC=@PC,
    @E=@E,@D1=@D1,@D2=@D2,@D3=@D3,
    @OG=@OG,@OG2=@OG2,@OGB=@OGB,@OM=@OM,@OMB=@OMB,@OD=@OD,@OP=@OP,@OX=@OX,
    @TG=@TG,@TG2=@TG2,@TGB=@TGB,@TM=@TM,@TMB=@TMB,@TX=@TX,@TY=@TY,@GB=@GB;
  INSERT @results VALUES(@seq,@user,@label,@expected,@actual,@passed,
    LEFT(CASE WHEN @expected IS NOT NULL AND @before<>@after
        THEN N''失败操作留下数据变化，原子性验证失败。''+COALESCE(@message,N'''')
        ELSE COALESCE(@message,N''正常操作成功。'') END,1000));
  SET @seq+=1;
 END;

 -- 最终正例核对：历史快照不受改价影响，退款不加分，会员资料更正不改积分。
 IF NOT EXISTS(SELECT 1 FROM dbo.SalesOrder WHERE order_id=@OM AND member_id=@MA AND guest_id IS NULL
              AND total_amount=19.6 AND status=N''已完成'')
  OR NOT EXISTS(SELECT 1 FROM dbo.OrderItem WHERE item_id=@TM AND base_price_snapshot=6.8 AND unit_price=9.8)
  OR NOT EXISTS(SELECT 1 FROM dbo.Member WHERE member_id=@MA AND points=19)
  OR NOT EXISTS(SELECT 1 FROM dbo.Member WHERE member_id=@MC AND points=0)
  OR NOT EXISTS(SELECT 1 FROM dbo.Member WHERE member_id=@MB AND points=0)
  OR (SELECT COUNT(*) FROM dbo.SalesOrder WHERE order_id IN(@OG,@OG2) AND guest_id=@GA AND member_id IS NULL)<>2
  OR NOT EXISTS(SELECT 1 FROM sys.database_role_members WHERE member_principal_id=DATABASE_PRINCIPAL_ID(N''demo_clerk'')
                AND role_principal_id=DATABASE_PRINCIPAL_ID(N''teabar_clerk''))
 BEGIN
  SELECT * FROM @results WHERE passed=0;
  THROW 52501,N''价格快照、积分、会话ID复用或角色分开维护的最终核对失败。'',1;
 END;
 ROLLBACK TRANSACTION;
 IF USER_NAME()<>@administrator THROW 52502,N''未恢复管理员上下文。'',1;
 IF (SELECT COUNT(*) FROM @results)<>84 THROW 52901,N''提取的角色用例数量不是84。'',1;
 INSERT #RegressionResults(suite,case_name,expected_error,actual_error,passed,detail)
  SELECT N''legacy-role'',case_name,expected_error,actual_error,passed,detail FROM @results;
 SELECT seq,user_name,case_name,expected_error,actual_error,
        CASE passed WHEN 1 THEN N''通过'' ELSE N''失败'' END AS result,detail FROM @results ORDER BY seq;
 IF EXISTS(SELECT 1 FROM @results WHERE passed=0)
  THROW 52503,N''存在未通过的权限或业务操作验证，请检查实际错误。'',1;
 SELECT N''角色及业务验证全部通过，测试数据与临时绑定已回滚'' AS stage,COUNT(*) AS passed_cases FROM @results;
END TRY
BEGIN CATCH
 IF @impersonating=1 REVERT;
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
');
    EXEC(N'-- Test-only fixtures and strict JSON / D01 / Web context cases. Entire fixture transaction rolls back.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
DECLARE @administrator SYSNAME=USER_NAME(),@impersonating BIT=0,@created_entry BIT=0;
DECLARE @prefix VARCHAR(8)=''V1''+LEFT(REPLACE(CONVERT(VARCHAR(36),NEWID()),''-'',''''),6);
DECLARE @product VARCHAR(10)=@prefix+''P1'',@zero VARCHAR(10)=@prefix+''P0'',@ingredient VARCHAR(10)=@prefix+''I1'',
    @spec VARCHAR(10)=@prefix+''S1'',@addon VARCHAR(10)=@prefix+''A1'',@order VARCHAR(10)=@prefix+''O1'',
    @item VARCHAR(10)=@prefix+''T1'',@item2 VARCHAR(10)=@prefix+''T2'',@member VARCHAR(10)=@prefix+''M1'',@member2 VARCHAR(10)=@prefix+''M2'';
DECLARE @good NVARCHAR(MAX)=(SELECT @item AS item_id,@product AS product_id,2 AS quantity FOR JSON PATH);
DECLARE @choices NVARCHAR(MAX)=(SELECT @item AS item_id,@spec AS spec_id FOR JSON PATH);
DECLARE @extras NVARCHAR(MAX)=(SELECT @item AS item_id,@addon AS addon_id FOR JSON PATH);
DECLARE @multi NVARCHAR(MAX)=(SELECT x.item_id,@product AS product_id,1 AS quantity
    FROM (VALUES(@item),(@item2)) AS x(item_id) FOR JSON PATH);
DECLARE @mixed NVARCHAR(MAX)=(SELECT x.item_id,x.product_id,1 AS quantity
    FROM (VALUES(@item,@product),(@item2,@zero)) AS x(item_id,product_id) FOR JSON PATH);
DECLARE @twochoices NVARCHAR(MAX)=(SELECT x.item_id,@spec AS spec_id FROM(VALUES(@item),(@item2)) AS x(item_id) FOR JSON PATH);
DECLARE @singlezero NVARCHAR(MAX)=(SELECT @item2 AS item_id,@zero AS product_id,1 AS quantity FOR JSON PATH);
DECLARE @zerochoices NVARCHAR(MAX)=(SELECT @item2 AS item_id,@spec AS spec_id FOR JSON PATH);
DECLARE @cases TABLE(seq INT IDENTITY PRIMARY KEY,case_name NVARCHAR(150),user_name SYSNAME NULL,
    statement NVARCHAR(MAX),expected_error INT NULL,setup NVARCHAR(MAX),assertion NVARCHAR(MAX));
DECLARE @results TABLE(case_name NVARCHAR(150),expected_error INT NULL,actual_error INT NULL,passed BIT,detail NVARCHAR(4000));
DECLARE @account_id INT,@manager_account INT,@member_account INT,@login_name NVARCHAR(50);
DECLARE @web_users TABLE(seq INT PRIMARY KEY,user_name SYSNAME,app_role VARCHAR(10),role_name SYSNAME);
INSERT @web_users VALUES(1,N''web_guest_a'',''customer'',N''teabar_customer''),(2,N''web_guest_b'',''customer'',N''teabar_customer''),
    (3,N''web_member_a'',''member'',N''teabar_member''),(4,N''web_member_b'',''member'',N''teabar_member''),
    (5,N''web_clerk'',''clerk'',N''teabar_clerk''),(6,N''web_manager'',''manager'',N''teabar_manager'');
DECLARE @phone1 VARCHAR(20),@phone2 VARCHAR(20);
WHILE @phone1 IS NULL OR EXISTS(SELECT 1 FROM dbo.Member WHERE phone=@phone1)
    SET @phone1=''199''+RIGHT(''00000000''+CONVERT(VARCHAR(8),ABS(CONVERT(BIGINT,CHECKSUM(NEWID())))%100000000),8);
WHILE @phone2 IS NULL OR @phone2=@phone1 OR EXISTS(SELECT 1 FROM dbo.Member WHERE phone=@phone2)
    SET @phone2=''199''+RIGHT(''00000000''+CONVERT(VARCHAR(8),ABS(CONVERT(BIGINT,CHECKSUM(NEWID())))%100000000),8);

BEGIN TRY
    BEGIN TRANSACTION;
    INSERT dbo.Member(member_id,name,phone,points) VALUES(@member,N''v1回归会员甲'',@phone1,0),(@member2,N''v1回归会员乙'',@phone2,0);
    INSERT dbo.Product(product_id,product_name,base_price,status) VALUES(@product,N''v1正常消耗'',6,N''在售''),(@zero,N''v1零消耗反例'',6,N''在售'');
    INSERT dbo.Ingredient(ingredient_id,ingredient_name,unit,stock,status) VALUES(@ingredient,N''v1测试原料'',N''ml'',100,N''可用'');
    INSERT dbo.Specification(spec_id,spec_type,spec_name) VALUES(@spec,N''糖度'',@spec);
    INSERT dbo.ProductSpecification(product_id,spec_id,price_delta,status) VALUES(@product,@spec,1,N''可用''),(@zero,@spec,0,N''可用'');
    INSERT dbo.Recipe(product_id,ingredient_id,base_amount) VALUES(@product,@ingredient,10),(@zero,@ingredient,10);
    INSERT dbo.SpecificationIngredient(product_id,spec_id,ingredient_id,factor) VALUES(@zero,@spec,@ingredient,0);
    INSERT dbo.AddOn(addon_id,addon_name,price,ingredient_id,extra_amount,status) VALUES(@addon,@addon,1,@ingredient,2,N''可用'');
    UPDATE teabar_auth.PrincipalBinding SET member_id=@member WHERE principal_name=N''demo_member_a'';
    UPDATE teabar_auth.PrincipalBinding SET member_id=@member2 WHERE principal_name=N''demo_member_b'';

    -- The fixture applies grants inside this transaction only. Existing accounts are restored on rollback.
    DECLARE @seq INT=1,@username SYSNAME,@approle VARCHAR(10),@dbrole SYSNAME,@sid VARBINARY(85),@command NVARCHAR(MAX);
    WHILE @seq<=6
    BEGIN
        SELECT @username=user_name,@approle=app_role,@dbrole=role_name FROM @web_users WHERE seq=@seq;
        IF DATABASE_PRINCIPAL_ID(@username) IS NULL
        BEGIN
            SET @command=N''CREATE USER ''+QUOTENAME(@username)+N'' WITHOUT LOGIN;''; EXEC sys.sp_executesql @command;
        END;
        IF NOT EXISTS(SELECT 1 FROM sys.database_principals WHERE name COLLATE DATABASE_DEFAULT=@username AND type=''S'' AND authentication_type=0)
            THROW 52902,N''Web测试用户名被非预期主体占用。'',1;
        IF EXISTS(SELECT 1 FROM sys.database_role_members WHERE member_principal_id=DATABASE_PRINCIPAL_ID(@username)
             AND role_principal_id<>DATABASE_PRINCIPAL_ID(@dbrole))
            THROW 52902,N''Web用户已有额外角色，拒绝掩盖其配置。'',1;
        IF NOT EXISTS(SELECT 1 FROM sys.database_role_members WHERE member_principal_id=DATABASE_PRINCIPAL_ID(@username)
             AND role_principal_id=DATABASE_PRINCIPAL_ID(@dbrole))
        BEGIN
            SET @command=N''ALTER ROLE ''+QUOTENAME(@dbrole)+N'' ADD MEMBER ''+QUOTENAME(@username)+N'';''; EXEC sys.sp_executesql @command;
        END;
        SELECT @sid=sid FROM sys.database_principals WHERE name COLLATE DATABASE_DEFAULT=@username;
        IF @approle IN(''customer'',''member'')
        BEGIN
            IF NOT EXISTS(SELECT 1 FROM teabar_auth.PrincipalBinding WHERE principal_sid=@sid)
                INSERT teabar_auth.PrincipalBinding(principal_sid,principal_name,member_id,guest_id)
                    VALUES(@sid,@username,CASE WHEN @approle=''member'' THEN CASE WHEN @seq=3 THEN @member ELSE @member2 END END,
                           CASE WHEN @approle=''customer'' THEN NEWID() END);
            UPDATE teabar_auth.PrincipalBinding SET principal_name=@username,is_active=1,
                member_id=CASE WHEN @approle=''member'' THEN CASE WHEN @seq=3 THEN @member ELSE @member2 END END,
                guest_id=CASE WHEN @approle=''customer'' THEN NEWID() END WHERE principal_sid=@sid;
        END;
        IF NOT EXISTS(SELECT 1 FROM teabar_auth.WebAccount WHERE principal_sid=@sid)
            INSERT teabar_auth.WebAccount(login_name,password_hash,app_role,principal_sid)
                VALUES(LOWER(@prefix)+N''.''+CONVERT(NVARCHAR(2),@seq),N''fixture-placeholder-not-a-usable-password-hash'',@approle,@sid);
        UPDATE teabar_auth.WebAccount SET password_hash=N''fixture-placeholder-not-a-usable-password-hash'',
            app_role=@approle,is_active=1,session_version=1 WHERE principal_sid=@sid;
        SET @seq+=1;
    END;
    SELECT @account_id=a.account_id,@login_name=a.login_name FROM teabar_auth.WebAccount AS a
        JOIN sys.database_principals AS p ON p.sid=a.principal_sid WHERE p.name=N''web_guest_a'';
    SELECT @manager_account=a.account_id FROM teabar_auth.WebAccount AS a
        JOIN sys.database_principals AS p ON p.sid=a.principal_sid WHERE p.name=N''web_manager'';
    SELECT @member_account=a.account_id FROM teabar_auth.WebAccount AS a
        JOIN sys.database_principals AS p ON p.sid=a.principal_sid WHERE p.name=N''web_member_a'';
    IF DATABASE_PRINCIPAL_ID(N''teabar_web_app'') IS NULL CREATE USER teabar_web_app WITHOUT LOGIN;
    IF EXISTS(SELECT 1 FROM sys.database_role_members WHERE member_principal_id=DATABASE_PRINCIPAL_ID(N''teabar_web_app''))
        THROW 52902,N''应用入口不应属于任何数据库业务或固定角色。'',1;
    GRANT EXECUTE ON OBJECT::teabar_auth.usp_GetWebCredential TO teabar_web_app;
    GRANT EXECUTE ON OBJECT::teabar_auth.usp_GetWebContext TO teabar_web_app;
    GRANT SELECT ON OBJECT::teabar_api.vw_Menu TO teabar_web_app;
    GRANT SELECT ON OBJECT::teabar_api.vw_AvailableSpecifications TO teabar_web_app;
    GRANT SELECT ON OBJECT::teabar_api.vw_AvailableAddOns TO teabar_web_app;
    DECLARE grant_metadata CURSOR LOCAL FAST_FORWARD FOR SELECT user_name FROM @web_users;
    OPEN grant_metadata; FETCH NEXT FROM grant_metadata INTO @username;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @command=N''GRANT VIEW DEFINITION ON USER::''+QUOTENAME(@username)+N'' TO teabar_web_app;''
            +N''GRANT IMPERSONATE ON USER::''+QUOTENAME(@username)+N'' TO teabar_web_app;'';
        EXEC sys.sp_executesql @command;
        FETCH NEXT FROM grant_metadata INTO @username;
    END;
    CLOSE grant_metadata; DEALLOCATE grant_metadata;
    DECLARE grant_role_metadata CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT role_name FROM @web_users;
    OPEN grant_role_metadata; FETCH NEXT FROM grant_role_metadata INTO @dbrole;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @command=N''GRANT VIEW DEFINITION ON ROLE::''+QUOTENAME(@dbrole)+N'' TO teabar_web_app;''; EXEC sys.sp_executesql @command;
        FETCH NEXT FROM grant_role_metadata INTO @dbrole;
    END;
    CLOSE grant_role_metadata; DEALLOCATE grant_role_metadata;

    INSERT @cases(case_name,user_name,statement,expected_error,setup,assertion) VALUES
    (N''JSON正常两杯、价格与正消耗'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,@good,@choices,N''''[]'''',1;'',NULL,NULL,
        N''IF NOT EXISTS(SELECT 1 FROM dbo.SalesOrder WHERE order_id=@order AND total_amount=14) OR NOT EXISTS(SELECT 1 FROM dbo.OrderItemIngredient WHERE item_id=@item AND amount=20) OR NOT EXISTS(SELECT 1 FROM dbo.Ingredient WHERE ingredient_id=@ingredient AND stock=80) THROW 52902,N''''金额、消耗或扣库错误。'''',1;''),
    (N''JSON加料参与计价和同原料汇总'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,@good,@choices,@extras,1;'',NULL,NULL,
        N''IF NOT EXISTS(SELECT 1 FROM dbo.SalesOrder WHERE order_id=@order AND total_amount=16) OR NOT EXISTS(SELECT 1 FROM dbo.OrderItemIngredient WHERE item_id=@item AND amount=24) THROW 52902,N''''加料快照或汇总错误。'''',1;''),
    (N''JSON多商品明细完整下单'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,@multi,@twochoices,N''''[]'''',1;'',NULL,NULL,
        N''IF (SELECT COUNT(*) FROM dbo.OrderItem WHERE order_id=@order)<>2 OR NOT EXISTS(SELECT 1 FROM dbo.SalesOrder WHERE order_id=@order AND total_amount=14) THROW 52902,N''''多明细落单错误。'''',1;''),
    (N''D01单条零消耗整单拒绝'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,@singlezero,@zerochoices,N''''[]'''',1;'',52018,NULL,NULL),
    (N''D01同单正常加零消耗仍整单拒绝'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,@mixed,@twochoices,N''''[]'''',1;'',52018,NULL,NULL),
    (N''D01原TVP入口同样检查逐明细'',N''demo_guest_a'',N''DECLARE @l teabar_api.OrderLines,@s teabar_api.OrderSpecs,@a teabar_api.OrderAddOns; INSERT @l VALUES(@item,@product,1),(@item2,@zero,1); INSERT @s VALUES(@item,@spec),(@item2,@spec); EXEC teabar_api.usp_PlacePaidOrder @order,@l,@s,@a,1;'',52018,NULL,NULL),
    (N''库存不足不留下部分写入'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,@good,@choices,N''''[]'''',1;'',52016,N''UPDATE dbo.Ingredient SET stock=1 WHERE ingredient_id=@ingredient;'',NULL),
    (N''付款失败不落单'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,@good,@choices,N''''[]'''',0;'',52001,NULL,NULL),
    (N''拒绝超长订单编号而非截断'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson N''''12345678901'''',@good,@choices,N''''[]'''',1;'',52602,NULL,NULL),
    (N''拒绝尾部空白订单编号'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson N''''O1 '''',@good,@choices,N''''[]'''',1;'',52602,NULL,NULL),
    (N''拒绝NULL JSON'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,NULL,@choices,N''''[]'''',1;'',52600,NULL,NULL),
    (N''拒绝非法JSON'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,N''''['''',@choices,N''''[]'''',1;'',52600,NULL,NULL),
    (N''拒绝对象代替数组'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,N''''{}'''',@choices,N''''[]'''',1;'',52600,NULL,NULL),
    (N''拒绝空明细数组'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,N''''[]'''',N''''[]'''',N''''[]'''',1;'',52600,NULL,NULL),
    (N''拒绝数组中的非对象'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,N''''[1]'''',N''''[]'''',N''''[]'''',1;'',52601,NULL,NULL),
    (N''拒绝缺失字段'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,N''''[{"item_id":"T1"}]'''',N''''[]'''',N''''[]'''',1;'',52601,NULL,NULL),
    (N''拒绝大小写错误字段'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,N''''[{"Item_id":"T1","product_id":"P1","quantity":1}]'''',N''''[]'''',N''''[]'''',1;'',52601,NULL,NULL),
    (N''拒绝字段名尾部空格'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,N''''[{"item_id ":"T1","product_id":"P1","quantity":1}]'''',N''''[]'''',N''''[]'''',1;'',52601,NULL,NULL),
    (N''拒绝重复对象属性'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,N''''[{"item_id":"T1","item_id":"T2","product_id":"P1","quantity":1}]'''',N''''[]'''',N''''[]'''',1;'',52601,NULL,NULL),
    (N''拒绝客户端提交价格或身份'',N''demo_guest_a'',N''DECLARE @j NVARCHAR(MAX)=JSON_MODIFY(@good,''''$[0].unit_price'''',0); EXEC teabar_api.usp_PlacePaidOrderJson @order,@j,@choices,N''''[]'''',1;'',52601,NULL,NULL),
    (N''拒绝数字字符串数量'',N''demo_guest_a'',N''DECLARE @j NVARCHAR(MAX)=JSON_MODIFY(@good,''''$[0].quantity'''',N''''2''''); EXEC teabar_api.usp_PlacePaidOrderJson @order,@j,@choices,N''''[]'''',1;'',52602,NULL,NULL),
    (N''拒绝小数数量'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,N''''[{"item_id":"T1","product_id":"P1","quantity":1.5}]'''',N''''[]'''',N''''[]'''',1;'',52602,NULL,NULL),
    (N''拒绝科学记数法数量'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,N''''[{"item_id":"T1","product_id":"P1","quantity":1e1}]'''',N''''[]'''',N''''[]'''',1;'',52602,NULL,NULL),
    (N''拒绝超INT数量'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,N''''[{"item_id":"T1","product_id":"P1","quantity":2147483648}]'''',N''''[]'''',N''''[]'''',1;'',52602,NULL,NULL),
    (N''拒绝零数量'',N''demo_guest_a'',N''DECLARE @j NVARCHAR(MAX)=JSON_MODIFY(@good,''''$[0].quantity'''',0); EXEC teabar_api.usp_PlacePaidOrderJson @order,@j,@choices,N''''[]'''',1;'',52602,NULL,NULL),
    (N''拒绝NULL数量'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,N''''[{"item_id":"T1","product_id":"P1","quantity":null}]'''',N''''[]'''',N''''[]'''',1;'',52602,NULL,NULL),
    (N''拒绝布尔数量'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,N''''[{"item_id":"T1","product_id":"P1","quantity":true}]'''',N''''[]'''',N''''[]'''',1;'',52602,NULL,NULL),
    (N''拒绝超长商品编号'',N''demo_guest_a'',N''DECLARE @j NVARCHAR(MAX)=JSON_MODIFY(@good,''''$[0].product_id'''',N''''12345678901''''); EXEC teabar_api.usp_PlacePaidOrderJson @order,@j,@choices,N''''[]'''',1;'',52602,NULL,NULL),
    (N''拒绝SQL注入式编号且无副作用'',N''demo_guest_a'',N''DECLARE @j NVARCHAR(MAX)=JSON_MODIFY(@good,''''$[0].product_id'''',N''''x'''''''' OR 1=1''''); EXEC teabar_api.usp_PlacePaidOrderJson @order,@j,@choices,N''''[]'''',1;'',52602,NULL,NULL),
    (N''拒绝重复明细'',N''demo_guest_a'',N''DECLARE @j NVARCHAR(MAX)=N''''[''''+SUBSTRING(@good,2,LEN(@good)-2)+N'''',''''+SUBSTRING(@good,2,LEN(@good)-2)+N'''']''''; EXEC teabar_api.usp_PlacePaidOrderJson @order,@j,@choices,N''''[]'''',1;'',52603,NULL,NULL),
    (N''拒绝重复规格选择'',N''demo_guest_a'',N''DECLARE @j NVARCHAR(MAX)=N''''[''''+SUBSTRING(@choices,2,LEN(@choices)-2)+N'''',''''+SUBSTRING(@choices,2,LEN(@choices)-2)+N'''']''''; EXEC teabar_api.usp_PlacePaidOrderJson @order,@good,@j,N''''[]'''',1;'',52603,NULL,NULL),
    (N''拒绝跨明细引用'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,@good,@zerochoices,N''''[]'''',1;'',52604,NULL,NULL),
    (N''漏选规格交由核心拒绝'',N''demo_guest_a'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,@good,N''''[]'''',N''''[]'''',1;'',52009,NULL,NULL),
    (N''店员不能调用顾客JSON入口'',N''demo_clerk'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,@good,@choices,N''''[]'''',1;'',229,NULL,NULL),
    (N''应用入口不能直接调用下单'',N''teabar_web_app'',N''EXEC teabar_api.usp_PlacePaidOrderJson @order,@good,@choices,N''''[]'''',1;'',229,NULL,NULL),
    (N''应用入口可读公开菜单'',N''teabar_web_app'',N''IF NOT EXISTS(SELECT 1 FROM teabar_api.vw_Menu WHERE product_id=@product) THROW 52902,N''''入口公开菜单不可用。'''',1;'',NULL,NULL,NULL),
    (N''应用入口不能直接读账号哈希表'',N''teabar_web_app'',N''SELECT account_id FROM teabar_auth.WebAccount;'',229,NULL,NULL),
    (N''业务用户不能读WebAccount'',N''web_manager'',N''SELECT account_id FROM teabar_auth.WebAccount;'',229,NULL,NULL),
    (N''业务用户不能调用认证查询'',N''web_guest_a'',N''EXEC teabar_auth.usp_GetWebCredential @login_name;'',229,NULL,NULL),
    (N''凭据查询仅返回受控单账号'',N''teabar_web_app'',N''DECLARE @r TABLE(account_id INT,password_hash NVARCHAR(512),session_version INT); INSERT @r EXEC teabar_auth.usp_GetWebCredential @login_name; IF (SELECT COUNT(*) FROM @r)<>1 OR NOT EXISTS(SELECT 1 FROM @r WHERE account_id=@account_id AND session_version=1) THROW 52902,N''''凭据查询错误。'''',1;'',NULL,NULL,NULL),
    (N''拒绝截断后匹配超长登录名'',N''teabar_web_app'',N''DECLARE @r TABLE(account_id INT,password_hash NVARCHAR(512),session_version INT); DECLARE @n NVARCHAR(MAX)=@login_name+REPLICATE(N''''x'''',100); INSERT @r EXEC teabar_auth.usp_GetWebCredential @n; IF EXISTS(SELECT 1 FROM @r) THROW 52902,N''''超长登录名被截断接受。'''',1;'',NULL,NULL,NULL),
    (N''受限入口可获取活动购买者上下文'',N''teabar_web_app'',N''DECLARE @r TABLE(account_id INT,app_role VARCHAR(10),principal_sid VARBINARY(85),principal_name SYSNAME,session_version INT); INSERT @r EXEC teabar_auth.usp_GetWebContext @account_id,1; IF NOT EXISTS(SELECT 1 FROM @r WHERE principal_name=N''''web_guest_a'''' AND app_role=''''customer'''') THROW 52902,N''''上下文错误。'''',1;'',NULL,NULL,NULL),
    (N''工作账号无需购买绑定也可获取上下文'',N''teabar_web_app'',N''DECLARE @r TABLE(account_id INT,app_role VARCHAR(10),principal_sid VARBINARY(85),principal_name SYSNAME,session_version INT); INSERT @r EXEC teabar_auth.usp_GetWebContext @manager_account,1; IF NOT EXISTS(SELECT 1 FROM @r WHERE principal_name=N''''web_manager'''' AND app_role=''''manager'''') THROW 52902,N''''工作上下文错误。'''',1;'',NULL,NULL,NULL),
    (N''旧会话版本被拒绝'',N''teabar_web_app'',N''EXEC teabar_auth.usp_GetWebContext @account_id,1;'',52700,N''UPDATE teabar_auth.WebAccount SET session_version=2 WHERE account_id=@account_id;'',NULL),
    (N''账号停用后上下文被拒绝'',N''teabar_web_app'',N''EXEC teabar_auth.usp_GetWebContext @account_id,1;'',52700,N''UPDATE teabar_auth.WebAccount SET is_active=0 WHERE account_id=@account_id;'',NULL),
    (N''账号角色与数据库用户不符被拒绝'',N''teabar_web_app'',N''EXEC teabar_auth.usp_GetWebContext @account_id,1;'',52700,N''UPDATE teabar_auth.WebAccount SET app_role=''''manager'''' WHERE account_id=@account_id;'',NULL),
    (N''购买绑定停用被拒绝'',N''teabar_web_app'',N''EXEC teabar_auth.usp_GetWebContext @account_id,1;'',52700,N''UPDATE teabar_auth.PrincipalBinding SET is_active=0 WHERE principal_name=N''''web_guest_a'''';'',NULL),
    (N''额外数据库角色被拒绝'',N''teabar_web_app'',N''EXEC teabar_auth.usp_GetWebContext @account_id,1;'',52700,N''ALTER ROLE teabar_manager ADD MEMBER web_guest_a;'',NULL),
    (N''用户直接表授权被拒绝'',N''teabar_web_app'',N''EXEC teabar_auth.usp_GetWebContext @account_id,1;'',52700,N''GRANT SELECT ON OBJECT::dbo.Member TO web_guest_a;'',NULL),
    (N''用户拥有架构被拒绝'',N''teabar_web_app'',N''EXEC teabar_auth.usp_GetWebContext @account_id,1;'',52700,N''EXEC(N''''CREATE SCHEMA v1_regression_owned AUTHORIZATION web_guest_a;'''');'',NULL),
    (N''活动会员上下文可用'',N''teabar_web_app'',N''DECLARE @id INT=(SELECT @member_account); DECLARE @r TABLE(account_id INT,app_role VARCHAR(10),principal_sid VARBINARY(85),principal_name SYSNAME,session_version INT); INSERT @r EXEC teabar_auth.usp_GetWebContext @id,1; IF NOT EXISTS(SELECT 1 FROM @r WHERE principal_name=N''''web_member_a'''' AND app_role=''''member'''') THROW 52902,N''''会员上下文错误。'''',1;'',NULL,NULL,NULL),
    (N''入口可按允许名单切换顾客执行下单'',N''teabar_web_app'',N''BEGIN TRY EXECUTE AS USER=N''''web_guest_a''''; EXEC teabar_api.usp_PlacePaidOrderJson @order,@good,@choices,N''''[]'''',1; REVERT; END TRY BEGIN CATCH IF USER_NAME()=N''''web_guest_a'''' REVERT; THROW; END CATCH;'',NULL,NULL,
        N''IF NOT EXISTS(SELECT 1 FROM dbo.SalesOrder AS o JOIN teabar_auth.PrincipalBinding AS b ON b.guest_id=o.guest_id WHERE o.order_id=@order AND b.principal_name=N''''web_guest_a'''' AND o.total_amount=14) THROW 52902,N''''切换身份后的购买归属错误。'''',1;''),
    (N''入口不能切换demo回归用户'',N''teabar_web_app'',N''EXECUTE AS USER=N''''demo_guest_a''''; REVERT;'',15517,NULL,NULL);

    -- Permission denial number for EXECUTE AS can be 15517 or 15151 by engine/version.
    -- The dedicated case accepts only either denial, never an arbitrary error or successful switch.
    DECLARE @params NVARCHAR(MAX)=N''@good NVARCHAR(MAX),@choices NVARCHAR(MAX),@extras NVARCHAR(MAX),@multi NVARCHAR(MAX),
      @mixed NVARCHAR(MAX),@twochoices NVARCHAR(MAX),@singlezero NVARCHAR(MAX),@zerochoices NVARCHAR(MAX),
      @order VARCHAR(10),@item VARCHAR(10),@item2 VARCHAR(10),@product VARCHAR(10),@zero VARCHAR(10),@spec VARCHAR(10),
      @ingredient VARCHAR(10),@addon VARCHAR(10),@member VARCHAR(10),@member2 VARCHAR(10),@account_id INT,@manager_account INT,@login_name NVARCHAR(50),@member_account INT'';
    DECLARE @label NVARCHAR(150),@user SYSNAME,@statement NVARCHAR(MAX),@expected INT,@actual INT,@setup NVARCHAR(MAX),@assertion NVARCHAR(MAX),@message NVARCHAR(4000),@before VARBINARY(32),@after VARBINARY(32),@passed BIT;
    DECLARE @fingerprint NVARCHAR(MAX)=N''SELECT @h=HASHBYTES(''''SHA2_256'''',
        (SELECT * FROM dbo.SalesOrder ORDER BY order_id FOR XML RAW,BINARY BASE64)
       +(SELECT * FROM dbo.OrderItem ORDER BY item_id FOR XML RAW,BINARY BASE64)
       +(SELECT * FROM dbo.ItemSpec ORDER BY item_id,spec_type FOR XML RAW,BINARY BASE64)
       +(SELECT * FROM dbo.ItemAddOn ORDER BY item_id,addon_id FOR XML RAW,BINARY BASE64)
       +(SELECT * FROM dbo.OrderItemIngredient ORDER BY item_id,ingredient_id FOR XML RAW,BINARY BASE64)
       +(SELECT * FROM dbo.Ingredient ORDER BY ingredient_id FOR XML RAW,BINARY BASE64)
       +(SELECT * FROM dbo.Member ORDER BY member_id FOR XML RAW,BINARY BASE64)
       +(SELECT * FROM teabar_auth.WebAccount ORDER BY account_id FOR XML RAW,BINARY BASE64)
       +(SELECT * FROM teabar_auth.PrincipalBinding ORDER BY principal_sid FOR XML RAW,BINARY BASE64));'';
    SET @seq=1;
    WHILE @seq<=(SELECT COUNT(*) FROM @cases)
    BEGIN
        SELECT @label=case_name,@user=user_name,@statement=statement,@expected=expected_error,@setup=setup,@assertion=assertion FROM @cases WHERE seq=@seq;
        -- SQL Server dooms an explicit transaction on denied EXECUTE AS, even with XACT_ABORT OFF.
        -- Run this one denial after the fixture rollback, with no explicit transaction.
        IF @expected=15517 BEGIN SET @seq+=1; CONTINUE; END;
        PRINT N''v1.0 case ''+CONVERT(NVARCHAR(10),@seq)+N'': ''+@label;
        SAVE TRANSACTION new_test_case;
        IF @setup IS NOT NULL EXEC sys.sp_executesql @setup,@params,@good,@choices,@extras,@multi,@mixed,@twochoices,@singlezero,@zerochoices,
            @order,@item,@item2,@product,@zero,@spec,@ingredient,@addon,@member,@member2,@account_id,@manager_account,@login_name,@member_account;
        EXEC sys.sp_executesql @fingerprint,N''@h VARBINARY(32) OUTPUT'',@h=@before OUTPUT;
        SET @actual=NULL; SET @message=NULL;
        BEGIN TRY
            IF @user IS NOT NULL BEGIN EXECUTE AS USER=@user; SET @impersonating=1; END;
            EXEC sys.sp_executesql @statement,@params,@good,@choices,@extras,@multi,@mixed,@twochoices,@singlezero,@zerochoices,
                @order,@item,@item2,@product,@zero,@spec,@ingredient,@addon,@member,@member2,@account_id,@manager_account,@login_name,@member_account;
            IF @impersonating=1 BEGIN REVERT; SET @impersonating=0; END;
            IF @assertion IS NOT NULL EXEC sys.sp_executesql @assertion,@params,@good,@choices,@extras,@multi,@mixed,@twochoices,@singlezero,@zerochoices,
                @order,@item,@item2,@product,@zero,@spec,@ingredient,@addon,@member,@member2,@account_id,@manager_account,@login_name,@member_account;
        END TRY
        BEGIN CATCH
            SET @actual=ERROR_NUMBER(); SET @message=ERROR_MESSAGE();
            IF @impersonating=1 BEGIN REVERT; SET @impersonating=0; END;
            IF XACT_STATE()<>1 THROW;
        END CATCH;
        EXEC sys.sp_executesql @fingerprint,N''@h VARBINARY(32) OUTPUT'',@h=@after OUTPUT;
        SET @passed=CASE WHEN @expected IS NULL AND @actual IS NULL THEN 1
            WHEN @expected IS NOT NULL AND @before=@after AND (@actual=@expected OR (@expected=15517 AND @actual=15151)) THEN 1 ELSE 0 END;
        ROLLBACK TRANSACTION new_test_case;
        INSERT @results VALUES(@label,@expected,@actual,@passed,COALESCE(@message,N''执行及断言通过；反例要求数据哈希不变。''));
        SET @seq+=1;
    END;
    ROLLBACK TRANSACTION;
    IF USER_NAME()<>@administrator OR @@TRANCOUNT<>0 THROW 52902,N''测试未恢复管理员上下文或未释放事务。'',1;
    IF (SELECT COUNT(*) FROM @cases WHERE expected_error=15517)<>1
        THROW 52902,N''独立身份切换拒绝用例数量错误。'',1;
    SELECT @label=case_name,@statement=statement,@expected=expected_error FROM @cases WHERE expected_error=15517;
    PRINT N''v1.0 isolated case: ''+@label;
    IF DATABASE_PRINCIPAL_ID(N''teabar_web_app'') IS NULL
    BEGIN
        CREATE USER teabar_web_app WITHOUT LOGIN;
        SET @created_entry=1;
    END;
    SET @actual=NULL; SET @message=NULL;
    BEGIN TRY
        EXECUTE AS USER=N''teabar_web_app''; SET @impersonating=1;
        EXEC sys.sp_executesql @statement;
        REVERT; SET @impersonating=0;
    END TRY
    BEGIN CATCH
        SET @actual=ERROR_NUMBER(); SET @message=ERROR_MESSAGE();
        IF @impersonating=1 BEGIN REVERT; SET @impersonating=0; END;
    END CATCH;
    IF @created_entry=1 BEGIN DROP USER teabar_web_app; SET @created_entry=0; END;
    INSERT @results VALUES(@label,@expected,@actual,
        CASE WHEN @actual IN(15517,15151) AND USER_NAME()=@administrator AND @@TRANCOUNT=0 THEN 1 ELSE 0 END,
        COALESCE(@message,N''未得到预期拒绝。''));
    IF (SELECT COUNT(*) FROM @results)<>53 THROW 52902,N''新增用例数量不是53。'',1;
    INSERT #RegressionResults(suite,case_name,expected_error,actual_error,passed,detail)
        SELECT N''v1.0-new'',case_name,expected_error,actual_error,passed,detail FROM @results;
    SELECT case_name,expected_error,actual_error,passed,detail FROM @results;
END TRY
BEGIN CATCH
    IF @impersonating=1 REVERT;
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    IF @created_entry=1 AND USER_NAME()=@administrator DROP USER teabar_web_app;
    SELECT N''V1_TEST_ABORTED'' AS stage,@seq AS case_number,@label AS case_name,
        ERROR_NUMBER() AS error_number,ERROR_LINE() AS error_line,ERROR_PROCEDURE() AS error_procedure,ERROR_MESSAGE() AS detail;
    THROW;
END CATCH;
');

    DECLARE final_tables CURSOR LOCAL FAST_FORWARD FOR SELECT name,schema_name,order_columns FROM @tables ORDER BY name;
    OPEN final_tables; FETCH NEXT FROM final_tables INTO @table,@schema,@ordering;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @sql=N'SELECT @n=COUNT_BIG(*) FROM '+QUOTENAME(@schema)+N'.'+QUOTENAME(@table)+N';'
          +N'SELECT @h=HASHBYTES(''SHA2_256'',(SELECT * FROM '+QUOTENAME(@schema)+N'.'+QUOTENAME(@table)
          +N' ORDER BY '+@ordering+N' FOR XML RAW,BINARY BASE64));';
        EXEC sys.sp_executesql @sql,N'@n BIGINT OUTPUT,@h VARBINARY(32) OUTPUT',@n=@rows OUTPUT,@h=@hash OUTPUT;
        INSERT @snapshot_after VALUES(@table,@rows,@hash);
        FETCH NEXT FROM final_tables INTO @table,@schema,@ordering;
    END;
    CLOSE final_tables; DEALLOCATE final_tables;
    EXEC sys.sp_executesql @security_fingerprint,N'@h VARBINARY(32) OUTPUT',@h=@security_after OUTPUT;
    IF EXISTS(SELECT * FROM @snapshot_before EXCEPT SELECT * FROM @snapshot_after)
       OR EXISTS(SELECT * FROM @snapshot_after EXCEPT SELECT * FROM @snapshot_before)
       OR @security_before<>@security_after
       OR @@TRANCOUNT<>0
        THROW 52901,N'回归后数据、用户、角色、授权或架构未完整恢复，或事务未释放。',1;
    INSERT #RegressionResults VALUES(N'cleanup',N'17表数据及用户、角色、授权恢复',NULL,NULL,1,N'测试业务行、Web账号、绑定及安全配置均已回滚；IDENTITY分配可能留下正常编号间隙。');
    SELECT N'SECURITY_BEFORE_AFTER' AS stage,CONVERT(VARCHAR(64),@security_before,2) AS before_hash,
        CONVERT(VARCHAR(64),@security_after,2) AS after_hash;
    SELECT N'BEFORE_AFTER' AS stage,b.name,b.row_count AS before_rows,a.row_count AS after_rows,
        CONVERT(VARCHAR(64),b.data_hash,2) AS before_hash,CONVERT(VARCHAR(64),a.data_hash,2) AS after_hash
    FROM @snapshot_before AS b JOIN @snapshot_after AS a ON a.name=b.name ORDER BY b.name;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    INSERT #RegressionResults VALUES(N'runner',N'回归执行被阻止或用例失败',NULL,ERROR_NUMBER(),0,ERROR_MESSAGE());
    SELECT suite,case_name,expected_error,actual_error,passed,detail FROM #RegressionResults;
    SELECT COUNT(*) AS total,SUM(CASE WHEN passed=1 THEN 1 ELSE 0 END) AS passed,
        SUM(CASE WHEN passed=0 THEN 1 ELSE 0 END) AS failed FROM #RegressionResults;
    DROP TABLE #RegressionResults;
    THROW;
END CATCH;
SELECT suite,COUNT(*) AS total,SUM(CASE WHEN passed=1 THEN 1 ELSE 0 END) AS passed,
    SUM(CASE WHEN passed=0 THEN 1 ELSE 0 END) AS failed FROM #RegressionResults GROUP BY suite;
SELECT suite,case_name,expected_error,actual_error,passed,detail FROM #RegressionResults WHERE passed=0;
IF EXISTS(SELECT 1 FROM #RegressionResults WHERE passed=0)
BEGIN
    DROP TABLE #RegressionResults;
    THROW 52903,N'回归未全部通过。',1;
END;
SELECT N'REGRESSION_PASSED_TEST_DATA_ROLLED_BACK' AS result,COUNT(*) AS passed_cases FROM #RegressionResults;
DROP TABLE #RegressionResults;
