-- Week 6 standalone migration; module definitions and source manifest are embedded.
-- NO USE/GO/SQLCMD; verify target database and flags below before running.
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
SET XACT_ABORT ON;
-- Generated source manifest; all names are fixed source identifiers, not caller input.
DECLARE @expected_tables TABLE(schema_name SYSNAME,table_name SYSNAME,order_columns NVARCHAR(300),expected_rows BIGINT);
INSERT @expected_tables VALUES
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
DECLARE @expected_columns TABLE(schema_name SYSNAME,table_name SYSNAME,column_name SYSNAME,type_name SYSNAME,max_length SMALLINT,precision_value TINYINT,scale_value TINYINT,is_nullable BIT,is_computed BIT);
INSERT @expected_columns VALUES
(N'dbo',N'Employee',N'employee_id',N'varchar',10,0,0,0,0),
(N'dbo',N'Employee',N'name',N'nvarchar',100,0,0,0,0),
(N'dbo',N'Employee',N'status',N'nvarchar',20,0,0,0,0),
(N'dbo',N'Employee',N'salary',N'decimal',9,10,2,0,0),
(N'dbo',N'Employee',N'role',N'nvarchar',40,0,0,0,0),
(N'dbo',N'DutyRoster',N'duty_id',N'varchar',10,0,0,0,0),
(N'dbo',N'DutyRoster',N'employee_id',N'varchar',10,0,0,0,0),
(N'dbo',N'DutyRoster',N'start_time',N'datetime2',6,19,0,0,0),
(N'dbo',N'DutyRoster',N'end_time',N'datetime2',6,19,0,0,0),
(N'dbo',N'Member',N'member_id',N'varchar',10,0,0,0,0),
(N'dbo',N'Member',N'name',N'nvarchar',100,0,0,0,0),
(N'dbo',N'Member',N'phone',N'varchar',20,0,0,0,0),
(N'dbo',N'Member',N'points',N'int',4,10,0,0,0),
(N'dbo',N'SalesOrder',N'order_id',N'varchar',10,0,0,0,0),
(N'dbo',N'SalesOrder',N'member_id',N'varchar',10,0,0,1,0),
(N'dbo',N'SalesOrder',N'guest_id',N'uniqueidentifier',16,0,0,1,0),
(N'dbo',N'SalesOrder',N'order_time',N'datetime2',6,19,0,0,0),
(N'dbo',N'SalesOrder',N'total_amount',N'decimal',9,10,2,0,0),
(N'dbo',N'SalesOrder',N'status',N'nvarchar',40,0,0,0,0),
(N'dbo',N'Product',N'product_id',N'varchar',10,0,0,0,0),
(N'dbo',N'Product',N'product_name',N'nvarchar',100,0,0,0,0),
(N'dbo',N'Product',N'base_price',N'decimal',9,10,2,0,0),
(N'dbo',N'Product',N'status',N'nvarchar',20,0,0,0,0),
(N'dbo',N'Product',N'description',N'nvarchar',400,0,0,1,0),
(N'dbo',N'Specification',N'spec_id',N'varchar',10,0,0,0,0),
(N'dbo',N'Specification',N'spec_type',N'nvarchar',40,0,0,0,0),
(N'dbo',N'Specification',N'spec_name',N'nvarchar',40,0,0,0,0),
(N'dbo',N'Ingredient',N'ingredient_id',N'varchar',10,0,0,0,0),
(N'dbo',N'Ingredient',N'ingredient_name',N'nvarchar',100,0,0,0,0),
(N'dbo',N'Ingredient',N'unit',N'nvarchar',20,0,0,0,0),
(N'dbo',N'Ingredient',N'stock',N'decimal',9,10,2,0,0),
(N'dbo',N'Ingredient',N'status',N'nvarchar',20,0,0,0,0),
(N'dbo',N'OrderItem',N'item_id',N'varchar',10,0,0,0,0),
(N'dbo',N'OrderItem',N'order_id',N'varchar',10,0,0,0,0),
(N'dbo',N'OrderItem',N'product_id',N'varchar',10,0,0,0,0),
(N'dbo',N'OrderItem',N'product_name_snapshot',N'nvarchar',100,0,0,0,0),
(N'dbo',N'OrderItem',N'quantity',N'int',4,10,0,0,0),
(N'dbo',N'OrderItem',N'base_price_snapshot',N'decimal',9,10,2,0,0),
(N'dbo',N'OrderItem',N'unit_price',N'decimal',9,10,2,0,0),
(N'dbo',N'OrderItem',N'sub_amount',N'decimal',9,10,2,0,1),
(N'dbo',N'ProductSpecification',N'product_id',N'varchar',10,0,0,0,0),
(N'dbo',N'ProductSpecification',N'spec_id',N'varchar',10,0,0,0,0),
(N'dbo',N'ProductSpecification',N'price_delta',N'decimal',9,10,2,0,0),
(N'dbo',N'ProductSpecification',N'status',N'nvarchar',20,0,0,0,0),
(N'dbo',N'Recipe',N'product_id',N'varchar',10,0,0,0,0),
(N'dbo',N'Recipe',N'ingredient_id',N'varchar',10,0,0,0,0),
(N'dbo',N'Recipe',N'base_amount',N'decimal',9,10,2,0,0),
(N'dbo',N'AddOn',N'addon_id',N'varchar',10,0,0,0,0),
(N'dbo',N'AddOn',N'addon_name',N'nvarchar',100,0,0,0,0),
(N'dbo',N'AddOn',N'price',N'decimal',9,10,2,0,0),
(N'dbo',N'AddOn',N'ingredient_id',N'varchar',10,0,0,0,0),
(N'dbo',N'AddOn',N'extra_amount',N'decimal',9,10,2,0,0),
(N'dbo',N'AddOn',N'status',N'nvarchar',20,0,0,0,0),
(N'dbo',N'ItemSpec',N'item_id',N'varchar',10,0,0,0,0),
(N'dbo',N'ItemSpec',N'spec_type',N'nvarchar',40,0,0,0,0),
(N'dbo',N'ItemSpec',N'spec_id',N'varchar',10,0,0,0,0),
(N'dbo',N'ItemSpec',N'spec_name_snapshot',N'nvarchar',40,0,0,0,0),
(N'dbo',N'ItemSpec',N'price_delta_snapshot',N'decimal',9,10,2,0,0),
(N'dbo',N'ItemAddOn',N'item_id',N'varchar',10,0,0,0,0),
(N'dbo',N'ItemAddOn',N'addon_id',N'varchar',10,0,0,0,0),
(N'dbo',N'ItemAddOn',N'addon_name_snapshot',N'nvarchar',100,0,0,0,0),
(N'dbo',N'ItemAddOn',N'price_snapshot',N'decimal',9,10,2,0,0),
(N'dbo',N'OrderItemIngredient',N'item_id',N'varchar',10,0,0,0,0),
(N'dbo',N'OrderItemIngredient',N'ingredient_id',N'varchar',10,0,0,0,0),
(N'dbo',N'OrderItemIngredient',N'amount',N'decimal',9,10,2,0,0),
(N'dbo',N'SpecificationIngredient',N'product_id',N'varchar',10,0,0,0,0),
(N'dbo',N'SpecificationIngredient',N'spec_id',N'varchar',10,0,0,0,0),
(N'dbo',N'SpecificationIngredient',N'ingredient_id',N'varchar',10,0,0,0,0),
(N'dbo',N'SpecificationIngredient',N'factor',N'decimal',5,5,2,0,0),
(N'teabar_auth',N'PrincipalBinding',N'principal_sid',N'varbinary',85,0,0,0,0),
(N'teabar_auth',N'PrincipalBinding',N'principal_name',N'nvarchar',256,0,0,0,0),
(N'teabar_auth',N'PrincipalBinding',N'member_id',N'varchar',10,0,0,1,0),
(N'teabar_auth',N'PrincipalBinding',N'guest_id',N'uniqueidentifier',16,0,0,1,0),
(N'teabar_auth',N'PrincipalBinding',N'is_active',N'bit',1,1,0,0,0);
DECLARE @expected_keys TABLE(schema_name SYSNAME,table_name SYSNAME,constraint_name SYSNAME,key_type CHAR(2),key_columns NVARCHAR(300));
INSERT @expected_keys VALUES
(N'dbo',N'Employee',N'PK_Employee',N'PK',N'employee_id'),
(N'dbo',N'DutyRoster',N'PK_DutyRoster',N'PK',N'duty_id'),
(N'dbo',N'DutyRoster',N'UQ_DutyRoster_Employee_StartTime',N'UQ',N'employee_id,start_time'),
(N'dbo',N'Member',N'PK_Member',N'PK',N'member_id'),
(N'dbo',N'Member',N'UK_Member_Phone',N'UQ',N'phone'),
(N'dbo',N'SalesOrder',N'PK_SalesOrder',N'PK',N'order_id'),
(N'dbo',N'Product',N'PK_Product',N'PK',N'product_id'),
(N'dbo',N'Specification',N'PK_Specification',N'PK',N'spec_id'),
(N'dbo',N'Specification',N'UK_Specification_typename',N'UQ',N'spec_type,spec_name'),
(N'dbo',N'Specification',N'UK_Specification_idtype',N'UQ',N'spec_id,spec_type'),
(N'dbo',N'Ingredient',N'PK_Ingredient',N'PK',N'ingredient_id'),
(N'dbo',N'OrderItem',N'PK_OrderItem',N'PK',N'item_id'),
(N'dbo',N'ProductSpecification',N'PK_ProductSpecification',N'PK',N'product_id,spec_id'),
(N'dbo',N'Recipe',N'PK_Recipe',N'PK',N'product_id,ingredient_id'),
(N'dbo',N'AddOn',N'PK_AddOn',N'PK',N'addon_id'),
(N'dbo',N'AddOn',N'UK_AddOn_name',N'UQ',N'addon_name'),
(N'dbo',N'ItemSpec',N'PK_ItemSpec',N'PK',N'item_id,spec_type'),
(N'dbo',N'ItemAddOn',N'PK_ItemAddOn',N'PK',N'item_id,addon_id'),
(N'dbo',N'OrderItemIngredient',N'PK_OrderItemIngredient',N'PK',N'item_id,ingredient_id'),
(N'dbo',N'SpecificationIngredient',N'PK_SpecificationIngredient',N'PK',N'product_id,spec_id,ingredient_id'),
(N'teabar_auth',N'PrincipalBinding',N'PK_PrincipalBinding',N'PK',N'principal_sid'),
(N'teabar_auth',N'PrincipalBinding',N'UQ_PrincipalBinding_Name',N'UQ',N'principal_name');
DECLARE @expected_fks TABLE(constraint_name SYSNAME,child_schema SYSNAME,child_table SYSNAME,child_columns NVARCHAR(300),parent_schema SYSNAME,parent_table SYSNAME,parent_columns NVARCHAR(300));
INSERT @expected_fks VALUES
(N'FK_DutyRoster_Employee',N'dbo',N'DutyRoster',N'employee_id',N'dbo',N'Employee',N'employee_id'),
(N'FK_SalesOrder_Member',N'dbo',N'SalesOrder',N'member_id',N'dbo',N'Member',N'member_id'),
(N'FK_OrderItem_Order',N'dbo',N'OrderItem',N'order_id',N'dbo',N'SalesOrder',N'order_id'),
(N'FK_OrderItem_Product',N'dbo',N'OrderItem',N'product_id',N'dbo',N'Product',N'product_id'),
(N'FK_ProductSpecification_Product',N'dbo',N'ProductSpecification',N'product_id',N'dbo',N'Product',N'product_id'),
(N'FK_ProductSpecification_Specification',N'dbo',N'ProductSpecification',N'spec_id',N'dbo',N'Specification',N'spec_id'),
(N'FK_Recipe_Product',N'dbo',N'Recipe',N'product_id',N'dbo',N'Product',N'product_id'),
(N'FK_Recipe_Ingredient',N'dbo',N'Recipe',N'ingredient_id',N'dbo',N'Ingredient',N'ingredient_id'),
(N'FK_AddOn_Ingredient',N'dbo',N'AddOn',N'ingredient_id',N'dbo',N'Ingredient',N'ingredient_id'),
(N'FK_ItemSpec_OrderItem',N'dbo',N'ItemSpec',N'item_id',N'dbo',N'OrderItem',N'item_id'),
(N'FK_ItemSpec_Spec_id',N'dbo',N'ItemSpec',N'spec_id,spec_type',N'dbo',N'Specification',N'spec_id,spec_type'),
(N'FK_ItemAddOn_OrderItem',N'dbo',N'ItemAddOn',N'item_id',N'dbo',N'OrderItem',N'item_id'),
(N'FK_ItemAddOn_AddOn',N'dbo',N'ItemAddOn',N'addon_id',N'dbo',N'AddOn',N'addon_id'),
(N'FK_OrderItemIngredient_OrderItem',N'dbo',N'OrderItemIngredient',N'item_id',N'dbo',N'OrderItem',N'item_id'),
(N'FK_OrderItemIngredient_Ingredient',N'dbo',N'OrderItemIngredient',N'ingredient_id',N'dbo',N'Ingredient',N'ingredient_id'),
(N'FK_SpecificationIngredient_ProductSpec',N'dbo',N'SpecificationIngredient',N'product_id,spec_id',N'dbo',N'ProductSpecification',N'product_id,spec_id'),
(N'FK_SpecificationIngredient_Ingredient',N'dbo',N'SpecificationIngredient',N'ingredient_id',N'dbo',N'Ingredient',N'ingredient_id'),
(N'FK_SpecificationIngredient_Recipe',N'dbo',N'SpecificationIngredient',N'product_id,ingredient_id',N'dbo',N'Recipe',N'product_id,ingredient_id'),
(N'FK_PrincipalBinding_Member',N'teabar_auth',N'PrincipalBinding',N'member_id',N'dbo',N'Member',N'member_id');
DECLARE @expected_checks TABLE(constraint_name SYSNAME);
INSERT @expected_checks VALUES
(N'CK_AddOn_ExtraAmount'),
(N'CK_AddOn_Id_NotBlank'),
(N'CK_AddOn_Name_NotBlank'),
(N'CK_AddOn_Price'),
(N'CK_AddOn_Status'),
(N'CK_DutyRoster_Id_NotBlank'),
(N'CK_DutyRoster_Time'),
(N'CK_Employee_Id_NotBlank'),
(N'CK_Employee_Name_NotBlank'),
(N'CK_Employee_Role'),
(N'CK_Employee_Salary'),
(N'CK_Employee_Status'),
(N'CK_Ingredient_Id_NotBlank'),
(N'CK_Ingredient_Name_NotBlank'),
(N'CK_Ingredient_PieceStock'),
(N'CK_Ingredient_Status'),
(N'CK_Ingredient_Stock'),
(N'CK_Ingredient_Unit'),
(N'CK_ItemAddOn_Name_NotBlank'),
(N'CK_ItemAddOn_Price'),
(N'CK_ItemSpec_Name_NotBlank'),
(N'CK_Member_Id_NotBlank'),
(N'CK_Member_Name_NotBlank'),
(N'CK_Member_Phone_Format'),
(N'CK_Member_Points'),
(N'CK_OrderItemIngredient_Amount'),
(N'CK_OrderItem_BasePrice'),
(N'CK_OrderItem_Id_NotBlank'),
(N'CK_OrderItem_ProductName_NotBlank'),
(N'CK_OrderItem_Quantity'),
(N'CK_OrderItem_UnitPrice'),
(N'CK_PrincipalBinding_Identity'),
(N'CK_ProductSpecification_Status'),
(N'CK_Product_Id_NotBlank'),
(N'CK_Product_Name_NotBlank'),
(N'CK_Product_Price'),
(N'CK_Product_Status'),
(N'CK_Recipe_BaseAmount'),
(N'CK_SalesOrder_Amount'),
(N'CK_SalesOrder_Id_NotBlank'),
(N'CK_SalesOrder_Owner'),
(N'CK_SalesOrder_status'),
(N'CK_SpecificationIngredient_Factor'),
(N'CK_Specification_Id_NotBlank'),
(N'CK_Specification_Name_NotBlank'),
(N'CK_Specification_Type');
DECLARE @expected_defaults TABLE(table_name SYSNAME,column_name SYSNAME);
INSERT @expected_defaults VALUES
(N'Employee',N'status'),
(N'Member',N'points'),
(N'SalesOrder',N'order_time'),
(N'SalesOrder',N'status'),
(N'Product',N'status'),
(N'Ingredient',N'stock'),
(N'Ingredient',N'status'),
(N'OrderItem',N'quantity'),
(N'ProductSpecification',N'price_delta'),
(N'ProductSpecification',N'status'),
(N'AddOn',N'status'),
(N'PrincipalBinding',N'is_active');
DECLARE @expected_modules TABLE(schema_name SYSNAME,object_name SYSNAME,object_type VARCHAR(2));
INSERT @expected_modules VALUES
(N'teabar_auth',N'fn_CurrentIdentity',N'IF'),
(N'teabar_api',N'vw_Menu',N'V'),
(N'teabar_api',N'vw_AvailableSpecifications',N'V'),
(N'teabar_api',N'vw_AvailableAddOns',N'V'),
(N'teabar_api',N'vw_MyOrders',N'V'),
(N'teabar_api',N'vw_MyOrderItems',N'V'),
(N'teabar_api',N'vw_MyItemSpecs',N'V'),
(N'teabar_api',N'vw_MyItemAddOns',N'V'),
(N'teabar_api',N'vw_MyMember',N'V'),
(N'teabar_api',N'vw_WorkOrders',N'V'),
(N'teabar_api',N'vw_WorkOrderItems',N'V'),
(N'teabar_api',N'vw_WorkItemSpecs',N'V'),
(N'teabar_api',N'vw_WorkItemAddOns',N'V'),
(N'teabar_api',N'vw_WorkConsumption',N'V'),
(N'teabar_api',N'vw_WorkTeam',N'V'),
(N'teabar_api',N'vw_DailySales',N'V'),
(N'teabar_api',N'vw_ProductSales',N'V'),
(N'teabar_api',N'usp_PlacePaidOrder',N'P'),
(N'teabar_api',N'usp_AdvanceOrder',N'P'),
(N'teabar_api',N'usp_RefundOrder',N'P'),
(N'teabar_api',N'usp_AdjustStock',N'P'),
(N'teabar_api',N'usp_SaveMember',N'P'),
(N'teabar_api',N'usp_FindMember',N'P'),
(N'teabar_api',N'usp_SaveProduct',N'P'),
(N'teabar_api',N'usp_SaveIngredient',N'P'),
(N'teabar_api',N'usp_SaveEmployee',N'P'),
(N'teabar_api',N'usp_SaveSpecification',N'P'),
(N'teabar_api',N'usp_SaveProductSpecification',N'P'),
(N'teabar_api',N'usp_SaveRecipe',N'P'),
(N'teabar_api',N'usp_SaveSpecificationIngredient',N'P'),
(N'teabar_api',N'usp_SaveAddOn',N'P'),
(N'teabar_api',N'usp_SaveDutyRoster',N'P'),
(N'dbo',N'vw_ProductCatalog',N'V'),
(N'dbo',N'vw_ProductSpecification',N'V'),
(N'dbo',N'vw_SpecificationIngredientRule',N'V'),
(N'dbo',N'vw_AddOnAvailability',N'V'),
(N'dbo',N'vw_IngredientStock',N'V'),
(N'dbo',N'vw_OrderSummary',N'V'),
(N'dbo',N'vw_OrderDetail',N'V'),
(N'dbo',N'vw_OrderIngredientUsage',N'V'),
(N'dbo',N'vw_MemberConsumptionStatistics',N'V'),
(N'dbo',N'vw_DutyRosterDetail',N'V'),
(N'dbo',N'vw_OrderDutyTeam',N'V'),
(N'dbo',N'vw_ProductSalesStatistics',N'V'),
(N'dbo',N'vw_DailySalesStatistics',N'V');
DECLARE @expected_roles TABLE(role_name SYSNAME);
INSERT @expected_roles VALUES
(N'teabar_customer'),
(N'teabar_member'),
(N'teabar_clerk'),
(N'teabar_manager');
DECLARE @expected_users TABLE(user_name SYSNAME,role_name SYSNAME);
INSERT @expected_users VALUES
(N'demo_guest_a',N'teabar_customer'),
(N'demo_guest_b',N'teabar_customer'),
(N'demo_member_a',N'teabar_member'),
(N'demo_member_b',N'teabar_member'),
(N'demo_clerk',N'teabar_clerk'),
(N'demo_manager',N'teabar_manager');
DECLARE @source_core_hash VARBINARY(32)=0xdf55ebfd6a4ed75c284867d1a8bb7bf6ff5985e4f4a8f95d274859fd05e1e198;
DECLARE @source_core_literal_hash VARBINARY(32)=0x5a3789322ae00b75b7733fb118f228170dbdcd540779d66a26a50778b6c3e13c;
IF TYPE_ID(N'teabar_api.OrderLines') IS NULL OR TYPE_ID(N'teabar_api.OrderSpecs') IS NULL OR TYPE_ID(N'teabar_api.OrderAddOns') IS NULL THROW 52802,N'缺少冻结TVP类型。',1;
-- Migration transaction follows the embedded source manifest and session options.
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
    EXEC(N'ALTER PROCEDURE teabar_api.usp_PlacePaidOrder
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
        -- v1.0 D01: check EVERY input item before stock deduction or persistent inserts.
        IF EXISTS(SELECT 1 FROM @items AS i WHERE NOT EXISTS(
            SELECT 1 FROM @consumption AS c WHERE c.item_id=i.item_id AND c.amount>0))
            THROW 52018, N''订单包含未产生正原料消耗的明细，整单拒绝。'', 1;
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
END;
');
    EXEC(N'CREATE PROCEDURE teabar_api.usp_PlacePaidOrderJson
    @order_id NVARCHAR(MAX),
    @items_json NVARCHAR(MAX),
    @specs_json NVARCHAR(MAX),
    @addons_json NVARCHAR(MAX),
    @payment_succeeded BIT
AS
BEGIN
    SET NOCOUNT ON;
    -- No writes and no business transaction until all JSON has been validated.
    IF @order_id IS NULL OR DATALENGTH(@order_id) NOT BETWEEN 2 AND 20
       OR @order_id COLLATE Latin1_General_100_BIN2 LIKE N''%[^A-Za-z0-9_-]%''
        THROW 52602, N''订单编号须为1至10位ASCII字母、数字、下划线或短横线。'', 1;

    DECLARE @documents TABLE (kind CHAR(1) PRIMARY KEY, document NVARCHAR(MAX));
    INSERT @documents VALUES (''I'', @items_json), (''S'', @specs_json), (''A'', @addons_json);
    IF EXISTS (SELECT 1 FROM @documents WHERE document IS NULL OR ISJSON(document) <> 1)
        THROW 52600, N''订单参数必须为合法JSON数组。'', 1;
    -- Wrap the root to determine its JSON type without relying on SQL 2022-only ISJSON(..., ARRAY).
    IF EXISTS (
        SELECT 1 FROM @documents AS d
        CROSS APPLY OPENJSON(N''['' + d.document + N'']'') AS root
        WHERE root.[type] <> 4
    ) THROW 52600, N''订单参数必须为JSON数组，不能传对象或标量。'', 1;
    IF NOT EXISTS (SELECT 1 FROM OPENJSON(@items_json))
        THROW 52600, N''订单至少需要一条明细。'', 1;

    DECLARE @rows TABLE (kind CHAR(1), row_no INT, document NVARCHAR(MAX), PRIMARY KEY(kind,row_no));
    IF EXISTS (SELECT 1 FROM @documents AS d CROSS APPLY OPENJSON(d.document) AS j WHERE j.[type] <> 5)
        THROW 52601, N''数组中的每一项都必须是对象。'', 1;
    INSERT @rows SELECT d.kind, CONVERT(INT,j.[key]), j.value
    FROM @documents AS d CROSS APPLY OPENJSON(d.document) AS j;

    DECLARE @properties TABLE (
        kind CHAR(1), row_no INT, property_name NVARCHAR(4000) COLLATE Latin1_General_100_BIN2,
        property_value NVARCHAR(MAX), json_type INT
    );
    INSERT @properties SELECT r.kind,r.row_no,j.[key],j.value,j.[type]
    FROM @rows AS r CROSS APPLY OPENJSON(r.document) AS j;
    DECLARE @allowed TABLE (kind CHAR(1), property_name NVARCHAR(30) COLLATE Latin1_General_100_BIN2);
    INSERT @allowed VALUES (''I'',N''item_id''),(''I'',N''product_id''),(''I'',N''quantity''),
        (''S'',N''item_id''),(''S'',N''spec_id''),(''A'',N''item_id''),(''A'',N''addon_id'');
    IF EXISTS (SELECT 1 FROM @properties AS p WHERE NOT EXISTS (
        SELECT 1 FROM @allowed AS a WHERE a.kind=p.kind AND a.property_name=p.property_name
          AND DATALENGTH(a.property_name)=DATALENGTH(p.property_name)))
       OR EXISTS (SELECT kind,row_no,property_name FROM @properties
                  GROUP BY kind,row_no,property_name HAVING COUNT(*)<>1)
       OR EXISTS (SELECT 1 FROM @rows AS r JOIN @allowed AS a ON a.kind=r.kind
                  WHERE NOT EXISTS (SELECT 1 FROM @properties AS p WHERE p.kind=r.kind
                    AND p.row_no=r.row_no AND p.property_name=a.property_name))
        THROW 52601, N''JSON对象字段缺失、重复、大小写不符或包含额外字段。'', 1;
    IF EXISTS (SELECT 1 FROM @properties WHERE property_name<>N''quantity'' AND (
           json_type<>1 OR property_value IS NULL OR DATALENGTH(property_value) NOT BETWEEN 2 AND 20
           OR property_value COLLATE Latin1_General_100_BIN2 LIKE N''%[^A-Za-z0-9_-]%''))
       OR EXISTS (SELECT 1 FROM @properties WHERE property_name=N''quantity'' AND (
           json_type<>2 OR property_value IS NULL OR DATALENGTH(property_value)=0
           OR property_value COLLATE Latin1_General_100_BIN2 LIKE N''%[^0-9]%''
           OR TRY_CONVERT(INT,property_value) IS NULL OR TRY_CONVERT(INT,property_value)<=0))
        THROW 52602, N''JSON编号或购买数量的类型、格式、长度或范围不正确。'', 1;

    DECLARE @parsed TABLE (kind CHAR(1), row_no INT, item_id VARCHAR(10) COLLATE DATABASE_DEFAULT,
        selection_id VARCHAR(10) COLLATE DATABASE_DEFAULT, quantity INT);
    INSERT @parsed
    SELECT kind,row_no,
        CONVERT(VARCHAR(10),MAX(CASE WHEN property_name=N''item_id'' THEN property_value END)),
        CONVERT(VARCHAR(10),MAX(CASE WHEN property_name IN (N''product_id'',N''spec_id'',N''addon_id'') THEN property_value END)),
        MAX(CASE WHEN property_name=N''quantity'' THEN TRY_CONVERT(INT,property_value) END)
    FROM @properties GROUP BY kind,row_no;
    IF EXISTS (SELECT item_id FROM @parsed WHERE kind=''I'' GROUP BY item_id HAVING COUNT(*)>1)
       OR EXISTS (SELECT kind,item_id,selection_id FROM @parsed WHERE kind IN (''S'',''A'')
                  GROUP BY kind,item_id,selection_id HAVING COUNT(*)>1)
        THROW 52603, N''明细编号或规格、加料选择重复。'', 1;
    IF EXISTS (SELECT 1 FROM @parsed AS choice WHERE choice.kind IN (''S'',''A'') AND NOT EXISTS (
        SELECT 1 FROM @parsed AS item WHERE item.kind=''I'' AND item.item_id=choice.item_id))
        THROW 52604, N''规格或加料引用了本次订单以外的明细。'', 1;

    DECLARE @items teabar_api.OrderLines, @specs teabar_api.OrderSpecs, @addons teabar_api.OrderAddOns;
    INSERT @items SELECT item_id,selection_id,quantity FROM @parsed WHERE kind=''I'';
    INSERT @specs SELECT item_id,selection_id FROM @parsed WHERE kind=''S'';
    INSERT @addons SELECT item_id,selection_id FROM @parsed WHERE kind=''A'';
    DECLARE @validated_order_id VARCHAR(10)=CONVERT(VARCHAR(10),@order_id);
    EXEC teabar_api.usp_PlacePaidOrder @validated_order_id,@items,@specs,@addons,@payment_succeeded;
END;
');
    EXEC(N'CREATE PROCEDURE teabar_auth.usp_GetWebCredential @login_name NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    -- Return the same empty result shape for invalid, missing and disabled accounts.
    SELECT account_id,password_hash,session_version
    FROM teabar_auth.WebAccount
    WHERE @login_name IS NOT NULL
      AND DATALENGTH(@login_name) BETWEEN 6 AND 100
      AND @login_name COLLATE Latin1_General_100_BIN2 NOT LIKE N''%[^a-z0-9._-]%''
      AND login_name=@login_name AND is_active=1;
END;
');
    EXEC(N'CREATE PROCEDURE teabar_auth.usp_GetWebContext @account_id INT, @session_version INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sid VARBINARY(85),@role VARCHAR(10),@actual_version INT,@name SYSNAME,@pid INT,@expected_role SYSNAME;
    SELECT @sid=principal_sid,@role=app_role,@actual_version=session_version
    FROM teabar_auth.WebAccount WHERE account_id=@account_id AND is_active=1;
    IF @sid IS NULL OR @session_version IS NULL OR @actual_version<>@session_version
        THROW 52700, N''账号或会话已失效。'', 1;
    IF (SELECT COUNT(*) FROM sys.database_principals WHERE sid=@sid AND type=''S'' AND authentication_type=0)<>1
        THROW 52700, N''数据库用户映射无效。'', 1;
    SELECT @pid=principal_id,@name=name FROM sys.database_principals
    WHERE sid=@sid AND type=''S'' AND authentication_type=0;
    SET @expected_role=CASE @role WHEN ''customer'' THEN N''teabar_customer'' WHEN ''member'' THEN N''teabar_member''
        WHEN ''clerk'' THEN N''teabar_clerk'' WHEN ''manager'' THEN N''teabar_manager'' END;
    IF @expected_role IS NULL OR NOT (
        (@role=''customer'' AND @name COLLATE DATABASE_DEFAULT IN (N''web_guest_a'',N''web_guest_b''))
        OR (@role=''member'' AND @name COLLATE DATABASE_DEFAULT IN (N''web_member_a'',N''web_member_b''))
        OR (@role=''clerk'' AND @name COLLATE DATABASE_DEFAULT=N''web_clerk'')
        OR (@role=''manager'' AND @name COLLATE DATABASE_DEFAULT=N''web_manager''))
        THROW 52700, N''账号角色与允许的数据库用户不匹配。'', 1;
    IF (SELECT COUNT(*) FROM sys.database_role_members WHERE member_principal_id=@pid)<>1
       OR NOT EXISTS (SELECT 1 FROM sys.database_role_members
            WHERE member_principal_id=@pid AND role_principal_id=DATABASE_PRINCIPAL_ID(@expected_role))
       OR EXISTS (SELECT 1 FROM sys.schemas WHERE principal_id=@pid)
       OR EXISTS (SELECT 1 FROM sys.database_principals WHERE owning_principal_id=@pid)
       OR EXISTS (SELECT 1 FROM sys.database_permissions WHERE grantee_principal_id=@pid AND state IN (''G'',''W'')
                  AND NOT (class=0 AND permission_name=N''CONNECT''))
        THROW 52700, N''数据库用户的角色、所有权或直接授权不符合应用边界。'', 1;
    IF @role IN (''customer'',''member'') AND NOT EXISTS (
        SELECT 1 FROM teabar_auth.PrincipalBinding AS b WHERE b.principal_sid=@sid AND b.is_active=1
          AND b.principal_name COLLATE DATABASE_DEFAULT=@name COLLATE DATABASE_DEFAULT
          AND ((@role=''customer'' AND b.guest_id IS NOT NULL AND b.member_id IS NULL)
            OR (@role=''member'' AND b.member_id IS NOT NULL AND b.guest_id IS NULL)))
        THROW 52700, N''购买身份绑定不存在、停用或与账号角色不匹配。'', 1;
    SELECT @account_id AS account_id,@role AS app_role,@sid AS principal_sid,
        @name AS principal_name,@actual_version AS session_version;
END;
');
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
