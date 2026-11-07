"""从零创建独立 Work/Test 库，拒绝覆盖已有库；永不重建冻结源 TeabarDB。

管理员运行：python database/admin/prepare_test_database.py --database TeabarDB_Phase2_Test
干净演示库：python database/admin/prepare_test_database.py --database TeabarDB_Phase2_Work
包含演示账号初始化及 B Web 扩展；已有测试库应直接运行 pytest，不重复建库。
"""
from __future__ import annotations
import argparse
import contextlib
import io
import hashlib
import json
import re
from pathlib import Path
import pyodbc

ROOT = Path(__file__).resolve().parents[2]
TARGET = "TeabarDB_Phase2_Test"
ALLOWED_TARGETS = ("TeabarDB_Phase2_Test", "TeabarDB_Phase2_Work")
GO = re.compile(r"^\s*GO\s*(?:--.*)?$", re.MULTILINE | re.IGNORECASE)

def connection_string(server, database, driver):
    # Server/driver are administrator configuration, never HTTP inputs.
    return f"DRIVER={{{driver}}};SERVER={server};DATABASE={database};Trusted_Connection=yes;TrustServerCertificate=yes;APP=teabar-prepare-test"

def source_fingerprint(conn):
    cursor = conn.cursor()
    try:
        tables = cursor.execute("SELECT s.name,t.name FROM TeabarDB.sys.tables t JOIN TeabarDB.sys.schemas s ON s.schema_id=t.schema_id ORDER BY s.name,t.name").fetchall()
        rows=[]
        for schema, table in tables:
            quoted=lambda v: '['+v.replace(']',']]')+']'
            item=cursor.execute(f"SELECT COUNT_BIG(*),CHECKSUM_AGG(BINARY_CHECKSUM(*)) FROM [TeabarDB].{quoted(schema)}.{quoted(table)}").fetchone()
            rows.append([schema,table,*item])
        metadata=cursor.execute("SELECT s.name,o.name,o.type,CONVERT(varchar(30),o.modify_date,126) FROM TeabarDB.sys.objects o JOIN TeabarDB.sys.schemas s ON s.schema_id=o.schema_id WHERE o.is_ms_shipped=0 ORDER BY s.name,o.name,o.type").fetchall()
        payload=json.dumps({'rows':rows,'objects':[list(r) for r in metadata]},ensure_ascii=False,default=str,sort_keys=True)
        return hashlib.sha256(payload.encode()).hexdigest()
    finally:
        cursor.close()

def execute(conn, sql, label, log):
    cursor=conn.cursor()
    try:
        for i,batch in enumerate(GO.split(sql)):
            if not batch.strip():
                continue
            cursor.execute(batch)
            while True:
                if cursor.description:
                    columns=[c[0] for c in cursor.description]
                    for row in cursor.fetchall():
                        log.append(json.dumps({'script':label,'batch':i,'result':dict(zip(columns,row))},ensure_ascii=False,default=str))
                if not cursor.nextset():
                    break
        log.append(json.dumps({'script':label,'status':'OK'}))
    finally:
        cursor.close()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server',default='localhost')
    parser.add_argument('--database',choices=ALLOWED_TARGETS,default=TARGET)
    parser.add_argument('--driver',default='ODBC Driver 18 for SQL Server')
    parser.add_argument('--output',type=Path,default=ROOT/'results/phase2/web/2026-11-07-fixes/database-setup.txt')
    args=parser.parse_args()
    target=args.database
    pyodbc.pooling=False
    log=[]
    conn=pyodbc.connect(connection_string(args.server,'master',args.driver),autocommit=True,timeout=5)
    before=None
    source_changed=False
    try:
        cursor=conn.cursor()
        try:
            if cursor.execute('SELECT DB_ID(?)',target).fetchone()[0] is not None:
                raise RuntimeError(f'{target} 已存在：拒绝覆盖；请使用现有测试库或由管理员另行处理。')
            if cursor.execute("SELECT DB_ID('TeabarDB')").fetchone()[0] is not None:
                before=source_fingerprint(conn)
            # Only fixed allowlisted target name can be created. No DROP path exists.
            cursor.execute(f'CREATE DATABASE [{target}]')
            cursor.execute(f'USE [{target}]')
        finally:
            cursor.close()
        raw=(ROOT/'db_creation.sql').read_text(encoding='utf-8-sig')
        marker='-- 持久化计算列所需会话选项'
        if raw.count(marker)!=1:
            raise RuntimeError('建库脚本起始标记不匹配；拒绝执行原删除逻辑。')
        # Exclude all original USE master/DROP/CREATE DATABASE batches entirely.
        execute(conn,raw[raw.index(marker):],'db_creation.sql (schema only)',log)
        for name in ('seed_data.sql','constraint.sql','role.sql','view.sql'):
            sql=(ROOT/name).read_text(encoding='utf-8-sig')
            sql=re.sub(r'\bUSE\s+TeabarDB\s*;',f'USE [{target}];',sql,flags=re.I)
            sql=sql.replace("N'TeabarDB'",f"N'{target}'")
            execute(conn,sql,name,log)
        path=ROOT/'database/migrations/v0.1-to-v1.0/migration.sql'
        sql=path.read_text(encoding='utf-8-sig')
        expected="DECLARE @ExpectedDatabase SYSNAME=N'TeabarDB_Phase2_Work';"
        commit='DECLARE @CommitMigration BIT=0;'
        if sql.count(expected)!=1 or sql.count(commit)!=1:
            raise RuntimeError('迁移安全参数不匹配；拒绝修改/执行。')
        sql=sql.replace(expected,f"DECLARE @ExpectedDatabase SYSNAME=N'{target}';").replace(commit,'DECLARE @CommitMigration BIT=1;')
        execute(conn,sql,f'migration.sql (target {target}, commit)',log)
        sql=(ROOT/'database/regression/regression.sql').read_text(encoding='utf-8-sig')
        if sql.count(expected)!=1:
            raise RuntimeError('回归目标安全参数不匹配。')
        execute(conn,sql.replace(expected,f"DECLARE @ExpectedDatabase SYSNAME=N'{target}';"),f'regression.sql (target {target})',log)
        from init_web_accounts import main as initialize_accounts
        captured=io.StringIO()
        with contextlib.redirect_stdout(captured):
            code=initialize_accounts(['--server',args.server,'--database',target,'--driver',args.driver])
        if code:
            raise RuntimeError(f'Web账号初始化失败：{code}')
        log.append(json.dumps({'script':'init_web_accounts.py','output':captured.getvalue()},ensure_ascii=False))
        log.append(json.dumps({'result':'TEST_DATABASE_CREATED','database':target}))
    finally:
        if before:
            after=source_fingerprint(conn)
            source_changed=before!=after
            log.append(json.dumps({'source':'TeabarDB','before':before,'after':after,'unchanged':not source_changed}))
        conn.close()
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text('\n'.join(log)+'\n',encoding='utf-8')
    if source_changed:
        raise RuntimeError('源库指纹发生变化，请检查其他并行写入；本工具未写源库。')
    print(f'创建完成：{target}；证据：{args.output}')
    return 0

if __name__=='__main__':
    raise SystemExit(main())
