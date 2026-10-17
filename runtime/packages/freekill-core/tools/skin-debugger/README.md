# 皮肤骨骼调试器

独立窗口复用 FreeKill 已内置的 Spine 引擎，预览、拖动和缩放骨骼皮肤，复制皮肤系统可直接使用的 `extra_data`。不需要安装 Qt SDK，也不需要重新编译客户端。普通启动仍进入游戏；带 `--skin-debugger` 时只加载调试窗口，不加载大厅或牌桌页面。

## 打开

Windows 双击本目录的 **启动调试器.cmd**。本地发布目录还提供 **皮肤骨骼调试器.cmd** / **皮肤骨骼调试器.lnk**。

也可以在 FreeKill 游戏目录运行：

```powershell
.\FreeKill.exe --skin-debugger
```

启动脚本默认按 `游戏目录/packages/freekill-core/tools/skin-debugger` 的位置定位游戏；工具被放在其他位置时，可执行：

```powershell
.\Start-SkinDebugger.ps1 -GameRoot 'C:/Games/FreeKill'
```

需要包含 `Spine` 模块及其加载完成信号的客户端；当前本地客户端已验证。编辑器不会转换骨骼格式或增添客户端尚未支持的 Spine 版本。

## 调整皮肤

1. 选择皮肤文件夹，或拖入 `.skel` / Spine `.json` 文件。图集 `.atlas` 和它引用的所有 PNG 应保持原目录结构；多页图集无需逐张导入。
2. 文件夹会按 `BeiJing` / `beijing`、`XingXiang` / `daiji`、`QianJing` 等名称识别背景、人物、前景。单个无法识别名称的文件放入选中层。多个不确定的文件不会随意分配，可选中目标层后分别打开。
3. 图集默认使用与骨骼同名的 `.atlas`；名字不一致时点击“指定图集”。直接修改路径也可加载。
4. 选择立绘框预设，然后选中图层，拖动移动，滚轮缩放。方向键移动 1 个立绘框像素，按住 Shift 移动 10 像素。右侧可直接输入小数。背景、人物和前景独立调整。
5. 版本和动画列表会自动读取，待机 / 出场下拉框显示动画名与时长，也可手动填写名称（区分大小写）。新导入素材优先识别常见待机和出场名称；恢复工程或导入参数会保留指定名称。待机留空显示默认姿势。支持暂停、重播、出场后接待机、骨骼线和取消裁剪查看框外部分。
6. 点击“复制 extra_data”，用于皮肤注册条目的 `extra_data`，保留原来的皮肤名、武将、下载地址和 `files` 列表。已有配置还含其他字段时，仅更新同名参数，保留其他字段。

“预览倍率”只影响调试窗口显示大小，不写入配置。“渲染比例”对应 `render_scale`，按游戏公式补偿最终大小，不等同于人物缩放。

位置为比例：`x_offset` 以框宽为 1，`y_offset` 以框高为 1，0.5 是中点；允许负数和超过 1 的值。导出明确的 `bg_*`、`body_*`、`front_*` 字段；临时隐藏图层只影响预览，不会悄悄删除导出配置。

## 攻击、技能、受伤动画

每层都可设置攻击、技能、受伤动画并点击“试播”。三个字段均可留空，空值表示不播放，不会拿出场动画替代。试播会同步触发所有可见且配置了该动作的图层；播放一次后恢复各层待机。暂停状态下动作也暂停，点击“继续”即可播放。

对应的皮肤配置为 `attack_anim`、`skill_anim`、`hurt_anim`；单层可用 `bg_*`、`body_*`、`front_*` 覆盖。单层空字符串同样优先，可禁用从通用字段继承的动作。旧的 `special_anim` / `*_special_anim` 作为技能动画别名保留，明确的 `skill_anim` / `*_skill_anim` 优先。

游戏内触发规则：

- 攻击：使用标记为 `is_damage_card` 的伤害牌，通过客户端收到的实际用牌日志触发，支持实体牌及虚拟/转化牌；不会在选择牌、打出响应牌或仅显示目标线时误触发。
- 技能：收到普通技能或大招发动通知时触发。
- 受伤：收到伤害通知时触发；单纯失去体力不触发。

播放优先级为受伤 > 技能 > 攻击。低优先级动作不打断正在播放的高优先级动作；同级或更高优先级的新动作替换旧动作，不累计排队。没有对应动画的图层维持原来的动作。默认界面及 OL/十周年界面均接入相同的皮肤播放接口，服务端/asio 不需要增加协议。

独立的受击特效骨骼可以导入前景层：把该层的待机、出场留空，仅设置受伤动画。此时该层平时隐藏，只在受伤时播放一次，结束后再次隐藏。文件夹导入可识别 `ShouJi` / `hurt` 等受击文件名并放入前景；其他无法识别的文件仍需手动指定。

例如“帝皇铠甲”素材：人物 `DiHuangXiaCaoCao_LiHui_XingXiang.skel` 包含 `ChuChang`、`DaiJi`、`GongJi`；`DiHuangXiaCaoCao_ShouJi.skel` 的受击动作为 `play`。人物放在 body、受击特效放在 front 时，可使用：

```lua
extra_data = {
  body_normal_anim = "DaiJi",
  body_shown_anim = "ChuChang",
  body_attack_anim = "GongJi",
  body_skill_anim = "",
  body_hurt_anim = "",
  front_normal_anim = "",
  front_shown_anim = "",
  front_attack_anim = "",
  front_skill_anim = "",
  front_hurt_anim = "play",
  -- 位置与缩放继续使用调试器导出的各层参数。
},
```

皮肤注册条目的 `body`、`front` 和 `files` 仍需正确指定骨骼、图集及所有贴图文件。该示例素材没有独立的技能动作，所以默认留空；如确实要复用攻击动作作为技能动作，可自行将技能字段设为 `GongJi`。

## 自动入框

选中已加载的图层后，可以使用：

- **首帧入框**：使用当前选择的待机动画在 0 秒的姿势；待机留空时使用默认姿势。这不是任意播放时刻的截图适配。
- **整段动画入框**：按 30 帧/秒采样待机动画，合并范围后一次性调整位置和缩放。启用“重播时含出场”且填写了出场动画时，同时测量出场与待机。动画结束帧也纳入采样。

勾选“入框时包含战斗动作”后，整段测量也会计入已配置的攻击、技能、受伤动作。默认不勾选，避免大幅位移的攻击或全屏特效把正常立绘缩得过小。只在事件中显示的图层会直接测量其配置的动作。

“入框留白”以实际立绘框像素计算，默认 4 像素。操作只调整选中层，可以撤销和重做；背景、人物、前景仍可分别手动微调，不会改变预览倍率或其他图层。

范围取自与游戏相同后端生成的附件顶点，排除完全透明的绘制批。范围包含图片本身的透明边缘；采样不是连续时间的精确极值，也不代表按非透明像素进行抠图。入框后可播放检查飘带、粒子等效果，再微调留白。单个动画超过 300 秒时会提示改用首帧适配。测量在后台执行；切换素材、图层或调整参数后，旧结果不会覆盖新的设置。

## 检测模块与构建

版本、动画时长和入框范围由调试器专用的 `native/SkinInspector` 模块提供，读取独立骨骼实例，不改变预览中的播放状态。模块按版本复用 FreeKill 的后端和九个 Spine 运行库，读取和采样均不依赖 SpineViewer、REA 或 .NET。最终画面继续由客户端原生 Spine 引擎绘制。

随包附带 Windows x64 / Qt 6.9.1 MinGW 构建的 `skininspector.dll`。Qt 运行时须与插件兼容；其他系统或不兼容的客户端可使用匹配工具链构建。模块不可用时，界面会提示，手动填写动画、拖动、缩放和参数导出仍可使用。常规使用不需要 Qt SDK。

模块源码位于 `tools/skin-debugger/native`。开发者可用 PowerShell 7、CMake、Qt 和 MinGW 构建：

```powershell
.\Build-Inspector.ps1 -FreeKillSource 'C:/dev/FreeKill' -QtRoot 'C:/Qt/6.9.1/mingw_64' -CompilerBin 'C:/Qt/Tools/mingw1310_64/bin'
```

构建脚本只读取 FreeKill 源码，将后端副本放入独立构建目录，增加动画元数据访问后编译；不改原源码，也不重编或替换游戏主程序。输出模块和第三方声明复制到 core 的 `Fk/Tools/SkinDebugger/native/SkinInspector`，随 core 一起分发。原生模块使用到的原始后端和运行库源码来自指定的 FreeKill 源码目录；修改底层后端后应重新构建模块。

## 复用已有配置

“导入参数”接受已有的 `extra_data = { ... }` 或 JSON 对象，包括通用 `scale` / `x_offset` / `y_offset` 与各图层独立字段。独立字段优先，值为 0 时也不会被通用值覆盖。仅解析数字、字符串及受支持的字段，不执行 Lua 表达式。

“复制工程”额外保存骨骼和图集的本机路径、图层参数及立绘框宽高、圆角。将 JSON 保存为文本，下次用“恢复工程”粘贴即可接着调整。工程使用本机绝对路径，移动素材后应重新指定文件。

导入参数针对当前已加载的图层，不会自动下载或改写素材。当前直接编辑三个主骨骼图层；不直接预览 `extra_bg` / `extra_front` 列表或 `static_bg`。这些字段和其他未编辑字段需在原皮肤注册条目中保留，不能被精简的导出配置覆盖。

## 与游戏保持一致

沿用 `LunarLtk/Components/Photo/SkinArea.qml` 的原点、`SpineVersion.Auto`、非预乘 Alpha 和缩放规则：

```text
x = frameWidth * x_offset
y = frameHeight * y_offset
scale = layer_scale * frameHeight / render_scale / 175
```

裁剪预设来自实际立绘区域：默认界面 103×166（圆角 6）、OL 136×157、十周年 172×227（圆角 8）。这些是立绘区域的尺寸，不含外框、名字栏和状态图标；其他布局或双将半幅可自行输入实际宽高。预览采用与游戏相同的超采样及蒙版路径，放大调试时仍保持清晰。

界面和工具模块位于 `Fk/Tools/SkinDebugger`，通过 core 发布；`Fk/main.qml` 负责独立入口。客户端源码及正式骨骼渲染路径不需要改动。

## 验证

`test/skin_debugger/` 仅保留在制作者本地，由 `.gitignore` 排除，不随仓库分发。以下自动测试需先取得该目录；普通游戏、皮肤动画和调试器日常使用不依赖它。`Fk/Tools/SkinDebugger` 调试器本体继续正常分发。

数据转换 / 导入导出检查：

```powershell
node test/skin_debugger/geometry_test.cjs
node test/skin_debugger/event_routing_test.cjs
python test/skin_debugger/client_actions_test.py
```

有 Qt SDK 时，分别运行交互与普通启动入口测试。交互测试中的 Spine 为测试替身，只验证编辑器操作；原生测试另行验证真实骨骼加载和动画：

```powershell
qmltestrunner -input test/skin_debugger/tst_editor.qml -import test/skin_debugger/imports
qmltestrunner -input test/skin_debugger/tst_actions.qml -import test/skin_debugger/imports
qmltestrunner -input test/skin_debugger/tst_inspector.qml
$env:QML_XHR_ALLOW_FILE_READ = '1'
qmltestrunner -input test/skin_debugger/tst_skin_area.qml -import test/skin_debugger/imports
qmltestrunner -input test/skin_debugger/tst_entry.qml -import test/skin_debugger/entry-imports
```

`tst_inspector.qml` 使用真实检测模块和本机谋庞统缓存，验证版本、动画时长、首帧/整段范围、错误提示和新请求覆盖旧请求；没有该素材时需先准备对应缓存。

本机已缓存谋庞统“玉帛雕翎”时，在游戏目录运行以下命令可自动验证原生加载、动画、文件夹识别、动画列表、自动入框、导出、撤销 / 重做和工程往返，完成后退出：

```powershell
.\FreeKill.exe --skin-debugger --skin-debugger-smoke-test
```

测试数据是本机现有骨骼素材，未随工具复制或打包。

`client_actions_test.py` 使用游戏目录中的 Windows `lua54.dll`，只在隔离环境执行实际的用牌日志处理函数。`event_routing_test.cjs` 检查实际事件路由、参数映射与两套界面的接口；需要旁边存在 `lunarltk-qsgs-ui` 仓库。`tst_actions.qml` 和 `tst_skin_area.qml` 使用骨骼测试替身；真实动作另用本机素材验证：

```powershell
.\FreeKill.exe --skin-debugger --skin-debugger-action-test '--skin-debugger-action-assets=C:/path/to/帝皇铠甲'
```

该测试核对实际游戏骨骼封装和调试器的攻击播放、回待机、空动作、受伤层显隐、优先级、导出和工程往返，不启动对局。普通启动不加载测试代码。
