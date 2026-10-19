# Android 测试版源码

2026-10-19 对局、观战和出牌卡顿热修复见 [测试与修复记录](../docs/安卓卡顿热修复-20261019.md)。可用 Qt 6.8.3 执行 `python android/tools/test_gameplay_work.py --work-dir 测试输出目录`，验证普通游戏消息不触发好友状态重绑、对局停止全树扫描，并保留入口和弹窗生命周期。

`payload/` 与 2026-10-19 分发 APK 的自定义运行时文件逐项对应。`java/` 包含启动文件更新、Git 目录恢复和跨服务器下载源同步；不改动服务器校验或上传账号数据。

构建需要 Android SDK（API 36、Build Tools 36.0.0）、JDK 21，以及已下载的同包名测试版 APK 作为原生 Qt / 引擎基线。设置 `ANDROID_HOME` 和 `JAVA_HOME` 后：

```powershell
python android/tools/compile_helper.py
python android/tools/build_apk.py --baseline 测试版.apk --keystore 自己的密钥.p12 --storepass-file 密码文件 --output 新月杀测试版.apk
```

签名密钥与密码文件由构建者自行保管，不提交到 Git。使用不同密钥的构建不能直接覆盖他人原签名版本。

该工具重新打包自定义运行时和辅助 DEX，保留基线 APK 的 Qt 主 DEX、Manifest、原生库与游戏核心文件；完整原生引擎构建以原项目对应版本的构建说明为准。

## 背景图片兼容修复 · 2026-10-19

针对小米 14 更换图片后只有背景变白的反馈，`CounterBackgroundImages` 在 Qt 文件选择回调前读取相册 URI，将静态图片按 EXIF 方向转正、限制解码内存与纹理尺寸，并保存为应用目录中的普通 SDR PNG。Qt 获得持久文件 URI；读取失败时取消选择，保留原背景。GIF 与非图片选择保持原流程。

在指定的 Android 测试设备上执行真实图片测试：

```powershell
python android/tools/test_background_images.py --serial 设备序列号 --work-dir 测试输出目录
```

该脚本安装独立临时测试应用，测试结束仅卸载这个应用，不覆盖游戏。Android 35 模拟器已通过相册文档 URI、异步主线程回调、生成文件重新读取、EXIF、4000 万像素 PNG、5000 万像素采样上限及失败保留测试。完整游戏在该 x86 模拟器中旧包与新包均在原生启动阶段退出，未完成游戏内选图及重启验收；小米 14 真机复测待完成。
