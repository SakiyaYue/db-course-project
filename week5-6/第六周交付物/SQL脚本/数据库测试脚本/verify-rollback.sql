SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
SET XACT_ABORT ON;
-- Read-only rollback check; execute only on the named work copy after injected failure/dry run.
DECLARE @ExpectedDatabase SYSNAME=N'TeabarDB_Phase2_Work';
IF DB_NAME()<>@ExpectedDatabase OR DB_NAME() IN(N'TeabarDB',N'master',N'model',N'msdb',N'tempdb') OR @@TRANCOUNT<>0
 THROW 52808,N'请在独立工作库、无未结束事务时核对回滚。',1;
IF (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0)<>16
 OR (SELECT COUNT(*) FROM sys.columns AS c JOIN sys.tables AS t ON t.object_id=c.object_id WHERE t.is_ms_shipped=0)<>74
 OR (SELECT COUNT(*) FROM sys.foreign_keys)<>19
 OR OBJECT_ID(N'teabar_auth.WebAccount') IS NOT NULL
 OR OBJECT_ID(N'teabar_api.usp_PlacePaidOrderJson') IS NOT NULL
 OR OBJECT_ID(N'teabar_auth.usp_GetWebCredential') IS NOT NULL
 OR OBJECT_ID(N'teabar_auth.usp_GetWebContext') IS NOT NULL
 OR EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'TeabarDB.SchemaVersion')
 OR EXISTS(SELECT 1 FROM sys.indexes WHERE (object_id=OBJECT_ID(N'dbo.SalesOrder') AND name IN(N'IX_SalesOrder_Member_Time',N'IX_SalesOrder_Guest_Time'))
       OR (object_id=OBJECT_ID(N'dbo.OrderItem') AND name=N'IX_OrderItem_Order'))
 OR HASHBYTES('SHA2_256',REPLACE(OBJECT_DEFINITION(OBJECT_ID(N'teabar_api.usp_PlacePaidOrder')),CHAR(13),N'')) NOT IN(0xdf55ebfd6a4ed75c284867d1a8bb7bf6ff5985e4f4a8f95d274859fd05e1e198,0x5a3789322ae00b75b7733fb118f228170dbdcd540779d66a26a50778b6c3e13c)
 OR OBJECT_DEFINITION(OBJECT_ID(N'teabar_api.usp_PlacePaidOrder')) IS NULL
 THROW 52808,N'回滚后对象或核心定义不符合冻结v0.1。',1;
SELECT N'ROLLBACK_OBJECT_CHECK_PASSED' AS result,DB_NAME() AS database_name;
-- Compare these fingerprints to PRE_MIGRATION in the saved log, not only to object counts.
DECLARE @t SYSNAME,@s SYSNAME,@o NVARCHAR(300),@sql NVARCHAR(MAX),@n BIGINT,@h VARBINARY(32);
DECLARE @data TABLE(table_name SYSNAME,row_count BIGINT,data_hash VARBINARY(32));
DECLARE @tables TABLE(schema_name SYSNAME,table_name SYSNAME,order_columns NVARCHAR(300),expected_rows BIGINT);
INSERT @tables VALUES
(N'dbo',N'Employee',N'[employee_id]',4),
(N'dbo',N'DutyRoster',N'[duty_id]',5),
(N'dbo',N'Member',N'[member_id]',4),
(N'dbo',N'SalesOrder',N'[order_id]',5),
(N'dbo',N'Product',N'[product_id]',4),
(N'dbo',N'Specification',N'[spec_id]',9),
(N'dbo',N'Ingredient',N'[ingredient_id]',9),
(N'dbo',N'OrderItem',N'[item_id]',7),
(N'dbo',N'ProductSpecification',N'[product_id],[spec_id]',36),
(N'dbo',N'Recipe',N'[product_id],[ingredient_id]',17),
(N'dbo',N'AddOn',N'[addon_id]',3),
(N'dbo',N'ItemSpec',N'[item_id],[spec_type]',21),
(N'dbo',N'ItemAddOn',N'[item_id],[addon_id]',4),
(N'dbo',N'OrderItemIngredient',N'[item_id],[ingredient_id]',29),
(N'dbo',N'SpecificationIngredient',N'[product_id],[spec_id],[ingredient_id]',75),
(N'teabar_auth',N'PrincipalBinding',N'[principal_sid]',4);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT schema_name,table_name,order_columns FROM @tables;
OPEN c; FETCH NEXT FROM c INTO @s,@t,@o;
WHILE @@FETCH_STATUS=0
BEGIN
 SET @sql=N'SELECT @n=COUNT_BIG(*) FROM '+QUOTENAME(@s)+N'.'+QUOTENAME(@t)+N';SELECT @h=HASHBYTES(''SHA2_256'',(SELECT * FROM '
   +QUOTENAME(@s)+N'.'+QUOTENAME(@t)+N' ORDER BY '+@o+N' FOR XML RAW,BINARY BASE64));';
 EXEC sys.sp_executesql @sql,N'@n BIGINT OUTPUT,@h VARBINARY(32) OUTPUT',@n=@n OUTPUT,@h=@h OUTPUT;
 INSERT @data VALUES(@t,@n,@h);
 FETCH NEXT FROM c INTO @s,@t,@o;
END;
CLOSE c; DEALLOCATE c;
IF EXISTS(SELECT 1 FROM @data AS d JOIN @tables AS e ON e.table_name=d.table_name WHERE d.row_count<>e.expected_rows)
 THROW 52808,N'回滚后基准行数不符。',1;
SELECT table_name,row_count,CONVERT(VARCHAR(64),data_hash,2) AS data_hash FROM @data ORDER BY table_name;
