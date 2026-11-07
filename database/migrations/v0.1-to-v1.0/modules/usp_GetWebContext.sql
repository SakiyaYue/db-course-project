CREATE PROCEDURE teabar_auth.usp_GetWebContext @account_id INT, @session_version INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sid VARBINARY(85),@role VARCHAR(10),@actual_version INT,@name SYSNAME,@pid INT,@expected_role SYSNAME;
    SELECT @sid=principal_sid,@role=app_role,@actual_version=session_version
    FROM teabar_auth.WebAccount WHERE account_id=@account_id AND is_active=1;
    IF @sid IS NULL OR @session_version IS NULL OR @actual_version<>@session_version
        THROW 52700, N'账号或会话已失效。', 1;
    IF (SELECT COUNT(*) FROM sys.database_principals WHERE sid=@sid AND type='S' AND authentication_type=0)<>1
        THROW 52700, N'数据库用户映射无效。', 1;
    SELECT @pid=principal_id,@name=name FROM sys.database_principals
    WHERE sid=@sid AND type='S' AND authentication_type=0;
    SET @expected_role=CASE @role WHEN 'customer' THEN N'teabar_customer' WHEN 'member' THEN N'teabar_member'
        WHEN 'clerk' THEN N'teabar_clerk' WHEN 'manager' THEN N'teabar_manager' END;
    IF @expected_role IS NULL OR NOT (
        (@role='customer' AND @name COLLATE DATABASE_DEFAULT IN (N'web_guest_a',N'web_guest_b'))
        OR (@role='member' AND @name COLLATE DATABASE_DEFAULT IN (N'web_member_a',N'web_member_b'))
        OR (@role='clerk' AND @name COLLATE DATABASE_DEFAULT=N'web_clerk')
        OR (@role='manager' AND @name COLLATE DATABASE_DEFAULT=N'web_manager'))
        THROW 52700, N'账号角色与允许的数据库用户不匹配。', 1;
    IF (SELECT COUNT(*) FROM sys.database_role_members WHERE member_principal_id=@pid)<>1
       OR NOT EXISTS (SELECT 1 FROM sys.database_role_members
            WHERE member_principal_id=@pid AND role_principal_id=DATABASE_PRINCIPAL_ID(@expected_role))
       OR EXISTS (SELECT 1 FROM sys.schemas WHERE principal_id=@pid)
       OR EXISTS (SELECT 1 FROM sys.database_principals WHERE owning_principal_id=@pid)
       OR EXISTS (SELECT 1 FROM sys.database_permissions WHERE grantee_principal_id=@pid AND state IN ('G','W')
                  AND NOT (class=0 AND permission_name=N'CONNECT'))
        THROW 52700, N'数据库用户的角色、所有权或直接授权不符合应用边界。', 1;
    IF @role IN ('customer','member') AND NOT EXISTS (
        SELECT 1 FROM teabar_auth.PrincipalBinding AS b WHERE b.principal_sid=@sid AND b.is_active=1
          AND b.principal_name COLLATE DATABASE_DEFAULT=@name COLLATE DATABASE_DEFAULT
          AND ((@role='customer' AND b.guest_id IS NOT NULL AND b.member_id IS NULL)
            OR (@role='member' AND b.member_id IS NOT NULL AND b.guest_id IS NULL)))
        THROW 52700, N'购买身份绑定不存在、停用或与账号角色不匹配。', 1;
    SELECT @account_id AS account_id,@role AS app_role,@sid AS principal_sid,
        @name AS principal_name,@actual_version AS session_version;
END;
