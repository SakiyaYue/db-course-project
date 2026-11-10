-- Additive read interface; install through init_web_accounts.py in Work/Test only.
IF DB_NAME() NOT IN (N'TeabarDB_Phase2_Test', N'TeabarDB_Phase2_Work')
    THROW 52822, N'Refusing order extensions outside Work/Test.', 1;
IF OBJECT_ID(N'teabar_api.vw_MyOrderItems', N'V') IS NULL
    THROW 52822, N'Install the v1.0 interfaces first.', 1;
-- Dynamic DDL keeps guards and all changes in the same batch/transaction.
EXEC(N'CREATE OR ALTER VIEW teabar_api.vw_MyConsumption AS
SELECT i.order_id, c.item_id, c.ingredient_id, g.ingredient_name, g.unit, c.amount
FROM dbo.OrderItemIngredient AS c
JOIN teabar_api.vw_MyOrderItems AS i ON i.item_id = c.item_id
JOIN dbo.Ingredient AS g ON g.ingredient_id = c.ingredient_id;');
GRANT SELECT ON OBJECT::teabar_api.vw_MyConsumption TO teabar_customer, teabar_member;
-- No raw table grants; ownership chaining preserves the caller's buyer identity.
