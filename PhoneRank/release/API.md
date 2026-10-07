# 本机数据接口

默认 http://127.0.0.1:8765 。GET /health 返回服务状态；GET /api/v1/catalog 返回已发布 JSON，支持 ETag / If-None-Match。手机只需要后者。

管理接口限本机。GET /admin/api/state 建立会话并返回 csrf、catalog 草稿、candidates、history、publishedAt。修改请求为 JSON，携带该会话 cookie 及 X-CSRF-Token，并满足同源检查。

- GET /admin/api/records/{phones|chips}/{id}：data 与 version。
- POST /admin/api/save：kind、data（完整记录）、version；新增 version=0。
- POST /admin/api/delete：kind、id、version。
- POST /admin/api/publish：空对象，原子生成发布快照。
- GET /admin/api/export：草稿 JSON。
- POST /admin/api/collect：source（antutu/geekbench）、白名单 url，可选 html；只产生候选。
- POST /admin/api/apply：candidate_id、kind、target_id、version；人工确认后合并成绩，保留其他规格。
- POST /admin/api/reject：id。
- POST /admin/api/restore：audit_id；恢复修改/删除前的单条记录，进入草稿。

错误 JSON 含 error。无效数据400；本机/CSRF限制403；记录不存在404；版本冲突409。管理界面负责提示刷新冲突；发布不会自动触发客户端更新。

正式公开部署需要另外设计身份认证、HTTPS、备份和服务运维；此版本适用于一台电脑上的本机管理员。
