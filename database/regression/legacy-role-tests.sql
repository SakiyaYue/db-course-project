-- Generated test-only extraction from role.sql; no installation DDL.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
DECLARE @administrator SYSNAME=USER_NAME(), @impersonating BIT=0;
DECLARE @prefix VARCHAR(8)='VT'+LEFT(REPLACE(CONVERT(VARCHAR(36),NEWID()),'-',''),6);
DECLARE @P VARCHAR(10)=@prefix+'P1',@P2 VARCHAR(10)=@prefix+'P2',
 @S1 VARCHAR(10)=@prefix+'S1',@S2 VARCHAR(10)=@prefix+'S2',@S3 VARCHAR(10)=@prefix+'S3',
 @S4 VARCHAR(10)=@prefix+'S4',@S5 VARCHAR(10)=@prefix+'S5',
 @I1 VARCHAR(10)=@prefix+'I1',@I2 VARCHAR(10)=@prefix+'I2',@I3 VARCHAR(10)=@prefix+'I3',
 @I4 VARCHAR(10)=@prefix+'I4',@A VARCHAR(10)=@prefix+'A1',@A2 VARCHAR(10)=@prefix+'A2',
 @MA VARCHAR(10)=@prefix+'M1',@MB VARCHAR(10)=@prefix+'M2',@MC VARCHAR(10)=@prefix+'M3',
 @E VARCHAR(10)=@prefix+'E1',@D1 VARCHAR(10)=@prefix+'D1',@D2 VARCHAR(10)=@prefix+'D2',@D3 VARCHAR(10)=@prefix+'D3',
 @OG VARCHAR(10)=@prefix+'O1',@OG2 VARCHAR(10)=@prefix+'O2',@OGB VARCHAR(10)=@prefix+'O3',
 @OM VARCHAR(10)=@prefix+'O4',@OMB VARCHAR(10)=@prefix+'O5',@OD VARCHAR(10)=@prefix+'O6',
 @OP VARCHAR(10)=@prefix+'O7',@OX VARCHAR(10)=@prefix+'OX',
 @TG VARCHAR(10)=@prefix+'T1',@TG2 VARCHAR(10)=@prefix+'T2',@TGB VARCHAR(10)=@prefix+'T3',
 @TM VARCHAR(10)=@prefix+'T4',@TMB VARCHAR(10)=@prefix+'T5',@TX VARCHAR(10)=@prefix+'TX',@TY VARCHAR(10)=@prefix+'TY';
DECLARE @PA VARCHAR(20),@PB VARCHAR(20),@PC VARCHAR(20),@GA UNIQUEIDENTIFIER,@GB UNIQUEIDENTIFIER;
WHILE @PA IS NULL OR EXISTS(SELECT 1 FROM dbo.Member WHERE phone=@PA)
 SET @PA='199'+RIGHT('00000000'+CONVERT(VARCHAR(8),ABS(CONVERT(BIGINT,CHECKSUM(NEWID())))%100000000),8);
WHILE @PB IS NULL OR @PB=@PA OR EXISTS(SELECT 1 FROM dbo.Member WHERE phone=@PB)
 SET @PB='199'+RIGHT('00000000'+CONVERT(VARCHAR(8),ABS(CONVERT(BIGINT,CHECKSUM(NEWID())))%100000000),8);
WHILE @PC IS NULL OR @PC IN(@PA,@PB) OR EXISTS(SELECT 1 FROM dbo.Member WHERE phone=@PC)
 SET @PC='199'+RIGHT('00000000'+CONVERT(VARCHAR(8),ABS(CONVERT(BIGINT,CHECKSUM(NEWID())))%100000000),8);
SELECT @GA=guest_id FROM teabar_auth.PrincipalBinding WHERE principal_name=N'demo_guest_a';
SELECT @GB=guest_id FROM teabar_auth.PrincipalBinding WHERE principal_name=N'demo_guest_b';

DECLARE @cases TABLE(
 seq INT IDENTITY PRIMARY KEY, user_name SYSNAME, case_name NVARCHAR(100),
 statement NVARCHAR(MAX), expected_error INT NULL, setup NVARCHAR(MAX), teardown NVARCHAR(MAX));
INSERT @cases(user_name,case_name,statement,expected_error,setup,teardown) VALUES
    (N'demo_guest_a', N'顾客浏览可售商品及选项', N'IF NOT EXISTS (SELECT 1 FROM teabar_api.vw_Menu WHERE product_id=@P) THROW 52500,N''商品未显示'',1; SELECT product_id,product_name,base_price FROM teabar_api.vw_Menu WHERE product_id=@P;', NULL, NULL, NULL),
    (N'demo_guest_a', N'顾客付款下单：两杯、规格及加料', N'DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TG, @P, 2);
INSERT @s VALUES(@TG, @S1), (@TG, @S2), (@TG, @S3);
INSERT @addon_selection VALUES(@TG, @A);
EXEC teabar_api.usp_PlacePaidOrder @OG, @l, @s, @addon_selection, 1;', NULL, NULL, N'IF NOT EXISTS(SELECT 1 FROM dbo.SalesOrder WHERE order_id=@OG AND total_amount=19.6)
 OR NOT EXISTS(SELECT 1 FROM dbo.OrderItemIngredient WHERE item_id=@TG AND ingredient_id=@I1 AND amount=26)
 OR NOT EXISTS(SELECT 1 FROM dbo.OrderItemIngredient WHERE item_id=@TG AND ingredient_id=@I2 AND amount=200)
 OR NOT EXISTS(SELECT 1 FROM dbo.OrderItemIngredient WHERE item_id=@TG AND ingredient_id=@I3 AND amount=2)
 THROW 52500,N''价格或多规格、同原料加料计算不正确'',1;'),
    (N'demo_guest_a', N'同一顾客会话再次下单', N'DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TG2, @P, 1);
INSERT @s VALUES(@TG2, @S1), (@TG2, @S2), (@TG2, @S3);

EXEC teabar_api.usp_PlacePaidOrder @OG2, @l, @s, @addon_selection, 1;', NULL, NULL, NULL),
    (N'demo_guest_b', N'第二名顾客独立下单', N'DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TGB, @P, 1);
INSERT @s VALUES(@TGB, @S1), (@TGB, @S2), (@TGB, @S3);

EXEC teabar_api.usp_PlacePaidOrder @OGB, @l, @s, @addon_selection, 1;', NULL, NULL, NULL),
    (N'demo_member_a', N'会员付款下单并绑定本人身份', N'DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TM, @P, 2);
INSERT @s VALUES(@TM, @S1), (@TM, @S2), (@TM, @S3);
INSERT @addon_selection VALUES(@TM, @A);
EXEC teabar_api.usp_PlacePaidOrder @OM, @l, @s, @addon_selection, 1;', NULL, NULL, NULL),
    (N'demo_member_b', N'第二名会员独立下单', N'DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TMB, @P, 1);
INSERT @s VALUES(@TMB, @S1), (@TMB, @S2), (@TMB, @S3);

EXEC teabar_api.usp_PlacePaidOrder @OMB, @l, @s, @addon_selection, 1;', NULL, NULL, NULL),
    (N'demo_guest_a', N'顾客仅能查询本人订单', N'IF NOT EXISTS(SELECT 1 FROM teabar_api.vw_MyOrders WHERE order_id=@OG)
 OR EXISTS(SELECT 1 FROM teabar_api.vw_MyOrders WHERE order_id IN(@OGB,@OM,@OMB))
 THROW 52500,N''游客订单未隔离'',1;
 SELECT * FROM teabar_api.vw_MyOrderItems WHERE order_id=@OG;', NULL, NULL, NULL),
    (N'demo_member_a', N'会员资料和消费记录仅限本人', N'IF NOT EXISTS(SELECT 1 FROM teabar_api.vw_MyMember WHERE member_id=@MA)
 OR EXISTS(SELECT 1 FROM teabar_api.vw_MyMember WHERE member_id=@MB)
 OR EXISTS(SELECT 1 FROM teabar_api.vw_MyOrders WHERE order_id IN(@OG,@OMB,@OD))
 THROW 52500,N''会员数据未隔离'',1; SELECT * FROM teabar_api.vw_MyMember;', NULL, NULL, NULL),
    (N'demo_guest_a', N'伪造SESSION_CONTEXT不能改订单身份', N'DECLARE @previous SQL_VARIANT=SESSION_CONTEXT(N''guest_id'');
EXEC sys.sp_set_session_context @key=N''guest_id'',@value=@GB;
BEGIN TRY
 IF EXISTS(SELECT 1 FROM teabar_api.vw_MyOrders WHERE order_id=@OGB) THROW 52500,N''会话变量绕过了身份绑定'',1;
 EXEC sys.sp_set_session_context @key=N''guest_id'',@value=@previous;
END TRY
BEGIN CATCH
 EXEC sys.sp_set_session_context @key=N''guest_id'',@value=@previous; THROW;
END CATCH;', NULL, NULL, NULL),
    (N'demo_clerk', N'店员仅查当天及全部未完成订单', N'IF EXISTS(SELECT 1 FROM teabar_api.vw_WorkOrders WHERE order_id=@OD)
 OR NOT EXISTS(SELECT 1 FROM teabar_api.vw_WorkOrders WHERE order_id=@OP)
 OR NOT EXISTS(SELECT 1 FROM teabar_api.vw_WorkOrders WHERE order_id=@OM)
 THROW 52500,N''店员订单时间范围不正确'',1; SELECT * FROM teabar_api.vw_WorkOrders WHERE order_id IN(@OM,@OP);', NULL, NULL, NULL),
    (N'demo_manager', N'店长可查看历史订单和经营统计', N'IF NOT EXISTS(SELECT 1 FROM dbo.SalesOrder WHERE order_id=@OD) THROW 52500,N''店长不能查历史'',1; SELECT * FROM teabar_api.vw_DailySales WHERE sale_date=CONVERT(DATE,DATEADD(DAY,-2,SYSDATETIME()));', NULL, NULL, NULL),
    (N'demo_guest_a', N'重复订单编号不能造成重复扣库', N'DECLARE @l teabar_api.OrderLines,@s teabar_api.OrderSpecs,@addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TX,@P,2); INSERT @s VALUES(@TX,@S1),(@TX,@S2),(@TX,@S3);
INSERT @addon_selection VALUES(@TX,@A);
EXEC teabar_api.usp_PlacePaidOrder @OG,@l,@s,@addon_selection,1;', 2627, NULL, NULL),
    (N'demo_guest_a', N'顾客不能直接插入他人归属的订单', N'INSERT dbo.SalesOrder(order_id,guest_id,total_amount) VALUES(@OX,@GB,0);', 229, NULL, NULL),
    (N'demo_guest_a', N'顾客不能直接读取全部订单', N'SELECT * FROM dbo.SalesOrder;', 229, NULL, NULL),
    (N'demo_member_a', N'会员不能直接读取会员名单', N'SELECT * FROM dbo.Member;', 229, NULL, NULL),
    (N'demo_clerk', N'店员不能读取员工工资', N'SELECT salary FROM dbo.Employee;', 229, NULL, NULL),
    (N'demo_guest_a', N'顾客不能读取会员专属资料视图', N'SELECT * FROM teabar_api.vw_MyMember;', 229, NULL, NULL),
    (N'demo_clerk', N'店员不能读取历史销售统计', N'SELECT * FROM teabar_api.vw_DailySales;', 229, NULL, NULL),
    (N'demo_guest_a', N'顾客不能退款他人游客订单', N'EXEC teabar_api.usp_RefundOrder @OGB;', 52105, NULL, NULL),
    (N'demo_member_a', N'会员不能退款其他会员订单', N'EXEC teabar_api.usp_RefundOrder @OMB;', 52105, NULL, NULL),
    (N'demo_guest_a', N'顾客不能直接篡改订单金额', N'UPDATE dbo.SalesOrder SET total_amount=0 WHERE order_id=@OG;', 229, NULL, NULL),
    (N'demo_member_a', N'会员不能自行修改积分', N'UPDATE dbo.Member SET points=9999 WHERE member_id=@MA;', 229, NULL, NULL),
    (N'demo_guest_a', N'顾客不能推进制作状态', N'EXEC teabar_api.usp_AdvanceOrder @OG,N''制作中'';', 229, NULL, NULL),
    (N'demo_clerk', N'店员没有代替顾客下单权限', N'EXEC teabar_api.usp_PlacePaidOrder;', 229, NULL, NULL),
    (N'demo_guest_a', N'支付失败不产生订单', N'DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TX, @P, 2);
INSERT @s VALUES(@TX, @S1), (@TX, @S2), (@TX, @S3);
INSERT @addon_selection VALUES(@TX, @A);
EXEC teabar_api.usp_PlacePaidOrder @OX, @l, @s, @addon_selection, 0;', 52001, NULL, NULL),
    (N'demo_guest_a', N'漏选已配置规格类型被拒绝', N'DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TX, @P, 2);
INSERT @s VALUES(@TX, @S1), (@TX, @S2);
INSERT @addon_selection VALUES(@TX, @A);
EXEC teabar_api.usp_PlacePaidOrder @OX, @l, @s, @addon_selection, 1;', 52009, NULL, NULL),
    (N'demo_guest_a', N'同类型选择两个规格被拒绝', N'DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TX, @P, 2);
INSERT @s VALUES(@TX, @S1), (@TX, @S4), (@TX, @S2), (@TX, @S3);
INSERT @addon_selection VALUES(@TX, @A);
EXEC teabar_api.usp_PlacePaidOrder @OX, @l, @s, @addon_selection, 1;', 52008, NULL, NULL),
    (N'demo_guest_a', N'不适用于商品的规格被拒绝', N'DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TX, @P, 2);
INSERT @s VALUES(@TX, @S1), (@TX, @S2), (@TX, @S5);
INSERT @addon_selection VALUES(@TX, @A);
EXEC teabar_api.usp_PlacePaidOrder @OX, @l, @s, @addon_selection, 1;', 52007, NULL, NULL),
    (N'demo_guest_a', N'下单接口没有可伪造的归属或金额参数', N'IF EXISTS (
 SELECT 1 FROM sys.parameters WHERE object_id=OBJECT_ID(N''teabar_api.usp_PlacePaidOrder'')
 AND name IN(N''@member_id'',N''@guest_id'',N''@total_amount''))
 THROW 52500,N''接口暴露了不应由调用者指定的参数'',1;', NULL, NULL, NULL),
    (N'demo_clerk', N'不能从排队中直接完成', N'EXEC teabar_api.usp_AdvanceOrder @OM,N''已完成'';', 52103, NULL, NULL),
    (N'demo_clerk', N'店员接单进入制作中', N'EXEC teabar_api.usp_AdvanceOrder @OM,N''制作中'';', NULL, NULL, NULL),
    (N'demo_member_a', N'制作中不允许退款', N'EXEC teabar_api.usp_RefundOrder @OM;', 52106, NULL, NULL),
    (N'demo_clerk', N'制作完成进入待取餐', N'EXEC teabar_api.usp_AdvanceOrder @OM,N''待取餐'';', NULL, NULL, NULL),
    (N'demo_clerk', N'交付完成并自动结算积分', N'EXEC teabar_api.usp_AdvanceOrder @OM,N''已完成'';', NULL, NULL, NULL),
    (N'demo_member_a', N'19.60元整单首次完成积19分', N'IF NOT EXISTS(SELECT 1 FROM teabar_api.vw_MyMember WHERE member_id=@MA AND points=19) THROW 52500,N''积分算法错误'',1;', NULL, NULL, NULL),
    (N'demo_clerk', N'重复完成不得再次加分', N'EXEC teabar_api.usp_AdvanceOrder @OM,N''已完成'';', 52103, NULL, NULL),
    (N'demo_member_a', N'已完成订单不允许退款', N'EXEC teabar_api.usp_RefundOrder @OM;', 52106, NULL, NULL),
    (N'demo_guest_a', N'配方变更后本人退款仍按付款快照返库', N'EXEC teabar_api.usp_RefundOrder @OG;', NULL, N'UPDATE dbo.Recipe SET base_amount=123 WHERE product_id=@P AND ingredient_id=@I1;', N'IF NOT EXISTS(SELECT 1 FROM dbo.Ingredient WHERE ingredient_id=@I1 AND stock=944)
 THROW 52500,N''退款重算了当前配方，未按原快照返库'',1;
UPDATE dbo.Recipe SET base_amount=10 WHERE product_id=@P AND ingredient_id=@I1;'),
    (N'demo_guest_a', N'重复退款不得重复返库', N'EXEC teabar_api.usp_RefundOrder @OG;', 52106, NULL, NULL),
    (N'demo_clerk', N'店员协助顾客退款', N'EXEC teabar_api.usp_RefundOrder @OGB;', NULL, NULL, NULL),
    (N'demo_manager', N'店长协助会员退款', N'EXEC teabar_api.usp_RefundOrder @OMB;', NULL, NULL, NULL),
    (N'demo_clerk', N'店员登记会员且积分初始为0', N'EXEC teabar_api.usp_SaveMember @MC,N''新会员'',@PC;', NULL, NULL, NULL),
    (N'demo_clerk', N'店员更正会员资料但不改积分', N'EXEC teabar_api.usp_SaveMember @MA,N''修改后的本人姓名'',@PA; EXEC teabar_api.usp_FindMember @PA;', NULL, NULL, NULL),
    (N'demo_manager', N'店长通过补库增加原料', N'EXEC teabar_api.usp_AdjustStock @I1,N''补库'',5;', NULL, NULL, NULL),
    (N'demo_clerk', N'店员不能补库', N'EXEC teabar_api.usp_AdjustStock @I1,N''补库'',5;', 229, NULL, NULL),
    (N'demo_manager', N'补库数量不能为0', N'EXEC teabar_api.usp_AdjustStock @I1,N''补库'',0;', 52110, NULL, NULL),
    (N'demo_manager', N'计件补库不能使用小数', N'EXEC teabar_api.usp_AdjustStock @I3,N''补库'',0.5;', 52111, NULL, NULL),
    (N'demo_manager', N'盘点实际库存允许为0', N'EXEC teabar_api.usp_AdjustStock @I3,N''盘点'',0;', NULL, NULL, NULL),
    (N'demo_manager', N'盘点库存不能为负', N'EXEC teabar_api.usp_AdjustStock @I3,N''盘点'',-1;', 52110, NULL, NULL),
    (N'demo_manager', N'店长也不能直接更新库存', N'UPDATE dbo.Ingredient SET stock=999 WHERE ingredient_id=@I1;', 229, NULL, NULL),
    (N'demo_manager', N'店长也不能直接改历史成交快照', N'UPDATE dbo.OrderItem SET unit_price=0 WHERE item_id=@TM;', 229, NULL, NULL),
    (N'demo_manager', N'店长没有物理删除商品权限', N'DELETE dbo.Product WHERE product_id=@P;', 229, NULL, NULL),
    (N'demo_manager', N'店长没有物理删除订单权限', N'DELETE dbo.SalesOrder WHERE order_id=@OM;', 229, NULL, NULL),
    (N'demo_manager', N'店长不能修改身份绑定', N'UPDATE teabar_auth.PrincipalBinding SET member_id=@MB WHERE principal_name=N''demo_member_a'';', 229, NULL, NULL),
    (N'demo_manager', N'店长不能授予数据库角色', N'ALTER ROLE teabar_manager ADD MEMBER demo_guest_a;', 15151, NULL, NULL),
    (N'demo_manager', N'店长改价不改历史金额和快照', N'EXEC teabar_api.usp_SaveProduct @P,N''改名后的商品'',7.8,N''在售'';', NULL, NULL, NULL),
    (N'demo_manager', N'已使用原料不能变更单位', N'EXEC teabar_api.usp_SaveIngredient @I1,N''糖浆'',N''g'',N''可用'';', 52113, NULL, NULL),
    (N'demo_manager', N'停用商品规格配置', N'EXEC teabar_api.usp_SaveProductSpecification @P,@S3,2,N''停用'';', NULL, NULL, NULL),
    (N'demo_guest_a', N'停用规格不能购买', N'DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TX, @P, 2);
INSERT @s VALUES(@TX, @S1), (@TX, @S2), (@TX, @S3);
INSERT @addon_selection VALUES(@TX, @A);
EXEC teabar_api.usp_PlacePaidOrder @OX, @l, @s, @addon_selection, 1;', 52007, NULL, NULL),
    (N'demo_manager', N'计件规格规则拒绝1.5个', N'EXEC teabar_api.usp_SaveSpecificationIngredient @P,@S3,@I3,1.5;', 52116, NULL, NULL),
    (N'demo_manager', N'重新启用已完成的规格配置', N'EXEC teabar_api.usp_SaveProductSpecification @P,@S3,2,N''可用'';', NULL, NULL, NULL),
    (N'demo_manager', N'模拟库存不足的盘点', N'EXEC teabar_api.usp_AdjustStock @I1,N''盘点'',1;', NULL, NULL, NULL),
    (N'demo_guest_a', N'库存不足整单回滚不留下半张订单', N'DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TX, @P, 2);
INSERT @s VALUES(@TX, @S1), (@TX, @S2), (@TX, @S3);
INSERT @addon_selection VALUES(@TX, @A);
EXEC teabar_api.usp_PlacePaidOrder @OX, @l, @s, @addon_selection, 1;', 52016, NULL, NULL),
    (N'demo_manager', N'补齐可用库存供后续测试', N'EXEC teabar_api.usp_AdjustStock @I1,N''盘点'',1000; EXEC teabar_api.usp_AdjustStock @I3,N''盘点'',100;', NULL, NULL, NULL),
    (N'demo_guest_a', N'多条明细需求先汇总防止各自足够但整单不足', N'DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TX, @P, 1),(@TY,@P,1);
INSERT @s VALUES(@TX,@S1),(@TX,@S2),(@TX,@S3),(@TY,@S1),(@TY,@S2),(@TY,@S3);

EXEC teabar_api.usp_PlacePaidOrder @OX, @l, @s, @addon_selection, 1;', 52016, N'UPDATE dbo.Ingredient SET stock=15 WHERE ingredient_id=@I1;', N'UPDATE dbo.Ingredient SET stock=1000 WHERE ingredient_id=@I1;'),
    (N'demo_guest_a', N'每杯1.5个即使买两杯也拒绝', N'DECLARE @l teabar_api.OrderLines, @s teabar_api.OrderSpecs, @addon_selection teabar_api.OrderAddOns;
INSERT @l VALUES(@TX, @P, 2);
INSERT @s VALUES(@TX, @S1), (@TX, @S2), (@TX, @S3);
INSERT @addon_selection VALUES(@TX, @A);
EXEC teabar_api.usp_PlacePaidOrder @OX, @l, @s, @addon_selection, 1;', 52014, N'INSERT dbo.SpecificationIngredient(product_id,spec_id,ingredient_id,factor) VALUES(@P,@S3,@I3,1.5);', N'DELETE dbo.SpecificationIngredient WHERE product_id=@P AND spec_id=@S3 AND ingredient_id=@I3;'),
    (N'demo_manager', N'店长创建新原料、商品和配方', N'EXEC teabar_api.usp_SaveIngredient @I4,N''新原料'',N''ml'',N''可用'';
 EXEC teabar_api.usp_SaveProduct @P2,N''新商品'',1,N''下架'';
 EXEC teabar_api.usp_SaveRecipe @P2,@I4,0.5;', NULL, NULL, NULL),
    (N'demo_manager', N'店长创建规格、规则并启用配置', N'EXEC teabar_api.usp_SaveSpecification @S5,N''杯型'',@S5;
 EXEC teabar_api.usp_SaveProductSpecification @P2,@S5,-0.5,N''停用'';
 EXEC teabar_api.usp_SaveSpecificationIngredient @P2,@S5,@I4,2;
 EXEC teabar_api.usp_SaveProductSpecification @P2,@S5,-0.5,N''可用'';
 EXEC teabar_api.usp_SaveProduct @P2,N''新商品'',1,N''在售'';', NULL, NULL, NULL),
    (N'demo_manager', N'店长创建独立加料', N'EXEC teabar_api.usp_SaveAddOn @A2,@A2,1,@I4,2,N''可用'';', NULL, NULL, NULL),
    (N'demo_manager', N'店长登记员工及相邻班次', N'EXEC teabar_api.usp_SaveEmployee @E,N''测试员工'',N''在职'',0,N''店员'';
 EXEC teabar_api.usp_SaveDutyRoster @D1,@E,''2099-01-01T08:00:00'',''2099-01-01T16:00:00'';
 EXEC teabar_api.usp_SaveDutyRoster @D2,@E,''2099-01-01T16:00:00'',''2099-01-01T23:00:00'';', NULL, NULL, NULL),
    (N'demo_manager', N'同一员工不同开始时间仍不允许排班重叠', N'EXEC teabar_api.usp_SaveDutyRoster @D3,@E,''2099-01-01T12:00:00'',''2099-01-01T18:00:00'';', 52121, NULL, NULL),
    (N'demo_manager', N'员工岗位和离职资料不自动修改数据库角色', N'EXEC teabar_api.usp_SaveEmployee @E,N''测试员工'',N''离职'',0,N''店长'';', NULL, NULL, NULL),
    (N'demo_manager', N'不能为离职员工新排班', N'EXEC teabar_api.usp_SaveDutyRoster @D3,@E,''2099-01-02T08:00:00'',''2099-01-02T16:00:00'';', 52120, NULL, NULL),
    (N'demo_guest_a', N'零糖系数不取消独立加料且加料不乘杯型系数', N'DECLARE @zo VARCHAR(10)=LEFT(@P,8)+''OZ'',@zi VARCHAR(10)=LEFT(@P,8)+''TZ'';
DECLARE @zl teabar_api.OrderLines,@zs teabar_api.OrderSpecs,@za teabar_api.OrderAddOns;
INSERT @zl VALUES(@zi,@P,2); INSERT @zs VALUES(@zi,@S4),(@zi,@S2),(@zi,@S3); INSERT @za VALUES(@zi,@A);
EXEC teabar_api.usp_PlacePaidOrder @zo,@zl,@zs,@za,1;', NULL, NULL,
N'IF NOT EXISTS(SELECT 1 FROM dbo.OrderItemIngredient WHERE item_id=LEFT(@P,8)+''TZ'' AND ingredient_id=@I1 AND amount=6)
 OR NOT EXISTS(SELECT 1 FROM dbo.OrderItemIngredient WHERE item_id=LEFT(@P,8)+''TZ'' AND ingredient_id=@I2 AND amount=200)
 OR NOT EXISTS(SELECT 1 FROM dbo.OrderItemIngredient WHERE item_id=LEFT(@P,8)+''TZ'' AND ingredient_id=@I3 AND amount=2)
  THROW 52500,N''零系数或独立加料计算错误'',1;'),
    (N'demo_manager', N'准备两类型和三类型计件组合配置', N'DECLARE @pz VARCHAR(10)=LEFT(@P,8)+''PZ'',@py VARCHAR(10)=LEFT(@P,8)+''PY'',@iz VARCHAR(10)=LEFT(@P,8)+''IZ'';
 EXEC teabar_api.usp_SaveIngredient @iz,N''组合测试原料'',N''个'',N''可用'';
 EXEC teabar_api.usp_AdjustStock @iz,N''补库'',1000;
 EXEC teabar_api.usp_SaveProduct @pz,N''两类型组合测试'',1,N''下架'';
 EXEC teabar_api.usp_SaveProduct @py,N''三类型组合测试'',1,N''下架'';
 EXEC teabar_api.usp_SaveRecipe @pz,@iz,2;
 EXEC teabar_api.usp_SaveRecipe @py,@iz,4;
 EXEC teabar_api.usp_SaveProductSpecification @pz,@S1,0,N''停用'';
 EXEC teabar_api.usp_SaveProductSpecification @pz,@S4,0,N''停用'';
 EXEC teabar_api.usp_SaveProductSpecification @pz,@S3,0,N''停用'';
 EXEC teabar_api.usp_SaveSpecificationIngredient @pz,@S1,@iz,1.5;
 EXEC teabar_api.usp_SaveSpecificationIngredient @pz,@S4,@iz,1.5;
 EXEC teabar_api.usp_SaveSpecificationIngredient @pz,@S3,@iz,1.5;
 EXEC teabar_api.usp_SaveProductSpecification @py,@S1,0,N''停用'';
 EXEC teabar_api.usp_SaveProductSpecification @py,@S2,0,N''停用'';
 EXEC teabar_api.usp_SaveProductSpecification @py,@S3,0,N''停用'';
 EXEC teabar_api.usp_SaveSpecificationIngredient @py,@S1,@iz,1.5;
 EXEC teabar_api.usp_SaveSpecificationIngredient @py,@S2,@iz,1.5;
 EXEC teabar_api.usp_SaveSpecificationIngredient @py,@S3,@iz,1.5;', NULL, NULL, NULL),
    (N'demo_manager', N'同类型备选不相乘且停用类型不参与组合', N'DECLARE @pz VARCHAR(10)=LEFT(@P,8)+''PZ'';
 EXEC teabar_api.usp_SaveProductSpecification @pz,@S1,0,N''可用'';
 EXEC teabar_api.usp_SaveProductSpecification @pz,@S4,0,N''可用'';', NULL, NULL, NULL),
    (N'demo_manager', N'两个单项整数但组合4.5个时拒绝启用', N'DECLARE @pz VARCHAR(10)=LEFT(@P,8)+''PZ'';
 EXEC teabar_api.usp_SaveProductSpecification @pz,@S3,9,N''可用'';', 52116, NULL, NULL),
    (N'demo_manager', N'修正规则后合法两类型组合可以启用', N'DECLARE @pz VARCHAR(10)=LEFT(@P,8)+''PZ'',@iz VARCHAR(10)=LEFT(@P,8)+''IZ'';
 EXEC teabar_api.usp_SaveSpecificationIngredient @pz,@S3,@iz,2;
 EXEC teabar_api.usp_SaveProductSpecification @pz,@S3,0,N''可用'';', NULL, NULL, NULL),
    (N'demo_manager', N'三类型配置先启用合法的两类型组合', N'DECLARE @py VARCHAR(10)=LEFT(@P,8)+''PY'';
 EXEC teabar_api.usp_SaveProductSpecification @py,@S1,0,N''可用'';
 EXEC teabar_api.usp_SaveProductSpecification @py,@S2,0,N''可用'';', NULL, NULL, NULL),
    (N'demo_manager', N'任意两项整数但三类型组合13.5个时拒绝启用', N'DECLARE @py VARCHAR(10)=LEFT(@P,8)+''PY'';
 EXEC teabar_api.usp_SaveProductSpecification @py,@S3,9,N''可用'';', 52116, NULL, NULL),
    (N'demo_manager', N'修正规则后合法三类型组合可以启用上架', N'DECLARE @py VARCHAR(10)=LEFT(@P,8)+''PY'',@iz VARCHAR(10)=LEFT(@P,8)+''IZ'';
 EXEC teabar_api.usp_SaveSpecificationIngredient @py,@S3,@iz,2;
 EXEC teabar_api.usp_SaveProductSpecification @py,@S3,0,N''可用'';
 EXEC teabar_api.usp_SaveProduct @py,N''三类型组合测试'',1,N''在售'';', NULL, NULL, NULL),
    (N'demo_manager', N'计件组合允许同类型的零系数备选', N'DECLARE @pz VARCHAR(10)=LEFT(@P,8)+''PZ'',@iz VARCHAR(10)=LEFT(@P,8)+''IZ'';
 EXEC teabar_api.usp_SaveProductSpecification @pz,@S4,0,N''停用'';
 EXEC teabar_api.usp_SaveSpecificationIngredient @pz,@S4,@iz,0;
 EXEC teabar_api.usp_SaveProductSpecification @pz,@S4,0,N''可用'';
 EXEC teabar_api.usp_SaveProduct @pz,N''两类型组合测试'',1,N''在售'';', NULL, NULL, NULL),
    (N'demo_manager', N'零系数备选不能掩盖另一个备选的非法组合', N'DECLARE @pz VARCHAR(10)=LEFT(@P,8)+''PZ'';
 EXEC teabar_api.usp_SaveProductSpecification @pz,@S3,9,N''可用'';', 52116,
 N'UPDATE dbo.ProductSpecification SET status=N''停用'' WHERE product_id=LEFT(@P,8)+''PZ'' AND spec_id=@S3;
 UPDATE dbo.SpecificationIngredient SET factor=1.5 WHERE product_id=LEFT(@P,8)+''PZ'' AND spec_id=@S3 AND ingredient_id=LEFT(@P,8)+''IZ'';',
 N'UPDATE dbo.SpecificationIngredient SET factor=2 WHERE product_id=LEFT(@P,8)+''PZ'' AND spec_id=@S3 AND ingredient_id=LEFT(@P,8)+''IZ'';
 UPDATE dbo.ProductSpecification SET status=N''可用'' WHERE product_id=LEFT(@P,8)+''PZ'' AND spec_id=@S3;'),
    (N'demo_guest_a', N'合法两类型及三类型组合下单正确扣减计件库存', N'DECLARE @pz VARCHAR(10)=LEFT(@P,8)+''PZ'',@py VARCHAR(10)=LEFT(@P,8)+''PY'',
 @oz VARCHAR(10)=LEFT(@P,8)+''OY'',@combo_item_a VARCHAR(10)=LEFT(@P,8)+''TT'',@combo_item_b VARCHAR(10)=LEFT(@P,8)+''TU'';
 DECLARE @l teabar_api.OrderLines,@s teabar_api.OrderSpecs,@combo_addons teabar_api.OrderAddOns;
 INSERT @l VALUES(@combo_item_a,@pz,1),(@combo_item_b,@py,1);
 INSERT @s VALUES(@combo_item_a,@S1),(@combo_item_a,@S3),(@combo_item_b,@S1),(@combo_item_b,@S2),(@combo_item_b,@S3);
 EXEC teabar_api.usp_PlacePaidOrder @oz,@l,@s,@combo_addons,1;', NULL, NULL,
 N'IF NOT EXISTS(SELECT 1 FROM dbo.OrderItemIngredient WHERE item_id=LEFT(@P,8)+''TT'' AND ingredient_id=LEFT(@P,8)+''IZ'' AND amount=6)
 OR NOT EXISTS(SELECT 1 FROM dbo.OrderItemIngredient WHERE item_id=LEFT(@P,8)+''TU'' AND ingredient_id=LEFT(@P,8)+''IZ'' AND amount=18)
 OR NOT EXISTS(SELECT 1 FROM dbo.Ingredient WHERE ingredient_id=LEFT(@P,8)+''IZ'' AND stock=976)
 THROW 52500,N''合法组合的计件扣库或快照错误'',1;');

DECLARE @results TABLE(
 seq INT PRIMARY KEY, user_name SYSNAME, case_name NVARCHAR(100),
 expected_error INT NULL, actual_error INT NULL, passed BIT, detail NVARCHAR(1000));
DECLARE @params NVARCHAR(MAX)=N'
 @P VARCHAR(10),@P2 VARCHAR(10),@S1 VARCHAR(10),@S2 VARCHAR(10),@S3 VARCHAR(10),@S4 VARCHAR(10),@S5 VARCHAR(10),
 @I1 VARCHAR(10),@I2 VARCHAR(10),@I3 VARCHAR(10),@I4 VARCHAR(10),@A VARCHAR(10),@A2 VARCHAR(10),
 @MA VARCHAR(10),@MB VARCHAR(10),@MC VARCHAR(10),@PA VARCHAR(20),@PB VARCHAR(20),@PC VARCHAR(20),
 @E VARCHAR(10),@D1 VARCHAR(10),@D2 VARCHAR(10),@D3 VARCHAR(10),
 @OG VARCHAR(10),@OG2 VARCHAR(10),@OGB VARCHAR(10),@OM VARCHAR(10),@OMB VARCHAR(10),
 @OD VARCHAR(10),@OP VARCHAR(10),@OX VARCHAR(10),
 @TG VARCHAR(10),@TG2 VARCHAR(10),@TGB VARCHAR(10),@TM VARCHAR(10),@TMB VARCHAR(10),@TX VARCHAR(10),@TY VARCHAR(10),
 @GB UNIQUEIDENTIFIER';

BEGIN TRY
 BEGIN TRANSACTION;
 -- 管理员建立独立随机测试数据，临时把两个示例会员映射至测试会员；最后一并回滚。
 INSERT dbo.Member(member_id,name,phone,points) VALUES(@MA,N'测试会员甲',@PA,0),(@MB,N'测试会员乙',@PB,0);
 UPDATE teabar_auth.PrincipalBinding SET member_id=@MA WHERE principal_name=N'demo_member_a';
 UPDATE teabar_auth.PrincipalBinding SET member_id=@MB WHERE principal_name=N'demo_member_b';
 INSERT dbo.Product(product_id,product_name,base_price,status) VALUES(@P,N'角色测试商品',6.8,N'在售');
 INSERT dbo.Ingredient(ingredient_id,ingredient_name,unit,stock,status)
 VALUES(@I1,N'角色测试糖浆',N'ml',1000,N'可用'),(@I2,N'角色测试茶汤',N'ml',1000,N'可用'),
       (@I3,N'角色测试杯子',N'个',100,N'可用');
 INSERT dbo.Specification(spec_id,spec_type,spec_name)
 VALUES(@S1,N'糖度',@S1),(@S2,N'温度',@S2),(@S3,N'杯型',@S3),(@S4,N'糖度',@S4);
 INSERT dbo.ProductSpecification(product_id,spec_id,price_delta,status)
 VALUES(@P,@S1,0,N'可用'),(@P,@S2,0,N'可用'),(@P,@S3,2,N'可用'),(@P,@S4,0,N'可用');
 INSERT dbo.Recipe(product_id,ingredient_id,base_amount) VALUES(@P,@I1,10),(@P,@I2,100),(@P,@I3,1);
 INSERT dbo.SpecificationIngredient(product_id,spec_id,ingredient_id,factor)
 VALUES(@P,@S1,@I1,0.5),(@P,@S2,@I2,0.5),(@P,@S3,@I1,2),(@P,@S3,@I2,2),(@P,@S4,@I1,0);
 INSERT dbo.AddOn(addon_id,addon_name,price,ingredient_id,extra_amount,status)
 VALUES(@A,@A,1,@I1,3,N'可用');
 -- 两条历史测试记录仅服务于查询范围验证，不演示完整下单流程。
 INSERT dbo.SalesOrder(order_id,member_id,order_time,total_amount,status)
 VALUES(@OD,@MB,DATEADD(DAY,-2,SYSDATETIME()),0,N'已完成'),
       (@OP,@MB,DATEADD(DAY,-2,SYSDATETIME()),0,N'排队中');

 DECLARE @seq INT=1,@count INT=(SELECT COUNT(*) FROM @cases),@user SYSNAME,@label NVARCHAR(100);
 DECLARE @sql NVARCHAR(MAX),@setup NVARCHAR(MAX),@teardown NVARCHAR(MAX),@expected INT,@actual INT,@message NVARCHAR(4000);
 DECLARE @before VARBINARY(32),@after VARBINARY(32),@passed BIT;
 WHILE @seq<=@count
 BEGIN
  SELECT @user=user_name,@label=case_name,@sql=statement,@expected=expected_error,@setup=setup,@teardown=teardown
  FROM @cases WHERE seq=@seq;
  IF @setup IS NOT NULL
   EXEC sys.sp_executesql @setup,@params,
    @P=@P,@P2=@P2,@S1=@S1,@S2=@S2,@S3=@S3,@S4=@S4,@S5=@S5,
    @I1=@I1,@I2=@I2,@I3=@I3,@I4=@I4,@A=@A,@A2=@A2,
    @MA=@MA,@MB=@MB,@MC=@MC,@PA=@PA,@PB=@PB,@PC=@PC,
    @E=@E,@D1=@D1,@D2=@D2,@D3=@D3,
    @OG=@OG,@OG2=@OG2,@OGB=@OGB,@OM=@OM,@OMB=@OMB,@OD=@OD,@OP=@OP,@OX=@OX,
    @TG=@TG,@TG2=@TG2,@TGB=@TGB,@TM=@TM,@TMB=@TMB,@TX=@TX,@TY=@TY,@GB=@GB;
  SET @actual=NULL; SET @message=NULL;
  SAVE TRANSACTION role_test_case;
  SELECT @before=HASHBYTES('SHA2_256',
        (SELECT * FROM dbo.Employee ORDER BY employee_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.DutyRoster ORDER BY duty_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.Member ORDER BY member_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.SalesOrder ORDER BY order_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.Product ORDER BY product_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.Specification ORDER BY spec_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.Ingredient ORDER BY ingredient_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.OrderItem ORDER BY item_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.ProductSpecification ORDER BY product_id,spec_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.Recipe ORDER BY product_id,ingredient_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.AddOn ORDER BY addon_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.ItemSpec ORDER BY item_id,spec_type FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.ItemAddOn ORDER BY item_id,addon_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.OrderItemIngredient ORDER BY item_id,ingredient_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.SpecificationIngredient ORDER BY product_id,spec_id,ingredient_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM teabar_auth.PrincipalBinding ORDER BY principal_sid FOR XML RAW, BINARY BASE64));
  BEGIN TRY
   EXECUTE AS USER=@user;
   SET @impersonating=1;
   EXEC sys.sp_executesql @sql,@params,
    @P=@P,@P2=@P2,@S1=@S1,@S2=@S2,@S3=@S3,@S4=@S4,@S5=@S5,
    @I1=@I1,@I2=@I2,@I3=@I3,@I4=@I4,@A=@A,@A2=@A2,
    @MA=@MA,@MB=@MB,@MC=@MC,@PA=@PA,@PB=@PB,@PC=@PC,
    @E=@E,@D1=@D1,@D2=@D2,@D3=@D3,
    @OG=@OG,@OG2=@OG2,@OGB=@OGB,@OM=@OM,@OMB=@OMB,@OD=@OD,@OP=@OP,@OX=@OX,
    @TG=@TG,@TG2=@TG2,@TGB=@TGB,@TM=@TM,@TMB=@TMB,@TX=@TX,@TY=@TY,@GB=@GB;
   REVERT; SET @impersonating=0;
  END TRY
  BEGIN CATCH
   SET @actual=ERROR_NUMBER(); SET @message=ERROR_MESSAGE();
   IF XACT_STATE()<>1
   BEGIN
    SELECT @seq AS case_number,@label AS case_name,@actual AS actual_error,@message AS detail,
           XACT_STATE() AS transaction_state;
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    IF @impersonating=1 BEGIN REVERT; SET @impersonating=0; END;
    THROW;
   END;
   IF @impersonating=1 BEGIN REVERT; SET @impersonating=0; END;
  END CATCH;
  SELECT @after=HASHBYTES('SHA2_256',
        (SELECT * FROM dbo.Employee ORDER BY employee_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.DutyRoster ORDER BY duty_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.Member ORDER BY member_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.SalesOrder ORDER BY order_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.Product ORDER BY product_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.Specification ORDER BY spec_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.Ingredient ORDER BY ingredient_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.OrderItem ORDER BY item_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.ProductSpecification ORDER BY product_id,spec_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.Recipe ORDER BY product_id,ingredient_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.AddOn ORDER BY addon_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.ItemSpec ORDER BY item_id,spec_type FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.ItemAddOn ORDER BY item_id,addon_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.OrderItemIngredient ORDER BY item_id,ingredient_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM dbo.SpecificationIngredient ORDER BY product_id,spec_id,ingredient_id FOR XML RAW, BINARY BASE64)
        + (SELECT * FROM teabar_auth.PrincipalBinding ORDER BY principal_sid FOR XML RAW, BINARY BASE64));
  SET @passed=CASE WHEN @expected IS NULL AND @actual IS NULL THEN 1
    WHEN @expected IS NOT NULL AND @actual=@expected AND @before=@after THEN 1 ELSE 0 END;
  IF @expected IS NOT NULL OR @actual IS NOT NULL ROLLBACK TRANSACTION role_test_case;
  IF @passed=0
  BEGIN
   SELECT @seq AS case_number,@user AS user_name,@label AS case_name,
          @expected AS expected_error,@actual AS actual_error,@message AS detail;
   THROW 52503,N'当前权限或业务验证未通过，已回滚测试事务。',1;
  END;
  IF @teardown IS NOT NULL
   EXEC sys.sp_executesql @teardown,@params,
    @P=@P,@P2=@P2,@S1=@S1,@S2=@S2,@S3=@S3,@S4=@S4,@S5=@S5,
    @I1=@I1,@I2=@I2,@I3=@I3,@I4=@I4,@A=@A,@A2=@A2,
    @MA=@MA,@MB=@MB,@MC=@MC,@PA=@PA,@PB=@PB,@PC=@PC,
    @E=@E,@D1=@D1,@D2=@D2,@D3=@D3,
    @OG=@OG,@OG2=@OG2,@OGB=@OGB,@OM=@OM,@OMB=@OMB,@OD=@OD,@OP=@OP,@OX=@OX,
    @TG=@TG,@TG2=@TG2,@TGB=@TGB,@TM=@TM,@TMB=@TMB,@TX=@TX,@TY=@TY,@GB=@GB;
  INSERT @results VALUES(@seq,@user,@label,@expected,@actual,@passed,
    LEFT(CASE WHEN @expected IS NOT NULL AND @before<>@after
        THEN N'失败操作留下数据变化，原子性验证失败。'+COALESCE(@message,N'')
        ELSE COALESCE(@message,N'正常操作成功。') END,1000));
  SET @seq+=1;
 END;

 -- 最终正例核对：历史快照不受改价影响，退款不加分，会员资料更正不改积分。
 IF NOT EXISTS(SELECT 1 FROM dbo.SalesOrder WHERE order_id=@OM AND member_id=@MA AND guest_id IS NULL
              AND total_amount=19.6 AND status=N'已完成')
  OR NOT EXISTS(SELECT 1 FROM dbo.OrderItem WHERE item_id=@TM AND base_price_snapshot=6.8 AND unit_price=9.8)
  OR NOT EXISTS(SELECT 1 FROM dbo.Member WHERE member_id=@MA AND points=19)
  OR NOT EXISTS(SELECT 1 FROM dbo.Member WHERE member_id=@MC AND points=0)
  OR NOT EXISTS(SELECT 1 FROM dbo.Member WHERE member_id=@MB AND points=0)
  OR (SELECT COUNT(*) FROM dbo.SalesOrder WHERE order_id IN(@OG,@OG2) AND guest_id=@GA AND member_id IS NULL)<>2
  OR NOT EXISTS(SELECT 1 FROM sys.database_role_members WHERE member_principal_id=DATABASE_PRINCIPAL_ID(N'demo_clerk')
                AND role_principal_id=DATABASE_PRINCIPAL_ID(N'teabar_clerk'))
 BEGIN
  SELECT * FROM @results WHERE passed=0;
  THROW 52501,N'价格快照、积分、会话ID复用或角色分开维护的最终核对失败。',1;
 END;
 ROLLBACK TRANSACTION;
 IF USER_NAME()<>@administrator THROW 52502,N'未恢复管理员上下文。',1;
 IF (SELECT COUNT(*) FROM @results)<>84 THROW 52901,N'提取的角色用例数量不是84。',1;
 INSERT #RegressionResults(suite,case_name,expected_error,actual_error,passed,detail)
  SELECT N'legacy-role',case_name,expected_error,actual_error,passed,detail FROM @results;
 SELECT seq,user_name,case_name,expected_error,actual_error,
        CASE passed WHEN 1 THEN N'通过' ELSE N'失败' END AS result,detail FROM @results ORDER BY seq;
 IF EXISTS(SELECT 1 FROM @results WHERE passed=0)
  THROW 52503,N'存在未通过的权限或业务操作验证，请检查实际错误。',1;
 SELECT N'角色及业务验证全部通过，测试数据与临时绑定已回滚' AS stage,COUNT(*) AS passed_cases FROM @results;
END TRY
BEGIN CATCH
 IF @impersonating=1 REVERT;
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
