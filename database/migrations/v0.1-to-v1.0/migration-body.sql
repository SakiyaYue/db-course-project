-- Included by build-scripts.py after generated source manifests and session options.
-- Single batch: CREATE/ALTER modules are executed as literal dynamic DDL.
DECLARE @ExpectedDatabase SYSNAME=N'TeabarDB_Phase2_Work';
DECLARE @CommitMigration BIT=0;        -- 0: validate then roll back; 1: explicitly commit.
DECLARE @InjectFailure BIT=0;          -- 1: throw after all DDL to exercise atomic rollback.
IF DB_NAME()<>@ExpectedDatabase OR DB_NAME() IN (N'TeabarDB',N'master',N'model',N'msdb',N'tempdb')
    THROW 52800, N'迁移仅允许在明确指定的独立工作副本执行，禁止冻结基线库。', 1;
IF @@TRANCOUNT<>0 OR USER_NAME()<>N'dbo'
    THROW 52800, N'请使用dbo管理员在无未结束事务的新窗口执行迁移。', 1;
IF TRY_CONVERT(INT,SERVERPROPERTY('ProductMajorVersion'))<13
   OR (SELECT compatibility_level FROM sys.databases WHERE database_id=DB_ID())<130
    THROW 52801, N'JSON接口需要SQL Server 2016或以上及至少130兼容级别。', 1;

DECLARE @before TABLE(schema_name SYSNAME,table_name SYSNAME,row_count BIGINT,data_hash VARBINARY(32),PRIMARY KEY(schema_name,table_name));
DECLARE @after TABLE(schema_name SYSNAME,table_name SYSNAME,row_count BIGINT,data_hash VARBINARY(32),PRIMARY KEY(schema_name,table_name));
DECLARE @schema SYSNAME,@table SYSNAME,@ordering NVARCHAR(MAX),@sql NVARCHAR(MAX),@rows BIGINT,@hash VARBINARY(32),@lock_result INT;
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC @lock_result=sys.sp_getapplock @Resource=N'TeabarDB/v0.1-to-v1.0',@LockMode=N'Exclusive',
        @LockOwner=N'Transaction',@LockTimeout=0;
    IF @lock_result<0 THROW 52801, N'另一个迁移正在进行。', 1;
    IF EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'TeabarDB.SchemaVersion')
        THROW 52802, N'源库已有版本标记，拒绝在已迁移或不明状态上重跑；请恢复干净v0.1工作副本。', 1;
    IF (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0)<>16
       OR (SELECT COUNT(*) FROM sys.columns AS c JOIN sys.tables AS t ON t.object_id=c.object_id WHERE t.is_ms_shipped=0)<>74
       OR EXISTS(SELECT 1 FROM @expected_columns AS e LEFT JOIN sys.schemas AS s ON s.name COLLATE DATABASE_DEFAULT=e.schema_name
          LEFT JOIN sys.tables AS t ON t.schema_id=s.schema_id AND t.name COLLATE DATABASE_DEFAULT=e.table_name
          LEFT JOIN sys.columns AS c ON c.object_id=t.object_id AND c.name COLLATE DATABASE_DEFAULT=e.column_name
          LEFT JOIN sys.types AS ty ON ty.user_type_id=c.system_type_id AND ty.user_type_id=ty.system_type_id
          WHERE c.column_id IS NULL OR ty.name COLLATE DATABASE_DEFAULT<>e.type_name OR c.max_length<>e.max_length
            OR c.precision<>e.precision_value OR c.scale<>e.scale_value OR c.is_nullable<>e.is_nullable
            OR c.is_computed<>e.is_computed OR c.is_identity<>0)
        THROW 52802, N'源库的表、列、类型、长度、精度或可空性不符合完整v0.1。', 1;
    IF (SELECT COUNT(*) FROM sys.foreign_keys)<>19
       OR (SELECT COUNT(*) FROM sys.key_constraints WHERE parent_object_id IN(SELECT object_id FROM sys.tables WHERE is_ms_shipped=0))<>22
       OR (SELECT COUNT(*) FROM sys.check_constraints WHERE parent_object_id IN(SELECT object_id FROM sys.tables WHERE is_ms_shipped=0))<>(SELECT COUNT(*) FROM @expected_checks)
       OR EXISTS(SELECT 1 FROM @expected_checks AS e LEFT JOIN sys.check_constraints AS c
                    ON c.name COLLATE DATABASE_DEFAULT=e.constraint_name WHERE c.object_id IS NULL)
       OR EXISTS(SELECT 1 FROM sys.foreign_keys WHERE is_disabled=1 OR is_not_trusted=1
                   OR delete_referential_action<>0 OR update_referential_action<>0)
       OR EXISTS(SELECT 1 FROM sys.check_constraints WHERE is_disabled=1 OR is_not_trusted=1)
        THROW 52802, N'源库键/约束数量、名称、启用、信任或级联状态不符合基线。', 1;
    IF EXISTS(SELECT 1 FROM @expected_keys AS e WHERE NOT EXISTS(
        SELECT 1 FROM sys.key_constraints AS k JOIN sys.tables AS t ON t.object_id=k.parent_object_id
        JOIN sys.schemas AS s ON s.schema_id=t.schema_id
        WHERE s.name COLLATE DATABASE_DEFAULT=e.schema_name AND t.name COLLATE DATABASE_DEFAULT=e.table_name
          AND k.name COLLATE DATABASE_DEFAULT=e.constraint_name
          AND k.type COLLATE DATABASE_DEFAULT=e.key_type AND e.key_columns=(
            SELECT STUFF((SELECT N','+c.name FROM sys.index_columns AS ic
            JOIN sys.columns AS c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
            WHERE ic.object_id=k.parent_object_id AND ic.index_id=k.unique_index_id AND ic.key_ordinal>0
            ORDER BY ic.key_ordinal FOR XML PATH(''),TYPE).value('.','nvarchar(max)'),1,1,N''))))
        THROW 52802, N'源库主码/唯一约束的列或顺序与冻结模式不同。', 1;
    IF EXISTS(SELECT 1 FROM @expected_fks AS e WHERE NOT EXISTS(
        SELECT 1 FROM sys.foreign_keys AS f WHERE f.name COLLATE DATABASE_DEFAULT=e.constraint_name
          AND OBJECT_SCHEMA_NAME(f.parent_object_id) COLLATE DATABASE_DEFAULT=e.child_schema
          AND OBJECT_NAME(f.parent_object_id) COLLATE DATABASE_DEFAULT=e.child_table
          AND OBJECT_SCHEMA_NAME(f.referenced_object_id) COLLATE DATABASE_DEFAULT=e.parent_schema
          AND OBJECT_NAME(f.referenced_object_id) COLLATE DATABASE_DEFAULT=e.parent_table
          AND e.child_columns=(SELECT STUFF((SELECT N','+COL_NAME(fc.parent_object_id,fc.parent_column_id)
            FROM sys.foreign_key_columns AS fc WHERE fc.constraint_object_id=f.object_id
            ORDER BY fc.constraint_column_id FOR XML PATH(''),TYPE).value('.','nvarchar(max)'),1,1,N''))
          AND e.parent_columns=(SELECT STUFF((SELECT N','+COL_NAME(fc.referenced_object_id,fc.referenced_column_id)
            FROM sys.foreign_key_columns AS fc WHERE fc.constraint_object_id=f.object_id
            ORDER BY fc.constraint_column_id FOR XML PATH(''),TYPE).value('.','nvarchar(max)'),1,1,N''))))
        THROW 52802, N'源库外键引用列或顺序与冻结模式不同。', 1;
    IF EXISTS(SELECT 1 FROM @expected_modules AS e LEFT JOIN sys.schemas AS s ON s.name COLLATE DATABASE_DEFAULT=e.schema_name
        LEFT JOIN sys.objects AS o ON o.schema_id=s.schema_id AND o.name COLLATE DATABASE_DEFAULT=e.object_name
        WHERE o.object_id IS NULL OR o.type COLLATE DATABASE_DEFAULT<>e.object_type)
       OR EXISTS(SELECT 1 FROM @expected_defaults AS e WHERE NOT EXISTS(
          SELECT 1 FROM sys.default_constraints AS d JOIN sys.columns AS c
          ON c.object_id=d.parent_object_id AND c.column_id=d.parent_column_id
          WHERE OBJECT_NAME(d.parent_object_id) COLLATE DATABASE_DEFAULT=e.table_name AND c.name COLLATE DATABASE_DEFAULT=e.column_name))
       OR NOT EXISTS(SELECT 1 FROM sys.computed_columns WHERE object_id=OBJECT_ID(N'dbo.OrderItem')
           AND name=N'sub_amount' AND is_persisted=1)
       OR HASHBYTES('SHA2_256',REPLACE(OBJECT_DEFINITION(OBJECT_ID(N'teabar_api.usp_PlacePaidOrder')),CHAR(13),N'')) NOT IN(@source_core_hash,@source_core_literal_hash)
       OR OBJECT_DEFINITION(OBJECT_ID(N'teabar_api.usp_PlacePaidOrder')) IS NULL
        THROW 52802, N'源库对象、默认值、计算列或核心下单定义与冻结源码不符。', 1;
    IF EXISTS(SELECT 1 FROM sys.schemas WHERE name IN (N'dbo',N'teabar_auth',N'teabar_api') AND principal_id<>DATABASE_PRINCIPAL_ID(N'dbo'))
       OR EXISTS(SELECT 1 FROM @expected_roles AS e WHERE NOT EXISTS(SELECT 1 FROM sys.database_principals AS p
            WHERE p.name COLLATE DATABASE_DEFAULT=e.role_name AND p.type='R' AND p.owning_principal_id=DATABASE_PRINCIPAL_ID(N'dbo')))
       OR EXISTS(SELECT 1 FROM @expected_users AS u WHERE NOT EXISTS(SELECT 1 FROM sys.database_principals AS p
            JOIN sys.database_role_members AS rm ON rm.member_principal_id=p.principal_id
            WHERE p.name COLLATE DATABASE_DEFAULT=u.user_name AND p.type='S' AND p.authentication_type=0
              AND rm.role_principal_id=DATABASE_PRINCIPAL_ID(u.role_name)))
       OR EXISTS(SELECT 1 FROM @expected_users AS u JOIN sys.database_principals AS p ON p.name COLLATE DATABASE_DEFAULT=u.user_name
            JOIN sys.database_role_members AS rm ON rm.member_principal_id=p.principal_id
            WHERE rm.role_principal_id<>DATABASE_PRINCIPAL_ID(u.role_name))
        THROW 52802, N'源库架构所有权、业务角色或demo用户不符合基线。', 1;
    IF EXISTS(SELECT 1 FROM sys.objects WHERE schema_id=SCHEMA_ID(N'teabar_auth') AND name IN (N'WebAccount',N'usp_GetWebCredential',N'usp_GetWebContext'))
       OR OBJECT_ID(N'teabar_api.usp_PlacePaidOrderJson') IS NOT NULL
       OR EXISTS(SELECT 1 FROM sys.indexes WHERE (object_id=OBJECT_ID(N'dbo.SalesOrder') AND name IN (N'IX_SalesOrder_Member_Time',N'IX_SalesOrder_Guest_Time'))
             OR (object_id=OBJECT_ID(N'dbo.OrderItem') AND name=N'IX_OrderItem_Order'))
        THROW 52803, N'目标对象同名冲突，不覆盖不明对象。', 1;

    DECLARE source_tables CURSOR LOCAL FAST_FORWARD FOR SELECT schema_name,table_name,order_columns FROM @expected_tables ORDER BY schema_name,table_name;
    OPEN source_tables;
    FETCH NEXT FROM source_tables INTO @schema,@table,@ordering;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @sql=N'SELECT @n=COUNT_BIG(*) FROM '+QUOTENAME(@schema)+N'.'+QUOTENAME(@table)+N' WITH(TABLOCKX,HOLDLOCK);'
          +N'SELECT @h=HASHBYTES(''SHA2_256'',(SELECT * FROM '+QUOTENAME(@schema)+N'.'+QUOTENAME(@table)
          +N' ORDER BY '+@ordering+N' FOR XML RAW,BINARY BASE64));';
        EXEC sys.sp_executesql @sql,N'@n BIGINT OUTPUT,@h VARBINARY(32) OUTPUT',@n=@rows OUTPUT,@h=@hash OUTPUT;
        INSERT @before VALUES(@schema,@table,@rows,@hash);
        FETCH NEXT FROM source_tables INTO @schema,@table,@ordering;
    END;
    CLOSE source_tables; DEALLOCATE source_tables;
    IF EXISTS(SELECT 1 FROM @before AS b JOIN @expected_tables AS e ON e.schema_name=b.schema_name AND e.table_name=b.table_name
        WHERE e.expected_rows<>b.row_count)
        THROW 52804, N'工作副本行数与冻结样例基线不同。', 1;
    IF EXISTS(SELECT 1 FROM dbo.OrderItem AS i WHERE NOT EXISTS(
        SELECT 1 FROM dbo.OrderItemIngredient AS c WHERE c.item_id=i.item_id AND c.amount>0))
    BEGIN
        SELECT i.item_id,i.order_id FROM dbo.OrderItem AS i WHERE NOT EXISTS(
            SELECT 1 FROM dbo.OrderItemIngredient AS c WHERE c.item_id=i.item_id AND c.amount>0);
        THROW 52804, N'历史明细缺少正消耗快照；拒绝迁移，不按当前配方编造历史。', 1;
    END;
    IF EXISTS(SELECT 1 FROM dbo.SalesOrder AS o OUTER APPLY(
        SELECT COUNT(*) AS n,SUM(sub_amount) AS amount FROM dbo.OrderItem AS i WHERE i.order_id=o.order_id) AS x
        WHERE x.n=0 OR x.amount<>o.total_amount)
       OR NOT EXISTS(SELECT 1 FROM dbo.Product WHERE product_id='P001' AND base_price=6 AND status=N'在售')
       OR NOT EXISTS(SELECT 1 FROM dbo.Ingredient WHERE ingredient_id='I001' AND stock=5000 AND unit=N'g')
       OR NOT EXISTS(SELECT 1 FROM dbo.Member WHERE member_id='M001' AND points=120)
       OR (SELECT COUNT(*) FROM dbo.SalesOrder WHERE status=N'已完成' AND order_time>='20261004' AND order_time<'20261005')<>3
       OR (SELECT SUM(total_amount) FROM dbo.SalesOrder WHERE status=N'已完成' AND order_time>='20261004' AND order_time<'20261005')<>46
       OR (SELECT SUM(i.quantity) FROM dbo.OrderItem AS i JOIN dbo.SalesOrder AS o ON o.order_id=i.order_id
           WHERE o.status=N'已完成' AND o.order_time>='20261004' AND o.order_time<'20261005')<>5
        THROW 52804, N'订单金额、关键库存/积分或经营基准不符。', 1;
    SELECT N'PRE_MIGRATION' AS stage,schema_name,table_name,row_count,CONVERT(VARCHAR(64),data_hash,2) AS data_hash FROM @before ORDER BY schema_name,table_name;

    EXEC(N'CREATE TABLE teabar_auth.WebAccount(
        account_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_WebAccount PRIMARY KEY,
        login_name NVARCHAR(50) NOT NULL CONSTRAINT UQ_WebAccount_LoginName UNIQUE,
        password_hash NVARCHAR(512) NOT NULL,
        app_role VARCHAR(10) NOT NULL,
        principal_sid VARBINARY(85) NOT NULL CONSTRAINT UQ_WebAccount_PrincipalSid UNIQUE,
        is_active BIT NOT NULL CONSTRAINT DF_WebAccount_Active DEFAULT 1,
        session_version INT NOT NULL CONSTRAINT DF_WebAccount_SessionVersion DEFAULT 1,
        CONSTRAINT CK_WebAccount_LoginName CHECK(DATALENGTH(login_name) BETWEEN 6 AND 100
          AND login_name COLLATE Latin1_General_100_BIN2 NOT LIKE N''%[^a-z0-9._-]%''),
        CONSTRAINT CK_WebAccount_PasswordHash CHECK(LEN(LTRIM(RTRIM(password_hash)))>0),
        CONSTRAINT CK_WebAccount_Role CHECK(app_role COLLATE Latin1_General_100_BIN2 IN (''customer'',''member'',''clerk'',''manager'')
          AND DATALENGTH(app_role)=LEN(app_role)),
        CONSTRAINT CK_WebAccount_Sid CHECK(DATALENGTH(principal_sid) BETWEEN 1 AND 85),
        CONSTRAINT CK_WebAccount_SessionVersion CHECK(session_version>0)
    );');
    CREATE NONCLUSTERED INDEX IX_SalesOrder_Member_Time ON dbo.SalesOrder(member_id,order_time)
        INCLUDE(total_amount,status) WHERE member_id IS NOT NULL;
    CREATE NONCLUSTERED INDEX IX_SalesOrder_Guest_Time ON dbo.SalesOrder(guest_id,order_time)
        INCLUDE(total_amount,status) WHERE guest_id IS NOT NULL;
    CREATE NONCLUSTERED INDEX IX_OrderItem_Order ON dbo.OrderItem(order_id)
        INCLUDE(product_id,quantity,unit_price,sub_amount,product_name_snapshot,base_price_snapshot);
    -- GENERATED_MODULES
    GRANT EXECUTE ON OBJECT::teabar_api.usp_PlacePaidOrderJson TO teabar_customer;
    GRANT EXECUTE ON OBJECT::teabar_api.usp_PlacePaidOrderJson TO teabar_member;
    -- Do not DENY here: dbo ownership-chain based credential access is intentional.
    -- No WebAccount or credential/context grants to public or business roles.

    IF (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0)<>17
       OR (SELECT COUNT(*) FROM sys.columns AS c JOIN sys.tables AS t ON t.object_id=c.object_id WHERE t.is_ms_shipped=0)<>81
       OR (SELECT COUNT(*) FROM sys.foreign_keys)<>19
       OR (SELECT COUNT(*) FROM sys.procedures WHERE schema_id IN(SCHEMA_ID(N'teabar_api'),SCHEMA_ID(N'teabar_auth')))<>18
        THROW 52805, N'迁移后目标对象数量不符。', 1;
    DECLARE target_tables CURSOR LOCAL FAST_FORWARD FOR SELECT schema_name,table_name,order_columns FROM @expected_tables ORDER BY schema_name,table_name;
    OPEN target_tables; FETCH NEXT FROM target_tables INTO @schema,@table,@ordering;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @sql=N'SELECT @n=COUNT_BIG(*) FROM '+QUOTENAME(@schema)+N'.'+QUOTENAME(@table)+N';'
          +N'SELECT @h=HASHBYTES(''SHA2_256'',(SELECT * FROM '+QUOTENAME(@schema)+N'.'+QUOTENAME(@table)
          +N' ORDER BY '+@ordering+N' FOR XML RAW,BINARY BASE64));';
        EXEC sys.sp_executesql @sql,N'@n BIGINT OUTPUT,@h VARBINARY(32) OUTPUT',@n=@rows OUTPUT,@h=@hash OUTPUT;
        INSERT @after VALUES(@schema,@table,@rows,@hash);
        FETCH NEXT FROM target_tables INTO @schema,@table,@ordering;
    END;
    CLOSE target_tables; DEALLOCATE target_tables;
    IF EXISTS(SELECT * FROM @before EXCEPT SELECT * FROM @after)
       OR EXISTS(SELECT * FROM @after EXCEPT SELECT * FROM @before)
        THROW 52805, N'迁移前后业务表或身份绑定有未解释变化。', 1;
    EXEC sys.sp_addextendedproperty @name=N'TeabarDB.SchemaVersion',@value=N'1.0';
    IF @InjectFailure=1 THROW 52809, N'主动注入DDL后失败，验证事务回滚。', 1;
    SELECT N'VALIDATED_BEFORE_COMMIT' AS stage,b.schema_name,b.table_name,b.row_count AS before_rows,a.row_count AS after_rows,
        CONVERT(VARCHAR(64),b.data_hash,2) AS before_hash,CONVERT(VARCHAR(64),a.data_hash,2) AS after_hash
    FROM @before AS b JOIN @after AS a ON a.schema_name=b.schema_name AND a.table_name=b.table_name;
    IF @CommitMigration=1
    BEGIN
        COMMIT TRANSACTION;
        SELECT N'COMMITTED_V1.0' AS result,DB_NAME() AS database_name,17 AS expected_tables,81 AS expected_columns,19 AS expected_foreign_keys;
    END
    ELSE
    BEGIN
        ROLLBACK TRANSACTION;
        IF OBJECT_ID(N'teabar_auth.WebAccount') IS NOT NULL
           OR EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'TeabarDB.SchemaVersion')
           OR HASHBYTES('SHA2_256',REPLACE(OBJECT_DEFINITION(OBJECT_ID(N'teabar_api.usp_PlacePaidOrder')),CHAR(13),N'')) NOT IN(@source_core_hash,@source_core_literal_hash)
            THROW 52808, N'演练回滚后状态不符。', 1;
        SELECT N'DRY_RUN_ROLLED_BACK_TO_V0.1' AS result,DB_NAME() AS database_name;
    END;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    DECLARE @rollback_xact_state INT=XACT_STATE(),@rollback_trancount INT=@@TRANCOUNT;
    SELECT N'MIGRATION_FAILED_ROLLED_BACK' AS result,ERROR_NUMBER() AS error_number,ERROR_MESSAGE() AS detail,
        @rollback_xact_state AS transaction_state,@rollback_trancount AS transaction_count,OBJECT_ID(N'teabar_auth.WebAccount') AS webaccount_after_rollback,
        CASE WHEN HASHBYTES('SHA2_256',REPLACE(OBJECT_DEFINITION(OBJECT_ID(N'teabar_api.usp_PlacePaidOrder')),CHAR(13),N'')) IN(@source_core_hash,@source_core_literal_hash) THEN 1 ELSE 0 END AS original_core_restored;
    THROW;
END CATCH;
