# 新月杀 iOS 端（新月杀测试版）

这是「新月杀测试版」的 iOS 移植工程，基于 FreeKill 0.5.25 的 C++/QML/Lua
客户端，并合入了与 Android/PC 测试版相同的运行时改动：

- 看破/私人标记数量显示（含旁观、回放）
- 好友列表、跟随观战（对局中/观战中 → 只发 `ObserveRoom`）
- 等待房间里的好友入口与位置修正（房主左侧、旁观聊天右侧）
- 菜单缩放时好友按钮逐帧跟随
- 专属称号【故剑遗】（黑金克苏鲁 QML 组件）
- card-counter 牌堆计数、社交模块等

运行时（`runtime/`）与 PC 分享包里的 `Fk`、`LunarLtk`、`card-counter`、
`packages`、`lua`、`ltk`、`audio`、`fonts`、`image` 是同一套文件；iOS 端只新增
C++ 启动适配和打包工程。

---

## ⚠️ 先看这一条：Windows 不能直接产出可安装的 IPA

iOS 应用必须用 **macOS + Xcode** 编译和签名。Windows 上没有 iOS SDK、
没有 `xcodebuild`、也没法给 IPA 签名，所以本机不能直接生成能装进 iPhone 的包。

这个目录里已经准备好了：

1. 完整的 iOS 工程（CMake + Qt 6.8.3 for iOS）
2. Lua / OpenSSL / libgit2 的 iOS 静态库构建脚本
3. 一条 GitHub Actions 流水线，在云端 macOS 上自动出 **未签名 IPA**
4. 在 Windows 上用 Sideloadly 签名安装的完整步骤

也就是说：**代码和流水线已经做完，最后只差在一个 macOS 环境里跑一次构建**。
**2026-10-17 更新：已在 GitHub Actions 的 macOS runner 上成功构建。**
本机下载的未签名 IPA：

```
deepseek/ios/apk/ios/新月杀测试版-0.5.25-ios-unsigned.ipa
SHA-256: a7209890b306c056e18fd820621433aed152b9b4cc4036f6a6dc44a7b3b49f5b
```

尚未在真机上运行验证；安装后如果有闪退/布局问题，把设备日志发回即可继续。

---

## 最简安装（推荐）

`apk/整合包/` 里已经放好 IPA、iTunes、Sideloadly 和一个一键脚本：

1. 双击 `apk/整合包/一键安装到iPhone.cmd`（需要管理员/UAC）；
2. 脚本自动安装 iTunes 和 Sideloadly，并打开 Sideloadly、把 IPA 路径放进剪贴板；
3. 连 iPhone、点“信任此电脑”；
4. 在 Sideloadly 里填免费 Apple ID（双重认证用 App 专用密码），点 Start；
5. iPhone 设置 → 通用 → VPN 与设备管理 → 信任证书。

苹果强制的 Apple ID 授权和“信任证书”无法脚本化，其余步骤已合并。
整合包只在本机，`apk/` 已在 `.gitignore` 中，不会上传 GitHub。

---

## 方式 A：GitHub Actions 云端构建（推荐，不需要自己有 Mac）

1. 在 GitHub 新建一个仓库（public/private 都行；public 的 macOS 分钟免费）。
2. 把 **本目录 `deepseek/ios/` 里的全部内容** 作为仓库根目录上传。
   - 注意：`.github/workflows/build-ios.yml` 必须在仓库根的
     `.github/workflows/` 下；本目录已经是这个结构。
3. 打开仓库的 **Actions → Build iOS (unsigned IPA) → Run workflow**。
4. 构建约 30–60 分钟，完成后在 run 页面下载 artifact
   **`xinyuesha-ios-unsigned`**，里面是：
   `新月杀测试版-0.5.25-ios-unsigned.ipa`
5. 在 Windows 上安装 Sideloadly（本目录 `apk/pc/` 已放好
   `iTunes64Setup.exe` 和 `SideloadlySetup64.exe`；先装 iTunes 再装 Sideloadly），
   USB 连接 iPhone：
   - 把 IPA 拖进 Sideloadly；
   - Apple ID 填自己的（免费账号即可）；
   - 点 Start，输入 Apple ID 密码（如开启双重认证，用专用密码）；
   - 首次安装后，iPhone → 设置 → 通用 → VPN 与设备管理 → 信任你的开发者证书。
6. 免费 Apple ID 的限制：**7 天过期、最多 3 个自签 app**；过期后用同样的
   IPA 重新签一次即可。付费开发者账号（$99/年）可 1 年有效。

> 如果 Sideloadly 提示需要卸载旧版本才能安装，卸载会一并删除
> `Documents/FreeKill`（账号、录像、皮肤）。重要数据请先在
> 「文件」App → 我的 iPhone → 新月杀测试版 → FreeKill 里备份。

> GitHub Actions 在中国大陆访问可能不稳定；如果拉取/上传很慢，可以改用
> 方式 B（自己的 Mac 或云 Mac），或先把本目录打包传到能访问 GitHub 的机器。

## 方式 B：自己的 Mac / 云 Mac

要求：macOS + Xcode（App Store 安装，至少 Xcode 15）、Homebrew、Python 3。

```bash
cd deepseek/ios
bash scripts/build_all_mac.sh
```

脚本会：

1. 用 `aqtinstall` 安装 Qt 6.8.3 for iOS（含 qtmultimedia / qt5compat /
   qtshadertools），以及配套的 macOS 桌面版 Qt 6.8.3（提供 moc / qsb /
   qmlcachegen 等交叉编译工具，CMake 变量 `QT_HOST_PATH`）；
2. 编译 Lua 5.4.8、OpenSSL 3.5.1、libgit2 1.9.7 的 arm64 静态库到 `ios-deps/`；
3. 用 Qt 的 `qt-cmake` + Xcode 生成并编译 `FreeKill.app`；
4. 打包 `build-ios/ipa/新月杀测试版-0.5.25-ios-unsigned.ipa`。

产物仍然是未签名的。两种安装方式：

- **Sideloadly / AltStore**（同方式 A）；
- **Xcode 直接装**：打开 `build-ios/FreeKill.xcodeproj`，在
  Signing & Capabilities 里选择自己的 Team，连接 iPhone 后 Run。
  这种方式不需要 Sideloadly，但需要有 Mac。

分步执行（调试用）：

```bash
bash scripts/build_deps.sh --prefix "$PWD/ios-deps"
bash scripts/build_ios.sh --qt "$HOME/Qt/6.8.3/ios" --deps "$PWD/ios-deps"
bash scripts/verify_app.sh "build-ios/.../FreeKill.app"
```

---

## 手机上的验收清单

1. 启动后横屏全屏，无闪退；首次启动会有几秒“复制运行时”，之后正常。
2. 登录主力服（139.196.92.71:9527）。
3. 进入等待房间：
   - 自己头像旁显示【故剑遗】称号；
   - 自己是房主时，好友按钮在「邀请玩家」**左侧**；
   - 旁观看不到邀请按钮时，好友按钮在「聊天」**右侧**；
   - 点菜单缩小/恢复时，好友按钮平滑跟随，不跳变。
4. 好友在对局中/观战中 → 好友行出现「跟随观战」，只旁观不发进入。
5. 旁观/回放时，看破等私人标记显示数量（不泄露牌名）。
6. 音频：背景音乐、技能音效、静音键拨到静音时仍有声音（Playback 类别）。
7. 聊天输入、中文键盘、横屏安全区（刘海/灵动岛）是否遮挡按钮。
8. 断线重连、录像回放、Spine 皮肤动画是否正常。

如果闪退或异常，请提供：

- iPhone 型号 + iOS 版本；
- Xcode → Window → Devices and Simulators → View Device Logs 里的崩溃日志；
- App 内 `freekill.server.log`（「文件」App → 我的 iPhone → 新月杀测试版 →
  FreeKill → `freekill.server.log`）。

---

## 目录结构

```
deepseek/ios/
├── CMakeLists.txt              # 顶层工程（iOS bundle / 资源 / QML 插件）
├── src/                        # FreeKill C++ 源码（含 iOS 启动补丁）
│   └── platform/ioshelper.mm   # AVAudioSession / 屏幕常亮 / 备份排除
├── thirdparty/                 # SoLoud + Lua 5.4.8 源码
├── runtime/                    # 与 PC 版一致的 QML/Lua/资源（会被打进 .app/res）
│   ├── Fk/ LunarLtk/ card-counter/ packages/ lua/ ltk/
│   ├── audio/ fonts/ image/ client/ server/ certs/ Spine/
│   └── *.qm fk_ver waiting_tips.txt
├── ios/
│   ├── Info.plist.in           # 包名、横屏、启动图、图标、局域网权限
│   ├── LaunchScreen.storyboard # 启动画面（深色底 + 标题）
│   ├── IosImports.qml          # 让 qmlimportscanner 链接静态 QML 插件
│   └── bundle/                 # AppIcon PNG（多尺寸）
├── scripts/
│   ├── build_deps.sh           # Lua + OpenSSL + libgit2（macOS）
│   ├── build_ios.sh            # 配置、编译、打包未签名 IPA
│   ├── build_all_mac.sh        # 一键 Mac 构建
│   └── verify_app.sh           # 打包前检查 .app 资源完整性
├── .github/workflows/build-ios.yml
├── apk/
│   ├── ios/                    # 手机端：IPA + sha256（仅本地）
│   ├── pc/                     # 电脑端：iTunes / Sideloadly（仅本地）
│   └── 整合包/                 # 一键安装：脚本 + IPA + 安装器（仅本地）
├── 安装说明.txt
└── docs/移植改动.md
```

---

## 版本与更新

- 版本号：`CMakeLists.txt` 的 `project(FreeKill VERSION 0.5.25)`，以及
  `runtime/fk_ver`（第一行 `0.5.25`）。
- 改 QML/Lua：直接改 `runtime/` 下对应文件，重新构建即可；首次启动/版本变化
  时 App 会把新运行时复制到 `Documents/FreeKill`。
- 改客户端 C++：改 `src/`，重新构建。
- 服务器地址、账号体系与 Android/PC 版完全一致；iOS 只是另一个客户端。

## 已知限制与风险

- **CI 已编译成功，尚未真机验证**：真机上的启动、QML 插件、Spine/Metal、
  安全区仍需要实测；请把设备日志发回。
- 最低 iOS 16.0（Qt 6.8.3 的要求）；只编 arm64 真机，不含模拟器。
- iOS 不允许后台常驻：切到后台一段时间后连接会断，回前台需重连。
- 免费签名 7 天过期；过期重签前先确认是否需要卸载（可能丢 Documents 数据）。
- Spine 骨骼使用 Qt RHI + Metal；`.qsb` 默认已包含 MSL 变体。若出现骨骼异常，
  可尝试在 Info.plist 增加 `QSG_RHI_BACKEND=opengl` 做 A/B（不保证 iOS 上
  仍支持 OpenGL ES）。
- 刘海/灵动岛安全区、iOS 键盘弹起时的布局，需要真机截图后再微调 QML。
- 不做 App Store 上架配置（没有 App Store 图标资产、隐私清单、审核材料）；
  当前目标是自签安装。若需要上架，另行补 Assets.car / PrivacyInfo.xcprivacy。

## 许可

FreeKill 本体为 GPL-3.0-or-later；本目录包含其源码与修改，整体按 GPL-3.0
分发。Spine 运行时代码、SoLoud、Lua、OpenSSL、libgit2 分别遵循各自许可证，
见 `thirdparty/` 与源码头部。
