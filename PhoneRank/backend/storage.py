import copy
import json
import math
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

def now(): return datetime.now(timezone.utc).isoformat(timespec='seconds')
def dumps(data): return json.dumps(data, ensure_ascii=False, allow_nan=False)

def validate_record(kind, record):
    if kind not in ('phones', 'chips') or not isinstance(record, dict): raise ValueError('无效的数据类型。')
    identity = record.get('id')
    if isinstance(identity, bool) or not isinstance(identity, (str, int)) or not str(identity) or len(str(identity)) > 100:
        raise ValueError('ID 必须是非空字符串或整数，长度不超过 100。')
    if isinstance(identity, int) and not 0 <= identity <= 9_007_199_254_740_991: raise ValueError('整数 ID 超出安全范围。')
    if any(c in str(identity) for c in '/\\\x00') or str(identity) in ('.','..'): raise ValueError('ID 不可包含路径分隔符。')
    if not isinstance(record.get('name'), str) or not record['name'].strip() or len(record['name']) > 250:
        raise ValueError('名称不能为空，最多 250 字符。')
    if kind == 'phones' and record.get('platform') not in ('android', 'ios'): raise ValueError('手机平台必须为 android 或 ios。')
    if kind == 'chips' and record.get('category') not in ('phone','apple-a','apple-m','other'): raise ValueError('无效芯片类别。')
    if len(dumps(record)) > 100_000: raise ValueError('单条数据过大。')
    object_fields = ('soc','antutu','geekbench','body','display','camera','battery','audio','haptics') if kind == 'phones' else ('cpu','gpu','memory','antutu','gb6','gb7')
    for field in object_fields:
        if field in record and not isinstance(record[field], dict): raise ValueError(f'{field} 必须是对象。')
    if kind == 'phones' and 'geekbench' in record:
        for version in ('gb6','gb7'):
            if version in record['geekbench'] and not isinstance(record['geekbench'][version], dict): raise ValueError(f'{version} 必须是对象。')
    def walk(value, depth=0, key=''):
        if depth > 12: raise ValueError('数据嵌套过深。')
        if isinstance(value, float) and not math.isfinite(value): raise ValueError('数字必须有限。')
        if isinstance(value, (int, float)) and not isinstance(value, bool) and value < 0: raise ValueError('参数或成绩不能为负数。')
        if isinstance(value, dict):
            for k, v in value.items(): walk(v, depth+1, k)
        elif isinstance(value, list):
            for v in value: walk(v, depth+1, key)
        elif key in ('single','multi','total','capacity','weight','refresh','samples') and value is not None and (not isinstance(value, (int, float)) or isinstance(value, bool)):
            # Existing source data occasionally carries descriptive display values.
            if key not in ('refresh', 'weight'): raise ValueError(f'{key} 必须是数字或 null。')
    walk(record)
    if 'sources' in record:
        if not isinstance(record['sources'], list): raise ValueError('sources 必须是数组。')
        for source in record['sources']:
            if not isinstance(source, dict) or not isinstance(source.get('label'), str) or not isinstance(source.get('url'), str): raise ValueError('来源需包含 label 与 url。')
            from urllib.parse import urlparse
            p = urlparse(source['url'])
            if p.scheme not in ('http','https') or not p.hostname or p.username or p.password: raise ValueError('来源网址必须为 http/https。')
    return record

def merge(base, patch):
    result = copy.deepcopy(base)
    for key, value in patch.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict): result[key] = merge(result[key], value)
        else: result[key] = copy.deepcopy(value)
    return result

class Store:
    def __init__(self, directory, seed):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        self.path = self.directory / 'catalog.sqlite3'
        with self.connect() as db:
            db.executescript('''
                CREATE TABLE IF NOT EXISTS records(kind TEXT,id TEXT,data TEXT,version INTEGER NOT NULL,PRIMARY KEY(kind,id));
                CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY,value TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS audit(id INTEGER PRIMARY KEY,at TEXT,action TEXT,kind TEXT,record_id TEXT,before_data TEXT,after_data TEXT);
                CREATE TABLE IF NOT EXISTS candidates(id INTEGER PRIMARY KEY,at TEXT,data TEXT,status TEXT NOT NULL DEFAULT 'pending');
                CREATE TABLE IF NOT EXISTS snapshots(id INTEGER PRIMARY KEY,at TEXT,data TEXT);
            ''')
            if not db.execute("SELECT 1 FROM settings WHERE key='published'").fetchone():
                for kind in ('phones','chips'):
                    for record in seed[kind]: db.execute('INSERT INTO records VALUES(?,?,?,1)', (kind,str(record['id']),dumps(record)))
                meta = {k:v for k,v in seed.items() if k not in ('phones','chips')}
                db.execute('INSERT INTO settings VALUES(?,?)', ('metadata',dumps(meta)))
                db.execute('INSERT INTO settings VALUES(?,?)', ('published',dumps(seed)))
                db.execute('INSERT INTO snapshots(at,data) VALUES(?,?)', (now(),dumps(seed)))
    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=15)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA journal_mode=WAL')
        try:
            with db:
                yield db
        finally:
            db.close()
    def published(self):
        with self.connect() as db: return json.loads(db.execute("SELECT value FROM settings WHERE key='published'").fetchone()[0])
    def draft(self, db=None):
        if db is None:
            with self.connect() as db: return self.draft(db)
        data = json.loads(db.execute("SELECT value FROM settings WHERE key='metadata'").fetchone()[0])
        for kind in ('phones','chips'):
            data[kind] = [json.loads(row[0]) for row in db.execute('SELECT data FROM records WHERE kind=? ORDER BY rowid',(kind,))]
        data['counts'] = {'total':len(data['phones']), 'android':sum(p.get('platform') == 'android' for p in data['phones']), 'ios':sum(p.get('platform') == 'ios' for p in data['phones']), 'chips':len(data['chips'])}
        return data
    def record(self, kind, identity):
        with self.connect() as db:
            row = db.execute('SELECT data,version FROM records WHERE kind=? AND id=?',(kind,str(identity))).fetchone()
            return {'data':json.loads(row['data']),'version':row['version']} if row else None
    def save(self, kind, record, version, candidate_id=None):
        validate_record(kind,record)
        identity = str(record['id'])
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            if candidate_id is not None and not db.execute("SELECT 1 FROM candidates WHERE id=? AND status='pending'",(candidate_id,)).fetchone():
                raise RuntimeError('待审核项已处理，请刷新。')
            row = db.execute('SELECT data,version FROM records WHERE kind=? AND id=?',(kind,identity)).fetchone()
            current_version = row['version'] if row else 0
            if version != current_version: raise RuntimeError('数据已被其他操作更新，请重新打开后编辑。')
            db.execute('INSERT INTO records VALUES(?,?,?,?) ON CONFLICT(kind,id) DO UPDATE SET data=excluded.data, version=excluded.version',(kind,identity,dumps(record),current_version+1))
            db.execute('INSERT INTO audit(at,action,kind,record_id,before_data,after_data) VALUES(?,?,?,?,?,?)',(now(),'save',kind,identity,row['data'] if row else None,dumps(record)))
            if candidate_id is not None:
                db.execute("UPDATE candidates SET status='applied' WHERE id=?",(candidate_id,))
        return current_version+1
    def delete(self, kind, identity, version):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            row = db.execute('SELECT data,version FROM records WHERE kind=? AND id=?',(kind,str(identity))).fetchone()
            if not row: raise ValueError('记录不存在。')
            if row['version'] != version: raise RuntimeError('记录已更新，请刷新。')
            db.execute('DELETE FROM records WHERE kind=? AND id=?',(kind,str(identity)))
            db.execute('INSERT INTO audit(at,action,kind,record_id,before_data) VALUES(?,?,?,?,?)',(now(),'delete',kind,str(identity),row['data']))
    def publish(self):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            data = self.draft(db)
            if not data['phones']: raise ValueError('不能发布空手机库。')
            for kind in ('phones','chips'):
                for record in data[kind]: validate_record(kind,record)
            data['generatedAt'] = datetime.now().astimezone().date().isoformat()
            data['publishedAt'] = now()
            db.execute("UPDATE settings SET value=? WHERE key='published'",(dumps(data),))
            db.execute('INSERT INTO snapshots(at,data) VALUES(?,?)',(now(),dumps(data)))
            db.execute('INSERT INTO audit(at,action) VALUES(?,?)',(now(),'publish'))
        return data
