-- Read-only comparison of frozen source and migrated work copy; no business writes.
SET NOCOUNT ON;
IF DB_NAME()<>N'TeabarDB_Phase2_Work' OR USER_NAME()<>N'dbo' OR @@TRANCOUNT<>0
    THROW 52900,N'请在指定工作库以dbo、无外层事务执行关键查询对照。',1;
IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'TeabarDB.SchemaVersion' AND CONVERT(NVARCHAR(20),value)=N'1.0')
    THROW 52900,N'工作库尚未提交v1.0。',1;
DECLARE @metrics TABLE(database_name SYSNAME,measure NVARCHAR(50),value NVARCHAR(100));
DECLARE @database SYSNAME,@sql NVARCHAR(MAX);
DECLARE databases_to_compare CURSOR LOCAL FAST_FORWARD FOR SELECT name FROM(VALUES(N'TeabarDB'),(N'TeabarDB_Phase2_Work')) AS d(name);
OPEN databases_to_compare; FETCH NEXT FROM databases_to_compare INTO @database;
WHILE @@FETCH_STATUS=0
BEGIN
    SET @sql=N'USE '+QUOTENAME(@database)+N';
    SELECT DB_NAME(),N''Product rows'',CONVERT(NVARCHAR(100),COUNT_BIG(*)) FROM dbo.Product
    UNION ALL SELECT DB_NAME(),N''Ingredient rows'',CONVERT(NVARCHAR(100),COUNT_BIG(*)) FROM dbo.Ingredient
    UNION ALL SELECT DB_NAME(),N''SalesOrder rows'',CONVERT(NVARCHAR(100),COUNT_BIG(*)) FROM dbo.SalesOrder
    UNION ALL SELECT DB_NAME(),N''OrderItem rows'',CONVERT(NVARCHAR(100),COUNT_BIG(*)) FROM dbo.OrderItem
    UNION ALL SELECT DB_NAME(),N''P001 base_price'',CONVERT(NVARCHAR(100),base_price) FROM dbo.Product WHERE product_id=''P001''
    UNION ALL SELECT DB_NAME(),N''I001 stock'',CONVERT(NVARCHAR(100),stock) FROM dbo.Ingredient WHERE ingredient_id=''I001''
    UNION ALL SELECT DB_NAME(),N''M001 points'',CONVERT(NVARCHAR(100),points) FROM dbo.Member WHERE member_id=''M001''
    UNION ALL SELECT DB_NAME(),N''2026-10-04 completed orders'',CONVERT(NVARCHAR(100),COUNT_BIG(*)) FROM dbo.SalesOrder WHERE status=N''已完成'' AND order_time>=''20261004'' AND order_time<''20261005''
    UNION ALL SELECT DB_NAME(),N''2026-10-04 cups'',CONVERT(NVARCHAR(100),SUM(i.quantity)) FROM dbo.OrderItem AS i JOIN dbo.SalesOrder AS o ON o.order_id=i.order_id WHERE o.status=N''已完成'' AND o.order_time>=''20261004'' AND o.order_time<''20261005''
    UNION ALL SELECT DB_NAME(),N''2026-10-04 amount'',CONVERT(NVARCHAR(100),SUM(total_amount)) FROM dbo.SalesOrder WHERE status=N''已完成'' AND order_time>=''20261004'' AND order_time<''20261005'';';
    INSERT @metrics EXEC sys.sp_executesql @sql;
    FETCH NEXT FROM databases_to_compare INTO @database;
END;
CLOSE databases_to_compare; DEALLOCATE databases_to_compare;
SELECT measure,MAX(CASE WHEN database_name=N'TeabarDB' THEN value END) AS frozen_source_value,
    MAX(CASE WHEN database_name=N'TeabarDB_Phase2_Work' THEN value END) AS migrated_value
FROM @metrics GROUP BY measure ORDER BY measure;
IF (SELECT COUNT(*) FROM @metrics)<>20
   OR EXISTS(SELECT measure FROM @metrics GROUP BY measure HAVING COUNT(*)<>2 OR MIN(value)<>MAX(value) OR COUNT(value)<>2)
    THROW 52901,N'关键查询对照不一致。',1;
SELECT N'KEY_QUERY_COMPARE_PASSED' AS result,10 AS matched_measures;
