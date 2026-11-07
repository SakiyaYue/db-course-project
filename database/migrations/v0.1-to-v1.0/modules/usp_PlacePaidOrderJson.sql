CREATE PROCEDURE teabar_api.usp_PlacePaidOrderJson
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
       OR @order_id COLLATE Latin1_General_100_BIN2 LIKE N'%[^A-Za-z0-9_-]%'
        THROW 52602, N'订单编号须为1至10位ASCII字母、数字、下划线或短横线。', 1;

    DECLARE @documents TABLE (kind CHAR(1) PRIMARY KEY, document NVARCHAR(MAX));
    INSERT @documents VALUES ('I', @items_json), ('S', @specs_json), ('A', @addons_json);
    IF EXISTS (SELECT 1 FROM @documents WHERE document IS NULL OR ISJSON(document) <> 1)
        THROW 52600, N'订单参数必须为合法JSON数组。', 1;
    -- Wrap the root to determine its JSON type without relying on SQL 2022-only ISJSON(..., ARRAY).
    IF EXISTS (
        SELECT 1 FROM @documents AS d
        CROSS APPLY OPENJSON(N'[' + d.document + N']') AS root
        WHERE root.[type] <> 4
    ) THROW 52600, N'订单参数必须为JSON数组，不能传对象或标量。', 1;
    IF NOT EXISTS (SELECT 1 FROM OPENJSON(@items_json))
        THROW 52600, N'订单至少需要一条明细。', 1;

    DECLARE @rows TABLE (kind CHAR(1), row_no INT, document NVARCHAR(MAX), PRIMARY KEY(kind,row_no));
    IF EXISTS (SELECT 1 FROM @documents AS d CROSS APPLY OPENJSON(d.document) AS j WHERE j.[type] <> 5)
        THROW 52601, N'数组中的每一项都必须是对象。', 1;
    INSERT @rows SELECT d.kind, CONVERT(INT,j.[key]), j.value
    FROM @documents AS d CROSS APPLY OPENJSON(d.document) AS j;

    DECLARE @properties TABLE (
        kind CHAR(1), row_no INT, property_name NVARCHAR(4000) COLLATE Latin1_General_100_BIN2,
        property_value NVARCHAR(MAX), json_type INT
    );
    INSERT @properties SELECT r.kind,r.row_no,j.[key],j.value,j.[type]
    FROM @rows AS r CROSS APPLY OPENJSON(r.document) AS j;
    DECLARE @allowed TABLE (kind CHAR(1), property_name NVARCHAR(30) COLLATE Latin1_General_100_BIN2);
    INSERT @allowed VALUES ('I',N'item_id'),('I',N'product_id'),('I',N'quantity'),
        ('S',N'item_id'),('S',N'spec_id'),('A',N'item_id'),('A',N'addon_id');
    IF EXISTS (SELECT 1 FROM @properties AS p WHERE NOT EXISTS (
        SELECT 1 FROM @allowed AS a WHERE a.kind=p.kind AND a.property_name=p.property_name
          AND DATALENGTH(a.property_name)=DATALENGTH(p.property_name)))
       OR EXISTS (SELECT kind,row_no,property_name FROM @properties
                  GROUP BY kind,row_no,property_name HAVING COUNT(*)<>1)
       OR EXISTS (SELECT 1 FROM @rows AS r JOIN @allowed AS a ON a.kind=r.kind
                  WHERE NOT EXISTS (SELECT 1 FROM @properties AS p WHERE p.kind=r.kind
                    AND p.row_no=r.row_no AND p.property_name=a.property_name))
        THROW 52601, N'JSON对象字段缺失、重复、大小写不符或包含额外字段。', 1;
    IF EXISTS (SELECT 1 FROM @properties WHERE property_name<>N'quantity' AND (
           json_type<>1 OR property_value IS NULL OR DATALENGTH(property_value) NOT BETWEEN 2 AND 20
           OR property_value COLLATE Latin1_General_100_BIN2 LIKE N'%[^A-Za-z0-9_-]%'))
       OR EXISTS (SELECT 1 FROM @properties WHERE property_name=N'quantity' AND (
           json_type<>2 OR property_value IS NULL OR DATALENGTH(property_value)=0
           OR property_value COLLATE Latin1_General_100_BIN2 LIKE N'%[^0-9]%'
           OR TRY_CONVERT(INT,property_value) IS NULL OR TRY_CONVERT(INT,property_value)<=0))
        THROW 52602, N'JSON编号或购买数量的类型、格式、长度或范围不正确。', 1;

    DECLARE @parsed TABLE (kind CHAR(1), row_no INT, item_id VARCHAR(10) COLLATE DATABASE_DEFAULT,
        selection_id VARCHAR(10) COLLATE DATABASE_DEFAULT, quantity INT);
    INSERT @parsed
    SELECT kind,row_no,
        CONVERT(VARCHAR(10),MAX(CASE WHEN property_name=N'item_id' THEN property_value END)),
        CONVERT(VARCHAR(10),MAX(CASE WHEN property_name IN (N'product_id',N'spec_id',N'addon_id') THEN property_value END)),
        MAX(CASE WHEN property_name=N'quantity' THEN TRY_CONVERT(INT,property_value) END)
    FROM @properties GROUP BY kind,row_no;
    IF EXISTS (SELECT item_id FROM @parsed WHERE kind='I' GROUP BY item_id HAVING COUNT(*)>1)
       OR EXISTS (SELECT kind,item_id,selection_id FROM @parsed WHERE kind IN ('S','A')
                  GROUP BY kind,item_id,selection_id HAVING COUNT(*)>1)
        THROW 52603, N'明细编号或规格、加料选择重复。', 1;
    IF EXISTS (SELECT 1 FROM @parsed AS choice WHERE choice.kind IN ('S','A') AND NOT EXISTS (
        SELECT 1 FROM @parsed AS item WHERE item.kind='I' AND item.item_id=choice.item_id))
        THROW 52604, N'规格或加料引用了本次订单以外的明细。', 1;

    DECLARE @items teabar_api.OrderLines, @specs teabar_api.OrderSpecs, @addons teabar_api.OrderAddOns;
    INSERT @items SELECT item_id,selection_id,quantity FROM @parsed WHERE kind='I';
    INSERT @specs SELECT item_id,selection_id FROM @parsed WHERE kind='S';
    INSERT @addons SELECT item_id,selection_id FROM @parsed WHERE kind='A';
    DECLARE @validated_order_id VARCHAR(10)=CONVERT(VARCHAR(10),@order_id);
    EXEC teabar_api.usp_PlacePaidOrder @validated_order_id,@items,@specs,@addons,@payment_succeeded;
END;
