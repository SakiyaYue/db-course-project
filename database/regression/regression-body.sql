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
-- GENERATED_REGRESSION_TABLES
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
    -- GENERATED_LEGACY_TESTS
    -- GENERATED_NEW_TESTS

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
