-- 第四周视图维护演示：创建 → 查询 → 修改定义 → 查询 → 删除。
-- 使用专用测试视图 dbo.vw_DemoProduct；不修改商品数据或正式视图。
-- 在 SSMS 中完整执行；每条 CREATE/ALTER VIEW 必须位于新批次开头。
USE TeabarDB;
GO
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- 清理上次未执行完的测试视图，便于重复演示。
DROP VIEW IF EXISTS dbo.vw_DemoProduct;
GO

-- C：创建视图，展示全部商品。
CREATE VIEW dbo.vw_DemoProduct
AS
SELECT product_id, product_name, base_price
FROM dbo.Product;
GO

-- R：查询创建结果，初始化样例应有 4 行。
SELECT product_id, product_name, base_price
FROM dbo.vw_DemoProduct
ORDER BY product_id;
GO

-- U：修改视图定义，只展示基础价至少 7 元的在售商品。
ALTER VIEW dbo.vw_DemoProduct
AS
SELECT product_id, product_name, base_price
FROM dbo.Product
WHERE status = N'在售' AND base_price >= 7;
GO

-- R：查询修改结果，初始化样例应有 2 行：珍珠奶茶、椰果奶茶。
SELECT product_id, product_name, base_price
FROM dbo.vw_DemoProduct
ORDER BY product_id;
GO

-- D：删除测试视图对象。
DROP VIEW dbo.vw_DemoProduct;
GO

-- 检查删除结果：应显示“已删除”。
SELECT CASE WHEN OBJECT_ID(N'dbo.vw_DemoProduct', N'V') IS NULL
            THEN N'已删除' ELSE N'仍存在' END AS demo_view_status;
GO
