# Android 测试版源码

`payload/` 与 2026-10-19 分发 APK 的自定义运行时文件逐项对应。`java/` 包含启动文件更新、Git 目录恢复和跨服务器下载源同步；不改动服务器校验或上传账号数据。

构建需要 Android SDK（API 36、Build Tools 36.0.0）、JDK 21，以及已下载的同包名测试版 APK 作为原生 Qt / 引擎基线。设置 `ANDROID_HOME` 和 `JAVA_HOME` 后：

```powershell
python android/tools/compile_helper.py
python android/tools/build_apk.py --baseline 测试版.apk --keystore 自己的密钥.p12 --storepass-file 密码文件 --output 新月杀测试版.apk
```

签名密钥与密码文件由构建者自行保管，不提交到 Git。使用不同密钥的构建不能直接覆盖他人原签名版本。

该工具重新打包自定义运行时和辅助 DEX，保留基线 APK 的 Qt 主 DEX、Manifest、原生库与游戏核心文件；完整原生引擎构建以原项目对应版本的构建说明为准。
