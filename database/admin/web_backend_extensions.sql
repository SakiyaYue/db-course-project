-- B additive integration objects. Run ONLY on an independent v1.0 Work/Test database.
IF DB_NAME() NOT IN (N'TeabarDB_Phase2_Test',N'TeabarDB_Phase2_Work')
    THROW 52822,N'Refusing to install Web extensions outside Work/Test.',1;
IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'TeabarDB.SchemaVersion' AND CONVERT(NVARCHAR(20),value)=N'1.0')
    THROW 52822,N'Install v1.0 migration first.',1;
-- Compatibility correction for the frozen v1.0 BIN2 character class.
-- NVARCHAR DATALENGTH 6..100 already means 3..50 ASCII characters.
IF OBJECT_ID(N'teabar_auth.CK_WebAccount_LoginName',N'C') IS NOT NULL
    ALTER TABLE teabar_auth.WebAccount DROP CONSTRAINT CK_WebAccount_LoginName;
ALTER TABLE teabar_auth.WebAccount WITH CHECK ADD CONSTRAINT CK_WebAccount_LoginName
    CHECK(DATALENGTH(login_name) BETWEEN 6 AND 100
          AND login_name COLLATE Latin1_General_100_BIN2 NOT LIKE N'%[^-a-z0-9._]%');
GO
CREATE OR ALTER PROCEDURE teabar_auth.usp_GetWebCredential @login_name NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT account_id,password_hash,session_version
    FROM teabar_auth.WebAccount
    WHERE @login_name IS NOT NULL AND DATALENGTH(@login_name) BETWEEN 6 AND 100
      AND @login_name COLLATE Latin1_General_100_BIN2 NOT LIKE N'%[^-a-z0-9._]%'
      AND login_name=@login_name AND is_active=1;
END;
GO
-- Apply the same correction to the JSON ID validator, leaving its entire core unchanged.
DECLARE @definition NVARCHAR(MAX)=OBJECT_DEFINITION(OBJECT_ID(N'teabar_api.usp_PlacePaidOrderJson'));
IF CHARINDEX(N'%[^A-Za-z0-9_-]%',@definition)>0
BEGIN
    -- Only replace the exact legacy pattern, not any business or identity logic.
    SET @definition=REPLACE(@definition,N'%[^A-Za-z0-9_-]%',N'%[^-A-Za-z0-9_]%');
END;
IF CHARINDEX(N'CREATE PROCEDURE',@definition)>0
    SET @definition=STUFF(@definition,CHARINDEX(N'CREATE PROCEDURE',@definition),16,N'ALTER PROCEDURE');
IF @definition IS NULL THROW 52822,N'Missing JSON order interface.',1;
EXEC sys.sp_executesql @definition;
GO
IF USER_ID(N'web_public') IS NULL CREATE USER web_public WITHOUT LOGIN;
GRANT SELECT ON teabar_api.vw_Menu TO web_public;
GRANT SELECT ON teabar_api.vw_AvailableSpecifications TO web_public;
GRANT SELECT ON teabar_api.vw_AvailableAddOns TO web_public;
GRANT IMPERSONATE ON USER::web_public TO teabar_web_app;
IF OBJECT_ID(N'teabar_auth.WebOrderRequest',N'U') IS NULL
CREATE TABLE teabar_auth.WebOrderRequest(
    principal_sid VARBINARY(85) NOT NULL,
    request_token VARCHAR(100) COLLATE Latin1_General_100_BIN2 NOT NULL,
    payload_hash CHAR(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
    order_id VARCHAR(10) NOT NULL,
    total_amount DECIMAL(10,2) NOT NULL,
    status NVARCHAR(20) NOT NULL,
    created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_WebOrderRequest PRIMARY KEY(principal_sid, request_token),
    CONSTRAINT FK_WebOrderRequest_Order FOREIGN KEY(order_id) REFERENCES dbo.SalesOrder(order_id)
);
-- Upgrade an earlier B draft without deleting receipt rows.
IF EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N'teabar_auth.WebOrderRequest')
          AND name=N'request_token' AND collation_name<>N'Latin1_General_100_BIN2')
BEGIN
    ALTER TABLE teabar_auth.WebOrderRequest DROP CONSTRAINT PK_WebOrderRequest;
    ALTER TABLE teabar_auth.WebOrderRequest ALTER COLUMN request_token VARCHAR(100) COLLATE Latin1_General_100_BIN2 NOT NULL;
    ALTER TABLE teabar_auth.WebOrderRequest ADD CONSTRAINT PK_WebOrderRequest PRIMARY KEY(principal_sid,request_token);
END;
GO
CREATE OR ALTER PROCEDURE teabar_api.usp_PlaceWebOrder
    @request_token VARCHAR(100), @payload_hash CHAR(64), @order_id NVARCHAR(MAX),
    @items_json NVARCHAR(MAX), @specs_json NVARCHAR(MAX), @addons_json NVARCHAR(MAX),
    @payment_succeeded BIT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    -- No EXECUTE AS OWNER: core procedure must see the authenticated buyer SID.
    IF COALESCE(IS_ROLEMEMBER(N'teabar_customer'),0)=0 AND COALESCE(IS_ROLEMEMBER(N'teabar_member'),0)=0
        THROW 52000,N'Buyer role required.',1;
    IF @request_token IS NULL OR LEN(@request_token) NOT BETWEEN 20 AND 100
        THROW 52602,N'Invalid request token.',1;
    IF @@TRANCOUNT<>0 THROW 52821,N'A fresh transaction is required.',1;
    DECLARE @sid VARBINARY(85)=(SELECT sid FROM sys.database_principals WHERE principal_id=DATABASE_PRINCIPAL_ID());
    DECLARE @resource NVARCHAR(255)=N'web-order:'+CONVERT(VARCHAR(64),HASHBYTES('SHA2_256',CONVERT(VARBINARY(MAX),@sid)+CONVERT(VARBINARY(MAX),@request_token)),2);
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @lock INT;
        EXEC @lock=sys.sp_getapplock @Resource=@resource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=5000;
        IF @lock<0 THROW 52821,N'Order request is busy.',1;
        IF EXISTS(SELECT 1 FROM teabar_auth.WebOrderRequest WHERE principal_sid=@sid AND request_token=@request_token)
        BEGIN
            IF EXISTS(SELECT 1 FROM teabar_auth.WebOrderRequest WHERE principal_sid=@sid AND request_token=@request_token AND payload_hash<>@payload_hash)
                THROW 52820,N'Request token payload mismatch.',1;
            SELECT order_id,total_amount,status FROM teabar_auth.WebOrderRequest
                WHERE principal_sid=@sid AND request_token=@request_token;
            COMMIT TRANSACTION;
            RETURN;
        END;
        EXEC teabar_api.usp_PlacePaidOrderJson @order_id,@items_json,@specs_json,@addons_json,@payment_succeeded;
        INSERT teabar_auth.WebOrderRequest(principal_sid,request_token,payload_hash,order_id,total_amount,status)
        SELECT @sid,@request_token,@payload_hash,order_id,total_amount,status
            FROM dbo.SalesOrder WHERE order_id=CONVERT(VARCHAR(10),@order_id);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
GRANT EXECUTE ON teabar_api.usp_PlaceWebOrder TO teabar_customer;
GRANT EXECUTE ON teabar_api.usp_PlaceWebOrder TO teabar_member;
