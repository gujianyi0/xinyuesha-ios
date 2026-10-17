# Windows 上用免费 Apple ID 签名安装 IPA

> 目标：把 CI 产出的 `新月杀测试版-0.5.25-ios-unsigned.ipa` 装到 iPhone。
> 免费 Apple ID 即可，不需要 99 美元的开发者账号。

## 1. 准备（一次性）

1. **iTunes（Apple 官网版）**：到 <https://www.apple.com/itunes/download/win64>
   下载安装。不要用 Microsoft Store 版；Sideloadly 需要它带的
   Apple Mobile Device Support 驱动。
2. **Sideloadly**：到 <https://sideloadly.io/> 下载 Windows 版并安装。
3. 用**数据线**连接 iPhone 和电脑，iPhone 上点「信任此电脑」。
   - 如果 iTunes 能识别 iPhone，Sideloadly 一般也能识别。
4. iPhone：设置 → 隐私与安全性 → 开发者模式（iOS 16+）→ 打开，重启后确认。

## 2. 签名安装

1. 打开 Sideloadly，顶部 `Device` 选择你的 iPhone。
2. 把 `新月杀测试版-0.5.25-ios-unsigned.ipa` 拖进 IPA 框（或点 IPA 图标选择）。
3. `Apple ID` 填你的 Apple ID（免费账号即可）。
4. 点 **Start**：
   - 弹出 Apple ID 登录窗口时输入密码；
   - 开了双重认证的账号，建议先在 <https://account.apple.com> 生成
     「App 专用密码」，用专用密码登录；
   - 等待进度条走完。
5. iPhone：设置 → 通用 → VPN 与设备管理 → 开发者 APP →
   点你的 Apple ID → **信任**。
6. 回到桌面打开「新月杀测试版」。

## 3. 免费账号的限制

- 签名 **7 天**后过期，App 打不开；用同一个 IPA 在 Sideloadly 里重新签一次
  即可（Start 会覆盖安装）。
- 一个免费账号最多同时签 **3 个** App。
- 重签/覆盖安装通常会保留 App 的 Documents 数据；如果 Sideloadly 提示必须
  先卸载，卸载会删除 `Documents/FreeKill`（账号、录像、皮肤）。重要数据先在
  「文件」App → 我的 iPhone → 新月杀测试版 → FreeKill 里备份。
- 免费账号的 bundle id 不要和别的自签 App 冲突；本工程固定为
  `com.cui.freekill.ios`，要改就改 `CMakeLists.txt` 的 `FK_IOS_BUNDLE_ID`
  重新构建。

## 4. 常见问题

| 现象 | 处理 |
|---|---|
| Sideloadly 看不到设备 | 装 Apple 官网 iTunes；服务里重启 `Apple Mobile Device Service`；换原装线/USB 口 |
| `Unable to connect to device` | 同上；先在 iTunes 里确认能看到设备 |
| Apple ID 登录失败 | 用 App 专用密码；或在 Sideloadly 设置里换 `Anisette` 服务器 |
| 安装后闪退 | 先在设置里信任证书；仍闪退就抓 Xcode/Console 日志发回 |
| 7 天后打不开 | 正常，重新签名安装 |
| 想保留数据 | 不要卸载 App，直接覆盖重签；先备份 Documents |

## 5. 之后如果要长期使用

- 付费开发者账号（$99/年）：证书 1 年有效，可用 Xcode 直接装，不需要每 7 天
  重签。
- 或者用 AltStore + 同一 Apple ID 自动续签（需要电脑/AltServer 在同一网络）。
