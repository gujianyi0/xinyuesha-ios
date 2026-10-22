# 新月杀测试版

Android、Windows PC、iOS 三端客户端，基于 [FreeKill / 新月杀](https://github.com/Qsgs-Fans/FreeKill) 0.5.25 整理和维护。

**维护者：[gujianyi0](https://github.com/gujianyi0)**

## 下载与安装

[查看安卓卡顿热修复](https://github.com/gujianyi0/xinyuesha-ios/releases/tag/test-0.5.25-20261019-r3) · [查看 iOS 修复与其他文件](https://github.com/gujianyi0/xinyuesha-ios/releases/tag/test-0.5.25-20261019-r2) · [SHA256 校验清单](downloads/SHA256SUMS.txt)

| 平台 | 安装包 | 要求与安装方式 |
| --- | --- | --- |
| Android | [下载 APK](https://github.com/gujianyi0/xinyuesha-ios/releases/download/test-0.5.25-20261019-r3/xinyuesha-test-android-20261019.apk) | Android 9+、ARM64；已有同签名测试版可直接覆盖安装，保留应用数据。 |
| Windows PC | [下载完整包](https://github.com/gujianyi0/xinyuesha-ios/releases/download/test-0.5.25-20261019/xinyuesha-test-windows-20261019.7z) · [已有版本更新补丁](https://github.com/gujianyi0/xinyuesha-ios/releases/download/test-0.5.25-20261019/xinyuesha-test-windows-patch-20261019.zip) | 64 位 Windows；完整解压后运行“启动新月杀测试版.cmd”；更新前关闭游戏。 |
| iOS | [下载独立 IPA](https://github.com/gujianyi0/xinyuesha-ios/releases/download/test-0.5.25-20261019-r2/xinyuesha-test-ios-20261019-unsigned.ipa) · [含工具的安装整合包](https://github.com/gujianyi0/xinyuesha-ios/releases/download/test-0.5.25-20261019-r2/xinyuesha-test-ios-bundle-20261019.zip) | 游戏最低 iOS 16.0；IPA 未签名，需要兼容的签名或安装工具。覆盖安装沿用旧版应用标识与签名身份。 |

安装游戏请下载上表对应文件。GitHub 的 **Code → Download ZIP** 是工程源码，不是完整的安装包。

## 功能

- 记牌器：跟随实际房间牌池统计，通过牌堆入口查看。
- 同游好友：头像、好友管理、跨房间邀请与跟随观战。
- 在线 / 隐身，以及对局中的一起玩预约。
- 调整好友入口显示范围，减少对原版界面的遮挡。

本轮更新和此前验证分别列出；自动回归不等于真机验收。

## 本轮更新 · 2026-10-22

三端角色语音列表进一步排除全部语音缺失的武将，分批检测并缓存目录，支持“重新检测”，并修正弹窗边界和列表刷新。已通过三端 Qt 模拟回归，本轮按用户要求未操作手机，待覆盖复测。

Android 已补齐角色语音组件的启动释放清单，修复新版覆盖后“聊天→角色”入口仍消失的问题。已在连接手机的主力服观战中确认按钮及角色列表可打开；APK SHA256 以清单为准。

Android / PC / iOS 已同步房间好友入口定位与聊天角色语音，基线资源 9b230c9；iOS 进一步补齐好友联网诊断、地址纠正，并重新编译系统网络通道（a1ad5d5）。聊天中点击“角色”选择房主启用将池中的武将，再在语音列表发送；切换房间后重选。

**iOS 好友联网仍待真机确认**：已确认 20261022.2 在正确根地址和流量下仍无 HTTP 响应，不能只归因于误填。最新 **20261022.4** 重新编译 iOS 系统 NSURLSession 通道，设置页应显示“iOS 系统网络”；失败返回系统错误码，保留证书校验、原好友身份和认证方式。iOS arm64 构建及 Foundation 测试 39706324603、三端 Qt 回归 39706323009 通过，实际 iPhone 连接仍需复测。正确备用地址是 `https://xinyuesha-friends-api.pages.dev`，不带 `/v1/state`。本轮未覆盖到安卓手机，Android / PC 分发文件保持上一轮版本。详见 [流量复测记录](docs/iOS好友流量复测-20261022.md) · [客户端更新记录](docs/房间入口角色语音与好友连接-20261022.md)。

## 此前已完成的验证


| 平台 | 已核对 | 仍需注意 |
| --- | --- | --- |
| Android | 已覆盖手机并核对安装包及实际加载资源；主力服观战中验证记牌器数量更新保持位置、战报手动回看。三端回归 39434388176 通过，切换武将包采样的后台开销有改善。新版图片导入已通过 Android 35 的文档 URI、大图、旋转和失败保留测试；签名与旧版一致。 | 长期游玩、小米 14 换背景及重启仍待真机复测。跨服更新核心后，等同步全部完成并按提示重启，再登录目标服。狐狸服 67 个扩展加载约 15.5 秒，尚未做引擎加载加速；OriginOS 切屏断线尚未修复。 |
| Windows PC | 完整包、补丁及分享文件夹一致；性能修正在 Qt 6.10.0 下通过 60 次新建/销毁场景及 6 万条模拟消息测试。 | 尚未做本轮 PC 双服与长期联网对局验收。 |
| iOS | 原生与资源已更新为 f1ed000，构建 39438953157 通过，修正武将牌标记只记录首次数据的问题。Qt 6.8.3 下通过数量、化身列表、图片说明、详情更新和清除再添加测试；保留此前战报回看、记牌器位置与生命周期性能回归。 | 本轮标记修正及长期游玩仍待 iPhone 真机复测，不能宣布全部卡顿解决。 |

本轮 [三端分发与性能检查](docs/三端分发与性能检查-20261020.md) 已补齐 iOS、PC 的对局性能修正；本轮三端进一步取消大厅/功能页定时扫描；稳定基线保留，长期游玩仍待复测。下载文件名沿用原名称，通过 SHA256SUMS 区分更新。[此前 iOS 修复](docs/修复记录-20261019-r2.md) · [安卓热修复与对照记录](docs/安卓卡顿热修复-20261019.md)。

## 连接主力服

服务器地址：

```text
139.196.92.71
```

端口：

```text
9527
```

## 源码目录

| 路径 | 内容 |
| --- | --- |
| [`android/`](android/) | 当前 APK 对应的自定义 QML / Lua、Java 启动与下载源修复代码、辅助 DEX 与 APK 打包工具。 |
| [`pc/`](pc/) | 当前 Windows 完整包对应的自定义界面与记牌 / 好友模块、界面覆盖更新工具。 |
| [`src/`](src/)、[`runtime/`](runtime/)、[`ios/`](ios/) | 保留现有原生工程及 iOS 沙盒、运行时与平台适配。 |
| [`scripts/`](scripts/) | iOS 依赖构建、IPA 打包及校验脚本；详见 [iOS 工程说明](docs/iOS工程.md)。 |
| [`.github/workflows/`](.github/workflows/) | 现有 iOS 云端构建流程；Android / PC 暂无对应自动构建工作流。 |
| [`downloads/`](downloads/) | 分发文件校验清单；安装包放在 Releases。 |

仓库地址沿用早期 iOS 移植工程名称，首页、源码入口和 Releases 已按三端整理。

## 许可证与原项目

保留 [LICENSE](LICENSE) 与各源码文件、第三方组件的原有许可证和作者声明。原项目：[FreeKill](https://github.com/Qsgs-Fans/FreeKill)，核心游戏逻辑：[freekill-core](https://github.com/Qsgs-Fans/freekill-core)。本仓库为社区测试版，游戏服务器的规则和资源校验继续生效。

最新 iOS 记牌器大牌池滑动修正与验证范围见 [专项记录](docs/iOS记牌器滑动性能-20261020.md)；此项尚待 iPhone 真机复测。

2026-10-20 功能页持续卡顿修正见 [专项记录](docs/功能页卡顿检查-20261020.md)；本次 iOS 界面反馈及忠胆英杰牌池规则见 [后续反馈记录](docs/iOS后续界面反馈-20261020.md)。

记牌器实时更新保持位置、战报回看和好友会话开销的最新修正见 [2026-10-20 专项记录](docs/记牌器更新保持位置-20261020.md)。三端分发文件与校验清单已同步；长期实际游玩仍待持续复测。

iOS 武将牌标记仅记录首次数据的修正见 [专项记录](docs/iOS武将标记更新-20261020.md)。该次仅更新 iOS；2026-10-22 三端均已进一步同步房间入口与角色语音，已安装旧版需要覆盖更新。
