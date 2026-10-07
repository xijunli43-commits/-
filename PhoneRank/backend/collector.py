import os
import threading
import time
from urllib.parse import urlparse
from urllib.robotparser import RobotFileParser
import requests
from parsers import allowed_url

USER_AGENT = 'PhoneRankDataManager/1.0'
_lock = threading.Lock()
_last_request = 0
_robots = {}

def session():
    client = requests.Session()
    client.headers['User-Agent'] = USER_AGENT
    # Use the user's existing Windows proxy, without changing system settings.
    if os.name == 'nt':
        try:
            import winreg
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r'Software\Microsoft\Windows\CurrentVersion\Internet Settings') as key:
                enabled = winreg.QueryValueEx(key, 'ProxyEnable')[0]
                proxy = winreg.QueryValueEx(key, 'ProxyServer')[0]
                if enabled and ';' not in proxy and '=' not in proxy:
                    client.proxies.update({'https': 'http://' + proxy if '://' not in proxy else proxy})
        except OSError: pass
    return client

def download(client, url, limit=2_000_000):
    try:
        response = client.get(url, timeout=(5, 12), allow_redirects=False, stream=True)
        with response:
            if response.status_code in (401,403,429): raise ValueError(f'网站拒绝自动访问（HTTP {response.status_code}）。可导入自己保存的公开页面 HTML。')
            if 300 <= response.status_code < 400: raise ValueError('网站发生重定向，未继续请求。请使用支持的最终 HTTPS 地址。')
            response.raise_for_status()
            body = bytearray()
            for chunk in response.iter_content(65536):
                body.extend(chunk)
                if len(body) > limit: raise ValueError('网页超过导入大小限制。')
            # Sites sometimes declare GB2312 while serving UTF-8.
            try: return bytes(body).decode('utf-8-sig')
            except UnicodeDecodeError: return bytes(body).decode('gb18030')
    except requests.RequestException as error:
        raise ValueError('无法读取来源网站，请检查网络或改为 HTML 导入。') from error

def fetch_public(url):
    global _last_request
    if not allowed_url(url) or urlparse(url).path == '/robots.txt': raise ValueError('仅接受安兔兔榜单或 Geekbench 6/7 CPU 详情页地址。')
    with _lock:
        if time.monotonic() - _last_request < 5: raise ValueError('请间隔至少 5 秒后再次抓取。')
        _last_request = time.monotonic()
    origin = 'https://' + urlparse(url).hostname
    with session() as client:
        cached = _robots.get(origin)
        if not cached or time.monotonic() - cached[0] > 3600:
            try: raw = download(client, origin + '/robots.txt', 200_000)
            except ValueError as error: raise ValueError('无法核查 robots.txt，本次未自动抓取；可使用 HTML 导入。') from error
            if '<html' in raw.lower(): raise ValueError('robots.txt 返回网页，无法确认访问规则；请使用 HTML 导入。')
            robot = RobotFileParser()
            robot.parse(raw.splitlines())
            _robots[origin] = (time.monotonic(), robot)
        else: robot = cached[1]
        if not robot.can_fetch(USER_AGENT, url): raise ValueError('网站 robots.txt 不允许自动读取此页；请使用手动数据或 HTML 导入。')
        return download(client, url)
