CREATE PROCEDURE teabar_auth.usp_GetWebCredential @login_name NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    -- Return the same empty result shape for invalid, missing and disabled accounts.
    SELECT account_id,password_hash,session_version
    FROM teabar_auth.WebAccount
    WHERE @login_name IS NOT NULL
      AND DATALENGTH(@login_name) BETWEEN 6 AND 100
      AND @login_name COLLATE Latin1_General_100_BIN2 NOT LIKE N'%[^a-z0-9._-]%'
      AND login_name=@login_name AND is_active=1;
END;
