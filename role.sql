-- 第四周：四种数据库角色、受控业务操作及正常/越权验证。
-- 执行顺序：db_creation.sql -> seed_data.sql -> constraint.sql -> role.sql。
-- 管理员在无未结束事务的新查询窗口完整执行，可重复运行，不重建数据库。
-- 所有安装 DDL 在一个事务中执行；验证事务最终回滚业务数据和临时身份绑定。
--
-- 顾客/会员：浏览、本人订单查询、模拟付款下单、本人排队订单退款。
-- 店员：当天订单+全部未完成订单、制作流转、协助退款、会员登记及资料更正。
-- 店长：全部经营数据、商品/原料/配方/规格/加料/员工/排班管理、补库与盘点。
-- 所有业务角色均不能直接增删改业务表或身份绑定，店长也没有数据库授权权限。
-- 业务 Employee.role/status 与数据库角色分开维护；离职后管理员另行撤销成员权限。
--
-- teabar_auth.PrincipalBinding 是数据库认证用户 SID 到购买身份的管理员绑定表，
-- 不代表新增顾客业务档案。游客同一次会话复用 guest_id；只有管理员维护绑定。
-- 下单接口不接受 member_id/guest_id，不信任客户端 SESSION_CONTEXT。
-- 6 个 WITHOUT LOGIN 用户仅用于 EXECUTE AS USER 实验，不创建服务器登录或密码。
-- 真实前端会话的注册及认证需由可信后端接入；本文件演示数据库侧隔离。
-- @payment_succeeded 是课程模拟支付结果，不能代替真实支付平台的确认。
--
-- 业务模块使用 CALLER（默认）及 dbo 所有权链，保留真实调用者身份；
-- 模块内部仅有静态业务 SQL，不以动态 SQL 或 EXECUTE AS OWNER 绕过身份检查。
-- 独立调用由过程提交/回滚；已有外层事务时使用保存点，无法提交的外层事务须回滚。
-- 参考：https://learn.microsoft.com/en-us/sql/relational-databases/tutorial-ownership-chains-and-context-switching
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

IF DB_NAME() <> N'TeabarDB' OR @@TRANCOUNT <> 0
    THROW 52400, N'请在 TeabarDB 的无未结束事务的新窗口执行。', 1;
IF COL_LENGTH(N'dbo.SalesOrder', N'guest_id') IS NULL
   OR OBJECT_ID(N'dbo.CK_SalesOrder_Owner', N'C') IS NULL
   OR OBJECT_ID(N'dbo.FK_SpecificationIngredient_Recipe', N'F') IS NULL
    THROW 52401, N'请先完整执行 constraint.sql。', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.Member WHERE member_id = 'M001')
   OR NOT EXISTS (SELECT 1 FROM dbo.Member WHERE member_id = 'M002')
    THROW 52402, N'示例会员账户依赖 seed_data.sql 的 M001、M002，请先装载样例。', 1;

DECLARE @roles TABLE (name SYSNAME PRIMARY KEY);
INSERT @roles VALUES(N'teabar_customer'), (N'teabar_member'), (N'teabar_clerk'), (N'teabar_manager');
DECLARE @users TABLE (name SYSNAME PRIMARY KEY, role_name SYSNAME);
INSERT @users VALUES
    (N'demo_guest_a', N'teabar_customer'), (N'demo_guest_b', N'teabar_customer'),
    (N'demo_member_a', N'teabar_member'), (N'demo_member_b', N'teabar_member'),
    (N'demo_clerk', N'teabar_clerk'), (N'demo_manager', N'teabar_manager');
DECLARE @business_tables TABLE (name SYSNAME PRIMARY KEY);
INSERT @business_tables VALUES
    (N'Employee'), (N'DutyRoster'), (N'Member'), (N'SalesOrder'), (N'Product'),
    (N'Specification'), (N'Ingredient'), (N'OrderItem'), (N'ProductSpecification'),
    (N'Recipe'), (N'AddOn'), (N'ItemSpec'), (N'ItemAddOn'),
    (N'OrderItemIngredient'), (N'SpecificationIngredient');
DECLARE @command NVARCHAR(MAX), @name SYSNAME, @role SYSNAME;

BEGIN TRY
    BEGIN TRANSACTION;

    IF SCHEMA_ID(N'teabar_auth') IS NULL EXEC(N'CREATE SCHEMA teabar_auth AUTHORIZATION dbo;');
    IF SCHEMA_ID(N'teabar_api') IS NULL EXEC(N'CREATE SCHEMA teabar_api AUTHORIZATION dbo;');
    IF EXISTS (SELECT 1 FROM sys.schemas WHERE name IN (N'teabar_auth', N'teabar_api', N'dbo')
               AND principal_id <> DATABASE_PRINCIPAL_ID(N'dbo'))
        THROW 52403, N'业务和授权模块需要 dbo 所有权链；不自动改变已有架构的所有者。', 1;

    IF OBJECT_ID(N'teabar_auth.PrincipalBinding', N'U') IS NULL
        EXEC(N'CREATE TABLE teabar_auth.PrincipalBinding (
            principal_sid VARBINARY(85) NOT NULL CONSTRAINT PK_PrincipalBinding PRIMARY KEY,
            principal_name SYSNAME NOT NULL CONSTRAINT UQ_PrincipalBinding_Name UNIQUE,
            member_id VARCHAR(10) NULL,
            guest_id UNIQUEIDENTIFIER NULL,
            is_active BIT NOT NULL CONSTRAINT DF_PrincipalBinding_Active DEFAULT 1,
            CONSTRAINT FK_PrincipalBinding_Member FOREIGN KEY(member_id) REFERENCES dbo.Member(member_id),
            CONSTRAINT CK_PrincipalBinding_Identity CHECK(
                (member_id IS NOT NULL AND guest_id IS NULL)
                OR (member_id IS NULL AND guest_id IS NOT NULL))
        );');
    IF TYPE_ID(N'teabar_api.OrderLines') IS NULL
        EXEC(N'CREATE TYPE teabar_api.OrderLines AS TABLE (
            item_id VARCHAR(10) NOT NULL PRIMARY KEY,
            product_id VARCHAR(10) NOT NULL, quantity INT NOT NULL CHECK(quantity > 0)
        );');
    IF TYPE_ID(N'teabar_api.OrderSpecs') IS NULL
        EXEC(N'CREATE TYPE teabar_api.OrderSpecs AS TABLE (
            item_id VARCHAR(10) NOT NULL, spec_id VARCHAR(10) NOT NULL,
            PRIMARY KEY(item_id, spec_id)
        );');
    IF TYPE_ID(N'teabar_api.OrderAddOns') IS NULL
        EXEC(N'CREATE TYPE teabar_api.OrderAddOns AS TABLE (
            item_id VARCHAR(10) NOT NULL, addon_id VARCHAR(10) NOT NULL,
            PRIMARY KEY(item_id, addon_id)
        );');

    DECLARE role_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT name FROM @roles;
    OPEN role_cursor;
    FETCH NEXT FROM role_cursor INTO @role;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF DATABASE_PRINCIPAL_ID(@role) IS NULL
        BEGIN
            SET @command = N'CREATE ROLE ' + QUOTENAME(@role) + N' AUTHORIZATION dbo;';
            EXEC sys.sp_executesql @command;
        END;
        IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @role
                   AND (type <> 'R' OR owning_principal_id <> DATABASE_PRINCIPAL_ID(N'dbo')))
            THROW 52404, N'保留角色名称已被其他类型或所有者占用。', 1;
        FETCH NEXT FROM role_cursor INTO @role;
    END;
    CLOSE role_cursor;
    DEALLOCATE role_cursor;

    DECLARE user_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT name, role_name FROM @users;
    OPEN user_cursor;
    FETCH NEXT FROM user_cursor INTO @name, @role;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF DATABASE_PRINCIPAL_ID(@name) IS NULL
        BEGIN
            SET @command = N'CREATE USER ' + QUOTENAME(@name) + N' WITHOUT LOGIN;';
            EXEC sys.sp_executesql @command;
        END;
        IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @name AND (type <> 'S' OR authentication_type <> 0))
            THROW 52405, N'示例用户名已被可登录账户占用，不自动更改其权限。', 1;
        IF EXISTS (
            SELECT 1 FROM sys.database_role_members AS rm
            JOIN sys.database_principals AS r ON r.principal_id = rm.role_principal_id
            WHERE rm.member_principal_id = DATABASE_PRINCIPAL_ID(@name) AND r.name <> @role
        )
            THROW 52406, N'示例用户存在额外角色成员关系，请管理员先核对，避免错误权限验证。', 1;
        IF NOT EXISTS (SELECT 1 FROM sys.database_role_members
            WHERE role_principal_id = DATABASE_PRINCIPAL_ID(@role) AND member_principal_id = DATABASE_PRINCIPAL_ID(@name))
        BEGIN
            SET @command = N'ALTER ROLE ' + QUOTENAME(@role) + N' ADD MEMBER ' + QUOTENAME(@name) + N';';
            EXEC sys.sp_executesql @command;
        END;
        FETCH NEXT FROM user_cursor INTO @name, @role;
    END;
    CLOSE user_cursor;
    DEALLOCATE user_cursor;

    -- 保留已建立会话的临时ID，重复安装不重新分配；SID不匹配时拒绝继承旧身份。
    EXEC(N'
        IF EXISTS (
            SELECT 1 FROM teabar_auth.PrincipalBinding AS b
            JOIN sys.database_principals AS p ON p.name = b.principal_name
            WHERE b.principal_name IN (N''demo_guest_a'', N''demo_guest_b'', N''demo_member_a'', N''demo_member_b'')
              AND b.principal_sid <> p.sid
        ) THROW 52407, N''示例用户SID已变更，请管理员清理旧身份绑定后再建立新绑定。'', 1;
        INSERT teabar_auth.PrincipalBinding(principal_sid, principal_name, member_id, guest_id)
        SELECT p.sid, p.name,
            CASE p.name WHEN N''demo_member_a'' THEN ''M001'' WHEN N''demo_member_b'' THEN ''M002'' ELSE NULL END,
            CASE WHEN p.name IN (N''demo_guest_a'', N''demo_guest_b'') THEN NEWID() ELSE NULL END
        FROM sys.database_principals AS p
        WHERE p.name IN (N''demo_guest_a'', N''demo_guest_b'', N''demo_member_a'', N''demo_member_b'')
          AND NOT EXISTS (SELECT 1 FROM teabar_auth.PrincipalBinding AS b WHERE b.principal_sid = p.sid);
    ');

    -- 查询视图与受控操作；用动态 DDL 满足 CREATE OR ALTER 必须单独批次的要求。
    -- 业务过程自身并不使用动态 SQL。
    -- fn_CurrentIdentity
    EXEC(N'CREATE OR ALTER FUNCTION teabar_auth.fn_CurrentIdentity()
RETURNS TABLE
AS RETURN (
    SELECT b.member_id, b.guest_id
    FROM teabar_auth.PrincipalBinding AS b
    JOIN sys.database_principals AS p ON p.sid = b.principal_sid
    WHERE p.principal_id = DATABASE_PRINCIPAL_ID() AND b.is_active = 1
);');

    -- vw_Menu
    EXEC(N'CREATE OR ALTER VIEW teabar_api.vw_Menu AS
SELECT p.product_id, p.product_name, p.base_price, p.description
FROM dbo.Product AS p
WHERE p.status = N''在售''
  AND EXISTS (SELECT 1 FROM dbo.Recipe AS r WHERE r.product_id = p.product_id)
  AND EXISTS (SELECT 1 FROM dbo.ProductSpecification AS ps WHERE ps.product_id = p.product_id AND ps.status = N''可用'')
  AND NOT EXISTS (
      SELECT s.spec_type FROM dbo.ProductSpecification AS ps
      JOIN dbo.Specification AS s ON s.spec_id = ps.spec_id
      WHERE ps.product_id = p.product_id
      GROUP BY s.spec_type
      HAVING SUM(CASE WHEN ps.status = N''可用'' THEN 1 ELSE 0 END) = 0
  );');

    -- vw_AvailableSpecifications
    EXEC(N'CREATE OR ALTER VIEW teabar_api.vw_AvailableSpecifications AS
SELECT ps.product_id, s.spec_id, s.spec_type, s.spec_name, ps.price_delta
FROM dbo.ProductSpecification AS ps
JOIN dbo.Specification AS s ON s.spec_id = ps.spec_id
JOIN teabar_api.vw_Menu AS m ON m.product_id = ps.product_id
WHERE ps.status = N''可用'';');

    -- vw_AvailableAddOns
    EXEC(N'CREATE OR ALTER VIEW teabar_api.vw_AvailableAddOns AS
SELECT a.addon_id, a.addon_name, a.price
FROM dbo.AddOn AS a JOIN dbo.Ingredient AS i ON i.ingredient_id = a.ingredient_id
WHERE a.status = N''可用'' AND i.status = N''可用'' AND i.stock >= a.extra_amount;');

    -- vw_MyOrders
    EXEC(N'CREATE OR ALTER VIEW teabar_api.vw_MyOrders AS
SELECT o.order_id, o.order_time, o.total_amount, o.status
FROM dbo.SalesOrder AS o CROSS JOIN teabar_auth.fn_CurrentIdentity() AS me
WHERE (me.member_id IS NOT NULL AND o.member_id = me.member_id)
   OR (me.guest_id IS NOT NULL AND o.guest_id = me.guest_id);');

    -- vw_MyOrderItems
    EXEC(N'CREATE OR ALTER VIEW teabar_api.vw_MyOrderItems AS
SELECT i.item_id, i.order_id, i.product_id, i.product_name_snapshot,
       i.quantity, i.base_price_snapshot, i.unit_price, i.sub_amount
FROM dbo.OrderItem AS i JOIN teabar_api.vw_MyOrders AS o ON o.order_id = i.order_id;');

    -- vw_MyItemSpecs
    EXEC(N'CREATE OR ALTER VIEW teabar_api.vw_MyItemSpecs AS
SELECT s.item_id, s.spec_type, s.spec_id, s.spec_name_snapshot, s.price_delta_snapshot
FROM dbo.ItemSpec AS s JOIN teabar_api.vw_MyOrderItems AS i ON i.item_id = s.item_id;');

    -- vw_MyItemAddOns
    EXEC(N'CREATE OR ALTER VIEW teabar_api.vw_MyItemAddOns AS
SELECT a.item_id, a.addon_id, a.addon_name_snapshot, a.price_snapshot
FROM dbo.ItemAddOn AS a JOIN teabar_api.vw_MyOrderItems AS i ON i.item_id = a.item_id;');

    -- vw_MyMember
    EXEC(N'CREATE OR ALTER VIEW teabar_api.vw_MyMember AS
SELECT m.member_id, m.name, m.phone, m.points
FROM dbo.Member AS m JOIN teabar_auth.fn_CurrentIdentity() AS me ON me.member_id = m.member_id;');

    -- vw_WorkOrders
    EXEC(N'CREATE OR ALTER VIEW teabar_api.vw_WorkOrders AS
SELECT order_id, member_id, order_time, total_amount, status
FROM dbo.SalesOrder
WHERE status IN (N''排队中'', N''制作中'', N''待取餐'')
   OR (order_time >= CONVERT(DATE, SYSDATETIME())
       AND order_time < DATEADD(DAY, 1, CONVERT(DATE, SYSDATETIME())));');

    -- vw_WorkOrderItems
    EXEC(N'CREATE OR ALTER VIEW teabar_api.vw_WorkOrderItems AS
SELECT i.item_id, i.order_id, i.product_id, i.product_name_snapshot,
       i.quantity, i.base_price_snapshot, i.unit_price, i.sub_amount
FROM dbo.OrderItem AS i JOIN teabar_api.vw_WorkOrders AS o ON o.order_id = i.order_id;');

    -- vw_WorkItemSpecs
    EXEC(N'CREATE OR ALTER VIEW teabar_api.vw_WorkItemSpecs AS
SELECT s.item_id, s.spec_type, s.spec_id, s.spec_name_snapshot, s.price_delta_snapshot
FROM dbo.ItemSpec AS s JOIN teabar_api.vw_WorkOrderItems AS i ON i.item_id = s.item_id;');

    -- vw_WorkItemAddOns
    EXEC(N'CREATE OR ALTER VIEW teabar_api.vw_WorkItemAddOns AS
SELECT a.item_id, a.addon_id, a.addon_name_snapshot, a.price_snapshot
FROM dbo.ItemAddOn AS a JOIN teabar_api.vw_WorkOrderItems AS i ON i.item_id = a.item_id;');

    -- vw_WorkConsumption
    EXEC(N'CREATE OR ALTER VIEW teabar_api.vw_WorkConsumption AS
SELECT c.item_id, c.ingredient_id, g.ingredient_name, g.unit, c.amount
FROM dbo.OrderItemIngredient AS c
JOIN teabar_api.vw_WorkOrderItems AS i ON i.item_id = c.item_id
JOIN dbo.Ingredient AS g ON g.ingredient_id = c.ingredient_id;');

    -- vw_WorkTeam
    EXEC(N'CREATE OR ALTER VIEW teabar_api.vw_WorkTeam AS
SELECT o.order_id, e.employee_id, e.name, e.role, d.start_time, d.end_time
FROM teabar_api.vw_WorkOrders AS o
JOIN dbo.DutyRoster AS d ON d.start_time <= o.order_time AND o.order_time < d.end_time
JOIN dbo.Employee AS e ON e.employee_id = d.employee_id;');

    -- vw_DailySales
    EXEC(N'CREATE OR ALTER VIEW teabar_api.vw_DailySales AS
SELECT CONVERT(DATE, order_time) AS sale_date, COUNT_BIG(*) AS order_count,
       SUM(total_amount) AS sales_amount
FROM dbo.SalesOrder WHERE status = N''已完成'' GROUP BY CONVERT(DATE, order_time);');

    -- vw_ProductSales
    EXEC(N'CREATE OR ALTER VIEW teabar_api.vw_ProductSales AS
SELECT p.product_id, p.product_name, SUM(CONVERT(BIGINT, i.quantity)) AS cups_sold,
       SUM(i.sub_amount) AS sales_amount
FROM dbo.OrderItem AS i JOIN dbo.SalesOrder AS o ON o.order_id = i.order_id
JOIN dbo.Product AS p ON p.product_id = i.product_id
WHERE o.status = N''已完成'' GROUP BY p.product_id, p.product_name;');

    -- usp_PlacePaidOrder
    EXEC(N'CREATE OR ALTER PROCEDURE teabar_api.usp_PlacePaidOrder
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
           OR (COALESCE(IS_ROLEMEMBER(N''teabar_customer''), 0) = 0
               AND COALESCE(IS_ROLEMEMBER(N''teabar_member''), 0) = 0)
            THROW 52000, N''当前购买身份未绑定或无下单权限。'', 1;
        IF @payment_succeeded IS NULL OR @payment_succeeded <> 1
            THROW 52001, N''模拟支付未成功，不创建正式订单。'', 1;
        IF @order_id IS NULL OR LEN(LTRIM(RTRIM(@order_id))) = 0 OR NOT EXISTS (SELECT 1 FROM @items)
            THROW 52002, N''订单编号及至少一条明细必须提供。'', 1;
        IF EXISTS (SELECT 1 FROM @items WHERE quantity <= 0 OR LEN(LTRIM(RTRIM(item_id))) = 0)
            THROW 52003, N''明细编号不能为空白，数量必须大于0。'', 1;
        IF EXISTS (SELECT 1 FROM @specs AS x WHERE NOT EXISTS (SELECT 1 FROM @items AS i WHERE i.item_id = x.item_id))
           OR EXISTS (SELECT 1 FROM @addons AS x WHERE NOT EXISTS (SELECT 1 FROM @items AS i WHERE i.item_id = x.item_id))
            THROW 52004, N''规格或加料引用了本次订单之外的明细。'', 1;

        DECLARE @prices TABLE (
            item_id VARCHAR(10) PRIMARY KEY, product_id VARCHAR(10), product_name NVARCHAR(50),
            quantity INT, base_price DECIMAL(10,2), unit_price DECIMAL(10,2)
        );
        INSERT @prices(item_id, product_id, product_name, quantity, base_price)
        SELECT i.item_id, i.product_id, p.product_name, i.quantity, p.base_price
        FROM @items AS i JOIN dbo.Product AS p WITH (UPDLOCK, HOLDLOCK) ON p.product_id = i.product_id
        WHERE p.status = N''在售'';
        IF (SELECT COUNT(*) FROM @prices) <> (SELECT COUNT(*) FROM @items)
            THROW 52005, N''商品不存在或未在售。'', 1;

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
            THROW 52006, N''商品尚未配置规格，不能直接按默认系数下单。'', 1;
        IF EXISTS (
            SELECT 1 FROM @specs AS x JOIN @prices AS i ON i.item_id = x.item_id
            WHERE NOT EXISTS (SELECT 1 FROM @configuration AS c WHERE c.product_id = i.product_id AND c.spec_id = x.spec_id AND c.status = N''可用'')
        )
            THROW 52007, N''所选规格不适用于该商品或已停用。'', 1;
        DECLARE @chosen TABLE (
            item_id VARCHAR(10), spec_type NVARCHAR(20), spec_id VARCHAR(10),
            spec_name NVARCHAR(20), price_delta DECIMAL(10,2)
        );
        INSERT @chosen
        SELECT x.item_id, c.spec_type, c.spec_id, c.spec_name, c.price_delta
        FROM @specs AS x JOIN @prices AS i ON i.item_id = x.item_id
        JOIN @configuration AS c ON c.product_id = i.product_id AND c.spec_id = x.spec_id;
        IF EXISTS (SELECT item_id, spec_type FROM @chosen GROUP BY item_id, spec_type HAVING COUNT(*) > 1)
            THROW 52008, N''同一明细同一规格类型只能选择一个选项。'', 1;
        IF EXISTS (
            SELECT i.item_id, c.spec_type FROM @prices AS i JOIN @configuration AS c ON c.product_id = i.product_id
            EXCEPT SELECT item_id, spec_type FROM @chosen
        )
            THROW 52009, N''每种已配置的规格类型必须明确选择一个，默认选项也必须传入。'', 1;

        DECLARE @extras TABLE (
            item_id VARCHAR(10), addon_id VARCHAR(10), addon_name NVARCHAR(50),
            price DECIMAL(10,2), ingredient_id VARCHAR(10), extra_amount DECIMAL(10,2)
        );
        INSERT @extras
        SELECT x.item_id, a.addon_id, a.addon_name, a.price, a.ingredient_id, a.extra_amount
        FROM @addons AS x JOIN dbo.AddOn AS a WITH (UPDLOCK, HOLDLOCK) ON a.addon_id = x.addon_id
        WHERE a.status = N''可用'';
        IF (SELECT COUNT(*) FROM @extras) <> (SELECT COUNT(*) FROM @addons)
            THROW 52010, N''加料不存在或缺货。'', 1;
        UPDATE i SET unit_price = i.base_price
            + COALESCE((SELECT SUM(c.price_delta) FROM @chosen AS c WHERE c.item_id = i.item_id), 0)
            + COALESCE((SELECT SUM(a.price) FROM @extras AS a WHERE a.item_id = i.item_id), 0)
        FROM @prices AS i;
        IF EXISTS (SELECT 1 FROM @prices WHERE unit_price < 0)
            THROW 52011, N''规格差价可以为负，但最终成交单价不能为负。'', 1;

        DECLARE @recipe TABLE (
            product_id VARCHAR(10), ingredient_id VARCHAR(10), base_amount DECIMAL(10,2),
            PRIMARY KEY(product_id, ingredient_id)
        );
        INSERT @recipe
        SELECT r.product_id, r.ingredient_id, r.base_amount
        FROM dbo.Recipe AS r WITH (UPDLOCK, HOLDLOCK) WHERE r.product_id IN (SELECT product_id FROM @prices);
        IF EXISTS (SELECT 1 FROM @prices AS i WHERE NOT EXISTS (SELECT 1 FROM @recipe AS r WHERE r.product_id = i.product_id))
            THROW 52012, N''商品缺少基础配方。'', 1;
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
            THROW 52013, N''规格规则引用了配方外原料。'', 1;

        DECLARE @raw TABLE (
            item_id VARCHAR(10), ingredient_id VARCHAR(10), per_cup DECIMAL(27,8), quantity INT
        );
        ;WITH Choices AS (
            SELECT i.item_id,
                (SELECT spec_id FROM @chosen WHERE item_id = i.item_id AND spec_type = N''糖度'') AS sugar,
                (SELECT spec_id FROM @chosen WHERE item_id = i.item_id AND spec_type = N''温度'') AS temperature,
                (SELECT spec_id FROM @chosen WHERE item_id = i.item_id AND spec_type = N''杯型'') AS cup
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
            WHERE g.unit = N''个'' AND r.per_cup <> FLOOR(r.per_cup)
        ) OR EXISTS (
            SELECT 1 FROM @recipe AS r JOIN dbo.Ingredient AS g WITH (HOLDLOCK) ON g.ingredient_id = r.ingredient_id
            WHERE g.unit = N''个'' AND r.base_amount <> FLOOR(r.base_amount)
        )
            THROW 52014, N''计件原料每杯用量必须为整数，不能靠杯数或四舍五入掩盖。'', 1;
        DECLARE @consumption TABLE (
            item_id VARCHAR(10), ingredient_id VARCHAR(10), amount DECIMAL(10,2),
            PRIMARY KEY(item_id, ingredient_id)
        );
        INSERT @consumption
        SELECT item_id, ingredient_id, CAST(ROUND(SUM(per_cup * quantity), 2) AS DECIMAL(10,2))
        FROM @raw GROUP BY item_id, ingredient_id
        HAVING ROUND(SUM(per_cup * quantity), 2) > 0;
        DECLARE @needed TABLE (ingredient_id VARCHAR(10) PRIMARY KEY, amount DECIMAL(10,2));
        INSERT @needed SELECT ingredient_id, SUM(amount) FROM @consumption GROUP BY ingredient_id;
        IF NOT EXISTS (SELECT 1 FROM @needed)
            THROW 52015, N''配方未产生有效原料需求。'', 1;
        DECLARE @needed_count INT = (SELECT COUNT(*) FROM @needed);
        UPDATE g WITH (UPDLOCK, HOLDLOCK) SET stock = g.stock - n.amount
        FROM dbo.Ingredient AS g JOIN @needed AS n ON n.ingredient_id = g.ingredient_id
        WHERE g.status = N''可用'' AND g.stock >= n.amount;
        IF @@ROWCOUNT <> @needed_count
            THROW 52016, N''整笔订单库存不足或原料缺货，下单全部回滚。'', 1;

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
            THROW 52017, N''订单总额与明细不一致。'', 1;
        SELECT @order_id AS order_id, @total AS total_amount, N''排队中'' AS status;
        IF @own_transaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_transaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @own_transaction = 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION role_operation;
        THROW;
    END CATCH;
END;');

    -- usp_AdvanceOrder
    EXEC(N'CREATE OR ALTER PROCEDURE teabar_api.usp_AdvanceOrder
    @order_id VARCHAR(10), @next_status NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    DECLARE @own_transaction BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    IF @own_transaction = 1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION role_operation;
    BEGIN TRY
        IF COALESCE(IS_ROLEMEMBER(N''teabar_clerk''), 0) <> 1
           AND COALESCE(IS_ROLEMEMBER(N''teabar_manager''), 0) <> 1
            THROW 52101, N''仅店员或店长可以执行此操作。'', 1;
        DECLARE @old NVARCHAR(20), @member_id VARCHAR(10), @total DECIMAL(10,2);
        SELECT @old = status, @member_id = member_id, @total = total_amount
        FROM dbo.SalesOrder WITH (UPDLOCK, HOLDLOCK) WHERE order_id = @order_id;
        IF @old IS NULL OR (
            COALESCE(IS_ROLEMEMBER(N''teabar_manager''), 0) = 0
            AND NOT EXISTS (SELECT 1 FROM teabar_api.vw_WorkOrders WHERE order_id = @order_id)
        )
            THROW 52102, N''订单不存在或不在当前工作查询范围。'', 1;
        IF @next_status IS NULL OR NOT (
            (@old = N''排队中'' AND @next_status = N''制作中'')
            OR (@old = N''制作中'' AND @next_status = N''待取餐'')
            OR (@old = N''待取餐'' AND @next_status = N''已完成'')
        )
            THROW 52103, N''只能按排队中、制作中、待取餐、已完成依次流转，不能跳步或重复完成。'', 1;
        UPDATE dbo.SalesOrder SET status = @next_status WHERE order_id = @order_id AND status = @old;
        IF @@ROWCOUNT <> 1 THROW 52104, N''订单状态已变化，请重新查询。'', 1;
        IF @next_status = N''已完成'' AND @member_id IS NOT NULL
            UPDATE dbo.Member SET points = points + CONVERT(INT, FLOOR(@total)) WHERE member_id = @member_id;
        SELECT @order_id AS order_id, @next_status AS status;
        IF @own_transaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_transaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @own_transaction = 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION role_operation;
        THROW;
    END CATCH;
END;');

    -- usp_RefundOrder
    EXEC(N'CREATE OR ALTER PROCEDURE teabar_api.usp_RefundOrder
    @order_id VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    DECLARE @own_transaction BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    IF @own_transaction = 1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION role_operation;
    BEGIN TRY
        DECLARE @member_id VARCHAR(10), @guest_id UNIQUEIDENTIFIER, @old NVARCHAR(20);
        DECLARE @staff BIT = CASE WHEN COALESCE(IS_ROLEMEMBER(N''teabar_clerk''), 0) = 1
            OR COALESCE(IS_ROLEMEMBER(N''teabar_manager''), 0) = 1 THEN 1 ELSE 0 END;
        SELECT @member_id = member_id, @guest_id = guest_id FROM teabar_auth.fn_CurrentIdentity();
        IF @staff = 0 AND NOT EXISTS (
            SELECT 1 FROM teabar_api.vw_MyOrders WHERE order_id = @order_id
        )
            THROW 52105, N''只能退款本人订单。'', 1;
        IF @staff = 1 AND COALESCE(IS_ROLEMEMBER(N''teabar_manager''), 0) = 0
           AND NOT EXISTS (SELECT 1 FROM teabar_api.vw_WorkOrders WHERE order_id = @order_id)
            THROW 52102, N''订单不在当前工作查询范围。'', 1;
        SELECT @old = status FROM dbo.SalesOrder WITH (UPDLOCK, HOLDLOCK) WHERE order_id = @order_id;
        IF @old IS NULL OR @old <> N''排队中''
            THROW 52106, N''仅排队中的订单允许退款；已取消订单不能重复返库。'', 1;
        DECLARE @return_stock TABLE (ingredient_id VARCHAR(10) PRIMARY KEY, amount DECIMAL(10,2));
        INSERT @return_stock
        SELECT c.ingredient_id, SUM(c.amount)
        FROM dbo.OrderItemIngredient AS c JOIN dbo.OrderItem AS i ON i.item_id = c.item_id
        WHERE i.order_id = @order_id GROUP BY c.ingredient_id;
        IF NOT EXISTS (SELECT 1 FROM @return_stock)
            THROW 52107, N''订单缺少付款时的原料消耗快照，不能重读当前配方返库。'', 1;
        UPDATE g SET stock = g.stock + r.amount
        FROM dbo.Ingredient AS g JOIN @return_stock AS r ON r.ingredient_id = g.ingredient_id;
        IF @@ROWCOUNT <> (SELECT COUNT(*) FROM @return_stock)
            THROW 52108, N''退款涉及的原料记录不完整。'', 1;
        UPDATE dbo.SalesOrder SET status = N''已取消'' WHERE order_id = @order_id AND status = N''排队中'';
        IF @@ROWCOUNT <> 1 THROW 52104, N''订单状态已变化，请重新查询。'', 1;
        SELECT @order_id AS order_id, N''已取消'' AS status;
        IF @own_transaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_transaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @own_transaction = 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION role_operation;
        THROW;
    END CATCH;
END;');

    -- usp_AdjustStock
    EXEC(N'CREATE OR ALTER PROCEDURE teabar_api.usp_AdjustStock
    @ingredient_id VARCHAR(10), @operation NVARCHAR(10), @amount DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    DECLARE @own_transaction BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    IF @own_transaction = 1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION role_operation;
    BEGIN TRY
        IF COALESCE(IS_ROLEMEMBER(N''teabar_manager''), 0) <> 1
            THROW 52100, N''仅店长角色可以执行此管理操作。'', 1;
        DECLARE @unit NVARCHAR(10);
        SELECT @unit = unit FROM dbo.Ingredient WITH (UPDLOCK, HOLDLOCK) WHERE ingredient_id = @ingredient_id;
        IF @unit IS NULL THROW 52109, N''原料不存在。'', 1;
        IF @amount IS NULL OR @operation IS NULL OR @operation NOT IN (N''补库'', N''盘点'')
           OR (@operation = N''补库'' AND @amount <= 0)
           OR (@operation = N''盘点'' AND @amount < 0)
            THROW 52110, N''补库数量须大于0；盘点实际库存须非负。'', 1;
        IF @unit = N''个'' AND @amount <> FLOOR(@amount)
            THROW 52111, N''计件原料的补库、盘点数量必须为整数。'', 1;
        UPDATE dbo.Ingredient SET stock = CASE @operation WHEN N''补库'' THEN stock + @amount ELSE @amount END
            WHERE ingredient_id = @ingredient_id;
        SELECT ingredient_id, stock, unit FROM dbo.Ingredient WHERE ingredient_id = @ingredient_id;
        IF @own_transaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_transaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @own_transaction = 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION role_operation;
        THROW;
    END CATCH;
END;');

    -- usp_SaveMember
    EXEC(N'CREATE OR ALTER PROCEDURE teabar_api.usp_SaveMember
    @member_id VARCHAR(10), @name NVARCHAR(50), @phone VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    DECLARE @own_transaction BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    IF @own_transaction = 1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION role_operation;
    BEGIN TRY
        IF COALESCE(IS_ROLEMEMBER(N''teabar_clerk''), 0) <> 1
           AND COALESCE(IS_ROLEMEMBER(N''teabar_manager''), 0) <> 1
            THROW 52101, N''仅店员或店长可以执行此操作。'', 1;
        -- 新建积分为0；更新仅改姓名、手机号，参数中没有积分。
        IF EXISTS (SELECT 1 FROM dbo.Member WITH (UPDLOCK, HOLDLOCK) WHERE member_id = @member_id)
            UPDATE dbo.Member SET name = @name, phone = @phone WHERE member_id = @member_id;
        ELSE INSERT dbo.Member(member_id, name, phone, points) VALUES(@member_id, @name, @phone, 0);
        IF @own_transaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_transaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @own_transaction = 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION role_operation;
        THROW;
    END CATCH;
END;');

    -- usp_FindMember
    EXEC(N'CREATE OR ALTER PROCEDURE teabar_api.usp_FindMember
    @phone VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    DECLARE @own_transaction BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    IF @own_transaction = 1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION role_operation;
    BEGIN TRY
        IF COALESCE(IS_ROLEMEMBER(N''teabar_clerk''), 0) <> 1
           AND COALESCE(IS_ROLEMEMBER(N''teabar_manager''), 0) <> 1
            THROW 52101, N''仅店员或店长可以执行此操作。'', 1;
        SELECT member_id, name, phone, points FROM dbo.Member WHERE phone = @phone;
        IF @own_transaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_transaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @own_transaction = 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION role_operation;
        THROW;
    END CATCH;
END;');

    -- usp_SaveProduct
    EXEC(N'CREATE OR ALTER PROCEDURE teabar_api.usp_SaveProduct
    @product_id VARCHAR(10), @product_name NVARCHAR(50), @base_price DECIMAL(10,2),
    @status NVARCHAR(10), @description NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    DECLARE @own_transaction BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    IF @own_transaction = 1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION role_operation;
    BEGIN TRY
        IF COALESCE(IS_ROLEMEMBER(N''teabar_manager''), 0) <> 1
            THROW 52100, N''仅店长角色可以执行此管理操作。'', 1;
        IF @status = N''在售'' AND (
            NOT EXISTS (SELECT 1 FROM dbo.Recipe WITH (HOLDLOCK) WHERE product_id = @product_id)
            OR NOT EXISTS (SELECT 1 FROM dbo.ProductSpecification WITH (HOLDLOCK) WHERE product_id = @product_id AND status = N''可用'')
            OR EXISTS (
                SELECT s.spec_type FROM dbo.ProductSpecification AS ps WITH (HOLDLOCK)
                JOIN dbo.Specification AS s ON s.spec_id = ps.spec_id
                WHERE ps.product_id = @product_id GROUP BY s.spec_type
                HAVING SUM(CASE WHEN ps.status = N''可用'' THEN 1 ELSE 0 END) = 0
            )
        )
            THROW 52112, N''商品上架前须有基础配方及各已配置类型的可用规格。'', 1;
        IF EXISTS (SELECT 1 FROM dbo.Product WITH (UPDLOCK, HOLDLOCK) WHERE product_id = @product_id)
            UPDATE dbo.Product SET product_name = @product_name, base_price = @base_price, status = @status, description = @description
                WHERE product_id = @product_id;
        ELSE INSERT dbo.Product(product_id, product_name, base_price, status, description)
            VALUES(@product_id, @product_name, @base_price, @status, @description);
        IF @own_transaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_transaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @own_transaction = 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION role_operation;
        THROW;
    END CATCH;
END;');

    -- usp_SaveIngredient
    EXEC(N'CREATE OR ALTER PROCEDURE teabar_api.usp_SaveIngredient
    @ingredient_id VARCHAR(10), @ingredient_name NVARCHAR(50), @unit NVARCHAR(10), @status NVARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    DECLARE @own_transaction BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    IF @own_transaction = 1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION role_operation;
    BEGIN TRY
        IF COALESCE(IS_ROLEMEMBER(N''teabar_manager''), 0) <> 1
            THROW 52100, N''仅店长角色可以执行此管理操作。'', 1;
        DECLARE @old_unit NVARCHAR(10), @stock DECIMAL(10,2);
        SELECT @old_unit = unit, @stock = stock FROM dbo.Ingredient WITH (UPDLOCK, HOLDLOCK)
            WHERE ingredient_id = @ingredient_id;
        IF @old_unit IS NOT NULL AND @old_unit <> @unit AND (
            @stock <> 0
            OR EXISTS (SELECT 1 FROM dbo.Recipe WHERE ingredient_id = @ingredient_id)
            OR EXISTS (SELECT 1 FROM dbo.AddOn WHERE ingredient_id = @ingredient_id)
            OR EXISTS (SELECT 1 FROM dbo.OrderItemIngredient WHERE ingredient_id = @ingredient_id)
        )
            THROW 52113, N''非零库存或已被引用的原料不能直接更改计量单位。'', 1;
        IF @old_unit IS NULL
            INSERT dbo.Ingredient(ingredient_id, ingredient_name, unit, status)
                VALUES(@ingredient_id, @ingredient_name, @unit, @status);
        ELSE UPDATE dbo.Ingredient SET ingredient_name = @ingredient_name, unit = @unit, status = @status
            WHERE ingredient_id = @ingredient_id;
        IF @own_transaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_transaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @own_transaction = 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION role_operation;
        THROW;
    END CATCH;
END;');

    -- usp_SaveEmployee
    EXEC(N'CREATE OR ALTER PROCEDURE teabar_api.usp_SaveEmployee
    @employee_id VARCHAR(10), @name NVARCHAR(50), @status NVARCHAR(10),
    @salary DECIMAL(10,2), @role NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    DECLARE @own_transaction BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    IF @own_transaction = 1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION role_operation;
    BEGIN TRY
        IF COALESCE(IS_ROLEMEMBER(N''teabar_manager''), 0) <> 1
            THROW 52100, N''仅店长角色可以执行此管理操作。'', 1;
        -- 仅更新业务资料；数据库管理员另行维护角色成员及离职账户。
        IF EXISTS (SELECT 1 FROM dbo.Employee WITH (UPDLOCK, HOLDLOCK) WHERE employee_id = @employee_id)
            UPDATE dbo.Employee SET name = @name, status = @status, salary = @salary, role = @role WHERE employee_id = @employee_id;
        ELSE INSERT dbo.Employee(employee_id, name, status, salary, role)
            VALUES(@employee_id, @name, @status, @salary, @role);
        IF @own_transaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_transaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @own_transaction = 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION role_operation;
        THROW;
    END CATCH;
END;');

    -- usp_SaveSpecification
    EXEC(N'CREATE OR ALTER PROCEDURE teabar_api.usp_SaveSpecification
    @spec_id VARCHAR(10), @spec_type NVARCHAR(20), @spec_name NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    DECLARE @own_transaction BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    IF @own_transaction = 1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION role_operation;
    BEGIN TRY
        IF COALESCE(IS_ROLEMEMBER(N''teabar_manager''), 0) <> 1
            THROW 52100, N''仅店长角色可以执行此管理操作。'', 1;
        DECLARE @old_type NVARCHAR(20);
        SELECT @old_type = spec_type FROM dbo.Specification WITH (UPDLOCK, HOLDLOCK) WHERE spec_id = @spec_id;
        IF @old_type IS NOT NULL AND @old_type <> @spec_type AND (
            EXISTS (SELECT 1 FROM dbo.ProductSpecification WHERE spec_id = @spec_id)
            OR EXISTS (SELECT 1 FROM dbo.ItemSpec WHERE spec_id = @spec_id)
        )
            THROW 52114, N''已使用的规格不能直接更换类型。'', 1;
        IF @old_type IS NULL INSERT dbo.Specification(spec_id, spec_type, spec_name) VALUES(@spec_id, @spec_type, @spec_name);
        ELSE UPDATE dbo.Specification SET spec_type = @spec_type, spec_name = @spec_name WHERE spec_id = @spec_id;
        IF @own_transaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_transaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @own_transaction = 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION role_operation;
        THROW;
    END CATCH;
END;');

    -- usp_SaveProductSpecification
    EXEC(N'CREATE OR ALTER PROCEDURE teabar_api.usp_SaveProductSpecification
    @product_id VARCHAR(10), @spec_id VARCHAR(10), @price_delta DECIMAL(10,2), @status NVARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    DECLARE @own_transaction BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    IF @own_transaction = 1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION role_operation;
    BEGIN TRY
        IF COALESCE(IS_ROLEMEMBER(N''teabar_manager''), 0) <> 1
            THROW 52100, N''仅店长角色可以执行此管理操作。'', 1;
        -- 同商品的启用操作串行执行，防止两个会话各自检查后启用非法组合。
        IF NOT EXISTS (SELECT 1 FROM dbo.Product WITH (UPDLOCK, HOLDLOCK) WHERE product_id = @product_id)
            THROW 52122, N''商品不存在，不能维护商品规格配置。'', 1;
        IF @status = N''可用'' AND NOT EXISTS (SELECT 1 FROM dbo.Recipe WITH (HOLDLOCK) WHERE product_id = @product_id)
            THROW 52115, N''规格启用前商品须有基础配方。'', 1;
        IF @status = N''可用'' AND EXISTS (
            SELECT 1 FROM dbo.Recipe AS r JOIN dbo.Ingredient AS g ON g.ingredient_id = r.ingredient_id
            LEFT JOIN dbo.SpecificationIngredient AS x
              ON x.product_id = r.product_id AND x.ingredient_id = r.ingredient_id AND x.spec_id = @spec_id
            WHERE r.product_id = @product_id AND g.unit = N''个''
              AND r.base_amount * COALESCE(x.factor, 1) <> FLOOR(r.base_amount * COALESCE(x.factor, 1))
        )
            THROW 52116, N''规格启用后不能产生非整数计件用量。'', 1;
        IF EXISTS (SELECT 1 FROM dbo.ProductSpecification WITH (UPDLOCK, HOLDLOCK) WHERE product_id = @product_id AND spec_id = @spec_id)
            UPDATE dbo.ProductSpecification SET price_delta = @price_delta, status = @status
                WHERE product_id = @product_id AND spec_id = @spec_id;
        ELSE INSERT dbo.ProductSpecification(product_id, spec_id, price_delta, status)
            VALUES(@product_id, @spec_id, @price_delta, @status);
        IF @status = N''可用''
        BEGIN
            -- 包含本次启用的选项，每种类型各取一个，检查全部可购买组合。
            -- 尚无可用选项的类型暂按系数1检查；同类型选项不会互相相乘。
            DECLARE @invalid_piece_combination BIT = 0;
            ;WITH EnabledOptions AS (
                SELECT ps.spec_id, s.spec_type
                FROM dbo.ProductSpecification AS ps WITH (UPDLOCK, HOLDLOCK)
                JOIN dbo.Specification AS s WITH (HOLDLOCK) ON s.spec_id = ps.spec_id
                WHERE ps.product_id = @product_id AND ps.status = N''可用''
            )
            SELECT @invalid_piece_combination = 1
            FROM dbo.Recipe AS r WITH (HOLDLOCK)
            JOIN dbo.Ingredient AS g WITH (HOLDLOCK) ON g.ingredient_id = r.ingredient_id
            LEFT JOIN EnabledOptions AS sugar ON sugar.spec_type = N''糖度''
            LEFT JOIN EnabledOptions AS temperature ON temperature.spec_type = N''温度''
            LEFT JOIN EnabledOptions AS cup ON cup.spec_type = N''杯型''
            LEFT JOIN dbo.SpecificationIngredient AS sf WITH (HOLDLOCK)
              ON sf.product_id = r.product_id AND sf.spec_id = sugar.spec_id AND sf.ingredient_id = r.ingredient_id
            LEFT JOIN dbo.SpecificationIngredient AS tf WITH (HOLDLOCK)
              ON tf.product_id = r.product_id AND tf.spec_id = temperature.spec_id AND tf.ingredient_id = r.ingredient_id
            LEFT JOIN dbo.SpecificationIngredient AS cf WITH (HOLDLOCK)
              ON cf.product_id = r.product_id AND cf.spec_id = cup.spec_id AND cf.ingredient_id = r.ingredient_id
            CROSS APPLY (SELECT r.base_amount * COALESCE(sf.factor, 1)
                         * COALESCE(tf.factor, 1) * COALESCE(cf.factor, 1) AS per_cup) AS demand
            WHERE r.product_id = @product_id AND g.unit = N''个''
              AND demand.per_cup <> FLOOR(demand.per_cup);
            IF @invalid_piece_combination = 1
                THROW 52116, N''规格组合启用后不能产生非整数计件用量。'', 1;
        END;
        IF @own_transaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_transaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @own_transaction = 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION role_operation;
        THROW;
    END CATCH;
END;');

    -- usp_SaveRecipe
    EXEC(N'CREATE OR ALTER PROCEDURE teabar_api.usp_SaveRecipe
    @product_id VARCHAR(10), @ingredient_id VARCHAR(10), @base_amount DECIMAL(10,2) = NULL,
    @remove BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    DECLARE @own_transaction BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    IF @own_transaction = 1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION role_operation;
    BEGIN TRY
        IF COALESCE(IS_ROLEMEMBER(N''teabar_manager''), 0) <> 1
            THROW 52100, N''仅店长角色可以执行此管理操作。'', 1;
        DECLARE @unit NVARCHAR(10);
        SELECT @unit = unit FROM dbo.Ingredient WITH (UPDLOCK, HOLDLOCK) WHERE ingredient_id = @ingredient_id;
        IF @remove IS NULL THROW 52117, N''是否移除配方必须明确指定。'', 1;
        IF @remove = 0 AND @unit = N''个'' AND @base_amount <> FLOOR(@base_amount)
            THROW 52116, N''计件原料的基础配方用量必须为整数。'', 1;
        -- 配方变更后停用商品规格，完成规则审查后再逐项启用。
        UPDATE dbo.ProductSpecification SET status = N''停用'' WHERE product_id = @product_id;
        IF @remove = 1
        BEGIN
            DELETE dbo.SpecificationIngredient WHERE product_id = @product_id AND ingredient_id = @ingredient_id;
            DELETE dbo.Recipe WHERE product_id = @product_id AND ingredient_id = @ingredient_id;
        END
        ELSE IF EXISTS (SELECT 1 FROM dbo.Recipe WITH (UPDLOCK, HOLDLOCK) WHERE product_id = @product_id AND ingredient_id = @ingredient_id)
            UPDATE dbo.Recipe SET base_amount = @base_amount WHERE product_id = @product_id AND ingredient_id = @ingredient_id;
        ELSE INSERT dbo.Recipe(product_id, ingredient_id, base_amount) VALUES(@product_id, @ingredient_id, @base_amount);
        IF @own_transaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_transaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @own_transaction = 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION role_operation;
        THROW;
    END CATCH;
END;');

    -- usp_SaveSpecificationIngredient
    EXEC(N'CREATE OR ALTER PROCEDURE teabar_api.usp_SaveSpecificationIngredient
    @product_id VARCHAR(10), @spec_id VARCHAR(10), @ingredient_id VARCHAR(10),
    @factor DECIMAL(5,2) = NULL, @remove BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    DECLARE @own_transaction BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    IF @own_transaction = 1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION role_operation;
    BEGIN TRY
        IF COALESCE(IS_ROLEMEMBER(N''teabar_manager''), 0) <> 1
            THROW 52100, N''仅店长角色可以执行此管理操作。'', 1;
        IF @remove IS NULL THROW 52117, N''是否移除规则必须明确指定。'', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.ProductSpecification WITH (UPDLOCK, HOLDLOCK)
            WHERE product_id = @product_id AND spec_id = @spec_id AND status = N''停用'')
            THROW 52118, N''修改原料系数前须先停用对应商品规格配置。'', 1;
        IF @remove = 1 DELETE dbo.SpecificationIngredient
            WHERE product_id = @product_id AND spec_id = @spec_id AND ingredient_id = @ingredient_id;
        ELSE
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.Recipe AS r JOIN dbo.Ingredient AS g ON g.ingredient_id = r.ingredient_id
                WHERE r.product_id = @product_id AND r.ingredient_id = @ingredient_id AND g.unit = N''个''
                  AND r.base_amount * @factor <> FLOOR(r.base_amount * @factor))
                THROW 52116, N''规则不能产生非整数计件用量。'', 1;
            IF EXISTS (SELECT 1 FROM dbo.SpecificationIngredient WITH (UPDLOCK, HOLDLOCK)
                WHERE product_id = @product_id AND spec_id = @spec_id AND ingredient_id = @ingredient_id)
                UPDATE dbo.SpecificationIngredient SET factor = @factor
                    WHERE product_id = @product_id AND spec_id = @spec_id AND ingredient_id = @ingredient_id;
            ELSE INSERT dbo.SpecificationIngredient(product_id, spec_id, ingredient_id, factor)
                VALUES(@product_id, @spec_id, @ingredient_id, @factor);
        END;
        IF @own_transaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_transaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @own_transaction = 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION role_operation;
        THROW;
    END CATCH;
END;');

    -- usp_SaveAddOn
    EXEC(N'CREATE OR ALTER PROCEDURE teabar_api.usp_SaveAddOn
    @addon_id VARCHAR(10), @addon_name NVARCHAR(50), @price DECIMAL(10,2),
    @ingredient_id VARCHAR(10), @extra_amount DECIMAL(10,2), @status NVARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    DECLARE @own_transaction BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    IF @own_transaction = 1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION role_operation;
    BEGIN TRY
        IF COALESCE(IS_ROLEMEMBER(N''teabar_manager''), 0) <> 1
            THROW 52100, N''仅店长角色可以执行此管理操作。'', 1;
        IF EXISTS (SELECT 1 FROM dbo.Ingredient WITH (HOLDLOCK) WHERE ingredient_id = @ingredient_id
            AND unit = N''个'' AND @extra_amount <> FLOOR(@extra_amount))
            THROW 52116, N''计件加料每份用量必须为整数。'', 1;
        IF EXISTS (SELECT 1 FROM dbo.AddOn WITH (UPDLOCK, HOLDLOCK) WHERE addon_id = @addon_id)
            UPDATE dbo.AddOn SET addon_name = @addon_name, price = @price, ingredient_id = @ingredient_id,
                extra_amount = @extra_amount, status = @status WHERE addon_id = @addon_id;
        ELSE INSERT dbo.AddOn(addon_id, addon_name, price, ingredient_id, extra_amount, status)
            VALUES(@addon_id, @addon_name, @price, @ingredient_id, @extra_amount, @status);
        IF @own_transaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_transaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @own_transaction = 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION role_operation;
        THROW;
    END CATCH;
END;');

    -- usp_SaveDutyRoster
    EXEC(N'CREATE OR ALTER PROCEDURE teabar_api.usp_SaveDutyRoster
    @duty_id VARCHAR(10), @employee_id VARCHAR(10), @start_time DATETIME2(0), @end_time DATETIME2(0)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    DECLARE @own_transaction BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    IF @own_transaction = 1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION role_operation;
    BEGIN TRY
        IF COALESCE(IS_ROLEMEMBER(N''teabar_manager''), 0) <> 1
            THROW 52100, N''仅店长角色可以执行此管理操作。'', 1;
        IF @start_time IS NULL OR @end_time IS NULL OR @start_time >= @end_time
            THROW 52119, N''值班开始必须早于结束。'', 1;
        -- 锁定员工行使同一员工的排班维护串行化，不限制不同员工同时值班。
        IF NOT EXISTS (SELECT 1 FROM dbo.Employee WITH (UPDLOCK, HOLDLOCK)
            WHERE employee_id = @employee_id AND status = N''在职'')
            THROW 52120, N''只能为在职员工新增或修改排班。'', 1;
        IF EXISTS (SELECT 1 FROM dbo.DutyRoster WITH (UPDLOCK, HOLDLOCK)
            WHERE employee_id = @employee_id AND duty_id <> @duty_id
              AND start_time < @end_time AND @start_time < end_time)
            THROW 52121, N''同一员工的值班区间不能重叠；首尾相接允许。'', 1;
        IF EXISTS (SELECT 1 FROM dbo.DutyRoster WITH (UPDLOCK, HOLDLOCK) WHERE duty_id = @duty_id)
            UPDATE dbo.DutyRoster SET employee_id = @employee_id, start_time = @start_time, end_time = @end_time WHERE duty_id = @duty_id;
        ELSE INSERT dbo.DutyRoster(duty_id, employee_id, start_time, end_time)
            VALUES(@duty_id, @employee_id, @start_time, @end_time);
        IF @own_transaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_transaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @own_transaction = 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION role_operation;
        THROW;
    END CATCH;
END;');

    -- 原始业务表：所有角色禁止直接写入；顾客/会员/店员也不能直接读取整表。
    DECLARE permission_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT r.name, t.name FROM @roles AS r CROSS JOIN @business_tables AS t;
    DECLARE @table SYSNAME;
    OPEN permission_cursor;
    FETCH NEXT FROM permission_cursor INTO @role, @table;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @command = N'DENY INSERT, UPDATE, DELETE ON OBJECT::dbo.' + QUOTENAME(@table) + N' TO ' + QUOTENAME(@role) + N';';
        EXEC sys.sp_executesql @command;
        SET @command = CASE WHEN @role = N'teabar_manager' THEN N'GRANT' ELSE N'DENY' END
            + N' SELECT ON OBJECT::dbo.' + QUOTENAME(@table) + N' TO ' + QUOTENAME(@role) + N';';
        EXEC sys.sp_executesql @command;
        FETCH NEXT FROM permission_cursor INTO @role, @table;
    END;
    CLOSE permission_cursor;
    DEALLOCATE permission_cursor;

    GRANT SELECT ON OBJECT::teabar_api.vw_Menu TO teabar_customer;
    GRANT SELECT ON OBJECT::teabar_api.vw_AvailableSpecifications TO teabar_customer;
    GRANT SELECT ON OBJECT::teabar_api.vw_AvailableAddOns TO teabar_customer;
    GRANT SELECT ON OBJECT::teabar_api.vw_Menu TO teabar_member;
    GRANT SELECT ON OBJECT::teabar_api.vw_AvailableSpecifications TO teabar_member;
    GRANT SELECT ON OBJECT::teabar_api.vw_AvailableAddOns TO teabar_member;
    GRANT SELECT ON OBJECT::teabar_api.vw_Menu TO teabar_clerk;
    GRANT SELECT ON OBJECT::teabar_api.vw_AvailableSpecifications TO teabar_clerk;
    GRANT SELECT ON OBJECT::teabar_api.vw_AvailableAddOns TO teabar_clerk;
    GRANT SELECT ON OBJECT::teabar_api.vw_Menu TO teabar_manager;
    GRANT SELECT ON OBJECT::teabar_api.vw_AvailableSpecifications TO teabar_manager;
    GRANT SELECT ON OBJECT::teabar_api.vw_AvailableAddOns TO teabar_manager;
    GRANT SELECT ON OBJECT::teabar_api.vw_MyOrders TO teabar_customer;
    GRANT SELECT ON OBJECT::teabar_api.vw_MyOrderItems TO teabar_customer;
    GRANT SELECT ON OBJECT::teabar_api.vw_MyItemSpecs TO teabar_customer;
    GRANT SELECT ON OBJECT::teabar_api.vw_MyItemAddOns TO teabar_customer;
    GRANT EXECUTE ON OBJECT::teabar_api.usp_PlacePaidOrder TO teabar_customer;
    GRANT EXECUTE, REFERENCES ON TYPE::teabar_api.OrderLines TO teabar_customer;
    GRANT EXECUTE, REFERENCES ON TYPE::teabar_api.OrderSpecs TO teabar_customer;
    GRANT EXECUTE, REFERENCES ON TYPE::teabar_api.OrderAddOns TO teabar_customer;
    GRANT SELECT ON OBJECT::teabar_api.vw_MyOrders TO teabar_member;
    GRANT SELECT ON OBJECT::teabar_api.vw_MyOrderItems TO teabar_member;
    GRANT SELECT ON OBJECT::teabar_api.vw_MyItemSpecs TO teabar_member;
    GRANT SELECT ON OBJECT::teabar_api.vw_MyItemAddOns TO teabar_member;
    GRANT EXECUTE ON OBJECT::teabar_api.usp_PlacePaidOrder TO teabar_member;
    GRANT EXECUTE, REFERENCES ON TYPE::teabar_api.OrderLines TO teabar_member;
    GRANT EXECUTE, REFERENCES ON TYPE::teabar_api.OrderSpecs TO teabar_member;
    GRANT EXECUTE, REFERENCES ON TYPE::teabar_api.OrderAddOns TO teabar_member;
    GRANT SELECT ON OBJECT::teabar_api.vw_MyMember TO teabar_member;
    GRANT SELECT ON OBJECT::teabar_api.vw_WorkOrders TO teabar_clerk;
    GRANT SELECT ON OBJECT::teabar_api.vw_WorkOrderItems TO teabar_clerk;
    GRANT SELECT ON OBJECT::teabar_api.vw_WorkItemSpecs TO teabar_clerk;
    GRANT SELECT ON OBJECT::teabar_api.vw_WorkItemAddOns TO teabar_clerk;
    GRANT SELECT ON OBJECT::teabar_api.vw_WorkConsumption TO teabar_clerk;
    GRANT SELECT ON OBJECT::teabar_api.vw_WorkTeam TO teabar_clerk;
    GRANT EXECUTE ON OBJECT::teabar_api.usp_AdvanceOrder TO teabar_clerk;
    GRANT EXECUTE ON OBJECT::teabar_api.usp_SaveMember TO teabar_clerk;
    GRANT EXECUTE ON OBJECT::teabar_api.usp_FindMember TO teabar_clerk;
    GRANT SELECT ON OBJECT::teabar_api.vw_WorkOrders TO teabar_manager;
    GRANT SELECT ON OBJECT::teabar_api.vw_WorkOrderItems TO teabar_manager;
    GRANT SELECT ON OBJECT::teabar_api.vw_WorkItemSpecs TO teabar_manager;
    GRANT SELECT ON OBJECT::teabar_api.vw_WorkItemAddOns TO teabar_manager;
    GRANT SELECT ON OBJECT::teabar_api.vw_WorkConsumption TO teabar_manager;
    GRANT SELECT ON OBJECT::teabar_api.vw_WorkTeam TO teabar_manager;
    GRANT EXECUTE ON OBJECT::teabar_api.usp_AdvanceOrder TO teabar_manager;
    GRANT EXECUTE ON OBJECT::teabar_api.usp_SaveMember TO teabar_manager;
    GRANT EXECUTE ON OBJECT::teabar_api.usp_FindMember TO teabar_manager;
    GRANT EXECUTE ON OBJECT::teabar_api.usp_RefundOrder TO teabar_customer;
    GRANT EXECUTE ON OBJECT::teabar_api.usp_RefundOrder TO teabar_member;
    GRANT EXECUTE ON OBJECT::teabar_api.usp_RefundOrder TO teabar_clerk;
    GRANT EXECUTE ON OBJECT::teabar_api.usp_RefundOrder TO teabar_manager;
    GRANT SELECT ON OBJECT::teabar_api.vw_DailySales TO teabar_manager;
    GRANT SELECT ON OBJECT::teabar_api.vw_ProductSales TO teabar_manager;
    GRANT EXECUTE ON OBJECT::teabar_api.usp_AdjustStock TO teabar_manager;
    GRANT EXECUTE ON OBJECT::teabar_api.usp_SaveProduct TO teabar_manager;
    GRANT EXECUTE ON OBJECT::teabar_api.usp_SaveIngredient TO teabar_manager;
    GRANT EXECUTE ON OBJECT::teabar_api.usp_SaveEmployee TO teabar_manager;
    GRANT EXECUTE ON OBJECT::teabar_api.usp_SaveSpecification TO teabar_manager;
    GRANT EXECUTE ON OBJECT::teabar_api.usp_SaveProductSpecification TO teabar_manager;
    GRANT EXECUTE ON OBJECT::teabar_api.usp_SaveRecipe TO teabar_manager;
    GRANT EXECUTE ON OBJECT::teabar_api.usp_SaveSpecificationIngredient TO teabar_manager;
    GRANT EXECUTE ON OBJECT::teabar_api.usp_SaveAddOn TO teabar_manager;
    GRANT EXECUTE ON OBJECT::teabar_api.usp_SaveDutyRoster TO teabar_manager;

    DECLARE safety_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT name FROM @roles;
    OPEN safety_cursor;
    FETCH NEXT FROM safety_cursor INTO @role;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @command = N'DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::teabar_auth.PrincipalBinding TO ' + QUOTENAME(@role)
            + N'; DENY ALTER ANY ROLE, ALTER ANY USER, CREATE ROLE TO ' + QUOTENAME(@role) + N';';
        EXEC sys.sp_executesql @command;
        FETCH NEXT FROM safety_cursor INTO @role;
    END;
    CLOSE safety_cursor;
    DEALLOCATE safety_cursor;

    COMMIT TRANSACTION;
    PRINT N'四种角色、六个示例用户、查询视图和受控操作安装成功。';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

-- 正常操作和越权验证在动态批次中编译，确保新建TVP类型已可用。
-- 业务数据、演示中暂时变更的身份绑定全部回滚；示例用户与角色本身保留。
SET XACT_ABORT OFF;
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
SET XACT_ABORT ON;

-- 管理员截图：角色成员及显式授权。无需对业务用户开放身份绑定表。
SELECT r.name AS role_name, u.name AS database_user
FROM sys.database_role_members AS rm
JOIN sys.database_principals AS r ON r.principal_id = rm.role_principal_id
JOIN sys.database_principals AS u ON u.principal_id = rm.member_principal_id
WHERE r.name IN (SELECT name FROM @roles)
ORDER BY r.name, u.name;
SELECT p.name AS role_name, d.state_desc, d.permission_name,
       d.class_desc,
       CASE WHEN d.class = 1 THEN OBJECT_SCHEMA_NAME(d.major_id)
            WHEN d.class = 6 THEN SCHEMA_NAME(ut.schema_id) END AS schema_name,
       CASE WHEN d.class = 1 THEN OBJECT_NAME(d.major_id)
            WHEN d.class = 6 THEN ut.name END AS object_name
FROM sys.database_permissions AS d
JOIN sys.database_principals AS p ON p.principal_id = d.grantee_principal_id
LEFT JOIN sys.types AS ut ON d.class = 6 AND ut.user_type_id = d.major_id
WHERE p.name IN (SELECT name FROM @roles)
ORDER BY p.name, d.class, d.major_id, d.permission_name;

-- 数据库管理员的手动维护示例（注释，不自动执行）：
-- ALTER ROLE teabar_clerk DROP MEMBER demo_clerk; -- 离职撤权
-- 岗位升迁时先移出旧角色，再加入新角色；不能让示例账户同时保留两种身份。
