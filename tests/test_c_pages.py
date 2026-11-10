"""C sections 1–7: rendered pages, PRG, validation and role boundaries."""
from unittest.mock import MagicMock
import secrets

import pytest

from app.errors import AppError
from app.services import maintenance_service

RESOURCES = ['products','ingredients','employees','specifications','product-specifications',
             'recipes','specification-ingredients','addons','duty-rosters']


def post(client, path, data):
    token = client.get('/api/csrf').get_json()['csrf_token']
    return client.post(path, data=dict(data, csrf_token=token))


@pytest.mark.parametrize('resource', RESOURCES)
def test_manager_forms_render(client, login, resource):
    login('manager1')
    response = client.get('/admin/maintenance/' + resource)
    assert response.status_code == 200
    text = response.get_data(as_text=True)
    assert '全部记录' in text and 'name="csrf_token"' in text
    assert 'SQL Server' not in text


@pytest.mark.parametrize('account', ['guesta','membera','clerk1'])
def test_non_manager_page_and_post_denied(client, login, account):
    login(account)
    for path in ['/admin/maintenance','/admin/maintenance/products','/admin/orders','/admin/orders/O001']:
        response = client.get(path)
        assert response.status_code == 403
        assert '无权' in response.get_data(as_text=True)
    assert post(client, '/admin/maintenance/products', {}).status_code == 403


def test_profile_and_role_navigation(client, login):
    login('membera')
    page = client.get('/my/profile')
    assert page.status_code == 200 and '当前积分' in page.get_data(as_text=True)
    assert '维护中心' not in page.get_data(as_text=True)
    login('guesta')
    assert client.get('/my/profile').status_code == 403
    login('clerk1')
    text = client.get('/work/orders').get_data(as_text=True)
    assert '当天订单' in text and '全部未完成' in text
    assert '维护中心' not in text and '历史订单' not in text


def test_history_pages_and_empty_filters(client, login, dbo):
    login('manager1')
    oid = dbo.execute('SELECT TOP(1) order_id FROM dbo.SalesOrder ORDER BY order_time').fetchone()[0]
    assert client.get('/admin/orders?status=&order_id=&date_from=&date_to=').status_code == 200
    detail = client.get('/admin/orders/' + oid)
    assert detail.status_code == 200 and '成交记录只读' in detail.get_data(as_text=True)
    assert 'method="post"' not in detail.get_data(as_text=True).split('<main')[1].split('</main>')[0]
    assert '没有符合条件' in client.get('/admin/orders?order_id=NOEXIST').get_data(as_text=True)
    assert client.get('/admin/orders?date_from=2026-11-10&date_to=2026-11-01').status_code == 400


def test_form_write_edit_prg_and_failure_retains_values(client, login, dbo):
    login('manager1')
    pid = 'C' + secrets.token_hex(3)
    path = '/admin/maintenance/products'
    body = dict(product_id=pid, product_name='C页面测试', base_price='8.50', status='下架', description='页面测试')
    try:
        bad = post(client, path, dict(body, base_price='NaN'))
        assert bad.status_code == 400 and 'C页面测试' in bad.get_data(as_text=True)
        saved = post(client, path, body)
        assert saved.status_code == 302
        assert '资料已保存' in client.get(saved.location).get_data(as_text=True)
        edit = client.get(path + '?key=' + pid)
        assert edit.status_code == 200 and 'readonly' in edit.get_data(as_text=True)
        assert post(client, path, dict(body, product_name='已修改', editing='1')).status_code == 302
        assert dbo.execute('SELECT product_name FROM dbo.Product WHERE product_id=?', pid).fetchone()[0] == '已修改'
    finally:
        dbo.execute('DELETE FROM dbo.Product WHERE product_id=?', pid)


def test_maintenance_failure_is_safe_and_keeps_input(client, login, monkeypatch):
    login('manager1')
    monkeypatch.setattr(maintenance_service, 'save_record', MagicMock(side_effect=AppError('transaction_failed','事务冲突或超时，请稍后重试。',503,detail='PRIVATE_SQL_SECRET')))
    response = post(client, '/admin/maintenance/products', dict(product_id='C1',product_name='保留输入',base_price='1',status='下架'))
    assert response.status_code == 503
    text = response.get_data(as_text=True)
    assert '保留输入' in text and '超时' in text and 'PRIVATE_SQL_SECRET' not in text


def test_database_unavailable_page_is_safe(app, client, monkeypatch):
    db = MagicMock()
    db.connection.side_effect = AppError('database_unavailable','无法连接数据库，请稍后重试。',503, detail='PRIVATE_CONNECTION_PASSWORD')
    monkeypatch.setitem(app.extensions,'teabar_db',db)
    response = client.get('/menu')
    assert response.status_code == 503
    assert '服务暂时不可用' in response.get_data(as_text=True)
    assert 'PRIVATE_CONNECTION_PASSWORD' not in response.get_data(as_text=True)


def test_expired_session_redirects_to_login(client, login, dbo):
    login('membera')
    original = dbo.execute("SELECT session_version FROM teabar_auth.WebAccount WHERE login_name='membera'").fetchone()[0]
    try:
        dbo.execute("UPDATE teabar_auth.WebAccount SET session_version=session_version+1 WHERE login_name='membera'")
        response = client.get('/my/profile', follow_redirects=True)
        assert response.status_code == 200
        assert '会话可能已失效' in response.get_data(as_text=True)
    finally:
        dbo.execute("UPDATE teabar_auth.WebAccount SET session_version=? WHERE login_name='membera'",original)


def test_anonymous_redirect_and_csrf(client):
    assert client.get('/admin/maintenance').status_code == 302
    assert client.post('/admin/maintenance/products',data={}).status_code == 400
