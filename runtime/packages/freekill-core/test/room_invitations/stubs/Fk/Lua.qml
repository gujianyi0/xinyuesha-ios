pragma Singleton
import QtQuick
QtObject {
  function tr(key) {
    const values = {
      "Invite Players": "邀请玩家", "Invite": "邀请", "Inviting...": "发送中…", "Invited (%1s)": "已邀请（%1秒）",
      "Online players in the lobby · updates automatically": "大厅在线玩家 · 名单实时更新",
      "Drag the header to move · invite again after 5 seconds": "拖动标题可移动窗口 · 每隔5秒可再次邀请",
      "No players available to invite": "暂无可邀请的玩家", "Room Invitation": "房间邀请",
      "%1 invites you to a room": "%1 邀请你加入房间", "Room: %1": "房间：%1", "Mode: %1": "模式：%1",
      "Join directly if a seat is available; otherwise spectate.": "有空位时直接加入；没有空位则进入旁观。",
      "Decline": "拒绝", "OK": "确定", "test_22": "欢乐2v2",
      "Block all room invitations": "屏蔽所有房间邀请"
    };
    return values[key] || key;
  }
}
