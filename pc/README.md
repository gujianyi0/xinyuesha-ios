# Windows PC 测试版源码

`payload/` 中的 11 个文件来自本次 Windows 完整包，包含原版入口壳、记牌器、好友系统及显示适配。未把 Android 专用的 Java 下载源桥接直接复制到 PC。

首次使用从 Releases 下载 Windows 完整包并解压，运行“启动新月杀测试版.cmd”。

开发或手动应用此处界面源文件时，先关闭游戏，将目标指向包含 `FreeKill.exe` 的 `FreeKill-release` 目录：

```powershell
python pc/tools/apply_payload.py --game-dir "D:/新月杀测试版/FreeKill-release"
```

工具只覆盖此目录 `payload/` 中列出的文件，并保存被覆盖文件的备份；不触碰账号配置、好友资料或扩展包数据库。它不是完整的游戏安装器。
