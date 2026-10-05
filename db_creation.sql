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
    spec_type NVARCHAR(20) NOT NULL,     -- 糖度/冰量/杯型
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
        CHECK (spec_type IN (N'糖度', N'冰量', N'杯型'))
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
    sub_amount DECIMAL(10, 2) NOT NULL,

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
        CHECK (unit_price >= 0),

    CONSTRAINT CK_OrderItem_SubAmount
        CHECK (sub_amount = unit_price*quantity)
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

-- ============================================================
-- 样例数据：AI 生成
-- 以下数据用于空表初始化；单独重复执行会因主键重复而失败。
-- 积分为样例期初余额，不包含本批订单积分结算。
-- 消耗量按全部杯数保存；零消耗不写入快照。
-- 库存直接填写样例剩余值；本节只插入数据，不执行库存扣减。
-- ============================================================

-- 员工
INSERT INTO Employee (employee_id, name, status, salary, role)
VALUES
    ('E001', N'张明', N'在职', 6500, N'店长'),
    ('E002', N'李华', N'在职', 4200, N'店员'),
    ('E003', N'王芳', N'在职', 4300, N'店员'),
    ('E004', N'赵强', N'离职', 4000, N'店员');

-- 值班安排（同一员工的班次不重叠）
INSERT INTO DutyRoster (duty_id, employee_id, start_time, end_time)
VALUES
    ('D001', 'E001', '2026-10-04T08:00:00', '2026-10-04T17:00:00'),
    ('D002', 'E002', '2026-10-04T08:00:00', '2026-10-04T16:00:00'),
    ('D003', 'E003', '2026-10-04T16:00:00', '2026-10-04T23:00:00'),
    ('D004', 'E001', '2026-10-03T08:00:00', '2026-10-03T17:00:00'),
    ('D005', 'E004', '2026-10-01T08:00:00', '2026-10-01T16:00:00');

-- 会员（含未下单会员）
INSERT INTO Member (member_id, name, phone, points)
VALUES
    ('M001', N'陈晨', '13800000001', 120),
    ('M002', N'刘洋', '13800000002', 60),
    ('M003', N'林晓', '13800000003', 0),
    ('M004', N'周悦', '13800000004', 200);

-- 商品（价格仅为课程样例）
INSERT INTO Product (product_id, product_name, base_price, status, description)
VALUES
    ('P001', N'冰鲜柠檬水', 6, N'在售', N'清爽柠檬茶饮'),
    ('P002', N'珍珠奶茶', 8, N'在售', N'茶汤、牛奶与珍珠搭配'),
    ('P003', N'椰果奶茶', 7, N'在售', N'茶汤、牛奶与椰果搭配'),
    ('P004', N'茉莉绿茶', 5, N'在售', NULL);

-- 规格：糖度、冰量、杯型
INSERT INTO Specification (spec_id, spec_type, spec_name)
VALUES
    ('S001', N'糖度', N'正常糖'),
    ('S002', N'糖度', N'五分糖'),
    ('S003', N'糖度', N'无糖'),
    ('S004', N'冰量', N'正常冰'),
    ('S005', N'冰量', N'少冰'),
    ('S006', N'冰量', N'去冰'),
    ('S007', N'杯型', N'中杯'),
    ('S008', N'杯型', N'大杯'),
    ('S009', N'杯型', N'超大杯');

-- 原料：stock 直接填写样例剩余库存
INSERT INTO Ingredient (ingredient_id, ingredient_name, unit, stock, status)
VALUES
    ('I001', N'柠檬', 'g', 5000, N'可用'),
    ('I002', N'糖浆', 'ml', 10000, N'可用'),
    ('I003', N'红茶汤', 'ml', 20000, N'可用'),
    ('I004', N'牛奶', 'ml', 12000, N'可用'),
    ('I005', N'珍珠', 'g', 5000, N'可用'),
    ('I006', N'芋圆', 'g', 4000, N'可用'),
    ('I007', N'冰块', 'g', 20000, N'可用'),
    ('I008', N'椰果', 'g', 5000, N'可用'),
    ('I009', N'茉莉绿茶汤', 'ml', 15000, N'可用');

-- 商品可选规格：大杯加 2 元，超大杯加 3 元
INSERT INTO ProductSpecification (product_id, spec_id, price_delta, status)
VALUES
    ('P001', 'S001', 0, N'可用'),
    ('P001', 'S002', 0, N'可用'),
    ('P001', 'S003', 0, N'可用'),
    ('P001', 'S004', 0, N'可用'),
    ('P001', 'S005', 0, N'可用'),
    ('P001', 'S006', 0, N'可用'),
    ('P001', 'S007', 0, N'可用'),
    ('P001', 'S008', 2, N'可用'),
    ('P001', 'S009', 3, N'可用'),
    ('P002', 'S001', 0, N'可用'),
    ('P002', 'S002', 0, N'可用'),
    ('P002', 'S003', 0, N'可用'),
    ('P002', 'S004', 0, N'可用'),
    ('P002', 'S005', 0, N'可用'),
    ('P002', 'S006', 0, N'可用'),
    ('P002', 'S007', 0, N'可用'),
    ('P002', 'S008', 2, N'可用'),
    ('P002', 'S009', 3, N'可用'),
    ('P003', 'S001', 0, N'可用'),
    ('P003', 'S002', 0, N'可用'),
    ('P003', 'S003', 0, N'可用'),
    ('P003', 'S004', 0, N'可用'),
    ('P003', 'S005', 0, N'可用'),
    ('P003', 'S006', 0, N'可用'),
    ('P003', 'S007', 0, N'可用'),
    ('P003', 'S008', 2, N'可用'),
    ('P003', 'S009', 3, N'可用'),
    ('P004', 'S001', 0, N'可用'),
    ('P004', 'S002', 0, N'可用'),
    ('P004', 'S003', 0, N'可用'),
    ('P004', 'S004', 0, N'可用'),
    ('P004', 'S005', 0, N'可用'),
    ('P004', 'S006', 0, N'可用'),
    ('P004', 'S007', 0, N'可用'),
    ('P004', 'S008', 2, N'可用'),
    ('P004', 'S009', 3, N'可用');

-- 中杯基础配方：正常糖、正常冰
INSERT INTO Recipe (product_id, ingredient_id, base_amount)
VALUES
    ('P001', 'I001', 50),
    ('P001', 'I002', 30),
    ('P001', 'I009', 200),
    ('P001', 'I007', 100),
    ('P002', 'I002', 30),
    ('P002', 'I003', 200),
    ('P002', 'I004', 100),
    ('P002', 'I005', 50),
    ('P002', 'I007', 100),
    ('P003', 'I002', 30),
    ('P003', 'I003', 200),
    ('P003', 'I004', 100),
    ('P003', 'I008', 40),
    ('P003', 'I007', 100),
    ('P004', 'I002', 20),
    ('P004', 'I009', 300),
    ('P004', 'I007', 100);

-- 加料：每杯每种最多一份，用量不随杯型系数变化
INSERT INTO AddOn (addon_id, addon_name, price, ingredient_id, extra_amount, status)
VALUES
    ('A001', N'加芋圆', 1, 'I006', 50, N'可用'),
    ('A002', N'加珍珠', 1, 'I005', 50, N'可用'),
    ('A003', N'加椰果', 1, 'I008', 40, N'可用');

-- 规格原料系数：糖度和冰量只调整对应原料，杯型调整全部基础配方原料
INSERT INTO SpecificationIngredient (product_id, spec_id, ingredient_id, factor)
VALUES
    ('P001', 'S001', 'I002', 1),
    ('P001', 'S002', 'I002', 0.5),
    ('P001', 'S003', 'I002', 0),
    ('P001', 'S004', 'I007', 1),
    ('P001', 'S005', 'I007', 0.5),
    ('P001', 'S006', 'I007', 0),
    ('P001', 'S007', 'I001', 1),
    ('P001', 'S008', 'I001', 1.25),
    ('P001', 'S009', 'I001', 1.5),
    ('P001', 'S007', 'I002', 1),
    ('P001', 'S008', 'I002', 1.25),
    ('P001', 'S009', 'I002', 1.5),
    ('P001', 'S007', 'I009', 1),
    ('P001', 'S008', 'I009', 1.25),
    ('P001', 'S009', 'I009', 1.5),
    ('P001', 'S007', 'I007', 1),
    ('P001', 'S008', 'I007', 1.25),
    ('P001', 'S009', 'I007', 1.5),
    ('P002', 'S001', 'I002', 1),
    ('P002', 'S002', 'I002', 0.5),
    ('P002', 'S003', 'I002', 0),
    ('P002', 'S004', 'I007', 1),
    ('P002', 'S005', 'I007', 0.5),
    ('P002', 'S006', 'I007', 0),
    ('P002', 'S007', 'I002', 1),
    ('P002', 'S008', 'I002', 1.25),
    ('P002', 'S009', 'I002', 1.5),
    ('P002', 'S007', 'I003', 1),
    ('P002', 'S008', 'I003', 1.25),
    ('P002', 'S009', 'I003', 1.5),
    ('P002', 'S007', 'I004', 1),
    ('P002', 'S008', 'I004', 1.25),
    ('P002', 'S009', 'I004', 1.5),
    ('P002', 'S007', 'I005', 1),
    ('P002', 'S008', 'I005', 1.25),
    ('P002', 'S009', 'I005', 1.5),
    ('P002', 'S007', 'I007', 1),
    ('P002', 'S008', 'I007', 1.25),
    ('P002', 'S009', 'I007', 1.5),
    ('P003', 'S001', 'I002', 1),
    ('P003', 'S002', 'I002', 0.5),
    ('P003', 'S003', 'I002', 0),
    ('P003', 'S004', 'I007', 1),
    ('P003', 'S005', 'I007', 0.5),
    ('P003', 'S006', 'I007', 0),
    ('P003', 'S007', 'I002', 1),
    ('P003', 'S008', 'I002', 1.25),
    ('P003', 'S009', 'I002', 1.5),
    ('P003', 'S007', 'I003', 1),
    ('P003', 'S008', 'I003', 1.25),
    ('P003', 'S009', 'I003', 1.5),
    ('P003', 'S007', 'I004', 1),
    ('P003', 'S008', 'I004', 1.25),
    ('P003', 'S009', 'I004', 1.5),
    ('P003', 'S007', 'I008', 1),
    ('P003', 'S008', 'I008', 1.25),
    ('P003', 'S009', 'I008', 1.5),
    ('P003', 'S007', 'I007', 1),
    ('P003', 'S008', 'I007', 1.25),
    ('P003', 'S009', 'I007', 1.5),
    ('P004', 'S001', 'I002', 1),
    ('P004', 'S002', 'I002', 0.5),
    ('P004', 'S003', 'I002', 0),
    ('P004', 'S004', 'I007', 1),
    ('P004', 'S005', 'I007', 0.5),
    ('P004', 'S006', 'I007', 0),
    ('P004', 'S007', 'I002', 1),
    ('P004', 'S008', 'I002', 1.25),
    ('P004', 'S009', 'I002', 1.5),
    ('P004', 'S007', 'I009', 1),
    ('P004', 'S008', 'I009', 1.25),
    ('P004', 'S009', 'I009', 1.5),
    ('P004', 'S007', 'I007', 1),
    ('P004', 'S008', 'I007', 1.25),
    ('P004', 'S009', 'I007', 1.5);

-- 正式订单：会员可空，包含已完成、制作中和排队中状态
INSERT INTO SalesOrder (order_id, member_id, order_time, total_amount, status)
VALUES
    ('O001', 'M001', '2026-10-04T10:00:00', 28, N'已完成'),
    ('O002', NULL, '2026-10-04T11:15:00', 9, N'已完成'),
    ('O003', 'M002', '2026-10-04T14:30:00', 9, N'已完成'),
    ('O004', NULL, '2026-10-04T16:30:00', 21, N'制作中'),
    ('O005', 'M003', '2026-10-04T16:35:00', 23, N'排队中');

-- 订单明细：单价含规格加价和加料价格
INSERT INTO OrderItem (item_id, order_id, product_id, product_name_snapshot, quantity, base_price_snapshot, unit_price, sub_amount)
VALUES
    ('T001', 'O001', 'P002', N'珍珠奶茶', 2, 8, 11, 22),
    ('T002', 'O001', 'P001', N'冰鲜柠檬水', 1, 6, 6, 6),
    ('T003', 'O002', 'P003', N'椰果奶茶', 1, 7, 9, 9),
    ('T004', 'O003', 'P002', N'珍珠奶茶', 1, 8, 9, 9),
    ('T005', 'O004', 'P004', N'茉莉绿茶', 3, 5, 7, 21),
    ('T006', 'O005', 'P001', N'冰鲜柠檬水', 2, 6, 8, 16),
    ('T007', 'O005', 'P003', N'椰果奶茶', 1, 7, 7, 7);

-- 明细规格选择：每条明细选择三种类型，各一个
INSERT INTO ItemSpec (item_id, spec_type, spec_id, spec_name_snapshot, price_delta_snapshot)
VALUES
    ('T001', N'糖度', 'S002', N'五分糖', 0),
    ('T001', N'冰量', 'S005', N'少冰', 0),
    ('T001', N'杯型', 'S008', N'大杯', 2),
    ('T002', N'糖度', 'S003', N'无糖', 0),
    ('T002', N'冰量', 'S006', N'去冰', 0),
    ('T002', N'杯型', 'S007', N'中杯', 0),
    ('T003', N'糖度', 'S001', N'正常糖', 0),
    ('T003', N'冰量', 'S004', N'正常冰', 0),
    ('T003', N'杯型', 'S007', N'中杯', 0),
    ('T004', N'糖度', 'S001', N'正常糖', 0),
    ('T004', N'冰量', 'S004', N'正常冰', 0),
    ('T004', N'杯型', 'S007', N'中杯', 0),
    ('T005', N'糖度', 'S002', N'五分糖', 0),
    ('T005', N'冰量', 'S005', N'少冰', 0),
    ('T005', N'杯型', 'S008', N'大杯', 2),
    ('T006', N'糖度', 'S001', N'正常糖', 0),
    ('T006', N'冰量', 'S004', N'正常冰', 0),
    ('T006', N'杯型', 'S008', N'大杯', 2),
    ('T007', N'糖度', 'S003', N'无糖', 0),
    ('T007', N'冰量', 'S006', N'去冰', 0),
    ('T007', N'杯型', 'S007', N'中杯', 0);

-- 明细加料选择：T003 同时选择两种加料
INSERT INTO ItemAddOn (item_id, addon_id, addon_name_snapshot, price_snapshot)
VALUES
    ('T001', 'A001', N'加芋圆', 1),
    ('T003', 'A002', N'加珍珠', 1),
    ('T003', 'A003', N'加椰果', 1),
    ('T004', 'A002', N'加珍珠', 1);

-- 原料消耗快照：基础用量 × 同原料所选规格系数之积 × 杯数，再加额外加料用量
INSERT INTO OrderItemIngredient (item_id, ingredient_id, amount)
VALUES
    ('T001', 'I002', 37.5),
    ('T001', 'I003', 500),
    ('T001', 'I004', 250),
    ('T001', 'I005', 125),
    ('T001', 'I007', 125),
    ('T001', 'I006', 100),
    ('T002', 'I001', 50),
    ('T002', 'I009', 200),
    ('T003', 'I002', 30),
    ('T003', 'I003', 200),
    ('T003', 'I004', 100),
    ('T003', 'I008', 80),
    ('T003', 'I007', 100),
    ('T003', 'I005', 50),
    ('T004', 'I002', 30),
    ('T004', 'I003', 200),
    ('T004', 'I004', 100),
    ('T004', 'I005', 100),
    ('T004', 'I007', 100),
    ('T005', 'I002', 37.5),
    ('T005', 'I009', 1125),
    ('T005', 'I007', 187.5),
    ('T006', 'I001', 125),
    ('T006', 'I002', 75),
    ('T006', 'I009', 500),
    ('T006', 'I007', 250),
    ('T007', 'I003', 200),
    ('T007', 'I004', 100),
    ('T007', 'I008', 40);

GO
