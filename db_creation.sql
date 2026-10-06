-- 第三周建库建表：仅创建数据库和表结构；样例数据另见 seed_data.sql。
USE master;
GO

-- 如果存在 TeabarDB，会将其先删除
IF DB_ID('TeabarDB') IS NOT NULL
BEGIN
	ALTER DATABASE TeabarDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
	DROP DATABASE TeabarDB;
END
GO

-- 创建并切换到数据库 TeabarDB
CREATE DATABASE TeabarDB;
GO
USE TeabarDB;
GO

-- 持久化计算列所需会话选项，供 SSMS 和 sqlcmd 使用。
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

-- 员工表
CREATE TABLE Employee (
    employee_id VARCHAR(10) NOT NULL,
    name NVARCHAR(50) NOT NULL,
    status NVARCHAR(10) NOT NULL DEFAULT N'在职',   -- 在职/离职
    salary DECIMAL(10, 2) NOT NULL,        -- 元/月
    role NVARCHAR(20) NOT NULL,            -- 店员/店长

    CONSTRAINT PK_Employee
        PRIMARY KEY (employee_id),

    CONSTRAINT CK_Employee_Id_NotBlank
        CHECK (LEN(LTRIM(RTRIM(employee_id))) > 0),

    CONSTRAINT CK_Employee_Name_NotBlank
        CHECK (LEN(LTRIM(RTRIM(name))) > 0),

    CONSTRAINT CK_Employee_Status
        CHECK (status IN (N'在职', N'离职')),

    CONSTRAINT CK_Employee_Salary
        CHECK (salary >= 0),

	CONSTRAINT CK_Employee_Role
        CHECK (role IN (N'店员', N'店长'))
);
GO

-- 值班表
CREATE TABLE DutyRoster (
    duty_id VARCHAR(10) NOT NULL,
    employee_id VARCHAR(10) NOT NULL,
    start_time DATETIME2(0) NOT NULL,
    end_time DATETIME2(0) NOT NULL,

    CONSTRAINT PK_DutyRoster
        PRIMARY KEY (duty_id),
    
    CONSTRAINT FK_DutyRoster_Employee
        FOREIGN KEY (employee_id)
        REFERENCES Employee(employee_id),

    CONSTRAINT UQ_DutyRoster_Employee_StartTime
        UNIQUE (employee_id, start_time),

    CONSTRAINT CK_DutyRoster_Time
        CHECK (start_time < end_time)
);
GO

-- 会员表
CREATE TABLE Member (
    member_id VARCHAR(10) NOT NULL,
    name NVARCHAR(50) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    points INT NOT NULL DEFAULT 0,

    CONSTRAINT PK_Member
        PRIMARY KEY (member_id),

    CONSTRAINT CK_Member_Id_NotBlank
        CHECK (LEN(LTRIM(RTRIM(member_id))) > 0),

    CONSTRAINT CK_Member_Name_NotBlank
        CHECK (LEN(LTRIM(RTRIM(name))) > 0),

    CONSTRAINT UK_Member_Phone
        UNIQUE (phone),

    CONSTRAINT CK_Member_Phone_Format
        CHECK (DATALENGTH(phone) = 11
            AND phone LIKE '1%'
            AND phone COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%'),

    CONSTRAINT CK_Member_Points
        CHECK (points >= 0)
);
GO

-- 正式订单表
CREATE TABLE SalesOrder (
    order_id VARCHAR(10) NOT NULL,
    member_id VARCHAR(10) NULL,
    order_time DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    total_amount DECIMAL(10, 2) NOT NULL,
    status NVARCHAR(20) NOT NULL DEFAULT N'排队中', -- 排队中/制作中/待取餐/已完成/已取消

    CONSTRAINT PK_SalesOrder
        PRIMARY KEY (order_id),

    CONSTRAINT CK_SalesOrder_Id_NotBlank
        CHECK (LEN(LTRIM(RTRIM(order_id))) > 0),

    CONSTRAINT FK_SalesOrder_Member
        FOREIGN KEY (member_id)
        REFERENCES Member(member_id),

    CONSTRAINT CK_SalesOrder_Amount
        CHECK (total_amount >= 0),

    CONSTRAINT CK_SalesOrder_status
        CHECK (status IN (N'排队中', N'制作中', N'待取餐', N'已完成', N'已取消'))
);
GO

-- 商品表
CREATE TABLE Product (
	product_id VARCHAR(10) NOT NULL,
	product_name NVARCHAR(50) NOT NULL,
	base_price DECIMAL(10, 2) NOT NULL,
	status NVARCHAR(10) NOT NULL DEFAULT N'下架', -- 在售/下架
	description NVARCHAR(200) NULL,

    CONSTRAINT PK_Product
        PRIMARY KEY (product_id),

    CONSTRAINT CK_Product_Id_NotBlank
        CHECK (LEN(LTRIM(RTRIM(product_id))) > 0),

    CONSTRAINT CK_Product_Name_NotBlank
        CHECK (LEN(LTRIM(RTRIM(product_name))) > 0),
        
	CONSTRAINT CK_Product_Price
        CHECK (base_price >= 0),

	CONSTRAINT CK_Product_Status
        CHECK (status IN (N'在售', N'下架'))
);
GO

-- 规格表
CREATE TABLE Specification (
    spec_id VARCHAR(10) NOT NULL,
    spec_type NVARCHAR(20) NOT NULL,     -- 糖度/温度/杯型
    spec_name NVARCHAR(20) NOT NULL,     -- 正常糖/五分糖/无糖/正常冰/少冰/去冰/中杯/大杯/超大杯

    CONSTRAINT PK_Specification
        PRIMARY KEY (spec_id),

    CONSTRAINT CK_Specification_Id_NotBlank
        CHECK (LEN(LTRIM(RTRIM(spec_id))) > 0),

    CONSTRAINT CK_Specification_Name_NotBlank
        CHECK (LEN(LTRIM(RTRIM(spec_name))) > 0),

    CONSTRAINT UK_Specification_typename
        UNIQUE (spec_type, spec_name),

    CONSTRAINT UK_Specification_idtype
        UNIQUE (spec_id, spec_type),

    CONSTRAINT CK_Specification_Type
        CHECK (spec_type IN (N'糖度', N'温度', N'杯型'))
);
GO

-- 原料与库存表
CREATE TABLE Ingredient (
    ingredient_id VARCHAR(10) NOT NULL,
    ingredient_name NVARCHAR(50) NOT NULL,
    unit NVARCHAR(10) NOT NULL,            -- g/ml/个等
    stock DECIMAL(10, 2) NOT NULL DEFAULT 0,
    status NVARCHAR(10) NOT NULL DEFAULT N'可用',   -- 可用/缺货

    CONSTRAINT PK_Ingredient
        PRIMARY KEY (ingredient_id),

    CONSTRAINT CK_Ingredient_Id_NotBlank
        CHECK (LEN(LTRIM(RTRIM(ingredient_id))) > 0),

    CONSTRAINT CK_Ingredient_Name_NotBlank
        CHECK (LEN(LTRIM(RTRIM(ingredient_name))) > 0),

    CONSTRAINT CK_Ingredient_Stock
        CHECK (stock >= 0),

    CONSTRAINT CK_Ingredient_Unit
        CHECK (unit IN (N'g', N'ml', N'个')),

    CONSTRAINT CK_Ingredient_Status
        CHECK (status IN (N'可用', N'缺货'))
);
GO

-- 订单明细表
CREATE TABLE OrderItem (
    item_id VARCHAR(10) NOT NULL,
    order_id VARCHAR(10) NOT NULL,
    product_id VARCHAR(10) NOT NULL,
    product_name_snapshot NVARCHAR(50) NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    base_price_snapshot DECIMAL(10, 2) NOT NULL,
    unit_price DECIMAL(10, 2) NOT NULL,
    sub_amount AS CAST(unit_price * quantity AS DECIMAL(10, 2)) PERSISTED NOT NULL,

    CONSTRAINT PK_OrderItem
        PRIMARY KEY (item_id),

    CONSTRAINT CK_OrderItem_ProductName_NotBlank
        CHECK (LEN(LTRIM(RTRIM(product_name_snapshot))) > 0),

    CONSTRAINT FK_OrderItem_Order
        FOREIGN KEY (order_id)
        REFERENCES SalesOrder(order_id),

    CONSTRAINT FK_OrderItem_Product
        FOREIGN KEY (product_id)
        REFERENCES Product(product_id),

    CONSTRAINT CK_OrderItem_Quantity
        CHECK (quantity > 0),

    CONSTRAINT CK_OrderItem_BasePrice
        CHECK (base_price_snapshot >= 0),

    CONSTRAINT CK_OrderItem_UnitPrice
        CHECK (unit_price >= 0)
);
GO

-- 商品规格配置表
CREATE TABLE ProductSpecification (
    product_id VARCHAR(10) NOT NULL,
    spec_id VARCHAR(10) NOT NULL,
    price_delta DECIMAL(10, 2) NOT NULL DEFAULT 0,
    status NVARCHAR(10) NOT NULL DEFAULT N'停用',   -- 可用/停用

    CONSTRAINT PK_ProductSpecification
        PRIMARY KEY (product_id, spec_id),

    CONSTRAINT FK_ProductSpecification_Product
        FOREIGN KEY (product_id)
        REFERENCES Product(product_id),

    CONSTRAINT FK_ProductSpecification_Specification
        FOREIGN KEY (spec_id)
        REFERENCES Specification(spec_id),

    CONSTRAINT CK_ProductSpecification_Status
        CHECK (status IN (N'可用', N'停用'))
);
GO

-- 基础配方表
CREATE TABLE Recipe (
    product_id VARCHAR(10) NOT NULL,
    ingredient_id VARCHAR(10) NOT NULL,
    base_amount DECIMAL(10, 2) NOT NULL,

    CONSTRAINT PK_Recipe
        PRIMARY KEY (product_id, ingredient_id),

    CONSTRAINT FK_Recipe_Product
        FOREIGN KEY (product_id)
        REFERENCES Product(product_id),

    CONSTRAINT FK_Recipe_Ingredient
        FOREIGN KEY (ingredient_id)
        REFERENCES Ingredient(ingredient_id),

    CONSTRAINT CK_Recipe_BaseAmount
        CHECK (base_amount > 0)
);
GO

-- 加料表
CREATE TABLE AddOn (
    addon_id VARCHAR(10) NOT NULL,
    addon_name NVARCHAR(50) NOT NULL,
    price DECIMAL(10, 2) NOT NULL,
    ingredient_id VARCHAR(10) NOT NULL,
    extra_amount DECIMAL(10, 2) NOT NULL,
    status NVARCHAR(10) NOT NULL DEFAULT N'可用',    --可用/缺货

    CONSTRAINT PK_AddOn
        PRIMARY KEY (addon_id),

    CONSTRAINT CK_AddOn_Id_NotBlank
        CHECK (LEN(LTRIM(RTRIM(addon_id))) > 0),

    CONSTRAINT CK_AddOn_Name_NotBlank
        CHECK (LEN(LTRIM(RTRIM(addon_name))) > 0),

    CONSTRAINT UK_AddOn_name
        UNIQUE (addon_name),

    CONSTRAINT FK_AddOn_Ingredient
        FOREIGN KEY (ingredient_id)
        REFERENCES Ingredient(ingredient_id),

    CONSTRAINT CK_AddOn_Price
        CHECK (price >= 0),

    CONSTRAINT CK_AddOn_ExtraAmount
        CHECK (extra_amount > 0),

    CONSTRAINT CK_AddOn_Status
        CHECK (status IN (N'可用', N'缺货'))
);
GO

-- 明细规格选择表
CREATE TABLE ItemSpec (
    item_id VARCHAR(10) NOT NULL,
    spec_type NVARCHAR(20) NOT NULL,
    spec_id VARCHAR(10) NOT NULL,
    spec_name_snapshot NVARCHAR(20) NOT NULL,
    price_delta_snapshot DECIMAL(10, 2) NOT NULL,

    CONSTRAINT PK_ItemSpec
        PRIMARY KEY (item_id, spec_type),

    CONSTRAINT CK_ItemSpec_Name_NotBlank
        CHECK (LEN(LTRIM(RTRIM(spec_name_snapshot))) > 0),

    CONSTRAINT FK_ItemSpec_OrderItem
        FOREIGN KEY (item_id)
        REFERENCES OrderItem(item_id),

    CONSTRAINT FK_ItemSpec_Spec_id
        FOREIGN KEY (spec_id, spec_type)
        REFERENCES Specification(spec_id, spec_type)
);
GO

-- 明细加料选择表
CREATE TABLE ItemAddOn (
    item_id VARCHAR(10) NOT NULL,
    addon_id VARCHAR(10) NOT NULL,
    addon_name_snapshot NVARCHAR(50) NOT NULL,
    price_snapshot DECIMAL(10, 2) NOT NULL,

    CONSTRAINT PK_ItemAddOn
        PRIMARY KEY (item_id, addon_id),

    CONSTRAINT CK_ItemAddOn_Name_NotBlank
        CHECK (LEN(LTRIM(RTRIM(addon_name_snapshot))) > 0),

    CONSTRAINT FK_ItemAddOn_OrderItem
        FOREIGN KEY (item_id)
        REFERENCES OrderItem(item_id),

    CONSTRAINT FK_ItemAddOn_AddOn
        FOREIGN KEY (addon_id)
        REFERENCES AddOn(addon_id),

    CONSTRAINT CK_ItemAddOn_Price
        CHECK (price_snapshot >= 0)
);
GO

-- 原料消耗快照表
CREATE TABLE OrderItemIngredient (
    item_id VARCHAR(10) NOT NULL,
    ingredient_id VARCHAR(10) NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,

    CONSTRAINT PK_OrderItemIngredient
        PRIMARY KEY (item_id, ingredient_id),

    CONSTRAINT FK_OrderItemIngredient_OrderItem
        FOREIGN KEY (item_id)
        REFERENCES OrderItem(item_id),

    CONSTRAINT FK_OrderItemIngredient_Ingredient
        FOREIGN KEY (ingredient_id)
        REFERENCES Ingredient(ingredient_id),

    CONSTRAINT CK_OrderItemIngredient_Amount
        CHECK (amount > 0)
);
GO

-- 商品规格原料系数表
CREATE TABLE SpecificationIngredient (
    product_id VARCHAR(10) NOT NULL,
    spec_id VARCHAR(10) NOT NULL,
    ingredient_id VARCHAR(10) NOT NULL,
    factor DECIMAL(5, 2) NOT NULL,

    CONSTRAINT PK_SpecificationIngredient
        PRIMARY KEY (product_id, spec_id, ingredient_id),

    CONSTRAINT FK_SpecificationIngredient_ProductSpec
        FOREIGN KEY (product_id, spec_id)
        REFERENCES ProductSpecification(product_id, spec_id),

    CONSTRAINT FK_SpecificationIngredient_Ingredient
        FOREIGN KEY (ingredient_id)
        REFERENCES Ingredient(ingredient_id),

    CONSTRAINT CK_SpecificationIngredient_Factor
        CHECK (factor >= 0)
);
GO
