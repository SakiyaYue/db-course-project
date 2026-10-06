-- 第四周：数据库完整性约束及正反例验证（SQL Server）。
-- 执行顺序：db_creation.sql -> seed_data.sql -> constraint.sql。
-- 先装载原有样例再执行本文件；后续非会员 INSERT 必须明确提供 guest_id。
-- 使用管理员的新查询窗口完整执行；不删除数据库，可重复执行。
-- 第一部分提交约束；第二部分仅使用随机编号的测试记录，验证后全部回滚。
--
-- guest_id 表示非会员的一次顾客会话；同一会话的多笔订单可以共用它。
-- member_id、guest_id 必须且只能填写一个，不为 guest_id 设置 UNIQUE 或 DEFAULT。
-- 兼容旧样例：缺少归属的非会员订单逐单分配 NEWID() 占位值；这些值不能还原
-- 原顾客会话，也不能当作已完成身份认证。新订单必须使用受信会话绑定的 ID。
--
-- 本文件负责键、引用、字段域、非空、默认值和游客/会员归属互斥。
-- 以下仍需后续受控业务操作实现，不能仅凭本文件宣称已经生效：
-- 订单/明细总额核对、已开放规格必选且可用、按配方计算和扣减全部原料、
-- 订单状态流转、仅排队中退款且仅返库一次、首次完成时按整单金额向下取整加分、
-- 同员工排班不得重叠、跨表用量的计件整数检查、已使用原料单位不得改变、
-- 订单身份与当前调用者匹配、历史快照不可修改及业务角色不允许删除记录。
-- 约束安装使用 WITH CHECK 核验既有数据，不使用 NOCHECK 绕过非法记录。
-- 语法参考：https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-table-transact-sql
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
    THROW 51300, N'请在 TeabarDB 中执行约束脚本。', 1;
IF @@TRANCOUNT <> 0
    THROW 51301, N'请在没有未结束事务的新查询窗口中执行。', 1;

DECLARE @tables TABLE (table_name SYSNAME PRIMARY KEY);
INSERT INTO @tables (table_name) VALUES
    (N'Employee'), (N'DutyRoster'), (N'Member'), (N'SalesOrder'),
    (N'Product'), (N'Specification'), (N'Ingredient'), (N'OrderItem'),
    (N'ProductSpecification'), (N'Recipe'), (N'AddOn'), (N'ItemSpec'),
    (N'ItemAddOn'), (N'OrderItemIngredient'), (N'SpecificationIngredient');
IF EXISTS (
    SELECT 1 FROM @tables
    WHERE OBJECT_ID(N'dbo.' + table_name, N'U') IS NULL
)
    THROW 51302, N'业务表不完整，请先执行现行建表脚本。', 1;
IF NOT EXISTS (
    SELECT 1 FROM sys.computed_columns
    WHERE object_id = OBJECT_ID(N'dbo.OrderItem') AND name = N'sub_amount'
      AND is_persisted = 1 AND is_nullable = 0
)
    THROW 51303, N'OrderItem.sub_amount 应为持久化非空计算列，请先更新表结构。', 1;

-- ============================================================
-- 一、安装约束：存在则保留，缺失则创建；失败时整个安装事务回滚。
-- ============================================================
DECLARE @guest_backfill_count INT = 0;
BEGIN TRY
    BEGIN TRANSACTION;

    IF COL_LENGTH(N'dbo.SalesOrder', N'guest_id') IS NULL
        EXEC(N'ALTER TABLE dbo.SalesOrder ADD guest_id UNIQUEIDENTIFIER NULL;');
    IF EXISTS (
        SELECT 1 FROM sys.columns
        WHERE object_id = OBJECT_ID(N'dbo.SalesOrder') AND name = N'guest_id'
          AND (TYPE_NAME(user_type_id) <> N'uniqueidentifier' OR is_nullable <> 1)
    )
        THROW 51304, N'SalesOrder.guest_id 应为允许 NULL 的 uniqueidentifier。', 1;

    -- 动态 SQL 让新字段在当前批次中完成添加后再参与编译。
    EXEC sys.sp_executesql
        N'UPDATE dbo.SalesOrder SET guest_id = NEWID()
          WHERE member_id IS NULL AND guest_id IS NULL;
          SET @backfilled = @@ROWCOUNT;',
        N'@backfilled INT OUTPUT', @backfilled = @guest_backfill_count OUTPUT;

    -- 非空字段清单与 db_creation.sql 一致；不改变可空的会员、游客及商品描述字段。
    DECLARE @not_null_columns TABLE (
        seq INT IDENTITY PRIMARY KEY,
        table_name SYSNAME, column_name SYSNAME, type_definition NVARCHAR(50)
    );
    INSERT INTO @not_null_columns (table_name, column_name, type_definition) VALUES
        (N'Employee', N'employee_id', N'VARCHAR(10)'),
        (N'Employee', N'name', N'NVARCHAR(50)'),
        (N'Employee', N'status', N'NVARCHAR(10)'),
        (N'Employee', N'salary', N'DECIMAL(10, 2)'),
        (N'Employee', N'role', N'NVARCHAR(20)'),
        (N'DutyRoster', N'duty_id', N'VARCHAR(10)'),
        (N'DutyRoster', N'employee_id', N'VARCHAR(10)'),
        (N'DutyRoster', N'start_time', N'DATETIME2(0)'),
        (N'DutyRoster', N'end_time', N'DATETIME2(0)'),
        (N'Member', N'member_id', N'VARCHAR(10)'),
        (N'Member', N'name', N'NVARCHAR(50)'),
        (N'Member', N'phone', N'VARCHAR(20)'),
        (N'Member', N'points', N'INT'),
        (N'SalesOrder', N'order_id', N'VARCHAR(10)'),
        (N'SalesOrder', N'order_time', N'DATETIME2(0)'),
        (N'SalesOrder', N'total_amount', N'DECIMAL(10, 2)'),
        (N'SalesOrder', N'status', N'NVARCHAR(20)'),
        (N'Product', N'product_id', N'VARCHAR(10)'),
        (N'Product', N'product_name', N'NVARCHAR(50)'),
        (N'Product', N'base_price', N'DECIMAL(10, 2)'),
        (N'Product', N'status', N'NVARCHAR(10)'),
        (N'Specification', N'spec_id', N'VARCHAR(10)'),
        (N'Specification', N'spec_type', N'NVARCHAR(20)'),
        (N'Specification', N'spec_name', N'NVARCHAR(20)'),
        (N'Ingredient', N'ingredient_id', N'VARCHAR(10)'),
        (N'Ingredient', N'ingredient_name', N'NVARCHAR(50)'),
        (N'Ingredient', N'unit', N'NVARCHAR(10)'),
        (N'Ingredient', N'stock', N'DECIMAL(10, 2)'),
        (N'Ingredient', N'status', N'NVARCHAR(10)'),
        (N'OrderItem', N'item_id', N'VARCHAR(10)'),
        (N'OrderItem', N'order_id', N'VARCHAR(10)'),
        (N'OrderItem', N'product_id', N'VARCHAR(10)'),
        (N'OrderItem', N'product_name_snapshot', N'NVARCHAR(50)'),
        (N'OrderItem', N'quantity', N'INT'),
        (N'OrderItem', N'base_price_snapshot', N'DECIMAL(10, 2)'),
        (N'OrderItem', N'unit_price', N'DECIMAL(10, 2)'),
        (N'ProductSpecification', N'product_id', N'VARCHAR(10)'),
        (N'ProductSpecification', N'spec_id', N'VARCHAR(10)'),
        (N'ProductSpecification', N'price_delta', N'DECIMAL(10, 2)'),
        (N'ProductSpecification', N'status', N'NVARCHAR(10)'),
        (N'Recipe', N'product_id', N'VARCHAR(10)'),
        (N'Recipe', N'ingredient_id', N'VARCHAR(10)'),
        (N'Recipe', N'base_amount', N'DECIMAL(10, 2)'),
        (N'AddOn', N'addon_id', N'VARCHAR(10)'),
        (N'AddOn', N'addon_name', N'NVARCHAR(50)'),
        (N'AddOn', N'price', N'DECIMAL(10, 2)'),
        (N'AddOn', N'ingredient_id', N'VARCHAR(10)'),
        (N'AddOn', N'extra_amount', N'DECIMAL(10, 2)'),
        (N'AddOn', N'status', N'NVARCHAR(10)'),
        (N'ItemSpec', N'item_id', N'VARCHAR(10)'),
        (N'ItemSpec', N'spec_type', N'NVARCHAR(20)'),
        (N'ItemSpec', N'spec_id', N'VARCHAR(10)'),
        (N'ItemSpec', N'spec_name_snapshot', N'NVARCHAR(20)'),
        (N'ItemSpec', N'price_delta_snapshot', N'DECIMAL(10, 2)'),
        (N'ItemAddOn', N'item_id', N'VARCHAR(10)'),
        (N'ItemAddOn', N'addon_id', N'VARCHAR(10)'),
        (N'ItemAddOn', N'addon_name_snapshot', N'NVARCHAR(50)'),
        (N'ItemAddOn', N'price_snapshot', N'DECIMAL(10, 2)'),
        (N'OrderItemIngredient', N'item_id', N'VARCHAR(10)'),
        (N'OrderItemIngredient', N'ingredient_id', N'VARCHAR(10)'),
        (N'OrderItemIngredient', N'amount', N'DECIMAL(10, 2)'),
        (N'SpecificationIngredient', N'product_id', N'VARCHAR(10)'),
        (N'SpecificationIngredient', N'spec_id', N'VARCHAR(10)'),
        (N'SpecificationIngredient', N'ingredient_id', N'VARCHAR(10)'),
        (N'SpecificationIngredient', N'factor', N'DECIMAL(5, 2)');

    DECLARE @column_seq INT = 1, @column_count INT = (SELECT COUNT(*) FROM @not_null_columns);
    DECLARE @column_table SYSNAME, @column_name SYSNAME, @column_type NVARCHAR(50);
    DECLARE @ddl NVARCHAR(MAX);
    WHILE @column_seq <= @column_count
    BEGIN
        SELECT @column_table = table_name, @column_name = column_name, @column_type = type_definition
        FROM @not_null_columns WHERE seq = @column_seq;
        IF NOT EXISTS (
            SELECT 1 FROM sys.columns
            WHERE object_id = OBJECT_ID(N'dbo.' + @column_table) AND name = @column_name
        )
            THROW 51305, N'业务表缺少现行建表脚本的必填字段，请先更新表结构。', 1;
        IF EXISTS (
            SELECT 1 FROM sys.columns
            WHERE object_id = OBJECT_ID(N'dbo.' + @column_table)
              AND name = @column_name AND is_nullable = 1
        )
        BEGIN
            SET @ddl = N'ALTER TABLE dbo.' + QUOTENAME(@column_table)
                + N' ALTER COLUMN ' + QUOTENAME(@column_name) + N' ' + @column_type + N' NOT NULL;';
            EXEC sys.sp_executesql @ddl;
        END;
        SET @column_seq += 1;
    END;

    -- 1. 主键、候选码、外键、CHECK：按表分组，保留建表脚本已有约束。
    -- PK/UQ 不重复创建；FK/CHECK 的既有数据在下方统一重新核验并启用。
    -- Employee
    IF OBJECT_ID(N'dbo.PK_Employee', N'PK') IS NULL
        EXEC(N'ALTER TABLE dbo.Employee ADD CONSTRAINT PK_Employee PRIMARY KEY (employee_id);');
    IF OBJECT_ID(N'dbo.CK_Employee_Id_NotBlank', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.Employee WITH CHECK ADD CONSTRAINT CK_Employee_Id_NotBlank CHECK (LEN(LTRIM(RTRIM(employee_id))) > 0);');
    IF OBJECT_ID(N'dbo.CK_Employee_Name_NotBlank', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.Employee WITH CHECK ADD CONSTRAINT CK_Employee_Name_NotBlank CHECK (LEN(LTRIM(RTRIM(name))) > 0);');
    IF OBJECT_ID(N'dbo.CK_Employee_Status', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.Employee WITH CHECK ADD CONSTRAINT CK_Employee_Status CHECK (status IN (N''在职'', N''离职''));');
    IF OBJECT_ID(N'dbo.CK_Employee_Salary', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.Employee WITH CHECK ADD CONSTRAINT CK_Employee_Salary CHECK (salary >= 0);');
    IF OBJECT_ID(N'dbo.CK_Employee_Role', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.Employee WITH CHECK ADD CONSTRAINT CK_Employee_Role CHECK (role IN (N''店员'', N''店长''));');

    -- DutyRoster
    IF OBJECT_ID(N'dbo.PK_DutyRoster', N'PK') IS NULL
        EXEC(N'ALTER TABLE dbo.DutyRoster ADD CONSTRAINT PK_DutyRoster PRIMARY KEY (duty_id);');
    IF OBJECT_ID(N'dbo.FK_DutyRoster_Employee', N'F') IS NULL
        EXEC(N'ALTER TABLE dbo.DutyRoster WITH CHECK ADD CONSTRAINT FK_DutyRoster_Employee FOREIGN KEY (employee_id) REFERENCES dbo.Employee(employee_id);');
    IF OBJECT_ID(N'dbo.UQ_DutyRoster_Employee_StartTime', N'UQ') IS NULL
        EXEC(N'ALTER TABLE dbo.DutyRoster ADD CONSTRAINT UQ_DutyRoster_Employee_StartTime UNIQUE (employee_id, start_time);');
    IF OBJECT_ID(N'dbo.CK_DutyRoster_Time', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.DutyRoster WITH CHECK ADD CONSTRAINT CK_DutyRoster_Time CHECK (start_time < end_time);');

    -- Member
    IF OBJECT_ID(N'dbo.PK_Member', N'PK') IS NULL
        EXEC(N'ALTER TABLE dbo.Member ADD CONSTRAINT PK_Member PRIMARY KEY (member_id);');
    IF OBJECT_ID(N'dbo.CK_Member_Id_NotBlank', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.Member WITH CHECK ADD CONSTRAINT CK_Member_Id_NotBlank CHECK (LEN(LTRIM(RTRIM(member_id))) > 0);');
    IF OBJECT_ID(N'dbo.CK_Member_Name_NotBlank', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.Member WITH CHECK ADD CONSTRAINT CK_Member_Name_NotBlank CHECK (LEN(LTRIM(RTRIM(name))) > 0);');
    IF OBJECT_ID(N'dbo.UK_Member_Phone', N'UQ') IS NULL
        EXEC(N'ALTER TABLE dbo.Member ADD CONSTRAINT UK_Member_Phone UNIQUE (phone);');
    IF OBJECT_ID(N'dbo.CK_Member_Phone_Format', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.Member WITH CHECK ADD CONSTRAINT CK_Member_Phone_Format CHECK (DATALENGTH(phone) = 11 AND phone LIKE ''1%'' AND phone COLLATE Latin1_General_100_BIN2 NOT LIKE ''%[^0-9]%'');');
    IF OBJECT_ID(N'dbo.CK_Member_Points', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.Member WITH CHECK ADD CONSTRAINT CK_Member_Points CHECK (points >= 0);');

    -- SalesOrder
    IF OBJECT_ID(N'dbo.PK_SalesOrder', N'PK') IS NULL
        EXEC(N'ALTER TABLE dbo.SalesOrder ADD CONSTRAINT PK_SalesOrder PRIMARY KEY (order_id);');
    IF OBJECT_ID(N'dbo.CK_SalesOrder_Id_NotBlank', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.SalesOrder WITH CHECK ADD CONSTRAINT CK_SalesOrder_Id_NotBlank CHECK (LEN(LTRIM(RTRIM(order_id))) > 0);');
    IF OBJECT_ID(N'dbo.FK_SalesOrder_Member', N'F') IS NULL
        EXEC(N'ALTER TABLE dbo.SalesOrder WITH CHECK ADD CONSTRAINT FK_SalesOrder_Member FOREIGN KEY (member_id) REFERENCES dbo.Member(member_id);');
    IF OBJECT_ID(N'dbo.CK_SalesOrder_Amount', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.SalesOrder WITH CHECK ADD CONSTRAINT CK_SalesOrder_Amount CHECK (total_amount >= 0);');
    IF OBJECT_ID(N'dbo.CK_SalesOrder_status', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.SalesOrder WITH CHECK ADD CONSTRAINT CK_SalesOrder_status CHECK (status IN (N''排队中'', N''制作中'', N''待取餐'', N''已完成'', N''已取消''));');

    -- Product
    IF OBJECT_ID(N'dbo.PK_Product', N'PK') IS NULL
        EXEC(N'ALTER TABLE dbo.Product ADD CONSTRAINT PK_Product PRIMARY KEY (product_id);');
    IF OBJECT_ID(N'dbo.CK_Product_Id_NotBlank', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.Product WITH CHECK ADD CONSTRAINT CK_Product_Id_NotBlank CHECK (LEN(LTRIM(RTRIM(product_id))) > 0);');
    IF OBJECT_ID(N'dbo.CK_Product_Name_NotBlank', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.Product WITH CHECK ADD CONSTRAINT CK_Product_Name_NotBlank CHECK (LEN(LTRIM(RTRIM(product_name))) > 0);');
    IF OBJECT_ID(N'dbo.CK_Product_Price', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.Product WITH CHECK ADD CONSTRAINT CK_Product_Price CHECK (base_price >= 0);');
    IF OBJECT_ID(N'dbo.CK_Product_Status', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.Product WITH CHECK ADD CONSTRAINT CK_Product_Status CHECK (status IN (N''在售'', N''下架''));');

    -- Specification
    IF OBJECT_ID(N'dbo.PK_Specification', N'PK') IS NULL
        EXEC(N'ALTER TABLE dbo.Specification ADD CONSTRAINT PK_Specification PRIMARY KEY (spec_id);');
    IF OBJECT_ID(N'dbo.CK_Specification_Id_NotBlank', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.Specification WITH CHECK ADD CONSTRAINT CK_Specification_Id_NotBlank CHECK (LEN(LTRIM(RTRIM(spec_id))) > 0);');
    IF OBJECT_ID(N'dbo.CK_Specification_Name_NotBlank', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.Specification WITH CHECK ADD CONSTRAINT CK_Specification_Name_NotBlank CHECK (LEN(LTRIM(RTRIM(spec_name))) > 0);');
    IF OBJECT_ID(N'dbo.UK_Specification_typename', N'UQ') IS NULL
        EXEC(N'ALTER TABLE dbo.Specification ADD CONSTRAINT UK_Specification_typename UNIQUE (spec_type, spec_name);');
    IF OBJECT_ID(N'dbo.UK_Specification_idtype', N'UQ') IS NULL
        EXEC(N'ALTER TABLE dbo.Specification ADD CONSTRAINT UK_Specification_idtype UNIQUE (spec_id, spec_type);');
    IF OBJECT_ID(N'dbo.CK_Specification_Type', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.Specification WITH CHECK ADD CONSTRAINT CK_Specification_Type CHECK (spec_type IN (N''糖度'', N''温度'', N''杯型''));');

    -- Ingredient
    IF OBJECT_ID(N'dbo.PK_Ingredient', N'PK') IS NULL
        EXEC(N'ALTER TABLE dbo.Ingredient ADD CONSTRAINT PK_Ingredient PRIMARY KEY (ingredient_id);');
    IF OBJECT_ID(N'dbo.CK_Ingredient_Id_NotBlank', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.Ingredient WITH CHECK ADD CONSTRAINT CK_Ingredient_Id_NotBlank CHECK (LEN(LTRIM(RTRIM(ingredient_id))) > 0);');
    IF OBJECT_ID(N'dbo.CK_Ingredient_Name_NotBlank', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.Ingredient WITH CHECK ADD CONSTRAINT CK_Ingredient_Name_NotBlank CHECK (LEN(LTRIM(RTRIM(ingredient_name))) > 0);');
    IF OBJECT_ID(N'dbo.CK_Ingredient_Stock', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.Ingredient WITH CHECK ADD CONSTRAINT CK_Ingredient_Stock CHECK (stock >= 0);');
    IF OBJECT_ID(N'dbo.CK_Ingredient_Unit', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.Ingredient WITH CHECK ADD CONSTRAINT CK_Ingredient_Unit CHECK (unit IN (N''g'', N''ml'', N''个''));');
    IF OBJECT_ID(N'dbo.CK_Ingredient_Status', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.Ingredient WITH CHECK ADD CONSTRAINT CK_Ingredient_Status CHECK (status IN (N''可用'', N''缺货''));');

    -- OrderItem
    IF OBJECT_ID(N'dbo.PK_OrderItem', N'PK') IS NULL
        EXEC(N'ALTER TABLE dbo.OrderItem ADD CONSTRAINT PK_OrderItem PRIMARY KEY (item_id);');
    IF OBJECT_ID(N'dbo.CK_OrderItem_ProductName_NotBlank', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.OrderItem WITH CHECK ADD CONSTRAINT CK_OrderItem_ProductName_NotBlank CHECK (LEN(LTRIM(RTRIM(product_name_snapshot))) > 0);');
    IF OBJECT_ID(N'dbo.FK_OrderItem_Order', N'F') IS NULL
        EXEC(N'ALTER TABLE dbo.OrderItem WITH CHECK ADD CONSTRAINT FK_OrderItem_Order FOREIGN KEY (order_id) REFERENCES dbo.SalesOrder(order_id);');
    IF OBJECT_ID(N'dbo.FK_OrderItem_Product', N'F') IS NULL
        EXEC(N'ALTER TABLE dbo.OrderItem WITH CHECK ADD CONSTRAINT FK_OrderItem_Product FOREIGN KEY (product_id) REFERENCES dbo.Product(product_id);');
    IF OBJECT_ID(N'dbo.CK_OrderItem_Quantity', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.OrderItem WITH CHECK ADD CONSTRAINT CK_OrderItem_Quantity CHECK (quantity > 0);');
    IF OBJECT_ID(N'dbo.CK_OrderItem_BasePrice', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.OrderItem WITH CHECK ADD CONSTRAINT CK_OrderItem_BasePrice CHECK (base_price_snapshot >= 0);');
    IF OBJECT_ID(N'dbo.CK_OrderItem_UnitPrice', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.OrderItem WITH CHECK ADD CONSTRAINT CK_OrderItem_UnitPrice CHECK (unit_price >= 0);');

    -- ProductSpecification
    IF OBJECT_ID(N'dbo.PK_ProductSpecification', N'PK') IS NULL
        EXEC(N'ALTER TABLE dbo.ProductSpecification ADD CONSTRAINT PK_ProductSpecification PRIMARY KEY (product_id, spec_id);');
    IF OBJECT_ID(N'dbo.FK_ProductSpecification_Product', N'F') IS NULL
        EXEC(N'ALTER TABLE dbo.ProductSpecification WITH CHECK ADD CONSTRAINT FK_ProductSpecification_Product FOREIGN KEY (product_id) REFERENCES dbo.Product(product_id);');
    IF OBJECT_ID(N'dbo.FK_ProductSpecification_Specification', N'F') IS NULL
        EXEC(N'ALTER TABLE dbo.ProductSpecification WITH CHECK ADD CONSTRAINT FK_ProductSpecification_Specification FOREIGN KEY (spec_id) REFERENCES dbo.Specification(spec_id);');
    IF OBJECT_ID(N'dbo.CK_ProductSpecification_Status', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.ProductSpecification WITH CHECK ADD CONSTRAINT CK_ProductSpecification_Status CHECK (status IN (N''可用'', N''停用''));');

    -- Recipe
    IF OBJECT_ID(N'dbo.PK_Recipe', N'PK') IS NULL
        EXEC(N'ALTER TABLE dbo.Recipe ADD CONSTRAINT PK_Recipe PRIMARY KEY (product_id, ingredient_id);');
    IF OBJECT_ID(N'dbo.FK_Recipe_Product', N'F') IS NULL
        EXEC(N'ALTER TABLE dbo.Recipe WITH CHECK ADD CONSTRAINT FK_Recipe_Product FOREIGN KEY (product_id) REFERENCES dbo.Product(product_id);');
    IF OBJECT_ID(N'dbo.FK_Recipe_Ingredient', N'F') IS NULL
        EXEC(N'ALTER TABLE dbo.Recipe WITH CHECK ADD CONSTRAINT FK_Recipe_Ingredient FOREIGN KEY (ingredient_id) REFERENCES dbo.Ingredient(ingredient_id);');
    IF OBJECT_ID(N'dbo.CK_Recipe_BaseAmount', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.Recipe WITH CHECK ADD CONSTRAINT CK_Recipe_BaseAmount CHECK (base_amount > 0);');

    -- AddOn
    IF OBJECT_ID(N'dbo.PK_AddOn', N'PK') IS NULL
        EXEC(N'ALTER TABLE dbo.AddOn ADD CONSTRAINT PK_AddOn PRIMARY KEY (addon_id);');
    IF OBJECT_ID(N'dbo.CK_AddOn_Id_NotBlank', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.AddOn WITH CHECK ADD CONSTRAINT CK_AddOn_Id_NotBlank CHECK (LEN(LTRIM(RTRIM(addon_id))) > 0);');
    IF OBJECT_ID(N'dbo.CK_AddOn_Name_NotBlank', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.AddOn WITH CHECK ADD CONSTRAINT CK_AddOn_Name_NotBlank CHECK (LEN(LTRIM(RTRIM(addon_name))) > 0);');
    IF OBJECT_ID(N'dbo.UK_AddOn_name', N'UQ') IS NULL
        EXEC(N'ALTER TABLE dbo.AddOn ADD CONSTRAINT UK_AddOn_name UNIQUE (addon_name);');
    IF OBJECT_ID(N'dbo.FK_AddOn_Ingredient', N'F') IS NULL
        EXEC(N'ALTER TABLE dbo.AddOn WITH CHECK ADD CONSTRAINT FK_AddOn_Ingredient FOREIGN KEY (ingredient_id) REFERENCES dbo.Ingredient(ingredient_id);');
    IF OBJECT_ID(N'dbo.CK_AddOn_Price', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.AddOn WITH CHECK ADD CONSTRAINT CK_AddOn_Price CHECK (price >= 0);');
    IF OBJECT_ID(N'dbo.CK_AddOn_ExtraAmount', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.AddOn WITH CHECK ADD CONSTRAINT CK_AddOn_ExtraAmount CHECK (extra_amount > 0);');
    IF OBJECT_ID(N'dbo.CK_AddOn_Status', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.AddOn WITH CHECK ADD CONSTRAINT CK_AddOn_Status CHECK (status IN (N''可用'', N''缺货''));');

    -- ItemSpec
    IF OBJECT_ID(N'dbo.PK_ItemSpec', N'PK') IS NULL
        EXEC(N'ALTER TABLE dbo.ItemSpec ADD CONSTRAINT PK_ItemSpec PRIMARY KEY (item_id, spec_type);');
    IF OBJECT_ID(N'dbo.CK_ItemSpec_Name_NotBlank', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.ItemSpec WITH CHECK ADD CONSTRAINT CK_ItemSpec_Name_NotBlank CHECK (LEN(LTRIM(RTRIM(spec_name_snapshot))) > 0);');
    IF OBJECT_ID(N'dbo.FK_ItemSpec_OrderItem', N'F') IS NULL
        EXEC(N'ALTER TABLE dbo.ItemSpec WITH CHECK ADD CONSTRAINT FK_ItemSpec_OrderItem FOREIGN KEY (item_id) REFERENCES dbo.OrderItem(item_id);');
    IF OBJECT_ID(N'dbo.FK_ItemSpec_Spec_id', N'F') IS NULL
        EXEC(N'ALTER TABLE dbo.ItemSpec WITH CHECK ADD CONSTRAINT FK_ItemSpec_Spec_id FOREIGN KEY (spec_id, spec_type) REFERENCES dbo.Specification(spec_id, spec_type);');

    -- ItemAddOn
    IF OBJECT_ID(N'dbo.PK_ItemAddOn', N'PK') IS NULL
        EXEC(N'ALTER TABLE dbo.ItemAddOn ADD CONSTRAINT PK_ItemAddOn PRIMARY KEY (item_id, addon_id);');
    IF OBJECT_ID(N'dbo.CK_ItemAddOn_Name_NotBlank', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.ItemAddOn WITH CHECK ADD CONSTRAINT CK_ItemAddOn_Name_NotBlank CHECK (LEN(LTRIM(RTRIM(addon_name_snapshot))) > 0);');
    IF OBJECT_ID(N'dbo.FK_ItemAddOn_OrderItem', N'F') IS NULL
        EXEC(N'ALTER TABLE dbo.ItemAddOn WITH CHECK ADD CONSTRAINT FK_ItemAddOn_OrderItem FOREIGN KEY (item_id) REFERENCES dbo.OrderItem(item_id);');
    IF OBJECT_ID(N'dbo.FK_ItemAddOn_AddOn', N'F') IS NULL
        EXEC(N'ALTER TABLE dbo.ItemAddOn WITH CHECK ADD CONSTRAINT FK_ItemAddOn_AddOn FOREIGN KEY (addon_id) REFERENCES dbo.AddOn(addon_id);');
    IF OBJECT_ID(N'dbo.CK_ItemAddOn_Price', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.ItemAddOn WITH CHECK ADD CONSTRAINT CK_ItemAddOn_Price CHECK (price_snapshot >= 0);');

    -- OrderItemIngredient
    IF OBJECT_ID(N'dbo.PK_OrderItemIngredient', N'PK') IS NULL
        EXEC(N'ALTER TABLE dbo.OrderItemIngredient ADD CONSTRAINT PK_OrderItemIngredient PRIMARY KEY (item_id, ingredient_id);');
    IF OBJECT_ID(N'dbo.FK_OrderItemIngredient_OrderItem', N'F') IS NULL
        EXEC(N'ALTER TABLE dbo.OrderItemIngredient WITH CHECK ADD CONSTRAINT FK_OrderItemIngredient_OrderItem FOREIGN KEY (item_id) REFERENCES dbo.OrderItem(item_id);');
    IF OBJECT_ID(N'dbo.FK_OrderItemIngredient_Ingredient', N'F') IS NULL
        EXEC(N'ALTER TABLE dbo.OrderItemIngredient WITH CHECK ADD CONSTRAINT FK_OrderItemIngredient_Ingredient FOREIGN KEY (ingredient_id) REFERENCES dbo.Ingredient(ingredient_id);');
    IF OBJECT_ID(N'dbo.CK_OrderItemIngredient_Amount', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.OrderItemIngredient WITH CHECK ADD CONSTRAINT CK_OrderItemIngredient_Amount CHECK (amount > 0);');

    -- SpecificationIngredient
    IF OBJECT_ID(N'dbo.PK_SpecificationIngredient', N'PK') IS NULL
        EXEC(N'ALTER TABLE dbo.SpecificationIngredient ADD CONSTRAINT PK_SpecificationIngredient PRIMARY KEY (product_id, spec_id, ingredient_id);');
    IF OBJECT_ID(N'dbo.FK_SpecificationIngredient_ProductSpec', N'F') IS NULL
        EXEC(N'ALTER TABLE dbo.SpecificationIngredient WITH CHECK ADD CONSTRAINT FK_SpecificationIngredient_ProductSpec FOREIGN KEY (product_id, spec_id) REFERENCES dbo.ProductSpecification(product_id, spec_id);');
    IF OBJECT_ID(N'dbo.FK_SpecificationIngredient_Ingredient', N'F') IS NULL
        EXEC(N'ALTER TABLE dbo.SpecificationIngredient WITH CHECK ADD CONSTRAINT FK_SpecificationIngredient_Ingredient FOREIGN KEY (ingredient_id) REFERENCES dbo.Ingredient(ingredient_id);');
    IF OBJECT_ID(N'dbo.FK_SpecificationIngredient_Recipe', N'F') IS NULL
        EXEC(N'ALTER TABLE dbo.SpecificationIngredient WITH CHECK ADD CONSTRAINT FK_SpecificationIngredient_Recipe FOREIGN KEY (product_id, ingredient_id) REFERENCES dbo.Recipe(product_id, ingredient_id);');
    IF OBJECT_ID(N'dbo.CK_SpecificationIngredient_Factor', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.SpecificationIngredient WITH CHECK ADD CONSTRAINT CK_SpecificationIngredient_Factor CHECK (factor >= 0);');

    -- 本轮补充：计件库存、遗漏的独立编号空白检查、订单身份互斥。
    IF OBJECT_ID(N'dbo.CK_Ingredient_PieceStock', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.Ingredient WITH CHECK ADD CONSTRAINT CK_Ingredient_PieceStock
            CHECK (unit <> N''个'' OR stock = FLOOR(stock));');
    IF OBJECT_ID(N'dbo.CK_DutyRoster_Id_NotBlank', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.DutyRoster WITH CHECK ADD CONSTRAINT CK_DutyRoster_Id_NotBlank
            CHECK (LEN(LTRIM(RTRIM(duty_id))) > 0);');
    IF OBJECT_ID(N'dbo.CK_OrderItem_Id_NotBlank', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.OrderItem WITH CHECK ADD CONSTRAINT CK_OrderItem_Id_NotBlank
            CHECK (LEN(LTRIM(RTRIM(item_id))) > 0);');
    IF OBJECT_ID(N'dbo.CK_SalesOrder_Owner', N'C') IS NULL
        EXEC(N'ALTER TABLE dbo.SalesOrder WITH CHECK ADD CONSTRAINT CK_SalesOrder_Owner
            CHECK ((member_id IS NOT NULL AND guest_id IS NULL)
                OR (member_id IS NULL AND guest_id IS NOT NULL));');

    -- 2. DEFAULT：按字段检查，保留建表时 SQL Server 自动命名的默认约束。
    IF NOT EXISTS (
        SELECT 1 FROM sys.default_constraints AS d
        JOIN sys.columns AS c ON c.object_id = d.parent_object_id AND c.column_id = d.parent_column_id
        WHERE d.parent_object_id = OBJECT_ID(N'dbo.Employee') AND c.name = N'status'
    )
        EXEC(N'ALTER TABLE dbo.Employee ADD CONSTRAINT DF_Employee_status DEFAULT N''在职'' FOR status;');
    IF NOT EXISTS (
        SELECT 1 FROM sys.default_constraints AS d
        JOIN sys.columns AS c ON c.object_id = d.parent_object_id AND c.column_id = d.parent_column_id
        WHERE d.parent_object_id = OBJECT_ID(N'dbo.Member') AND c.name = N'points'
    )
        EXEC(N'ALTER TABLE dbo.Member ADD CONSTRAINT DF_Member_points DEFAULT 0 FOR points;');
    IF NOT EXISTS (
        SELECT 1 FROM sys.default_constraints AS d
        JOIN sys.columns AS c ON c.object_id = d.parent_object_id AND c.column_id = d.parent_column_id
        WHERE d.parent_object_id = OBJECT_ID(N'dbo.SalesOrder') AND c.name = N'order_time'
    )
        EXEC(N'ALTER TABLE dbo.SalesOrder ADD CONSTRAINT DF_SalesOrder_order_time DEFAULT SYSDATETIME() FOR order_time;');
    IF NOT EXISTS (
        SELECT 1 FROM sys.default_constraints AS d
        JOIN sys.columns AS c ON c.object_id = d.parent_object_id AND c.column_id = d.parent_column_id
        WHERE d.parent_object_id = OBJECT_ID(N'dbo.SalesOrder') AND c.name = N'status'
    )
        EXEC(N'ALTER TABLE dbo.SalesOrder ADD CONSTRAINT DF_SalesOrder_status DEFAULT N''排队中'' FOR status;');
    IF NOT EXISTS (
        SELECT 1 FROM sys.default_constraints AS d
        JOIN sys.columns AS c ON c.object_id = d.parent_object_id AND c.column_id = d.parent_column_id
        WHERE d.parent_object_id = OBJECT_ID(N'dbo.Product') AND c.name = N'status'
    )
        EXEC(N'ALTER TABLE dbo.Product ADD CONSTRAINT DF_Product_status DEFAULT N''下架'' FOR status;');
    IF NOT EXISTS (
        SELECT 1 FROM sys.default_constraints AS d
        JOIN sys.columns AS c ON c.object_id = d.parent_object_id AND c.column_id = d.parent_column_id
        WHERE d.parent_object_id = OBJECT_ID(N'dbo.Ingredient') AND c.name = N'stock'
    )
        EXEC(N'ALTER TABLE dbo.Ingredient ADD CONSTRAINT DF_Ingredient_stock DEFAULT 0 FOR stock;');
    IF NOT EXISTS (
        SELECT 1 FROM sys.default_constraints AS d
        JOIN sys.columns AS c ON c.object_id = d.parent_object_id AND c.column_id = d.parent_column_id
        WHERE d.parent_object_id = OBJECT_ID(N'dbo.Ingredient') AND c.name = N'status'
    )
        EXEC(N'ALTER TABLE dbo.Ingredient ADD CONSTRAINT DF_Ingredient_status DEFAULT N''可用'' FOR status;');
    IF NOT EXISTS (
        SELECT 1 FROM sys.default_constraints AS d
        JOIN sys.columns AS c ON c.object_id = d.parent_object_id AND c.column_id = d.parent_column_id
        WHERE d.parent_object_id = OBJECT_ID(N'dbo.OrderItem') AND c.name = N'quantity'
    )
        EXEC(N'ALTER TABLE dbo.OrderItem ADD CONSTRAINT DF_OrderItem_quantity DEFAULT 1 FOR quantity;');
    IF NOT EXISTS (
        SELECT 1 FROM sys.default_constraints AS d
        JOIN sys.columns AS c ON c.object_id = d.parent_object_id AND c.column_id = d.parent_column_id
        WHERE d.parent_object_id = OBJECT_ID(N'dbo.ProductSpecification') AND c.name = N'price_delta'
    )
        EXEC(N'ALTER TABLE dbo.ProductSpecification ADD CONSTRAINT DF_ProductSpecification_price_delta DEFAULT 0 FOR price_delta;');
    IF NOT EXISTS (
        SELECT 1 FROM sys.default_constraints AS d
        JOIN sys.columns AS c ON c.object_id = d.parent_object_id AND c.column_id = d.parent_column_id
        WHERE d.parent_object_id = OBJECT_ID(N'dbo.ProductSpecification') AND c.name = N'status'
    )
        EXEC(N'ALTER TABLE dbo.ProductSpecification ADD CONSTRAINT DF_ProductSpecification_status DEFAULT N''停用'' FOR status;');
    IF NOT EXISTS (
        SELECT 1 FROM sys.default_constraints AS d
        JOIN sys.columns AS c ON c.object_id = d.parent_object_id AND c.column_id = d.parent_column_id
        WHERE d.parent_object_id = OBJECT_ID(N'dbo.AddOn') AND c.name = N'status'
    )
        EXEC(N'ALTER TABLE dbo.AddOn ADD CONSTRAINT DF_AddOn_status DEFAULT N''可用'' FOR status;');

    -- 3. 重新核验并启用这些业务表的全部 FK/CHECK，不留下禁用或不受信约束。
    DECLARE @constraint_table SYSNAME;
    DECLARE constraint_tables CURSOR LOCAL FAST_FORWARD FOR
        SELECT table_name FROM @tables ORDER BY table_name;
    OPEN constraint_tables;
    FETCH NEXT FROM constraint_tables INTO @constraint_table;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @ddl = N'ALTER TABLE dbo.' + QUOTENAME(@constraint_table)
            + N' WITH CHECK CHECK CONSTRAINT ALL;';
        EXEC sys.sp_executesql @ddl;
        FETCH NEXT FROM constraint_tables INTO @constraint_table;
    END;
    CLOSE constraint_tables;
    DEALLOCATE constraint_tables;

    COMMIT TRANSACTION;
    SELECT N'约束安装成功' AS stage,
           @guest_backfill_count AS legacy_guest_orders_assigned_placeholder_id;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

-- ============================================================
-- 二、正反例验证：不依赖样例编号，所有测试记录最后回滚。
-- ============================================================
-- CHECK/FK 反例会产生预期错误；关闭 XACT_ABORT 以便使用保存点继续验证。
-- 捕获时同时检查错误号和约束名称，避免把其他错误当成验证成功。
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

-- ============================================================
-- 三、检查安装结果：可用于完整性截图，不读取顾客个人资料。
-- ============================================================
SELECT t.name AS table_name, o.name AS constraint_name, o.type_desc,
       cc.definition AS check_definition, dc.definition AS default_definition,
       COALESCE(cc.is_disabled, fk.is_disabled) AS is_disabled,
       COALESCE(cc.is_not_trusted, fk.is_not_trusted) AS is_not_trusted
FROM sys.objects AS o
JOIN sys.tables AS t ON t.object_id = o.parent_object_id
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
LEFT JOIN sys.check_constraints AS cc ON cc.object_id = o.object_id
LEFT JOIN sys.foreign_keys AS fk ON fk.object_id = o.object_id
LEFT JOIN sys.default_constraints AS dc ON dc.object_id = o.object_id
WHERE s.name = N'dbo' AND t.name IN (SELECT table_name FROM @tables)
  AND o.type IN ('PK', 'UQ', 'F', 'C', 'D')
ORDER BY t.name, o.type, o.name;
