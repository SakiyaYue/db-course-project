"""验证数据库用户权限边界（模拟受限入口，不冒充真实受限服务器登录）。

仅对独立 Test/Work 库执行；创建临时探针用户的事务最终回滚。
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import pyodbc
from prepare_test_database import ROOT, connection_string

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server',default='localhost')
    parser.add_argument('--database',choices=['TeabarDB_Phase2_Test','TeabarDB_Phase2_Work'],default='TeabarDB_Phase2_Test')
    parser.add_argument('--output',type=Path,default=ROOT/'results/phase2/web/2026-11-07-fixes/web-permissions.txt')
    args=parser.parse_args()
    conn=pyodbc.connect(connection_string(args.server,args.database,'ODBC Driver 18 for SQL Server'),autocommit=True,timeout=5)
    results=[]
    def check_denied(cursor,label,sql,params=()):
        try:
            cursor.execute(sql,*params)
        except pyodbc.Error as exc:
            if not any(f'({n})' in str(exc) for n in (229,230,15151,15517)):
                raise
            results.append({'case':label,'result':'DENIED_AS_EXPECTED'})
        else:
            raise AssertionError(f'意外获准：{label}')
    cursor=conn.cursor()
    try:
        cursor.execute("SET XACT_ABORT OFF; BEGIN TRANSACTION; CREATE USER [web_entry_probe] WITHOUT LOGIN; ALTER ROLE teabar_web_app ADD MEMBER [web_entry_probe];")
        cursor.execute("EXECUTE AS USER='web_entry_probe'")
        try:
            check_denied(cursor,'entry cannot read account table','SELECT password_hash FROM teabar_auth.WebAccount')
            check_denied(cursor,'entry cannot read business table','SELECT * FROM dbo.SalesOrder')
            check_denied(cursor,'entry cannot change stock','UPDATE dbo.Ingredient SET stock=stock WHERE 1=0')
            assert cursor.execute("SELECT COALESCE(HAS_PERMS_BY_NAME('dbo','USER','IMPERSONATE'),0)").fetchone()[0]==0
            results.append({'case':'entry has no dbo impersonation permission','result':'DENIED_AS_EXPECTED'})
            cursor.execute('EXEC teabar_auth.usp_GetWebCredential ?', 'guesta')
            credential=cursor.fetchone()
            assert credential is not None
            account_id,_,version=credential
            cursor.execute('EXEC teabar_auth.usp_GetWebContext ?,?',account_id,version)
            context=cursor.fetchone()
            assert context[3]=='web_guest_a'
            results.append({'case':'entry credential and context APIs','result':'ALLOWED_AS_EXPECTED'})
            cursor.execute("EXECUTE AS USER='web_public'")
            try:
                assert cursor.execute('SELECT COUNT(*) FROM teabar_api.vw_Menu').fetchone()[0]==4
                results.append({'case':'entry can impersonate anonymous catalog identity','result':'ALLOWED_AS_EXPECTED'})
            finally:
                cursor.execute('REVERT')
            cursor.execute("EXECUTE AS USER='web_guest_a'")
            try:
                assert cursor.execute('SELECT COUNT(*) FROM teabar_api.vw_Menu').fetchone()[0]==4
                check_denied(cursor,'guest cannot read all orders','SELECT * FROM dbo.SalesOrder')
                check_denied(cursor,'guest cannot update member points','UPDATE dbo.Member SET points=points WHERE 1=0')
                assert cursor.execute("SELECT COALESCE(HAS_PERMS_BY_NAME('web_manager','USER','IMPERSONATE'),0)").fetchone()[0]==0
                results.append({'case':'guest has no manager impersonation permission','result':'DENIED_AS_EXPECTED'})
            finally:
                cursor.execute('REVERT')
        finally:
            cursor.execute('REVERT')
        for name in ('web_member_a','web_clerk','web_manager'):
            cursor.execute(f"EXECUTE AS USER='{name}'")
            try:
                check_denied(cursor,name+' cannot alter historical snapshots','UPDATE dbo.OrderItem SET product_name_snapshot=product_name_snapshot WHERE 1=0')
                check_denied(cursor,name+' cannot delete orders','DELETE dbo.SalesOrder WHERE 1=0')
                check_denied(cursor,name+' cannot read account secrets','SELECT password_hash FROM teabar_auth.WebAccount')
                if name=='web_member_a':
                    check_denied(cursor,'member cannot change points','UPDATE dbo.Member SET points=points WHERE 1=0')
                if name=='web_clerk':
                    check_denied(cursor,'clerk cannot adjust stock','EXEC teabar_api.usp_AdjustStock ?,?,?',('I001','补库',1))
                    check_denied(cursor,'clerk cannot read salary','SELECT salary FROM dbo.Employee')
                    check_denied(cursor,'clerk cannot change prices','UPDATE dbo.Product SET base_price=base_price WHERE 1=0')
            finally:
                cursor.execute('REVERT')
        cursor.execute("EXECUTE AS USER='web_public'")
        try:
            assert cursor.execute('SELECT COUNT(*) FROM teabar_api.vw_Menu').fetchone()[0]==4
            assert cursor.execute('SELECT COUNT(*) FROM teabar_api.vw_AvailableSpecifications').fetchone()[0]>0
            assert cursor.execute('SELECT COUNT(*) FROM teabar_api.vw_AvailableAddOns').fetchone()[0]>0
            check_denied(cursor,'public cannot read orders','SELECT * FROM teabar_api.vw_MyOrders')
            check_denied(cursor,'public cannot read account secrets','SELECT password_hash FROM teabar_auth.WebAccount')
            check_denied(cursor,'public cannot write orders','UPDATE dbo.SalesOrder SET status=status WHERE 1=0')
            results.append({'case':'public three catalog views','result':'ALLOWED_AS_EXPECTED'})
        finally:
            cursor.execute('REVERT')
        results.append({'result':'WEB_DATABASE_PERMISSION_PROBE_PASSED','cases':len(results),'scope':'EXECUTE AS USER simulation; not a separate restricted server login'})
    finally:
        try:
            cursor.execute('IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;')
        finally:
            cursor.close();conn.close()
            args.output.parent.mkdir(parents=True,exist_ok=True)
            args.output.write_text('\n'.join(json.dumps(x,ensure_ascii=False) for x in results)+'\n',encoding='utf-8')
    print(f'权限探针通过：{len(results)-1}项；事务已回滚；{args.output}')

if __name__=='__main__':
    main()
