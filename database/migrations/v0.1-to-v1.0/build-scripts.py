"""Generate reviewable SQL from frozen v0.1 and versioned v1.0 sources; never connect to SQL Server."""
from pathlib import Path
import hashlib
import importlib.util
import re

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
REG=ROOT/'database/regression'

def literal(s): return "N'"+s.replace("'","''")+"'"
def write(path,text): path.write_text(text.rstrip()+"\n",encoding='utf-8-sig')
def read(path): return path.read_text(encoding='utf-8-sig')
def values(name,columns,rows):
    def value(v):
        if v is None:return 'NULL'
        if isinstance(v,int):return str(v)
        return literal(v)
    return 'DECLARE '+name+' TABLE('+columns+');\nINSERT '+name+' VALUES\n'+',\n'.join('('+','.join(map(value,row))+')' for row in rows)+';\n'

role=read(ROOT/'role.sql')
constraint=read(ROOT/'constraint.sql')
creation=read(ROOT/'db_creation.sql')
modules={m.group(2):m.group(0).replace("''","'") for m in re.finditer(
    r'CREATE OR ALTER (PROCEDURE|VIEW|FUNCTION) (\w+\.\w+).*?(?=\'\);)',role,re.S)}
core=modules['teabar_api.usp_PlacePaidOrder']
anchor='        DECLARE @needed TABLE (ingredient_id VARCHAR(10) PRIMARY KEY, amount DECIMAL(10,2));'
assert core.count(anchor)==1
upgraded=core.replace(anchor,"""        -- v1.0 D01: check EVERY input item before stock deduction or persistent inserts.
        IF EXISTS(SELECT 1 FROM @items AS i WHERE NOT EXISTS(
            SELECT 1 FROM @consumption AS c WHERE c.item_id=i.item_id AND c.amount>0))
            THROW 52018, N'订单包含未产生正原料消耗的明细，整单拒绝。', 1;
"""+anchor)
write(HERE/'modules/usp_PlacePaidOrder.sql',upgraded.replace('CREATE OR ALTER PROCEDURE','ALTER PROCEDURE',1))

spec=importlib.util.spec_from_file_location('model',ROOT/'design/er/v1.0/build-design.py')
model=importlib.util.module_from_spec(spec);spec.loader.exec_module(model)
tables=model.read_schema(); del tables['WebAccount']
row_counts={'Employee':4,'DutyRoster':5,'Member':4,'SalesOrder':5,'Product':4,'Specification':9,
    'Ingredient':9,'OrderItem':7,'ProductSpecification':36,'Recipe':17,'AddOn':3,'ItemSpec':21,
    'ItemAddOn':4,'OrderItemIngredient':29,'SpecificationIngredient':75,'PrincipalBinding':4}
session="""SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
SET XACT_ABORT ON;
"""
manifest='-- Generated source manifest; all names are fixed source identifiers, not caller input.\n'
manifest+=values('@expected_tables','schema_name SYSNAME,table_name SYSNAME,order_columns NVARCHAR(300),expected_rows BIGINT',[
    (model.schema_name(t),t,','.join('['+c+']' for c in model.KEYS[t][0]),row_counts[t]) for t in tables])
column_rows=[]
for table,cols in tables.items():
    for c in cols:
        typ=c['type'].lower()
        if typ=='sysname':typ='nvarchar(128)'
        m=re.fullmatch(r'(\w+)(?:\((\d+)(?:,(\d+))?\))?',typ)
        base,n,scale=m.groups(); n=int(n or 0); scale=int(scale or 0)
        precision=0
        if base in ('varchar','nvarchar','varbinary'):length=n*(2 if base=='nvarchar' else 1)
        elif base=='decimal':length=5 if n<=9 else 9 if n<=19 else 13 if n<=28 else 17;precision=n
        elif base=='int':length=4;precision=10
        elif base=='bit':length=1;precision=1
        elif base=='uniqueidentifier':length=16
        elif base=='datetime2':length=6 if n<=2 else 7 if n<=4 else 8;precision=19+(n+1 if n else 0);scale=n
        else:raise AssertionError(typ)
        column_rows.append((model.schema_name(table),table,c['name'],base,length,precision,scale,int(c['nullable']),int(c['computed'])))
assert len(column_rows)==74
manifest+=values('@expected_columns','schema_name SYSNAME,table_name SYSNAME,column_name SYSNAME,type_name SYSNAME,max_length SMALLINT,precision_value TINYINT,scale_value TINYINT,is_nullable BIT,is_computed BIT',column_rows)
key_rows=[];fk_rows=[]
for table,body in re.findall(r'CREATE TABLE (\w+)\s*\((.*?)\n\);',creation,re.S):
    for name,kind,cols in re.findall(r'CONSTRAINT (\w+)\s+(PRIMARY KEY|UNIQUE)\s*\(([^)]+)\)',body):
        key_rows.append(('dbo',table,name,'PK' if kind=='PRIMARY KEY' else 'UQ',','.join(c.strip() for c in cols.split(','))))
    for name,child,parent,pc in re.findall(r'CONSTRAINT (\w+)\s+FOREIGN KEY\s*\(([^)]+)\)\s+REFERENCES (\w+)\s*\(([^)]+)\)',body,re.S):
        fk_rows.append((name,'dbo',table,','.join(c.strip() for c in child.split(',')),'dbo',parent,','.join(c.strip() for c in pc.split(','))))
key_rows += [('teabar_auth','PrincipalBinding','PK_PrincipalBinding','PK','principal_sid'),('teabar_auth','PrincipalBinding','UQ_PrincipalBinding_Name','UQ','principal_name')]
fk_rows += [('FK_SpecificationIngredient_Recipe','dbo','SpecificationIngredient','product_id,ingredient_id','dbo','Recipe','product_id,ingredient_id'),('FK_PrincipalBinding_Member','teabar_auth','PrincipalBinding','member_id','dbo','Member','member_id')]
assert len(key_rows)==22 and len(fk_rows)==19
manifest+=values('@expected_keys','schema_name SYSNAME,table_name SYSNAME,constraint_name SYSNAME,key_type CHAR(2),key_columns NVARCHAR(300)',key_rows)
manifest+=values('@expected_fks','constraint_name SYSNAME,child_schema SYSNAME,child_table SYSNAME,child_columns NVARCHAR(300),parent_schema SYSNAME,parent_table SYSNAME,parent_columns NVARCHAR(300)',fk_rows)
checks=sorted(set(re.findall(r'CONSTRAINT\s+(CK_\w+)',creation+'\n'+constraint+'\n'+role)))
assert len(checks)==46,len(checks)
manifest+=values('@expected_checks','constraint_name SYSNAME',[(x,) for x in checks])
defaults=[(table,c['name']) for table,cols in tables.items() for c in cols if c['default']!='—' and not c['computed']]
manifest+=values('@expected_defaults','table_name SYSNAME,column_name SYSNAME',defaults)
required=[]
for name,definition in modules.items():
    required.append((*name.split('.'),'P' if ' PROCEDURE ' in definition else 'V' if ' VIEW ' in definition else 'IF'))
for name in re.findall(r'CREATE OR ALTER VIEW\s+(dbo\.\w+)',read(ROOT/'view.sql')):required.append((*name.split('.'),'V'))
assert len(required)==45,len(required)
manifest+=values('@expected_modules','schema_name SYSNAME,object_name SYSNAME,object_type VARCHAR(2)',required)
manifest+=values('@expected_roles','role_name SYSNAME',[(x,) for x in ['teabar_customer','teabar_member','teabar_clerk','teabar_manager']])
manifest+=values('@expected_users','user_name SYSNAME,role_name SYSNAME',[
    ('demo_guest_a','teabar_customer'),('demo_guest_b','teabar_customer'),('demo_member_a','teabar_member'),
    ('demo_member_b','teabar_member'),('demo_clerk','teabar_clerk'),('demo_manager','teabar_manager')])
# SQL Server stores CREATE OR ALTER as CREATE plus three spaces in sys.sql_modules.
# Accept only the literal frozen source or this observed header rewrite; body remains exact.
core_literal_hash=hashlib.sha256(core.encode('utf-16le')).hexdigest()
core_catalog_hash=hashlib.sha256(core.replace('CREATE OR ALTER PROCEDURE','CREATE   PROCEDURE',1).encode('utf-16le')).hexdigest()
manifest+='DECLARE @source_core_hash VARBINARY(32)=0x'+core_catalog_hash+';\n'
manifest+='DECLARE @source_core_literal_hash VARBINARY(32)=0x'+core_literal_hash+';\n'
manifest+='IF TYPE_ID(N\'teabar_api.OrderLines\') IS NULL OR TYPE_ID(N\'teabar_api.OrderSpecs\') IS NULL OR TYPE_ID(N\'teabar_api.OrderAddOns\') IS NULL THROW 52802,N\'缺少冻结TVP类型。\',1;\n'
body=read(HERE/'migration-body.sql')
module_sql='\n'.join('    EXEC('+literal(read(HERE/'modules'/name))+');' for name in [
    'usp_PlacePaidOrder.sql','usp_PlacePaidOrderJson.sql','usp_GetWebCredential.sql','usp_GetWebContext.sql'])
body=body.replace('    -- GENERATED_MODULES',module_sql)
write(HERE/'migration.sql','-- GENERATED by build-scripts.py; edit versioned sources and rebuild.\n-- NO USE/GO/SQLCMD; verify target database and flags below before running.\n'+session+manifest+body)

# Extract only tests. No root USE, table/role installation or procedure replacement is copied.
start=constraint.index('SET XACT_ABORT OFF;',constraint.index('-- 二、正反例验证'))
end=constraint.index('-- 三、检查安装结果')
legacy_constraint=constraint[start:end]
legacy_constraint=legacy_constraint[:legacy_constraint.rfind('-- ============================================================')]
hook="""    IF (SELECT COUNT(*) FROM @results)<>44 THROW 52901,N'提取的约束用例数量不是44。',1;
    INSERT #RegressionResults(suite,case_name,expected_error,actual_error,passed,detail)
        SELECT N'legacy-constraint',case_name,expected_error,actual_error,passed,detail FROM @results;
"""
legacy_constraint=legacy_constraint.replace('    SET XACT_ABORT ON;\n    SELECT seq, case_name',hook+'    SET XACT_ABORT ON;\n    SELECT seq, case_name',1)
assert 'INSERT #RegressionResults' in legacy_constraint
write(REG/'legacy-constraint-tests.sql','-- Generated test-only extraction from constraint.sql; no installation DDL.\n'+legacy_constraint)
test_match=re.search(r"EXEC\(N'(SET NOCOUNT ON;\nSET XACT_ABORT OFF;.*?)'\);\nSET XACT_ABORT ON;",role,re.S)
assert test_match
legacy_role=test_match.group(1).replace("''","'")
hook=""" IF (SELECT COUNT(*) FROM @results)<>84 THROW 52901,N'提取的角色用例数量不是84。',1;
 INSERT #RegressionResults(suite,case_name,expected_error,actual_error,passed,detail)
  SELECT N'legacy-role',case_name,expected_error,actual_error,passed,detail FROM @results;
"""
legacy_role=legacy_role.replace(' SELECT seq,user_name,case_name,expected_error,actual_error,',hook+' SELECT seq,user_name,case_name,expected_error,actual_error,',1)
assert 'INSERT #RegressionResults' in legacy_role
write(REG/'legacy-role-tests.sql','-- Generated test-only extraction from role.sql; no installation DDL.\n'+legacy_role)

if (REG/'regression-body.sql').exists():
    regression=read(REG/'regression-body.sql')
    regression=regression.replace('-- GENERATED_REGRESSION_TABLES',
        'INSERT @tables VALUES\n'+',\n'.join('('+','.join(map(literal,[t,model.schema_name(t),','.join('['+c+']' for c in model.KEYS[t][0])]))+')' for t in [*tables,'WebAccount'])+';')
    regression=regression.replace('-- GENERATED_LEGACY_TESTS',
        'EXEC('+literal(legacy_constraint)+');\nEXEC('+literal(legacy_role)+');')
    if (REG/'v1.0-new-tests.sql').exists():
        regression=regression.replace('-- GENERATED_NEW_TESTS','EXEC('+literal(read(REG/'v1.0-new-tests.sql'))+');')
    write(REG/'regression.sql','-- GENERATED by database/migrations/v0.1-to-v1.0/build-scripts.py.\n'+session+regression)

verify="""-- Read-only rollback check; execute only on the named work copy after injected failure/dry run.
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
 OR HASHBYTES('SHA2_256',REPLACE(OBJECT_DEFINITION(OBJECT_ID(N'teabar_api.usp_PlacePaidOrder')),CHAR(13),N'')) NOT IN(SOURCEHASHES)
 OR OBJECT_DEFINITION(OBJECT_ID(N'teabar_api.usp_PlacePaidOrder')) IS NULL
 THROW 52808,N'回滚后对象或核心定义不符合冻结v0.1。',1;
SELECT N'ROLLBACK_OBJECT_CHECK_PASSED' AS result,DB_NAME() AS database_name;
-- Compare these fingerprints to PRE_MIGRATION in the saved log, not only to object counts.
DECLARE @t SYSNAME,@s SYSNAME,@o NVARCHAR(300),@sql NVARCHAR(MAX),@n BIGINT,@h VARBINARY(32);
DECLARE @data TABLE(table_name SYSNAME,row_count BIGINT,data_hash VARBINARY(32));
DECLARE @tables TABLE(schema_name SYSNAME,table_name SYSNAME,order_columns NVARCHAR(300),expected_rows BIGINT);
INSERT @tables VALUES
TABLEROWS;
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
""".replace('SOURCEHASHES','0x'+core_catalog_hash+',0x'+core_literal_hash).replace('TABLEROWS',
    ',\n'.join('('+','.join([literal(model.schema_name(t)),literal(t),literal(','.join('['+c+']' for c in model.KEYS[t][0])),str(row_counts[t])])+')' for t in tables))
write(REG/'verify-rollback.sql',session+verify)
source_verify=verify.replace("N'TeabarDB_Phase2_Work'","N'TeabarDB'").replace("IN(N'TeabarDB',N'master'","IN(N'master'")
source_verify=source_verify.replace('ROLLBACK_OBJECT_CHECK_PASSED','SOURCE_OBJECT_CHECK_PASSED')
source_verify=source_verify.replace('-- Read-only rollback check; execute only on the named work copy after injected failure/dry run.',
    '-- Read-only frozen-source fingerprint; run before and after work-copy operations, never performs DDL/DML.')
source_verify += """
SELECT N'SOURCE_METADATA' AS stage,HASHBYTES('SHA2_256',
 (SELECT object_id,definition,uses_ansi_nulls,uses_quoted_identifier,execute_as_principal_id
  FROM sys.sql_modules ORDER BY object_id FOR XML RAW,BINARY BASE64)
+(SELECT object_id,column_id,name,user_type_id,max_length,precision,scale,is_nullable,is_identity,is_computed
  FROM sys.columns WHERE object_id IN(SELECT object_id FROM sys.tables WHERE is_ms_shipped=0)
  ORDER BY object_id,column_id FOR XML RAW)
+(SELECT * FROM sys.database_role_members ORDER BY role_principal_id,member_principal_id FOR XML RAW)
+(SELECT * FROM sys.database_permissions ORDER BY class,major_id,minor_id,grantee_principal_id,grantor_principal_id,type FOR XML RAW)
+(SELECT object_id,name,definition,is_disabled,is_not_trusted FROM sys.check_constraints ORDER BY object_id FOR XML RAW)
+(SELECT object_id,name,parent_object_id,referenced_object_id,is_disabled,is_not_trusted
  FROM sys.foreign_keys ORDER BY object_id FOR XML RAW)) AS metadata_hash;
"""
write(REG/'source-integrity.sql',session+source_verify)
print('Built standalone migration and extracted 44 + 84 legacy tests. No SQL executed.')
