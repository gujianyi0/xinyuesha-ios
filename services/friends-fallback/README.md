# 好友服务备用入口

https://xinyuesha-friends-api.pages.dev

Pages 的 `_worker.js` 通过 `FRIENDS_SERVICE` 绑定转发到现有 `freekill-friends` Worker，参见 [Cloudflare 服务绑定](https://developers.cloudflare.com/pages/functions/bindings/#service-bindings)。没有单独创建好友数据库、注册体系或迁移身份。

客户端仍以原默认地址作为逻辑身份作用域。只有登录与同步请求遇到网络失败或超时才尝试另一条已验证的入口，成功后保持该线路；401、429 等业务状态按原规则处理。好友申请、邀请等写操作超时不自动重放。退出或切换账号会取消旧请求。

未登录访问 `/v1/state` 显示“好友服务登录已失效”及 HTTP 401 属正常鉴权响应；根路径“接口不存在”也不等于网络失败。客户端与 Safari 都超时的设备仍需检查实际网络可达性。备用入口也是 pages.dev，不能保证在屏蔽整个该域名后仍可访问。

维护：使用已登录的 Wrangler，在此目录执行 `wrangler pages deploy dist --project-name xinyuesha-friends-api --branch main`。此处仅维护转发入口，不发布或重置上游服务。不要把凭据、用户数据库或日志提交到公开仓库。

2026-10-22：主入口配置在 `../friends-primary`，复用本目录的同一份代理代码；JSON 响应明确标注 UTF-8，避免 Safari 导航到 API 时猜成其他编码。请求、正文、状态码、缓存及限流响应均保持上游结果。此项不等于修复客户端连接，最新流量复测见 [记录](../../docs/iOS好友流量复测-20261022.md)。
