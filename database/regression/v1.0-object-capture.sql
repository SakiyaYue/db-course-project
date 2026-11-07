-- Read-only target catalog evidence. Does not select WebAccount data or credential hashes.
SET NOCOUNT ON;
IF DB_NAME()<>N'TeabarDB_Phase2_Work' OR USER_NAME()<>N'dbo' OR @@TRANCOUNT<>0
    THROW 52900,N'请在指定工作库以dbo、无外层事务采集目标对象。',1;
IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'TeabarDB.SchemaVersion' AND CONVERT(NVARCHAR(20),value)=N'1.0')
    THROW 52900,N'工作库尚未提交v1.0。',1;
SELECT N'TARGET_TABLES' AS stage,s.name AS schema_name,t.name AS table_name
FROM sys.tables AS t JOIN sys.schemas AS s ON s.schema_id=t.schema_id WHERE t.is_ms_shipped=0 ORDER BY s.name,t.name;
SELECT N'TARGET_COLUMNS' AS stage,s.name AS schema_name,t.name AS table_name,c.column_id,c.name AS column_name,
    ty.name AS type_name,c.max_length,c.precision,c.scale,c.is_nullable,c.is_identity,c.is_computed,cc.is_persisted
FROM sys.tables AS t JOIN sys.schemas AS s ON s.schema_id=t.schema_id JOIN sys.columns AS c ON c.object_id=t.object_id
JOIN sys.types AS ty ON ty.user_type_id=c.user_type_id
LEFT JOIN sys.computed_columns AS cc ON cc.object_id=c.object_id AND cc.column_id=c.column_id
WHERE t.is_ms_shipped=0 ORDER BY s.name,t.name,c.column_id;
SELECT N'TARGET_KEYS' AS stage,OBJECT_SCHEMA_NAME(k.parent_object_id) AS schema_name,
    OBJECT_NAME(k.parent_object_id) AS table_name,k.name,k.type,c.name AS column_name,ic.key_ordinal
FROM sys.key_constraints AS k JOIN sys.tables AS t ON t.object_id=k.parent_object_id
JOIN sys.index_columns AS ic ON ic.object_id=k.parent_object_id AND ic.index_id=k.unique_index_id AND ic.key_ordinal>0
JOIN sys.columns AS c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
WHERE t.is_ms_shipped=0 ORDER BY schema_name,table_name,k.name,ic.key_ordinal;
SELECT N'TARGET_FK' AS stage,f.name,OBJECT_SCHEMA_NAME(f.parent_object_id) AS child_schema,OBJECT_NAME(f.parent_object_id) AS child_table,
    COL_NAME(fc.parent_object_id,fc.parent_column_id) AS child_column,
    OBJECT_SCHEMA_NAME(f.referenced_object_id) AS parent_schema,OBJECT_NAME(f.referenced_object_id) AS parent_table,
    COL_NAME(fc.referenced_object_id,fc.referenced_column_id) AS parent_column,fc.constraint_column_id,f.is_disabled,f.is_not_trusted
FROM sys.foreign_keys AS f JOIN sys.foreign_key_columns AS fc ON fc.constraint_object_id=f.object_id ORDER BY f.name,fc.constraint_column_id;
SELECT N'TARGET_CHECK' AS stage,OBJECT_SCHEMA_NAME(c.parent_object_id) AS schema_name,OBJECT_NAME(c.parent_object_id) AS table_name,
    c.name,c.definition,c.is_disabled,c.is_not_trusted
FROM sys.check_constraints AS c JOIN sys.tables AS t ON t.object_id=c.parent_object_id WHERE t.is_ms_shipped=0 ORDER BY schema_name,table_name,c.name;
SELECT N'TARGET_INDEX' AS stage,OBJECT_NAME(i.object_id) AS table_name,i.name,i.is_unique,i.is_disabled,i.filter_definition,
    c.name AS column_name,ic.key_ordinal,ic.is_included_column
FROM sys.indexes AS i JOIN sys.tables AS t ON t.object_id=i.object_id
JOIN sys.index_columns AS ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id
JOIN sys.columns AS c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
WHERE i.name IN(N'IX_SalesOrder_Member_Time',N'IX_SalesOrder_Guest_Time',N'IX_OrderItem_Order')
ORDER BY table_name,i.name,ic.index_column_id;
SELECT N'TARGET_MODULE' AS stage,OBJECT_SCHEMA_NAME(o.object_id) AS schema_name,o.name,o.type,
    sm.execute_as_principal_id,CONVERT(VARCHAR(64),HASHBYTES('SHA2_256',REPLACE(sm.definition,CHAR(13),N'')),2) AS definition_hash
FROM sys.objects AS o JOIN sys.sql_modules AS sm ON sm.object_id=o.object_id
WHERE o.is_ms_shipped=0 AND o.type IN('P','V','IF') ORDER BY schema_name,o.type,o.name;
SELECT N'TARGET_PARAMETER' AS stage,OBJECT_SCHEMA_NAME(p.object_id) AS schema_name,OBJECT_NAME(p.object_id) AS procedure_name,
    p.parameter_id,p.name,SCHEMA_NAME(ty.schema_id) AS type_schema,ty.name AS type_name,p.max_length,p.precision,p.scale,p.is_output,p.is_readonly
FROM sys.parameters AS p JOIN sys.procedures AS sp ON sp.object_id=p.object_id JOIN sys.types AS ty ON ty.user_type_id=p.user_type_id
WHERE sp.is_ms_shipped=0 ORDER BY schema_name,procedure_name,p.parameter_id;
SELECT N'TARGET_ROLE_MEMBER' AS stage,roles.name AS role_name,members.name AS member_name
FROM sys.database_role_members AS rm JOIN sys.database_principals AS roles ON roles.principal_id=rm.role_principal_id
JOIN sys.database_principals AS members ON members.principal_id=rm.member_principal_id
WHERE roles.name LIKE N'teabar[_]%' ORDER BY roles.name,members.name;
SELECT N'TARGET_NEW_PERMISSION' AS stage,grantees.name AS grantee,p.state_desc,p.permission_name,OBJECT_SCHEMA_NAME(p.major_id) AS schema_name,OBJECT_NAME(p.major_id) AS object_name
FROM sys.database_permissions AS p JOIN sys.database_principals AS grantees ON grantees.principal_id=p.grantee_principal_id
WHERE p.class=1 AND p.major_id IN(OBJECT_ID(N'teabar_api.usp_PlacePaidOrderJson'),OBJECT_ID(N'teabar_auth.WebAccount'),
    OBJECT_ID(N'teabar_auth.usp_GetWebCredential'),OBJECT_ID(N'teabar_auth.usp_GetWebContext')) ORDER BY grantees.name,object_name;
