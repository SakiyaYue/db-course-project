-- ADMIN PREPARATION TEMPLATE. Default only prints the plan; no database or filesystem change.
-- Use a fresh work DB name to reset. This script never drops a DB and never uses RESTORE WITH REPLACE.
USE master;
SET NOCOUNT ON;
DECLARE @Execute BIT=0;
DECLARE @Source SYSNAME=N'TeabarDB',@Work SYSNAME=N'TeabarDB_Phase2_Work';
DECLARE @BackupDirectory NVARCHAR(2048)=CONVERT(NVARCHAR(2048),SERVERPROPERTY('InstanceDefaultBackupPath'));
DECLARE @DataDirectory NVARCHAR(2048)=CONVERT(NVARCHAR(2048),SERVERPROPERTY('InstanceDefaultDataPath'));
IF @Source<>N'TeabarDB' OR @Work IN(N'TeabarDB',N'master',N'model',N'msdb',N'tempdb')
   OR @Work NOT LIKE N'TeabarDB[_]Phase2[_]Work%' OR DB_ID(@Work) IS NOT NULL
    THROW 52800,N'工作库必须使用独立、尚不存在的明确名称，禁止覆盖或重建冻结基线。',1;
IF DB_ID(@Source) IS NULL OR (SELECT state FROM sys.databases WHERE name=@Source)<>0
    THROW 52800,N'冻结源库不存在或不在线。',1;
IF @BackupDirectory IS NULL OR @DataDirectory IS NULL
   OR LEFT(@BackupDirectory,3) NOT LIKE N'[A-Za-z]:\' OR LEFT(@DataDirectory,3) NOT LIKE N'[A-Za-z]:\'
   OR CHARINDEX(N'..',@BackupDirectory)>0 OR CHARINDEX(N'..',@DataDirectory)>0
    THROW 52800,N'请配置服务端明确的绝对备份和数据目录。',1;
IF (SELECT COUNT(*) FROM sys.master_files WHERE database_id=DB_ID(@Source) AND type=0)<>1
   OR (SELECT COUNT(*) FROM sys.master_files WHERE database_id=DB_ID(@Source) AND type=1)<>1
    THROW 52800,N'本模板只支持当前一数据文件一日志文件结构；多文件库需另行逐文件规划。',1;
DECLARE @DataLogical SYSNAME,@LogLogical SYSNAME,@backup NVARCHAR(4000),@mdf NVARCHAR(4000),@ldf NVARCHAR(4000);
SELECT @DataLogical=name FROM sys.master_files WHERE database_id=DB_ID(@Source) AND type=0;
SELECT @LogLogical=name FROM sys.master_files WHERE database_id=DB_ID(@Source) AND type=1;
DECLARE @suffix NVARCHAR(32)=REPLACE(CONVERT(NVARCHAR(36),NEWID()),N'-',N'');
SET @backup=@BackupDirectory+N'\TeabarDB_v01_'+@suffix+N'.bak';
SET @mdf=@DataDirectory+N'\'+@Work+N'_'+@suffix+N'.mdf';
SET @ldf=@DataDirectory+N'\'+@Work+N'_'+@suffix+N'.ldf';
IF EXISTS(SELECT 1 FROM sys.master_files WHERE physical_name COLLATE DATABASE_DEFAULT IN(@mdf,@ldf))
    THROW 52800,N'计划文件路径已被数据库使用。',1;
SELECT CASE WHEN @Execute=0 THEN N'PLAN_ONLY' ELSE N'EXECUTION_REQUESTED' END AS mode,
    @Source AS source_database,@Work AS work_database,@backup AS backup_file,
    @DataLogical AS data_logical_name,@LogLogical AS log_logical_name,@mdf AS work_data_file,@ldf AS work_log_file;
IF @Execute=0 RETURN;
-- Directories must already exist and permit the SQL Server service identity to write.
-- COPY_ONLY does not change the normal differential backup base. Source business data is not rewritten.
BACKUP DATABASE @Source TO DISK=@backup WITH COPY_ONLY,CHECKSUM;
RESTORE VERIFYONLY FROM DISK=@backup WITH CHECKSUM;
RESTORE DATABASE @Work FROM DISK=@backup WITH MOVE @DataLogical TO @mdf,MOVE @LogLogical TO @ldf,CHECKSUM,RECOVERY;
SELECT N'WORK_COPY_RESTORED_KEEP_BACKUP' AS result,@Work AS work_database,@backup AS recovery_backup;
