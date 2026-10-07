import copy
import json
import tempfile
import unittest
from pathlib import Path
from app import create_app
from parsers import parse_antutu, parse_geekbench, allowed_url

class ServerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.app = create_app(Path(self.directory.name))
        self.app.testing = True
        self.client = self.app.test_client()
        self.csrf = self.client.get('/admin/api/state').json['csrf']

    def tearDown(self):
        self.directory.cleanup()

    def post(self, path, payload):
        return self.client.post(path, json=payload, headers={'X-CSRF-Token': self.csrf})

    def test_seed_catalog_and_counts(self):
        data = self.client.get('/api/v1/catalog').json
        self.assertEqual(len(data['phones']), 182)
        self.assertEqual(len(data['chips']), 80)

    def test_edit_is_draft_until_publish_and_conflict_detected(self):
        before = self.client.get('/api/v1/catalog').json
        record = self.client.get('/admin/api/records/phones/1').json
        changed = copy.deepcopy(record['data'])
        changed['name'] = '测试手机'
        self.assertEqual(self.post('/admin/api/save', {'kind':'phones','data':changed,'version':record['version']}).status_code, 200)
        self.assertEqual(self.post('/admin/api/save', {'kind':'phones','data':changed,'version':record['version']}).status_code, 409)
        self.assertEqual(self.client.get('/api/v1/catalog').json, before)
        self.assertEqual(self.post('/admin/api/publish', {}).status_code, 200)
        self.assertEqual(self.client.get('/api/v1/catalog').json['phones'][0]['name'], '测试手机')

    def test_loopback_csrf_host_and_validation(self):
        self.assertEqual(self.client.post('/admin/api/publish', json={}).status_code, 403)
        self.assertEqual(self.client.get('/admin/api/state', environ_overrides={'REMOTE_ADDR':'192.168.1.9'}).status_code, 403)
        self.assertEqual(self.client.get('/admin/api/state', headers={'Host':'evil.test'}).status_code, 403)
        self.assertEqual(self.post('/admin/api/save', {'kind':'phones','data':{'id':'bad','name':'','platform':'android'},'version':0}).status_code, 400)
        self.assertFalse(allowed_url('https://browser.geekbench.com.evil.test/v6/cpu/1'))
        self.assertFalse(allowed_url('http://127.0.0.1/'))
        self.assertFalse(allowed_url('https://browser.geekbench.com:1234/v6/cpu/1'))

    def test_parser_keeps_versions_and_missing_fields(self):
        html = '<h1>Example Phone</h1><div class="score-container"><div class="score">2300</div><div class="note">Single-Core Score</div></div><div class="score-container"><div class="score">6900</div><div class="note">Multi-Core Score</div></div>'
        candidate = parse_geekbench(html, 'https://browser.geekbench.com/v6/cpu/123')[0]
        self.assertEqual(candidate['patch']['geekbench']['gb6']['single'], 2300)
        self.assertNotIn('gb7', candidate['patch']['geekbench'])
        html = '<a id="ranking_news">2026年8月Android设备性能榜详解</a><ul class="newrank-b"><li><div class="nrank-a"><span class="numrank">1</span><span class="name">Test Phone(S-8 16+512)</span></div><div class="nrank-b"><span>100</span><span>200</span><span>300</span><span>400</span><span>1000 分</span></div></li></ul>'
        candidate = parse_antutu(html, 'https://www.antutu.com/ranking')[0]
        self.assertEqual(candidate['patch']['antutu']['total'], 1000)
        self.assertEqual(candidate['patch']['antutu']['period'], '2026年8月')

    def test_bad_parser_does_not_invent_results(self):
        with self.assertRaises(ValueError): parse_geekbench('<h1>Just a moment...</h1>', 'https://browser.geekbench.com/v6/cpu/1')
        with self.assertRaises(ValueError): parse_antutu('<html>Maintenance</html>', 'https://www.antutu.com/ranking')

    def test_online_query_filters_candidates_without_writing_records(self):
        html = '<h1>Example Phone</h1><div class="score-container"><div class="score">2300</div>Single-Core Score</div><div class="score-container"><div class="score">6900</div>Multi-Core Score</div>'
        before = self.client.get('/api/v1/catalog').json
        payload = {'source':'geekbench','url':'https://browser.geekbench.com/v6/cpu/123','html':html,'query':' EXAMPLE '}
        result = self.post('/admin/api/collect', payload)
        self.assertEqual(result.status_code, 200)
        self.assertEqual(len(result.json['candidates']), 1)
        self.assertEqual(self.client.get('/api/v1/catalog').json, before)
        payload['query'] = 'missing model'
        self.assertEqual(self.post('/admin/api/collect', payload).status_code, 400)
        self.assertEqual(len(self.client.get('/admin/api/state').json['candidates']), 1)

    def test_invalid_nested_record_is_rejected(self):
        record = self.client.get('/admin/api/records/phones/1').json
        record['data']['antutu'] = []
        self.assertEqual(self.post('/admin/api/save', {'kind':'phones','data':record['data'],'version':record['version']}).status_code, 400)

    def test_delete_and_restore_preserve_record(self):
        before = self.client.get('/admin/api/records/phones/1').json
        self.assertEqual(self.post('/admin/api/delete', {'kind':'phones','id':'1','version':before['version']}).status_code, 200)
        self.assertEqual(self.client.get('/admin/api/records/phones/1').status_code, 404)
        audit = self.client.get('/admin/api/state').json['history'][0]
        self.assertEqual(self.post('/admin/api/restore', {'audit_id':audit['id']}).status_code, 200)
        self.assertEqual(self.client.get('/admin/api/records/phones/1').json['data'], before['data'])

    def test_readonly_etag_and_admin_remote_block(self):
        result = self.client.get('/api/v1/catalog', environ_overrides={'REMOTE_ADDR':'192.168.1.9'})
        self.assertEqual(result.status_code, 200)
        self.assertEqual(self.client.get('/api/v1/catalog', headers={'If-None-Match':result.headers['ETag']}).status_code, 304)

    def test_import_patch_keeps_existing_specs(self):
        html = '<h1>Phone</h1><div class="score-container"><div class="score">2300</div><div class="note">Single-Core Score</div></div><div class="score-container"><div class="score">6900</div><div class="note">Multi-Core Score</div></div>'
        result = self.post('/admin/api/collect', {'source':'geekbench','url':'https://browser.geekbench.com/v6/cpu/1','html':html})
        self.assertEqual(result.status_code, 200)
        candidate = result.json['candidates'][0]
        before = self.client.get('/admin/api/records/phones/1').json
        result = self.post('/admin/api/apply', {'candidate_id':candidate['id'],'kind':'phones','target_id':'1','version':before['version']})
        self.assertEqual(result.status_code, 200)
        after = self.client.get('/admin/api/records/phones/1').json['data']
        self.assertEqual(after['battery'], before['data']['battery'])
        self.assertEqual(after['geekbench']['gb6']['single'], 2300)

if __name__ == '__main__': unittest.main()