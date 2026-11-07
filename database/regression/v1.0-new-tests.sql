-- Test-only fixtures and strict JSON / D01 / Web context cases. Entire fixture transaction rolls back.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
DECLARE @administrator SYSNAME=USER_NAME(),@impersonating BIT=0,@created_entry BIT=0;
DECLARE @prefix VARCHAR(8)='V1'+LEFT(REPLACE(CONVERT(VARCHAR(36),NEWID()),'-',''),6);
DECLARE @product VARCHAR(10)=@prefix+'P1',@zero VARCHAR(10)=@prefix+'P0',@ingredient VARCHAR(10)=@prefix+'I1',
    @spec VARCHAR(10)=@prefix+'S1',@addon VARCHAR(10)=@prefix+'A1',@order VARCHAR(10)=@prefix+'O1',
    @item VARCHAR(10)=@prefix+'T1',@item2 VARCHAR(10)=@prefix+'T2',@member VARCHAR(10)=@prefix+'M1',@member2 VARCHAR(10)=@prefix+'M2';
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
INSERT @web_users VALUES(1,N'web_guest_a','customer',N'teabar_customer'),(2,N'web_guest_b','customer',N'teabar_customer'),
    (3,N'web_member_a','member',N'teabar_member'),(4,N'web_member_b','member',N'teabar_member'),
    (5,N'web_clerk','clerk',N'teabar_clerk'),(6,N'web_manager','manager',N'teabar_manager');
DECLARE @phone1 VARCHAR(20),@phone2 VARCHAR(20);
WHILE @phone1 IS NULL OR EXISTS(SELECT 1 FROM dbo.Member WHERE phone=@phone1)
    SET @phone1='199'+RIGHT('00000000'+CONVERT(VARCHAR(8),ABS(CONVERT(BIGINT,CHECKSUM(NEWID())))%100000000),8);
WHILE @phone2 IS NULL OR @phone2=@phone1 OR EXISTS(SELECT 1 FROM dbo.Member WHERE phone=@phone2)
    SET @phone2='199'+RIGHT('00000000'+CONVERT(VARCHAR(8),ABS(CONVERT(BIGINT,CHECKSUM(NEWID())))%100000000),8);

BEGIN TRY
    BEGIN TRANSACTION;
    INSERT dbo.Member(member_id,name,phone,points) VALUES(@member,N'v1回归会员甲',@phone1,0),(@member2,N'v1回归会员乙',@phone2,0);
    INSERT dbo.Product(product_id,product_name,base_price,status) VALUES(@product,N'v1正常消耗',6,N'在售'),(@zero,N'v1零消耗反例',6,N'在售');
    INSERT dbo.Ingredient(ingredient_id,ingredient_name,unit,stock,status) VALUES(@ingredient,N'v1测试原料',N'ml',100,N'可用');
    INSERT dbo.Specification(spec_id,spec_type,spec_name) VALUES(@spec,N'糖度',@spec);
    INSERT dbo.ProductSpecification(product_id,spec_id,price_delta,status) VALUES(@product,@spec,1,N'可用'),(@zero,@spec,0,N'可用');
    INSERT dbo.Recipe(product_id,ingredient_id,base_amount) VALUES(@product,@ingredient,10),(@zero,@ingredient,10);
    INSERT dbo.SpecificationIngredient(product_id,spec_id,ingredient_id,factor) VALUES(@zero,@spec,@ingredient,0);
    INSERT dbo.AddOn(addon_id,addon_name,price,ingredient_id,extra_amount,status) VALUES(@addon,@addon,1,@ingredient,2,N'可用');
    UPDATE teabar_auth.PrincipalBinding SET member_id=@member WHERE principal_name=N'demo_member_a';
    UPDATE teabar_auth.PrincipalBinding SET member_id=@member2 WHERE principal_name=N'demo_member_b';

    -- The fixture applies grants inside this transaction only. Existing accounts are restored on rollback.
    DECLARE @seq INT=1,@username SYSNAME,@approle VARCHAR(10),@dbrole SYSNAME,@sid VARBINARY(85),@command NVARCHAR(MAX);
    WHILE @seq<=6
    BEGIN
        SELECT @username=user_name,@approle=app_role,@dbrole=role_name FROM @web_users WHERE seq=@seq;
        IF DATABASE_PRINCIPAL_ID(@username) IS NULL
        BEGIN
            SET @command=N'CREATE USER '+QUOTENAME(@username)+N' WITHOUT LOGIN;'; EXEC sys.sp_executesql @command;
        END;
        IF NOT EXISTS(SELECT 1 FROM sys.database_principals WHERE name COLLATE DATABASE_DEFAULT=@username AND type='S' AND authentication_type=0)
            THROW 52902,N'Web测试用户名被非预期主体占用。',1;
        IF EXISTS(SELECT 1 FROM sys.database_role_members WHERE member_principal_id=DATABASE_PRINCIPAL_ID(@username)
             AND role_principal_id<>DATABASE_PRINCIPAL_ID(@dbrole))
            THROW 52902,N'Web用户已有额外角色，拒绝掩盖其配置。',1;
        IF NOT EXISTS(SELECT 1 FROM sys.database_role_members WHERE member_principal_id=DATABASE_PRINCIPAL_ID(@username)
             AND role_principal_id=DATABASE_PRINCIPAL_ID(@dbrole))
        BEGIN
            SET @command=N'ALTER ROLE '+QUOTENAME(@dbrole)+N' ADD MEMBER '+QUOTENAME(@username)+N';'; EXEC sys.sp_executesql @command;
        END;
        SELECT @sid=sid FROM sys.database_principals WHERE name COLLATE DATABASE_DEFAULT=@username;
        IF @approle IN('customer','member')
        BEGIN
            IF NOT EXISTS(SELECT 1 FROM teabar_auth.PrincipalBinding WHERE principal_sid=@sid)
                INSERT teabar_auth.PrincipalBinding(principal_sid,principal_name,member_id,guest_id)
                    VALUES(@sid,@username,CASE WHEN @approle='member' THEN CASE WHEN @seq=3 THEN @member ELSE @member2 END END,
                           CASE WHEN @approle='customer' THEN NEWID() END);
            UPDATE teabar_auth.PrincipalBinding SET principal_name=@username,is_active=1,
                member_id=CASE WHEN @approle='member' THEN CASE WHEN @seq=3 THEN @member ELSE @member2 END END,
                guest_id=CASE WHEN @approle='customer' THEN NEWID() END WHERE principal_sid=@sid;
        END;
        IF NOT EXISTS(SELECT 1 FROM teabar_auth.WebAccount WHERE principal_sid=@sid)
            INSERT teabar_auth.WebAccount(login_name,password_hash,app_role,principal_sid)
                VALUES(LOWER(@prefix)+N'.'+CONVERT(NVARCHAR(2),@seq),N'fixture-placeholder-not-a-usable-password-hash',@approle,@sid);
        UPDATE teabar_auth.WebAccount SET password_hash=N'fixture-placeholder-not-a-usable-password-hash',
            app_role=@approle,is_active=1,session_version=1 WHERE principal_sid=@sid;
        SET @seq+=1;
    END;
    SELECT @account_id=a.account_id,@login_name=a.login_name FROM teabar_auth.WebAccount AS a
        JOIN sys.database_principals AS p ON p.sid=a.principal_sid WHERE p.name=N'web_guest_a';
    SELECT @manager_account=a.account_id FROM teabar_auth.WebAccount AS a
        JOIN sys.database_principals AS p ON p.sid=a.principal_sid WHERE p.name=N'web_manager';
    SELECT @member_account=a.account_id FROM teabar_auth.WebAccount AS a
        JOIN sys.database_principals AS p ON p.sid=a.principal_sid WHERE p.name=N'web_member_a';
    IF DATABASE_PRINCIPAL_ID(N'teabar_web_app') IS NULL CREATE USER teabar_web_app WITHOUT LOGIN;
    IF EXISTS(SELECT 1 FROM sys.database_role_members WHERE member_principal_id=DATABASE_PRINCIPAL_ID(N'teabar_web_app'))
        THROW 52902,N'应用入口不应属于任何数据库业务或固定角色。',1;
    GRANT EXECUTE ON OBJECT::teabar_auth.usp_GetWebCredential TO teabar_web_app;
    GRANT EXECUTE ON OBJECT::teabar_auth.usp_GetWebContext TO teabar_web_app;
    GRANT SELECT ON OBJECT::teabar_api.vw_Menu TO teabar_web_app;
    GRANT SELECT ON OBJECT::teabar_api.vw_AvailableSpecifications TO teabar_web_app;
    GRANT SELECT ON OBJECT::teabar_api.vw_AvailableAddOns TO teabar_web_app;
    DECLARE grant_metadata CURSOR LOCAL FAST_FORWARD FOR SELECT user_name FROM @web_users;
    OPEN grant_metadata; FETCH NEXT FROM grant_metadata INTO @username;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @command=N'GRANT VIEW DEFINITION ON USER::'+QUOTENAME(@username)+N' TO teabar_web_app;'
            +N'GRANT IMPERSONATE ON USER::'+QUOTENAME(@username)+N' TO teabar_web_app;';
        EXEC sys.sp_executesql @command;
        FETCH NEXT FROM grant_metadata INTO @username;
    END;
    CLOSE grant_metadata; DEALLOCATE grant_metadata;
    DECLARE grant_role_metadata CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT role_name FROM @web_users;
    OPEN grant_role_metadata; FETCH NEXT FROM grant_role_metadata INTO @dbrole;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @command=N'GRANT VIEW DEFINITION ON ROLE::'+QUOTENAME(@dbrole)+N' TO teabar_web_app;'; EXEC sys.sp_executesql @command;
        FETCH NEXT FROM grant_role_metadata INTO @dbrole;
    END;
    CLOSE grant_role_metadata; DEALLOCATE grant_role_metadata;

    INSERT @cases(case_name,user_name,statement,expected_error,setup,assertion) VALUES
    (N'JSON正常两杯、价格与正消耗',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,@good,@choices,N''[]'',1;',NULL,NULL,
        N'IF NOT EXISTS(SELECT 1 FROM dbo.SalesOrder WHERE order_id=@order AND total_amount=14) OR NOT EXISTS(SELECT 1 FROM dbo.OrderItemIngredient WHERE item_id=@item AND amount=20) OR NOT EXISTS(SELECT 1 FROM dbo.Ingredient WHERE ingredient_id=@ingredient AND stock=80) THROW 52902,N''金额、消耗或扣库错误。'',1;'),
    (N'JSON加料参与计价和同原料汇总',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,@good,@choices,@extras,1;',NULL,NULL,
        N'IF NOT EXISTS(SELECT 1 FROM dbo.SalesOrder WHERE order_id=@order AND total_amount=16) OR NOT EXISTS(SELECT 1 FROM dbo.OrderItemIngredient WHERE item_id=@item AND amount=24) THROW 52902,N''加料快照或汇总错误。'',1;'),
    (N'JSON多商品明细完整下单',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,@multi,@twochoices,N''[]'',1;',NULL,NULL,
        N'IF (SELECT COUNT(*) FROM dbo.OrderItem WHERE order_id=@order)<>2 OR NOT EXISTS(SELECT 1 FROM dbo.SalesOrder WHERE order_id=@order AND total_amount=14) THROW 52902,N''多明细落单错误。'',1;'),
    (N'D01单条零消耗整单拒绝',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,@singlezero,@zerochoices,N''[]'',1;',52018,NULL,NULL),
    (N'D01同单正常加零消耗仍整单拒绝',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,@mixed,@twochoices,N''[]'',1;',52018,NULL,NULL),
    (N'D01原TVP入口同样检查逐明细',N'demo_guest_a',N'DECLARE @l teabar_api.OrderLines,@s teabar_api.OrderSpecs,@a teabar_api.OrderAddOns; INSERT @l VALUES(@item,@product,1),(@item2,@zero,1); INSERT @s VALUES(@item,@spec),(@item2,@spec); EXEC teabar_api.usp_PlacePaidOrder @order,@l,@s,@a,1;',52018,NULL,NULL),
    (N'库存不足不留下部分写入',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,@good,@choices,N''[]'',1;',52016,N'UPDATE dbo.Ingredient SET stock=1 WHERE ingredient_id=@ingredient;',NULL),
    (N'付款失败不落单',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,@good,@choices,N''[]'',0;',52001,NULL,NULL),
    (N'拒绝超长订单编号而非截断',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson N''12345678901'',@good,@choices,N''[]'',1;',52602,NULL,NULL),
    (N'拒绝尾部空白订单编号',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson N''O1 '',@good,@choices,N''[]'',1;',52602,NULL,NULL),
    (N'拒绝NULL JSON',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,NULL,@choices,N''[]'',1;',52600,NULL,NULL),
    (N'拒绝非法JSON',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,N''['',@choices,N''[]'',1;',52600,NULL,NULL),
    (N'拒绝对象代替数组',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,N''{}'',@choices,N''[]'',1;',52600,NULL,NULL),
    (N'拒绝空明细数组',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,N''[]'',N''[]'',N''[]'',1;',52600,NULL,NULL),
    (N'拒绝数组中的非对象',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,N''[1]'',N''[]'',N''[]'',1;',52601,NULL,NULL),
    (N'拒绝缺失字段',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,N''[{"item_id":"T1"}]'',N''[]'',N''[]'',1;',52601,NULL,NULL),
    (N'拒绝大小写错误字段',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,N''[{"Item_id":"T1","product_id":"P1","quantity":1}]'',N''[]'',N''[]'',1;',52601,NULL,NULL),
    (N'拒绝字段名尾部空格',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,N''[{"item_id ":"T1","product_id":"P1","quantity":1}]'',N''[]'',N''[]'',1;',52601,NULL,NULL),
    (N'拒绝重复对象属性',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,N''[{"item_id":"T1","item_id":"T2","product_id":"P1","quantity":1}]'',N''[]'',N''[]'',1;',52601,NULL,NULL),
    (N'拒绝客户端提交价格或身份',N'demo_guest_a',N'DECLARE @j NVARCHAR(MAX)=JSON_MODIFY(@good,''$[0].unit_price'',0); EXEC teabar_api.usp_PlacePaidOrderJson @order,@j,@choices,N''[]'',1;',52601,NULL,NULL),
    (N'拒绝数字字符串数量',N'demo_guest_a',N'DECLARE @j NVARCHAR(MAX)=JSON_MODIFY(@good,''$[0].quantity'',N''2''); EXEC teabar_api.usp_PlacePaidOrderJson @order,@j,@choices,N''[]'',1;',52602,NULL,NULL),
    (N'拒绝小数数量',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,N''[{"item_id":"T1","product_id":"P1","quantity":1.5}]'',N''[]'',N''[]'',1;',52602,NULL,NULL),
    (N'拒绝科学记数法数量',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,N''[{"item_id":"T1","product_id":"P1","quantity":1e1}]'',N''[]'',N''[]'',1;',52602,NULL,NULL),
    (N'拒绝超INT数量',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,N''[{"item_id":"T1","product_id":"P1","quantity":2147483648}]'',N''[]'',N''[]'',1;',52602,NULL,NULL),
    (N'拒绝零数量',N'demo_guest_a',N'DECLARE @j NVARCHAR(MAX)=JSON_MODIFY(@good,''$[0].quantity'',0); EXEC teabar_api.usp_PlacePaidOrderJson @order,@j,@choices,N''[]'',1;',52602,NULL,NULL),
    (N'拒绝NULL数量',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,N''[{"item_id":"T1","product_id":"P1","quantity":null}]'',N''[]'',N''[]'',1;',52602,NULL,NULL),
    (N'拒绝布尔数量',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,N''[{"item_id":"T1","product_id":"P1","quantity":true}]'',N''[]'',N''[]'',1;',52602,NULL,NULL),
    (N'拒绝超长商品编号',N'demo_guest_a',N'DECLARE @j NVARCHAR(MAX)=JSON_MODIFY(@good,''$[0].product_id'',N''12345678901''); EXEC teabar_api.usp_PlacePaidOrderJson @order,@j,@choices,N''[]'',1;',52602,NULL,NULL),
    (N'拒绝SQL注入式编号且无副作用',N'demo_guest_a',N'DECLARE @j NVARCHAR(MAX)=JSON_MODIFY(@good,''$[0].product_id'',N''x'''' OR 1=1''); EXEC teabar_api.usp_PlacePaidOrderJson @order,@j,@choices,N''[]'',1;',52602,NULL,NULL),
    (N'拒绝重复明细',N'demo_guest_a',N'DECLARE @j NVARCHAR(MAX)=N''[''+SUBSTRING(@good,2,LEN(@good)-2)+N'',''+SUBSTRING(@good,2,LEN(@good)-2)+N'']''; EXEC teabar_api.usp_PlacePaidOrderJson @order,@j,@choices,N''[]'',1;',52603,NULL,NULL),
    (N'拒绝重复规格选择',N'demo_guest_a',N'DECLARE @j NVARCHAR(MAX)=N''[''+SUBSTRING(@choices,2,LEN(@choices)-2)+N'',''+SUBSTRING(@choices,2,LEN(@choices)-2)+N'']''; EXEC teabar_api.usp_PlacePaidOrderJson @order,@good,@j,N''[]'',1;',52603,NULL,NULL),
    (N'拒绝跨明细引用',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,@good,@zerochoices,N''[]'',1;',52604,NULL,NULL),
    (N'漏选规格交由核心拒绝',N'demo_guest_a',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,@good,N''[]'',N''[]'',1;',52009,NULL,NULL),
    (N'店员不能调用顾客JSON入口',N'demo_clerk',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,@good,@choices,N''[]'',1;',229,NULL,NULL),
    (N'应用入口不能直接调用下单',N'teabar_web_app',N'EXEC teabar_api.usp_PlacePaidOrderJson @order,@good,@choices,N''[]'',1;',229,NULL,NULL),
    (N'应用入口可读公开菜单',N'teabar_web_app',N'IF NOT EXISTS(SELECT 1 FROM teabar_api.vw_Menu WHERE product_id=@product) THROW 52902,N''入口公开菜单不可用。'',1;',NULL,NULL,NULL),
    (N'应用入口不能直接读账号哈希表',N'teabar_web_app',N'SELECT account_id FROM teabar_auth.WebAccount;',229,NULL,NULL),
    (N'业务用户不能读WebAccount',N'web_manager',N'SELECT account_id FROM teabar_auth.WebAccount;',229,NULL,NULL),
    (N'业务用户不能调用认证查询',N'web_guest_a',N'EXEC teabar_auth.usp_GetWebCredential @login_name;',229,NULL,NULL),
    (N'凭据查询仅返回受控单账号',N'teabar_web_app',N'DECLARE @r TABLE(account_id INT,password_hash NVARCHAR(512),session_version INT); INSERT @r EXEC teabar_auth.usp_GetWebCredential @login_name; IF (SELECT COUNT(*) FROM @r)<>1 OR NOT EXISTS(SELECT 1 FROM @r WHERE account_id=@account_id AND session_version=1) THROW 52902,N''凭据查询错误。'',1;',NULL,NULL,NULL),
    (N'拒绝截断后匹配超长登录名',N'teabar_web_app',N'DECLARE @r TABLE(account_id INT,password_hash NVARCHAR(512),session_version INT); DECLARE @n NVARCHAR(MAX)=@login_name+REPLICATE(N''x'',100); INSERT @r EXEC teabar_auth.usp_GetWebCredential @n; IF EXISTS(SELECT 1 FROM @r) THROW 52902,N''超长登录名被截断接受。'',1;',NULL,NULL,NULL),
    (N'受限入口可获取活动购买者上下文',N'teabar_web_app',N'DECLARE @r TABLE(account_id INT,app_role VARCHAR(10),principal_sid VARBINARY(85),principal_name SYSNAME,session_version INT); INSERT @r EXEC teabar_auth.usp_GetWebContext @account_id,1; IF NOT EXISTS(SELECT 1 FROM @r WHERE principal_name=N''web_guest_a'' AND app_role=''customer'') THROW 52902,N''上下文错误。'',1;',NULL,NULL,NULL),
    (N'工作账号无需购买绑定也可获取上下文',N'teabar_web_app',N'DECLARE @r TABLE(account_id INT,app_role VARCHAR(10),principal_sid VARBINARY(85),principal_name SYSNAME,session_version INT); INSERT @r EXEC teabar_auth.usp_GetWebContext @manager_account,1; IF NOT EXISTS(SELECT 1 FROM @r WHERE principal_name=N''web_manager'' AND app_role=''manager'') THROW 52902,N''工作上下文错误。'',1;',NULL,NULL,NULL),
    (N'旧会话版本被拒绝',N'teabar_web_app',N'EXEC teabar_auth.usp_GetWebContext @account_id,1;',52700,N'UPDATE teabar_auth.WebAccount SET session_version=2 WHERE account_id=@account_id;',NULL),
    (N'账号停用后上下文被拒绝',N'teabar_web_app',N'EXEC teabar_auth.usp_GetWebContext @account_id,1;',52700,N'UPDATE teabar_auth.WebAccount SET is_active=0 WHERE account_id=@account_id;',NULL),
    (N'账号角色与数据库用户不符被拒绝',N'teabar_web_app',N'EXEC teabar_auth.usp_GetWebContext @account_id,1;',52700,N'UPDATE teabar_auth.WebAccount SET app_role=''manager'' WHERE account_id=@account_id;',NULL),
    (N'购买绑定停用被拒绝',N'teabar_web_app',N'EXEC teabar_auth.usp_GetWebContext @account_id,1;',52700,N'UPDATE teabar_auth.PrincipalBinding SET is_active=0 WHERE principal_name=N''web_guest_a'';',NULL),
    (N'额外数据库角色被拒绝',N'teabar_web_app',N'EXEC teabar_auth.usp_GetWebContext @account_id,1;',52700,N'ALTER ROLE teabar_manager ADD MEMBER web_guest_a;',NULL),
    (N'用户直接表授权被拒绝',N'teabar_web_app',N'EXEC teabar_auth.usp_GetWebContext @account_id,1;',52700,N'GRANT SELECT ON OBJECT::dbo.Member TO web_guest_a;',NULL),
    (N'用户拥有架构被拒绝',N'teabar_web_app',N'EXEC teabar_auth.usp_GetWebContext @account_id,1;',52700,N'EXEC(N''CREATE SCHEMA v1_regression_owned AUTHORIZATION web_guest_a;'');',NULL),
    (N'活动会员上下文可用',N'teabar_web_app',N'DECLARE @id INT=(SELECT @member_account); DECLARE @r TABLE(account_id INT,app_role VARCHAR(10),principal_sid VARBINARY(85),principal_name SYSNAME,session_version INT); INSERT @r EXEC teabar_auth.usp_GetWebContext @id,1; IF NOT EXISTS(SELECT 1 FROM @r WHERE principal_name=N''web_member_a'' AND app_role=''member'') THROW 52902,N''会员上下文错误。'',1;',NULL,NULL,NULL),
    (N'入口可按允许名单切换顾客执行下单',N'teabar_web_app',N'BEGIN TRY EXECUTE AS USER=N''web_guest_a''; EXEC teabar_api.usp_PlacePaidOrderJson @order,@good,@choices,N''[]'',1; REVERT; END TRY BEGIN CATCH IF USER_NAME()=N''web_guest_a'' REVERT; THROW; END CATCH;',NULL,NULL,
        N'IF NOT EXISTS(SELECT 1 FROM dbo.SalesOrder AS o JOIN teabar_auth.PrincipalBinding AS b ON b.guest_id=o.guest_id WHERE o.order_id=@order AND b.principal_name=N''web_guest_a'' AND o.total_amount=14) THROW 52902,N''切换身份后的购买归属错误。'',1;'),
    (N'入口不能切换demo回归用户',N'teabar_web_app',N'EXECUTE AS USER=N''demo_guest_a''; REVERT;',15517,NULL,NULL);

    -- Permission denial number for EXECUTE AS can be 15517 or 15151 by engine/version.
    -- The dedicated case accepts only either denial, never an arbitrary error or successful switch.
    DECLARE @params NVARCHAR(MAX)=N'@good NVARCHAR(MAX),@choices NVARCHAR(MAX),@extras NVARCHAR(MAX),@multi NVARCHAR(MAX),
      @mixed NVARCHAR(MAX),@twochoices NVARCHAR(MAX),@singlezero NVARCHAR(MAX),@zerochoices NVARCHAR(MAX),
      @order VARCHAR(10),@item VARCHAR(10),@item2 VARCHAR(10),@product VARCHAR(10),@zero VARCHAR(10),@spec VARCHAR(10),
      @ingredient VARCHAR(10),@addon VARCHAR(10),@member VARCHAR(10),@member2 VARCHAR(10),@account_id INT,@manager_account INT,@login_name NVARCHAR(50),@member_account INT';
    DECLARE @label NVARCHAR(150),@user SYSNAME,@statement NVARCHAR(MAX),@expected INT,@actual INT,@setup NVARCHAR(MAX),@assertion NVARCHAR(MAX),@message NVARCHAR(4000),@before VARBINARY(32),@after VARBINARY(32),@passed BIT;
    DECLARE @fingerprint NVARCHAR(MAX)=N'SELECT @h=HASHBYTES(''SHA2_256'',
        (SELECT * FROM dbo.SalesOrder ORDER BY order_id FOR XML RAW,BINARY BASE64)
       +(SELECT * FROM dbo.OrderItem ORDER BY item_id FOR XML RAW,BINARY BASE64)
       +(SELECT * FROM dbo.ItemSpec ORDER BY item_id,spec_type FOR XML RAW,BINARY BASE64)
       +(SELECT * FROM dbo.ItemAddOn ORDER BY item_id,addon_id FOR XML RAW,BINARY BASE64)
       +(SELECT * FROM dbo.OrderItemIngredient ORDER BY item_id,ingredient_id FOR XML RAW,BINARY BASE64)
       +(SELECT * FROM dbo.Ingredient ORDER BY ingredient_id FOR XML RAW,BINARY BASE64)
       +(SELECT * FROM dbo.Member ORDER BY member_id FOR XML RAW,BINARY BASE64)
       +(SELECT * FROM teabar_auth.WebAccount ORDER BY account_id FOR XML RAW,BINARY BASE64)
       +(SELECT * FROM teabar_auth.PrincipalBinding ORDER BY principal_sid FOR XML RAW,BINARY BASE64));';
    SET @seq=1;
    WHILE @seq<=(SELECT COUNT(*) FROM @cases)
    BEGIN
        SELECT @label=case_name,@user=user_name,@statement=statement,@expected=expected_error,@setup=setup,@assertion=assertion FROM @cases WHERE seq=@seq;
        -- SQL Server dooms an explicit transaction on denied EXECUTE AS, even with XACT_ABORT OFF.
        -- Run this one denial after the fixture rollback, with no explicit transaction.
        IF @expected=15517 BEGIN SET @seq+=1; CONTINUE; END;
        PRINT N'v1.0 case '+CONVERT(NVARCHAR(10),@seq)+N': '+@label;
        SAVE TRANSACTION new_test_case;
        IF @setup IS NOT NULL EXEC sys.sp_executesql @setup,@params,@good,@choices,@extras,@multi,@mixed,@twochoices,@singlezero,@zerochoices,
            @order,@item,@item2,@product,@zero,@spec,@ingredient,@addon,@member,@member2,@account_id,@manager_account,@login_name,@member_account;
        EXEC sys.sp_executesql @fingerprint,N'@h VARBINARY(32) OUTPUT',@h=@before OUTPUT;
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
        EXEC sys.sp_executesql @fingerprint,N'@h VARBINARY(32) OUTPUT',@h=@after OUTPUT;
        SET @passed=CASE WHEN @expected IS NULL AND @actual IS NULL THEN 1
            WHEN @expected IS NOT NULL AND @before=@after AND (@actual=@expected OR (@expected=15517 AND @actual=15151)) THEN 1 ELSE 0 END;
        ROLLBACK TRANSACTION new_test_case;
        INSERT @results VALUES(@label,@expected,@actual,@passed,COALESCE(@message,N'执行及断言通过；反例要求数据哈希不变。'));
        SET @seq+=1;
    END;
    ROLLBACK TRANSACTION;
    IF USER_NAME()<>@administrator OR @@TRANCOUNT<>0 THROW 52902,N'测试未恢复管理员上下文或未释放事务。',1;
    IF (SELECT COUNT(*) FROM @cases WHERE expected_error=15517)<>1
        THROW 52902,N'独立身份切换拒绝用例数量错误。',1;
    SELECT @label=case_name,@statement=statement,@expected=expected_error FROM @cases WHERE expected_error=15517;
    PRINT N'v1.0 isolated case: '+@label;
    IF DATABASE_PRINCIPAL_ID(N'teabar_web_app') IS NULL
    BEGIN
        CREATE USER teabar_web_app WITHOUT LOGIN;
        SET @created_entry=1;
    END;
    SET @actual=NULL; SET @message=NULL;
    BEGIN TRY
        EXECUTE AS USER=N'teabar_web_app'; SET @impersonating=1;
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
        COALESCE(@message,N'未得到预期拒绝。'));
    IF (SELECT COUNT(*) FROM @results)<>53 THROW 52902,N'新增用例数量不是53。',1;
    INSERT #RegressionResults(suite,case_name,expected_error,actual_error,passed,detail)
        SELECT N'v1.0-new',case_name,expected_error,actual_error,passed,detail FROM @results;
    SELECT case_name,expected_error,actual_error,passed,detail FROM @results;
END TRY
BEGIN CATCH
    IF @impersonating=1 REVERT;
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    IF @created_entry=1 AND USER_NAME()=@administrator DROP USER teabar_web_app;
    SELECT N'V1_TEST_ABORTED' AS stage,@seq AS case_number,@label AS case_name,
        ERROR_NUMBER() AS error_number,ERROR_LINE() AS error_line,ERROR_PROCEDURE() AS error_procedure,ERROR_MESSAGE() AS detail;
    THROW;
END CATCH;
