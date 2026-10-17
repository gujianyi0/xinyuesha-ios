# 房间邀请客户端验证

房间邀请由支持 `RoomInvitations` 的 asio 服务端提供。等待室右下操作栏使用现有绿色按钮，对局使用现有 `MetroButton`，并预留 68 像素底部操作带，包含自己立绘、座次文字、光晕、手牌和技能的边界；其他 UI 包未提供 `roomInviteButton` 时，由公共 `RoomPage` 在场景外预留 52 像素页脚提供入口。UI 包自定义按钮应发出 `invitePlayersRequested()` 信号。

菜单展开时只隐藏公共按钮，不改变场景高度。尺寸或邀请资格变化后，通用调用现有手牌区域的重新定位接口，使直接挂在场景下的手牌与容器同步移动。旁观、旧服务端或单机不预留邀请空间。

`RoomInvites` 保存当前服务器会话状态，账号的屏蔽偏好以服务器 `RoomInviteSettings` 为准，不写入全局配置。新服务器初始化、换账号和退出到启动页时清空；登录成功进入大厅的 `App.backToStart(true)` 只清理旧页面，保留先前收到的邀请能力和屏蔽偏好；同账号旁观切换带来的 `Setup` 保留偏好与支持状态；进入房间清除待处理邀请。邀请只发送给大厅在线且未屏蔽的玩家，仅有座位的房间玩家可以发起，旁观、单机、录像不能发起。

打开邀请窗订阅名单，关闭即取消订阅。服务器推送变化，客户端不循环请求玩家列表。成功邀请后按服务器返回的剩余时间显示“已邀请”，5 秒后可重邀。邀请过期、撤销或屏蔽后关闭弹窗；多个邀请依次展示。确认时使用按下按钮时的 token，避免服务器替换邀请时误接受另一条邀请。

接受邀请后的加入/满员旁观由服务端决定，复用客户端已有 `EnterRoom` / `Observe` 路径。客户端不提前假定空位，不尝试自行绕过房间校验。

## 隔离测试

测试不会连接服务器、读取账号数据库、发送真实邀请或写游戏录像。QML 测试从当前仓库复制真实组件到临时目录，替换客户端桥接单例，并用无动画的 Spine 占位模块检查完整房间类型导入（不验证骨骼渲染）；输出目录保存截图和日志，临时副本在运行后清理。

```powershell
python test/room_invitations/run_qml_tests.py --qt-bin C:/Qt/6.9.1/mingw_64/bin --output C:/Temp/room-invitation-test
python test/room_invitations/run_lua_tests.py
```

QML 验证实时名单、5 秒重邀、接受与拒绝、队列、重复消息、撤销、过期、按下期间替换 token、屏蔽与恢复、保存失败及超时、断线与账号初始化、旧服务端/单机/录像/旁观限制、拖动窗口、50 人滚动列表、设置页载入。实际 RootPage、RoomPage、WaitingRoom 与默认 Room 的类型导入也会检查。截图为 `invite-list.png`、`invitation-prompt.png`、`control-setting.png`。

登录回归提取真实 `Init.enterLobby` 回调，调用真实 `AppUtil` 与 `Mediator`，按 asio 的 `Setup → SetServerSettings → RoomInviteSettings → EnterLobby` 顺序检查清理页面后账号偏好仍在、游戏控制开关可用、进入房间可邀请；实际退出和网络断开仍清空状态。

Lua 测试验证真实 `ClientCallback` 对邀请消息的转发、录像排除与回放拦截，并检查修改的 Lua 文件语法。完整双客户端互邀、满员旁观、账号持久化仍需与新版 asio 联调。
