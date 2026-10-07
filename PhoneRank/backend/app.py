import copy
import hashlib
import json
import secrets
import sqlite3
from pathlib import Path
from urllib.parse import urlparse
from flask import Flask, jsonify, request, send_from_directory, session
from werkzeug.exceptions import HTTPException
from collector import fetch_public
from parsers import allowed_url, parse_antutu, parse_geekbench
from storage import Store, dumps, merge, now

BASE = Path(__file__).resolve().parent

def create_app(data_dir=None):
    data_dir = Path(data_dir or BASE / 'data')
    data_dir.mkdir(parents=True, exist_ok=True)
    seed = json.loads((BASE.parent / 'PhoneRank/Resources/catalog.json').read_text(encoding='utf-8'))
    store = Store(data_dir, seed)
    secret_file = data_dir / 'session.key'
    if not secret_file.exists(): secret_file.write_bytes(secrets.token_bytes(32))
    app = Flask(__name__, static_folder='static', static_url_path='/static')
    app.config.update(SECRET_KEY=secret_file.read_bytes(), MAX_CONTENT_LENGTH=3_000_000,
                      SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE='Strict')
    app.extensions['store'] = store

    @app.before_request
    def protect_admin():
        if request.path.startswith('/admin') or request.path == '/':
            if request.remote_addr not in ('127.0.0.1','::1') or request.host.split(':')[0] not in ('127.0.0.1','localhost','[::1]'):
                return jsonify(error='管理后台仅允许在这台电脑通过 localhost 访问。'), 403
            if request.method not in ('GET','HEAD','OPTIONS'):
                origin = request.headers.get('Origin')
                if origin and origin != request.host_url.rstrip('/'): return jsonify(error='跨站请求被拒绝。'), 403
                expected = session.get('csrf')
                supplied = request.headers.get('X-CSRF-Token', '')
                if not expected or not secrets.compare_digest(expected, supplied): return jsonify(error='会话已失效，请刷新页面。'), 403

    @app.after_request
    def headers(response):
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['X-Frame-Options'] = 'DENY'
        response.headers['Referrer-Policy'] = 'no-referrer'
        if not request.path.startswith('/preview'):
            response.headers['Content-Security-Policy'] = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"
        if request.path.startswith('/admin'): response.headers['Cache-Control'] = 'no-store'
        return response

    @app.errorhandler(ValueError)
    def bad_input(error): return jsonify(error=str(error)), 400
    @app.errorhandler(RuntimeError)
    def conflict(error): return jsonify(error=str(error)), 409
    @app.errorhandler(Exception)
    def unexpected(error):
        if isinstance(error, HTTPException): return jsonify(error=error.description), error.code
        app.logger.exception('Request failed')
        return jsonify(error='服务器处理失败，请查看本机日志。'), 500

    @app.get('/')
    def home(): return send_from_directory(BASE / 'static', 'index.html')
    @app.get('/health')
    def health(): return jsonify(status='ok', mode='local-admin', version='1.0.0')
    @app.get('/api/v1/catalog')
    def catalog():
        data = store.published()
        response = jsonify(data)
        response.set_etag(hashlib.sha256(dumps(data).encode()).hexdigest())
        return response.make_conditional(request)
    @app.get('/admin/api/state')
    def state():
        if 'csrf' not in session: session['csrf'] = secrets.token_urlsafe(32)
        data = store.draft()
        with store.connect() as db:
            candidates = [dict(row) for row in db.execute('SELECT id,at,data,status FROM candidates ORDER BY id DESC LIMIT 500')]
            for candidate in candidates: candidate['data'] = json.loads(candidate['data'])
            history = [dict(row) for row in db.execute('SELECT id,at,action,kind,record_id FROM audit ORDER BY id DESC LIMIT 50')]
        return jsonify(csrf=session['csrf'], catalog=data, candidates=candidates, history=history,
                       publishedAt=store.published().get('publishedAt', seed['generatedAt']))
    @app.get('/admin/api/records/<kind>/<identity>')
    def record(kind, identity):
        if kind not in ('phones','chips'): raise ValueError('无效类型。')
        result = store.record(kind, identity)
        return (jsonify(result), 200) if result else (jsonify(error='记录不存在。'),404)
    def body():
        data = request.get_json()
        if not isinstance(data,dict): raise ValueError('请求必须是 JSON 对象。')
        return data
    @app.post('/admin/api/save')
    def save():
        data = body()
        return jsonify(version=store.save(data.get('kind'), data.get('data'), data.get('version')))
    @app.post('/admin/api/delete')
    def delete():
        data = body()
        store.delete(data.get('kind'), data.get('id'), data.get('version'))
        return jsonify(ok=True)
    @app.post('/admin/api/publish')
    def publish(): return jsonify(counts=store.publish()['counts'])
    @app.get('/admin/api/export')
    def export():
        response = jsonify(store.draft())
        response.headers['Content-Disposition'] = 'attachment; filename="catalog-draft.json"'
        return response
    @app.post('/admin/api/collect')
    def collect():
        data = body()
        source, url = data.get('source'), data.get('url','')
        if not isinstance(url,str) or not allowed_url(url): raise ValueError('来源地址不受支持。')
        if source not in ('antutu','geekbench') or (source == 'antutu') != (urlparse(url).hostname == 'www.antutu.com'):
            raise ValueError('来源与网址不匹配。')
        html = data.get('html')
        if html is not None and (not isinstance(html,str) or len(html)>2_000_000): raise ValueError('HTML 内容无效或过大。')
        html = html if html else fetch_public(url)
        parser = parse_antutu if source == 'antutu' else parse_geekbench
        candidates = parser(html,url)
        keyword = data.get('query', '')
        if not isinstance(keyword, str) or len(keyword) > 100: raise ValueError('搜索关键词最多 100 字符。')
        keyword = keyword.strip().casefold()
        if keyword:
            candidates = [item for item in candidates if keyword in (item['name'] + ' ' + item.get('configuration', '')).casefold()]
            if not candidates: raise ValueError('此页面没有匹配的型号。请换关键词或来源页面，未创建候选。')
        result = []
        with store.connect() as db:
            for candidate in candidates:
                cursor = db.execute('INSERT INTO candidates(at,data) VALUES(?,?)',(now(),dumps(candidate)))
                result.append({'id':cursor.lastrowid,'data':candidate,'status':'pending'})
        return jsonify(candidates=result)
    @app.post('/admin/api/apply')
    def apply():
        data = body()
        with store.connect() as db:
            row = db.execute("SELECT data FROM candidates WHERE id=? AND status='pending'",(data.get('candidate_id'),)).fetchone()
        if not row: raise ValueError('待审核项不存在或已处理。')
        candidate = json.loads(row['data'])
        kind, identity = data.get('kind'), data.get('target_id')
        old = store.record(kind, identity)
        if not old: raise ValueError('请先选择已有记录，或手动新建后再导入成绩。')
        patch = copy.deepcopy(candidate['patch'])
        if candidate['source'] == 'antutu':
            if kind != candidate['kind']: raise ValueError('手机榜与芯片榜不可混用。')
            if kind == 'phones' and old['data'].get('platform') != candidate['platform']: raise ValueError('平台不匹配。')
        if candidate['source'] == 'geekbench' and kind == 'chips':
            patch = patch['geekbench']
            for scores in patch.values():
                scores['samples'] = 1
                scores['sources'] = [scores.pop('source')]
        updated = merge(old['data'],patch)
        sources = updated.setdefault('sources',[])
        if not any(s.get('url') == candidate['url'] for s in sources): sources.append({'label':candidate['source'] + ' 导入成绩','url':candidate['url']})
        version = store.save(kind,updated,data.get('version'),candidate_id=data.get('candidate_id'))
        return jsonify(version=version)
    @app.post('/admin/api/reject')
    def reject():
        data=body()
        with store.connect() as db: db.execute("UPDATE candidates SET status='rejected' WHERE id=? AND status='pending'",(data.get('id'),))
        return jsonify(ok=True)
    @app.post('/admin/api/restore')
    def restore():
        data=body()
        with store.connect() as db:
            row = db.execute('SELECT kind,record_id,before_data FROM audit WHERE id=?',(data.get('audit_id'),)).fetchone()
        if not row or not row['before_data']: raise ValueError('此历史记录没有可恢复的旧值。')
        current = store.record(row['kind'],row['record_id'])
        version = store.save(row['kind'],json.loads(row['before_data']),current['version'] if current else 0)
        return jsonify(version=version)
    @app.get('/preview/data.js')
    def preview_data(): return app.response_class('window.PHONE_DATA = '+dumps(store.published())+';', mimetype='text/javascript')
    @app.get('/preview/')
    def preview(): return send_from_directory(BASE / 'preview','index.html')
    @app.get('/preview/<path:filename>')
    def preview_asset(filename): return send_from_directory(BASE / 'preview',filename)
    return app