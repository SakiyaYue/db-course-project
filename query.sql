-- 第四周 Q01—Q18 共 18 项查询；说明见 docs/第四周查询.md。
-- 顺序：商品与配置 → 原料库存 → 购买试算 → 订单处理 → 会员 → 员工排班 → 经营统计。
-- 其中：Q17 为指定商品名称关键词和时间范围的销量／营业额，Q18 为每日经营汇总，Q14 为会员消费统计。
-- 仅 SELECT 业务表；INSERT 只用于本批次表变量，不做修改。
-- 前置：新版 TeabarDB + seed_data.sql；不执行 db_creation.sql 的删库段。
USE TeabarDB;
GO
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

-- 商品与可选配置（Q01—Q04）

-- Q01 商品目录：关键词空串显示全部；LIKE 关键词允许通配符。
DECLARE @keyword NVARCHAR(50) = N'奶茶';
SELECT product_id AS 商品编号, product_name AS 商品名称,
       base_price AS 基础价格, description AS 商品说明, status AS 商品状态
FROM dbo.Product
WHERE status = N'在售' AND product_name LIKE N'%' + @keyword + N'%'
ORDER BY base_price, product_id;
GO

-- Q02 商品可用规格；预期 P001 有 9 项。
DECLARE @product_id VARCHAR(10) = 'P001';
SELECT p.product_id, p.product_name, s.spec_id, s.spec_type, s.spec_name, ps.price_delta
FROM dbo.Product AS p
JOIN dbo.ProductSpecification AS ps ON ps.product_id = p.product_id
JOIN dbo.Specification AS s ON s.spec_id = ps.spec_id
WHERE p.product_id = @product_id AND p.status = N'在售' AND ps.status = N'可用'
ORDER BY s.spec_type, s.spec_id;
GO

-- Q03 单个规格作用于全部基础原料；缺失规则按 1，系数 0 必须保留。
DECLARE @product_id VARCHAR(10) = 'P001', @spec_id VARCHAR(10) = 'S008';
SELECT p.product_id, p.product_name, s.spec_type, s.spec_name,
       g.ingredient_id, g.ingredient_name, g.unit, r.base_amount,
       si.factor AS explicit_factor, COALESCE(si.factor, 1) AS effective_factor,
       r.base_amount * COALESCE(si.factor, 1) AS adjusted_amount,
       CASE WHEN si.ingredient_id IS NULL THEN N'无调整规则，按1' ELSE N'显式规则' END AS rule_source
FROM dbo.Product AS p
JOIN dbo.ProductSpecification AS ps ON ps.product_id = p.product_id
JOIN dbo.Specification AS s ON s.spec_id = ps.spec_id
JOIN dbo.Recipe AS r ON r.product_id = p.product_id
JOIN dbo.Ingredient AS g ON g.ingredient_id = r.ingredient_id
LEFT JOIN dbo.SpecificationIngredient AS si
  ON si.product_id = ps.product_id AND si.spec_id = ps.spec_id AND si.ingredient_id = r.ingredient_id
WHERE p.product_id = @product_id AND ps.spec_id = @spec_id AND ps.status = N'可用'
ORDER BY g.ingredient_id;
-- 正常为零行：发现系数规则超出商品基础配方。
SELECT si.product_id, si.spec_id, si.ingredient_id, si.factor
FROM dbo.SpecificationIngredient AS si
WHERE si.product_id = @product_id AND si.spec_id = @spec_id
AND NOT EXISTS (SELECT 1 FROM dbo.Recipe AS r
                WHERE r.product_id = si.product_id AND r.ingredient_id = si.ingredient_id);
GO

-- Q04 所有加料及一份是否可选；不是多杯购买判断。
SELECT a.addon_id, a.addon_name, a.price, a.extra_amount, a.status AS addon_status,
       g.ingredient_id, g.ingredient_name, g.unit, g.stock, g.status AS ingredient_status,
       CASE WHEN a.status = N'可用' AND g.status = N'可用' AND g.stock >= a.extra_amount
                 AND (g.unit <> N'个' OR (a.extra_amount = FLOOR(a.extra_amount) AND g.stock = FLOOR(g.stock)))
            THEN 1 ELSE 0 END AS can_choose_one
FROM dbo.AddOn AS a JOIN dbo.Ingredient AS g ON g.ingredient_id = a.ingredient_id
ORDER BY a.addon_id;
GO

-- 原料库存（Q05）

-- Q05 原料库存，可选名称与状态；按原料展示，禁止混单位求和。
DECLARE @keyword NVARCHAR(50) = N'', @status NVARCHAR(10) = NULL;
SELECT ingredient_id, ingredient_name, unit, stock, status,
       CASE WHEN unit = N'个' AND stock <> FLOOR(stock) THEN N'计件库存异常' ELSE N'正常' END AS unit_check
FROM dbo.Ingredient
WHERE ingredient_name LIKE N'%' + @keyword + N'%' AND (@status IS NULL OR status = @status)
ORDER BY ingredient_id;
GO

-- 购买方案试算（Q06—Q07）

-- Q06/Q07 共用输入，必须整体执行此批次。可增加多条不同配置的明细。
DECLARE @Plan TABLE (line_no INT PRIMARY KEY, product_id VARCHAR(10) NOT NULL, quantity INT NOT NULL);
DECLARE @ChosenSpecs TABLE (
    line_no INT NOT NULL, spec_type NVARCHAR(20) NOT NULL, spec_id VARCHAR(10) NOT NULL,
    PRIMARY KEY (line_no, spec_type)
);
DECLARE @ChosenAddOns TABLE (line_no INT NOT NULL, addon_id VARCHAR(10) NOT NULL, PRIMARY KEY (line_no, addon_id));
INSERT INTO @Plan VALUES (1, 'P001', 2), (2, 'P002', 1);
INSERT INTO @ChosenSpecs VALUES
    (1, N'糖度', 'S002'), (1, N'温度', 'S005'), (1, N'杯型', 'S008'),
    (2, N'糖度', 'S001'), (2, N'温度', 'S004'), (2, N'杯型', 'S007');
INSERT INTO @ChosenAddOns VALUES (1, 'A001'), (2, 'A002');
DECLARE @Problems TABLE (line_no INT NULL, reason NVARCHAR(200) NOT NULL);
IF NOT EXISTS (SELECT 1 FROM @Plan) INSERT INTO @Problems VALUES (NULL, N'购买方案不能为空');
INSERT INTO @Problems
SELECT l.line_no, N'数量必须大于零' FROM @Plan AS l WHERE l.quantity <= 0;
INSERT INTO @Problems
SELECT l.line_no, N'商品不存在或未在售'
FROM @Plan AS l LEFT JOIN dbo.Product AS p ON p.product_id = l.product_id
WHERE p.product_id IS NULL OR p.status <> N'在售';
INSERT INTO @Problems
SELECT l.line_no, N'商品没有基础配方' FROM @Plan AS l
WHERE NOT EXISTS (SELECT 1 FROM dbo.Recipe AS r WHERE r.product_id = l.product_id);
INSERT INTO @Problems
SELECT c.line_no, N'规格明细不存在、类型不匹配或商品配置不可用'
FROM @ChosenSpecs AS c
LEFT JOIN @Plan AS l ON l.line_no = c.line_no
LEFT JOIN dbo.Specification AS s ON s.spec_id = c.spec_id AND s.spec_type = c.spec_type
LEFT JOIN dbo.ProductSpecification AS ps ON ps.product_id = l.product_id AND ps.spec_id = c.spec_id
WHERE l.line_no IS NULL OR s.spec_id IS NULL OR ps.spec_id IS NULL OR ps.status <> N'可用';
-- 每种开放类型必须明确选择一个选项；默认选项也不能省略。
INSERT INTO @Problems
SELECT DISTINCT l.line_no, N'未选择商品开放的必选规格：' + s.spec_type
FROM @Plan AS l
JOIN dbo.ProductSpecification AS ps ON ps.product_id = l.product_id
JOIN dbo.Specification AS s ON s.spec_id = ps.spec_id
WHERE ps.status = N'可用'
  AND NOT EXISTS (SELECT 1 FROM @ChosenSpecs AS c
                  WHERE c.line_no = l.line_no AND c.spec_type = s.spec_type);
INSERT INTO @Problems
SELECT c.line_no, N'加料明细不存在、加料不存在或不可用'
FROM @ChosenAddOns AS c LEFT JOIN @Plan AS l ON l.line_no = c.line_no
LEFT JOIN dbo.AddOn AS a ON a.addon_id = c.addon_id
LEFT JOIN dbo.Ingredient AS g ON g.ingredient_id = a.ingredient_id
WHERE l.line_no IS NULL OR a.addon_id IS NULL OR a.status <> N'可用'
   OR g.ingredient_id IS NULL OR g.status <> N'可用';
INSERT INTO @Problems
SELECT DISTINCT c.line_no, N'所选规格规则包含配方之外的原料'
FROM @ChosenSpecs AS c JOIN @Plan AS l ON l.line_no = c.line_no
JOIN dbo.SpecificationIngredient AS si ON si.product_id = l.product_id AND si.spec_id = c.spec_id
WHERE NOT EXISTS (SELECT 1 FROM dbo.Recipe AS r
                  WHERE r.product_id = si.product_id AND r.ingredient_id = si.ingredient_id);

DECLARE @Prices TABLE (
    line_no INT PRIMARY KEY, product_id VARCHAR(10), quantity INT,
    base_price DECIMAL(10,2), spec_delta DECIMAL(38,2), addon_price DECIMAL(38,2),
    unit_price DECIMAL(10,2) NULL, sub_amount DECIMAL(10,2) NULL
);
IF NOT EXISTS (SELECT 1 FROM @Problems)
BEGIN
    ;WITH SpecPrices AS (
        SELECT c.line_no, CAST(SUM(ps.price_delta) AS DECIMAL(28,2)) AS delta
        FROM @ChosenSpecs AS c JOIN @Plan AS l ON l.line_no = c.line_no
        JOIN dbo.ProductSpecification AS ps ON ps.product_id = l.product_id AND ps.spec_id = c.spec_id
        GROUP BY c.line_no
    ), AddOnPrices AS (
        SELECT c.line_no, CAST(SUM(a.price) AS DECIMAL(28,2)) AS price FROM @ChosenAddOns AS c
        JOIN dbo.AddOn AS a ON a.addon_id = c.addon_id GROUP BY c.line_no
    )
    INSERT INTO @Prices
    SELECT l.line_no, l.product_id, l.quantity, p.base_price,
           COALESCE(s.delta, 0), COALESCE(a.price, 0), u.unit_price,
           TRY_CONVERT(DECIMAL(10,2), u.unit_price * CONVERT(DECIMAL(10,0), l.quantity))
    FROM @Plan AS l JOIN dbo.Product AS p ON p.product_id = l.product_id
    LEFT JOIN SpecPrices AS s ON s.line_no = l.line_no
    LEFT JOIN AddOnPrices AS a ON a.line_no = l.line_no
    CROSS APPLY (SELECT TRY_CONVERT(DECIMAL(10,2), p.base_price + COALESCE(s.delta, 0) + COALESCE(a.price, 0)) AS unit_price) AS u;
    INSERT INTO @Problems SELECT line_no, N'单价为负数或单价／小计超出金额字段容量'
    FROM @Prices WHERE unit_price IS NULL OR unit_price < 0 OR sub_amount IS NULL;
    IF TRY_CONVERT(DECIMAL(10,2), (SELECT SUM(sub_amount) FROM @Prices)) IS NULL
        INSERT INTO @Problems VALUES (NULL, N'整单金额超出字段容量');
END;
SELECT N'Q06 方案校验' AS section, line_no, reason FROM @Problems ORDER BY line_no, reason;
IF NOT EXISTS (SELECT 1 FROM @Problems)
BEGIN
    SELECT N'Q06 明细价格' AS section, * FROM @Prices ORDER BY line_no;
    SELECT N'Q06 整单金额' AS section, SUM(sub_amount) AS order_amount FROM @Prices;
END;

-- Q07 先算每杯原料，再按明细舍入，最后合并整单共享原料。
DECLARE @RawAmounts TABLE (line_no INT, ingredient_id VARCHAR(10), per_cup DECIMAL(38,8));
DECLARE @Amounts TABLE (line_no INT, ingredient_id VARCHAR(10), amount DECIMAL(10,2) NULL);
IF NOT EXISTS (SELECT 1 FROM @Problems)
BEGIN
    ;WITH Choices AS (
        SELECT line_no,
               NULLIF(MAX(CASE WHEN spec_type = N'糖度' THEN spec_id ELSE '' END), '') AS sugar_id,
               NULLIF(MAX(CASE WHEN spec_type = N'温度' THEN spec_id ELSE '' END), '') AS temperature_id,
               NULLIF(MAX(CASE WHEN spec_type = N'杯型' THEN spec_id ELSE '' END), '') AS cup_id
        FROM @ChosenSpecs GROUP BY line_no
    ), Components AS (
        SELECT l.line_no, r.ingredient_id,
               r.base_amount * COALESCE(s.factor, 1) * COALESCE(t.factor, 1) * COALESCE(c.factor, 1) AS per_cup
        FROM @Plan AS l JOIN dbo.Recipe AS r ON r.product_id = l.product_id
        LEFT JOIN Choices AS chosen ON chosen.line_no = l.line_no
        LEFT JOIN dbo.SpecificationIngredient AS s
          ON s.product_id = r.product_id AND s.ingredient_id = r.ingredient_id AND s.spec_id = chosen.sugar_id
        LEFT JOIN dbo.SpecificationIngredient AS t
          ON t.product_id = r.product_id AND t.ingredient_id = r.ingredient_id AND t.spec_id = chosen.temperature_id
        LEFT JOIN dbo.SpecificationIngredient AS c
          ON c.product_id = r.product_id AND c.ingredient_id = r.ingredient_id AND c.spec_id = chosen.cup_id
        UNION ALL
        SELECT chosen.line_no, a.ingredient_id, a.extra_amount
        FROM @ChosenAddOns AS chosen JOIN dbo.AddOn AS a ON a.addon_id = chosen.addon_id
    )
    INSERT INTO @RawAmounts SELECT line_no, ingredient_id, SUM(per_cup)
    FROM Components GROUP BY line_no, ingredient_id;

    INSERT INTO @Problems
    SELECT r.line_no, N'计件原料的每杯用量或库存不是整数'
    FROM @RawAmounts AS r JOIN dbo.Ingredient AS g ON g.ingredient_id = r.ingredient_id
    WHERE r.per_cup > 0 AND g.unit = N'个'
      AND (r.per_cup <> FLOOR(r.per_cup) OR g.stock <> FLOOR(g.stock));
    INSERT INTO @Amounts
    SELECT r.line_no, r.ingredient_id,
           TRY_CONVERT(DECIMAL(10,2), ROUND(CONVERT(DECIMAL(28,8), r.per_cup) * CONVERT(DECIMAL(10,0), l.quantity), 2))
    FROM @RawAmounts AS r JOIN @Plan AS l ON l.line_no = r.line_no;
    INSERT INTO @Problems SELECT line_no, N'明细原料用量超出快照字段容量'
    FROM @Amounts WHERE amount IS NULL;
END;
SELECT N'Q07 配置或计算问题' AS section, line_no, reason FROM @Problems ORDER BY line_no, reason;
IF NOT EXISTS (SELECT 1 FROM @Problems)
BEGIN
    ;WITH Required AS (
        SELECT ingredient_id, CAST(SUM(amount) AS DECIMAL(28,2)) AS required_amount FROM @Amounts
        WHERE amount > 0 GROUP BY ingredient_id
    )
    SELECT N'Q07 整单原料需求' AS section, r.ingredient_id, g.ingredient_name, g.unit,
           r.required_amount, g.stock, g.status,
           CASE WHEN r.required_amount > g.stock THEN r.required_amount - g.stock ELSE 0 END AS shortage,
           CASE WHEN g.status = N'可用' AND g.stock >= r.required_amount THEN 1 ELSE 0 END AS sufficient
    FROM Required AS r JOIN dbo.Ingredient AS g ON g.ingredient_id = r.ingredient_id
    ORDER BY r.ingredient_id;
    SELECT N'Q07 购买资格（查询时）' AS section,
           CASE WHEN EXISTS (
               SELECT 1 FROM @Amounts AS a JOIN dbo.Ingredient AS g ON g.ingredient_id = a.ingredient_id
               WHERE a.amount > 0 GROUP BY a.ingredient_id, g.stock, g.status
               HAVING SUM(a.amount) > g.stock OR g.status <> N'可用'
           ) THEN 0 ELSE 1 END AS can_purchase;
END
ELSE SELECT N'Q07 购买资格（查询时）' AS section, 0 AS can_purchase;
GO

-- 订单处理与退款依据（Q08—Q12）

-- Q08 一行一笔订单；NULL 筛选参数代表全部，不专指非会员。
DECLARE @start_time DATETIME2(0) = '2026-10-04T00:00:00', @end_time DATETIME2(0) = '2026-10-05T00:00:00';
DECLARE @order_id VARCHAR(10) = NULL, @member_id VARCHAR(10) = NULL, @status NVARCHAR(20) = NULL;
;WITH ItemTotals AS (
    SELECT order_id, COUNT(*) AS item_rows, SUM(CONVERT(BIGINT, quantity)) AS cups
    FROM dbo.OrderItem GROUP BY order_id
)
SELECT o.order_id, o.order_time, o.status, o.member_id,
       COALESCE(m.name, N'非会员') AS member_name, o.total_amount,
       COALESCE(i.item_rows, 0) AS item_rows, COALESCE(i.cups, 0) AS cups
FROM dbo.SalesOrder AS o LEFT JOIN dbo.Member AS m ON m.member_id = o.member_id
LEFT JOIN ItemTotals AS i ON i.order_id = o.order_id
WHERE o.order_time >= @start_time AND o.order_time < @end_time
  AND (@order_id IS NULL OR o.order_id = @order_id)
  AND (@member_id IS NULL OR o.member_id = @member_id)
  AND (@status IS NULL OR o.status = @status)
ORDER BY o.order_time, o.order_id;
GO

-- Q09 一行一条明细，规格先聚合，加料相关聚合；仅用历史名称和价格。
DECLARE @order_id VARCHAR(10) = 'O001';
;WITH Specs AS (
    SELECT item_id,
           NULLIF(MAX(CASE WHEN spec_type = N'糖度' THEN spec_name_snapshot ELSE N'' END), N'') AS sugar,
           NULLIF(MAX(CASE WHEN spec_type = N'温度' THEN spec_name_snapshot ELSE N'' END), N'') AS temperature,
           NULLIF(MAX(CASE WHEN spec_type = N'杯型' THEN spec_name_snapshot ELSE N'' END), N'') AS cup
    FROM dbo.ItemSpec GROUP BY item_id
)
SELECT o.order_id, o.order_time, o.status, i.item_id, i.product_name_snapshot,
       i.quantity, COALESCE(s.sugar, N'未记录') AS sugar,
       COALESCE(s.temperature, N'未记录') AS temperature, COALESCE(s.cup, N'未记录') AS cup,
       COALESCE(a.addons, N'无加料') AS addons, i.unit_price, i.sub_amount
FROM dbo.SalesOrder AS o JOIN dbo.OrderItem AS i ON i.order_id = o.order_id
LEFT JOIN Specs AS s ON s.item_id = i.item_id
OUTER APPLY (
    SELECT STUFF((SELECT N'、' + ia.addon_name_snapshot
                  FROM dbo.ItemAddOn AS ia WHERE ia.item_id = i.item_id
                  ORDER BY ia.addon_id FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, N'') AS addons
) AS a
WHERE o.order_id = @order_id ORDER BY i.item_id;
GO

-- Q10 活动订单队列，NULL 表示三种活动状态；不能据此查询制作时长。
DECLARE @start_time DATETIME2(0) = '2026-10-04T00:00:00', @end_time DATETIME2(0) = '2026-10-05T00:00:00';
DECLARE @queue_status NVARCHAR(20) = NULL;
SELECT o.order_id, o.order_time, o.status, o.total_amount, COALESCE(i.cups, 0) AS cups
FROM dbo.SalesOrder AS o
LEFT JOIN (SELECT order_id, SUM(CONVERT(BIGINT, quantity)) AS cups FROM dbo.OrderItem GROUP BY order_id) AS i
  ON i.order_id = o.order_id
WHERE o.status IN (N'排队中', N'制作中', N'待取餐')
  AND (@queue_status IS NULL OR o.status = @queue_status)
  AND o.order_time >= @start_time AND o.order_time < @end_time
ORDER BY o.order_time, o.order_id;
GO

-- Q11 两组结果：退款资格与已取消记录；资格查询不会执行退款。
DECLARE @start_time DATETIME2(0) = '2026-10-04T00:00:00', @end_time DATETIME2(0) = '2026-10-05T00:00:00';
SELECT N'排队中，可申请退款' AS category, o.order_id, o.order_time, o.status,
       o.member_id, COALESCE(m.name, N'非会员') AS member_name, o.total_amount
FROM dbo.SalesOrder AS o LEFT JOIN dbo.Member AS m ON m.member_id = o.member_id
WHERE o.status = N'排队中' AND o.order_time >= @start_time AND o.order_time < @end_time
ORDER BY o.order_time, o.order_id;
SELECT N'已取消，保留原成交金额' AS category, order_id, order_time, status, member_id, total_amount
FROM dbo.SalesOrder
WHERE status = N'已取消' AND order_time >= @start_time AND order_time < @end_time
ORDER BY order_time, order_id;
GO

-- Q12 订单原料快照与应返库数量；amount 已含全部杯数，不再乘 quantity。
-- 默认 O001 已完成：8 种历史原料，可返数量全部为 0。
-- 本批次只查询；没有返库流水，不能用结果证明实际返库成功。
DECLARE @order_id VARCHAR(10) = 'O001';

-- 第一组：订单是否存在、是否具备退款资格、是否缺少明细或消耗快照。
;WITH ItemChecks AS (
    SELECT i.item_id,
           CASE WHEN EXISTS (SELECT 1 FROM dbo.OrderItemIngredient AS c
                             WHERE c.item_id = i.item_id) THEN 0 ELSE 1 END AS missing_snapshot
    FROM dbo.OrderItem AS i
    WHERE i.order_id = @order_id
)
SELECT N'Q12 订单检查' AS section, @order_id AS requested_order_id,
       o.status, checks.item_rows, checks.missing_snapshot_items,
       CASE WHEN o.order_id IS NULL THEN N'订单不存在'
            WHEN checks.item_rows = 0 THEN N'订单没有明细，请检查'
            WHEN checks.missing_snapshot_items > 0 THEN N'明细缺少消耗快照，暂不能确定完整返库数量'
            WHEN o.status = N'排队中' THEN N'可按保存快照申请退款返库'
            WHEN o.status = N'已取消' THEN N'仅查看历史依据，不能再次返库'
            ELSE N'当前状态不允许退款，仅查看历史消耗' END AS snapshot_check
FROM (SELECT COUNT(*) AS item_rows,
             COALESCE(SUM(missing_snapshot), 0) AS missing_snapshot_items
      FROM ItemChecks) AS checks
LEFT JOIN dbo.SalesOrder AS o ON o.order_id = @order_id;

-- 第二组：同单不同明细使用的相同原料先合并；退款使用历史快照，不重算配方。
SELECT N'Q12 原料快照' AS section, o.order_id, o.status,
       c.ingredient_id, g.ingredient_name, g.unit,
       SUM(c.amount) AS saved_amount,
       CASE WHEN o.status = N'排队中'
                 AND NOT EXISTS (
                     SELECT 1 FROM dbo.OrderItem AS missing_item
                     WHERE missing_item.order_id = o.order_id
                       AND NOT EXISTS (SELECT 1 FROM dbo.OrderItemIngredient AS saved
                                       WHERE saved.item_id = missing_item.item_id)
                 )
            THEN SUM(c.amount) ELSE CAST(0 AS DECIMAL(38,2)) END AS refundable_amount
FROM dbo.SalesOrder AS o
JOIN dbo.OrderItem AS i ON i.order_id = o.order_id
JOIN dbo.OrderItemIngredient AS c ON c.item_id = i.item_id
JOIN dbo.Ingredient AS g ON g.ingredient_id = c.ingredient_id
WHERE o.order_id = @order_id
GROUP BY o.order_id, o.status, c.ingredient_id, g.ingredient_name, g.unit
ORDER BY c.ingredient_id;
GO

-- 会员管理（Q13—Q14）

-- Q13 会员资料与订单历史；第三组是从未下单会员（NOT EXISTS）。
DECLARE @member_id VARCHAR(10) = 'M001';
SELECT member_id, name, phone, points FROM dbo.Member WHERE member_id = @member_id;
SELECT order_id, order_time, status, total_amount FROM dbo.SalesOrder
WHERE member_id = @member_id ORDER BY order_time, order_id;
SELECT m.member_id, m.name, m.points FROM dbo.Member AS m
WHERE NOT EXISTS (SELECT 1 FROM dbo.SalesOrder AS o WHERE o.member_id = m.member_id)
ORDER BY m.member_id;
GO

-- Q14 会员累计消费统计；未完成和已取消订单不计入消费。
-- 空关键词表示全部会员，最低消费额可用于筛选重点会员。
DECLARE @member_keyword NVARCHAR(50) = N'';
DECLARE @min_total_spending DECIMAL(18,2) = 0;
SELECT member_id,
       member_name,
       phone,
       current_points,
       completed_order_count,
       cups_purchased,
       total_spending,
       average_order_amount,
       first_purchase_time,
       last_purchase_time
FROM dbo.vw_MemberConsumptionStatistics
WHERE member_name LIKE N'%' + @member_keyword + N'%'
  AND total_spending >= @min_total_spending
ORDER BY total_spending DESC, completed_order_count DESC, member_id;
GO

-- 员工与值班安排（Q15—Q16）

-- Q15 月薪仅供管理者使用；资料、相交排班、指定时刻值班三组结果。
DECLARE @employee_status NVARCHAR(10) = NULL;
DECLARE @start_time DATETIME2(0) = '2026-10-04T00:00:00', @end_time DATETIME2(0) = '2026-10-05T00:00:00';
DECLARE @at_time DATETIME2(0) = '2026-10-04T16:00:00';
SELECT employee_id, name, status, salary, role FROM dbo.Employee
WHERE @employee_status IS NULL OR status = @employee_status ORDER BY employee_id;
SELECT d.duty_id, e.employee_id, e.name, e.status AS current_employee_status, e.role, d.start_time, d.end_time
FROM dbo.DutyRoster AS d JOIN dbo.Employee AS e ON e.employee_id = d.employee_id
WHERE d.start_time < @end_time AND d.end_time > @start_time
ORDER BY d.start_time, e.employee_id;
SELECT e.employee_id, e.name, e.role, d.duty_id, d.start_time, d.end_time
FROM dbo.DutyRoster AS d JOIN dbo.Employee AS e ON e.employee_id = d.employee_id
WHERE d.start_time <= @at_time AND @at_time < d.end_time
ORDER BY e.employee_id;
GO

-- Q16 全部订单的值班归属；订单可匹配多人，不累加金额。
DECLARE @order_id VARCHAR(10) = NULL;
SELECT o.order_id, o.order_time, d.duty_id, e.employee_id, e.name, e.role, d.start_time, d.end_time,
       CASE WHEN d.duty_id IS NULL THEN N'未匹配排班' ELSE N'已匹配' END AS roster_match
FROM dbo.SalesOrder AS o
LEFT JOIN dbo.DutyRoster AS d ON d.start_time <= o.order_time AND o.order_time < d.end_time
LEFT JOIN dbo.Employee AS e ON e.employee_id = d.employee_id
WHERE @order_id IS NULL OR o.order_id = @order_id
ORDER BY o.order_time, o.order_id, e.employee_id, d.duty_id;
SELECT o.order_id, o.order_time, o.status FROM dbo.SalesOrder AS o
WHERE (@order_id IS NULL OR o.order_id = @order_id)
AND NOT EXISTS (SELECT 1 FROM dbo.DutyRoster AS d
                WHERE d.start_time <= o.order_time AND o.order_time < d.end_time)
ORDER BY o.order_time, o.order_id;
GO

-- 经营统计（Q17—Q18）

-- Q17 指定商品名称关键词和时间范围的销量／营业额。
-- 只计算已完成订单；开始时间包含，结束时间不包含。
-- 当前模式没有商品分类字段，因此用商品名称关键词表示品类，例如“奶茶”。
DECLARE @product_keyword NVARCHAR(50) = N'奶茶';
DECLARE @start_time DATETIME2(0) = '2026-10-04T00:00:00';
DECLARE @end_time DATETIME2(0) = '2026-10-05T00:00:00';

-- 第一组：关键词范围内各商品的销量和营业额。
SELECT s.product_id,
       s.product_name,
       COUNT(DISTINCT s.order_id) AS completed_order_count,
       SUM(s.cups_sold) AS cups_sold,
       SUM(s.sales_amount) AS sales_amount
FROM dbo.vw_ProductSalesStatistics AS s
WHERE s.order_time >= @start_time
  AND s.order_time < @end_time
  AND s.product_name LIKE N'%' + @product_keyword + N'%'
GROUP BY s.product_id, s.product_name
ORDER BY sales_amount DESC, cups_sold DESC, s.product_id;

-- 第二组：该关键词品类的合计。
SELECT @product_keyword AS product_keyword,
       @start_time AS start_time,
       @end_time AS end_time,
       COUNT(DISTINCT s.order_id) AS completed_order_count,
       COALESCE(SUM(s.cups_sold), 0) AS total_cups_sold,
       COALESCE(SUM(s.sales_amount), 0) AS total_sales_amount
FROM dbo.vw_ProductSalesStatistics AS s
WHERE s.order_time >= @start_time
  AND s.order_time < @end_time
  AND s.product_name LIKE N'%' + @product_keyword + N'%';
GO

-- Q18 指定日期的当日经营统计。
-- 只输入一个日期；查询范围自动取当天零点到次日零点。
-- 视图只保存有已完成订单的日期；LEFT JOIN 保证无销售日期仍返回一行 0。
DECLARE @business_date DATE = '2026-10-04';
SELECT d.business_date,
       COALESCE(s.completed_order_count, 0) AS completed_order_count,
       COALESCE(s.cups_sold, 0) AS cups_sold,
       CAST(COALESCE(s.sales_amount, 0) AS DECIMAL(38,2)) AS sales_amount,
       CAST(COALESCE(s.average_order_amount, 0) AS DECIMAL(18,2)) AS average_order_amount,
       COALESCE(s.member_order_count, 0) AS member_order_count,
       COALESCE(s.nonmember_order_count, 0) AS nonmember_order_count
FROM (SELECT @business_date AS business_date) AS d
LEFT JOIN dbo.vw_DailySalesStatistics AS s
  ON s.business_date = d.business_date;
GO
