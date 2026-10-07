"""Parse public pages into review candidates, never directly overwrite records."""
import re
from urllib.parse import urlparse
from bs4 import BeautifulSoup

def allowed_url(url):
    try:
        p = urlparse(url)
        if p.scheme != 'https' or p.username or p.password or p.port not in (None, 443) or p.fragment:
            return False
        if p.hostname == 'www.antutu.com':
            return p.path.rstrip('/') in ('/ranking', '/ranking/ios', '/ranking/soc', '/robots.txt')
        if p.hostname == 'browser.geekbench.com':
            return bool(re.fullmatch(r'/v[67]/cpu/\d+/?', p.path)) or p.path == '/robots.txt'
    except (ValueError, TypeError):
        pass
    return False

def score(text):
    value = re.sub(r'[,\s]', '', text).removesuffix('分')
    if not value.isdigit(): raise ValueError('分数字段结构发生变化，未导入。')
    number = int(value)
    if not 0 < number < 100_000_000: raise ValueError('成绩超出有效范围。')
    return number

def parse_antutu(html, url):
    soup = BeautifulSoup(html, 'html.parser')
    period = re.search(r'20\d{2}年\d{1,2}月', soup.get_text(' ', strip=True))
    if not period: raise ValueError('未找到榜单统计月份，不能安全导入。')
    is_chip = '/soc' in urlparse(url).path
    platform = 'ios' if '/ios' in urlparse(url).path else 'android'
    candidates = []
    for row in soup.select('ul.newrank-b'):
        name_el = row.select_one('.model-name') or row.select_one('.name')
        if not name_el: continue
        name = name_el.get_text(' ', strip=True)
        memory = row.select_one('.memory')
        configuration = memory.get_text(' ', strip=True) if memory else '未注明配置'
        if platform == 'ios' and not is_chip and not name.lower().startswith('iphone'): continue
        cells = row.select('.nrank-b > li')
        if not cells:
            cells = row.select('.nrank-b > span')
        if len(cells) == 6: cells = cells[1:]
        keys = ['cpu', 'gpu', 'mem', 'ux', 'total'] if not is_chip else ['cpu', 'gpu', 'total']
        if len(cells) != len(keys): raise ValueError('榜单列数变化，停止导入以避免错列。')
        scores = {key: score(cell.get_text(' ', strip=True)) for key, cell in zip(keys, cells)}
        scores.update(period=period.group(), source=url)
        rank = row.select_one('.numrank')
        patch = {'antutu': scores}
        if rank and rank.get_text(strip=True).isdigit(): patch['rank'] = int(rank.get_text(strip=True))
        candidates.append({'name':name.split('(')[0].strip(), 'kind':'chips' if is_chip else 'phones',
                           'platform':platform, 'patch':patch, 'url':url, 'source':'antutu',
                           'configuration':configuration,
                           'note':f'统计均分；来源配置：{configuration}。请核对目标内存/存储。' if not is_chip else 'SoC 综合分，不等同 Geekbench CPU 分数。'})
    if not candidates: raise ValueError('未识别到可导入的公开榜单；网站结构可能已变化。')
    return candidates

def parse_geekbench(html, url):
    version = re.search(r'/v([67])/cpu/\d+', urlparse(url).path)
    if not version: raise ValueError('仅支持 Geekbench 6/7 CPU 成绩详情页。')
    soup = BeautifulSoup(html, 'html.parser')
    if soup.select_one('#challenge-running, #challenge-form') or 'Just a moment' in soup.get_text():
        raise ValueError('Geekbench 要求浏览器验证。请自行打开页面后保存 HTML，再导入。')
    scores = {}
    for container in soup.select('.score-container'):
        text = container.get_text(' ', strip=True)
        value = container.select_one('.score')
        if not value: continue
        if 'Single-Core Score' in text: scores['single'] = score(value.get_text(strip=True))
        if 'Multi-Core Score' in text: scores['multi'] = score(value.get_text(strip=True))
    if set(scores) != {'single', 'multi'}:
        raise ValueError('未找到单核及多核成绩，请确认这是完整 CPU 成绩页。')
    name = soup.select_one('h1')
    scores['source'] = url
    return [{'name':name.get_text(' ', strip=True) if name else 'Geekbench 成绩', 'kind':'phones',
             'patch':{'geekbench':{'gb' + version.group(1):scores}}, 'url':url, 'source':'geekbench',
             'note':'单次用户提交成绩，非统计均值。请核对机型、系统和运行条件；导入芯片时样本数为 1。'}]
