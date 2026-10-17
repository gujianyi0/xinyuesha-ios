# iPhone 安装与排错（一键整合包）

> 正常安装只需要双击 `一键安装到iPhone.lnk`（或
> `apk/整合包/一键安装到iPhone.cmd`），按 `安装说明.txt` 完成 Apple ID 和
> 信任证书即可。本文只列常见问题，不再重复手动安装步骤。

## 一键脚本做了什么

1. 检查/安装 iTunes（优先 winget；失败则调用随包的 `iTunes64Setup.exe`）；
2. 检查/安装 Sideloadly（静默；失败则打开安装向导）；
3. 尝试启动 `Apple Mobile Device Service`；
4. 把 IPA 路径复制到剪贴板，打开 Sideloadly 并尝试带上 IPA。

脚本后端在 `apk/整合包/bin/install-to-iphone.ps1`，请勿删除。

## 常见问题

| 现象 | 处理 |
|---|---|
| UAC / SmartScreen 弹窗 | 点“是”/“更多信息 → 仍要运行” |
| Sideloadly 看不到设备 | 先重启电脑（iTunes 驱动首次安装后常见）；确认 iTunes 能看到 iPhone；换原装线/USB 口；服务里重启 `Apple Mobile Device Service` |
| Sideloadly 没自动带 IPA | 把 `apk/整合包/新月杀测试版-0.5.25-ios-unsigned.ipa` 拖进窗口 |
| Apple ID 登录失败 | 用 App 专用密码（<https://account.apple.com>）；或在 Sideloadly 设置里换 Anisette 服务器 |
| 安装后闪退 | 先到 设置 → 通用 → VPN 与设备管理 信任证书；仍闪退就把设备日志和 App 内 `FreeKill/freekill.server.log` 发回 |
| 7 天后打不开 | 免费 Apple ID 正常过期，用同一个 IPA 在 Sideloadly 重新 Start |
| 想保留数据 | 不要卸载 App，直接覆盖重签；先备份「文件」App → 我的 iPhone → 新月杀测试版 → FreeKill |

## 免费 Apple ID 的限制

- 签名 7 天有效，最多同时签 3 个 App；
- 覆盖重签通常保留 Documents 数据；卸载会删除；
- 想彻底免掉 iTunes/Sideloadly 和 7 天重签，需要付费 Apple Developer
  账号（$99/年）+ TestFlight。

## 只有手机、没有电脑？

免费 Apple ID 的首次签名仍需要电脑端工具（Sideloadly/AltStore/SideStore
的初始配对）；装好后 App 独立运行。彻底不用电脑的干净路径只有
**付费 Apple Developer + TestFlight**；SideStore 是折中（首次电脑配对，
之后手机续签）。
