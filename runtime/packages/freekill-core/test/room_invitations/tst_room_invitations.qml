import QtQuick
import QtQuick.Controls
import QtTest
import Fk
import Fk.Pages.Common
import Fk.Pages.Lobby

Rectangle {
  id: scene
  width: 1000; height: 700
  color: "#e4ece7"
  FontLoader { id: cjkFont; source: "file:///C:/Windows/Fonts/msyh.ttc" }
  RoomInviteDialog { id: listDialog }
  RoomInvitationPrompt { id: prompt }
  LobbyEntry { id: lobbyEntry }
  Component { id: settingsComponent; ControlSetting { width: 600; height: 600 } }

  TestCase {
    name: "RoomInvitations"
    when: windowShown
    function init() {
      listDialog.close(); prompt.close();
      RoomInvites.reset(); Cpp.calls = []; App.toasts = [];
      Config.consoleStartRequested = false; Config.replaying = false; Config.observing = false;
      RoomInvites.handle("RoomInviteSettings", { supported: true, blocked: false });
    }
    function cleanup() { listDialog.close(); prompt.close(); RoomInvites.reset(); }
    function notification(token, expiresInMs) {
      return { token: token, inviterName: "凤焰龙吟", roomName: "朋友开黑，一起玩", mode: "test_22", expiresInMs: expiresInMs || 60000 };
    }
    function onlinePlayers() {
      return [{ id: 11, name: "风焰龙吟" }, { id: 12, name: "一生挚爱" }, { id: 13, name: "星河旅人" }];
    }
    function openList() {
      RoomInvites.setRoom(true);
      listDialog.open();
      RoomInvites.handle("RoomInvitePlayers", { players: onlinePlayers() });
      wait(100);
    }
    function test_01_live_list_and_subscription() {
      openList();
      verify(listDialog.opened);
      compare(Cpp.calls[0].command, "SubscribeRoomInvites"); compare(Cpp.calls[0].data, true);
      const list = findChild(listDialog, "roomInvitePlayerList");
      compare(list.count, 3);
      RoomInvites.handle("RoomInvitePlayers", { players: [{ id: 12, name: "一生挚爱" }] });
      compare(list.count, 1);
      listDialog.close();
      compare(Cpp.calls[Cpp.calls.length - 1].command, "SubscribeRoomInvites");
      compare(Cpp.calls[Cpp.calls.length - 1].data, false);
      RoomInvites.handle("RoomInvitePlayers", { players: onlinePlayers() });
      compare(RoomInvites.players.length, 0);
    }
    function test_02_invite_cooldown_and_button() {
      openList();
      const list = findChild(listDialog, "roomInvitePlayerList");
      const button = findChild(list.itemAtIndex(0), "invitePlayer_11");
      verify(button !== null);
      mouseClick(button);
      compare(Cpp.calls[1].command, "InviteRoomPlayer"); compare(Cpp.calls[1].data, 11);
      verify(!button.enabled);
      RoomInvites.invite(11); compare(Cpp.calls.length, 2);
      RoomInvites.handle("RoomInviteResult", { playerId: 11, ok: true, retryAfterMs: 5000 });
      verify(button.text.includes("已邀请")); verify(!button.enabled);
      RoomInvites.cooldowns = ({ "11": Date.now() - 1 });
      RoomInvites.advanceClock();
      compare(RoomInvites.remaining(11), 0); verify(button.enabled);
      RoomInvites.invite(11); compare(Cpp.calls.length, 3);
      RoomInvites.handle("RoomInviteResult", { playerId: 11, ok: false, error: "请稍后再试", retryAfterMs: 2300 });
      verify(RoomInvites.remaining(11) >= 2); verify(!button.enabled);
    }
    function test_03_decline_accept_and_plain_text() {
      RoomInvites.handle("RoomInvitation", notification("first"));
      tryCompare(prompt, "opened", true);
      mouseClick(findChild(prompt, "declineRoomInvitation"));
      compare(Cpp.calls.length, 1); compare(Cpp.calls[0].data.accept, false);
      compare(Cpp.calls[0].data.token, "first");
      tryCompare(prompt, "visible", false);
      const message = notification("second"); message.inviterName = "<b>literal player</b>";
      RoomInvites.handle("RoomInvitation", message);
      tryCompare(prompt, "opened", true);
      mouseClick(findChild(prompt, "acceptRoomInvitation"));
      compare(Cpp.calls[1].data.accept, true); compare(Cpp.calls[1].data.token, "second");
      compare(RoomInvites.invitations.length, 0);
    }
    function test_04_expiry_closed_queue_and_enter_room() {
      RoomInvites.handle("RoomInvitation", notification("one"));
      RoomInvites.handle("RoomInvitation", notification("two"));
      RoomInvites.handle("RoomInvitation", notification("two"));
      compare(RoomInvites.invitations.length, 2);
      RoomInvites.handle("RoomInvitationClosed", { token: "one" });
      compare(RoomInvites.currentInvitation.token, "two");
      RoomInvites.invitations = [Object.assign({}, RoomInvites.currentInvitation, { expiresAt: Date.now() - 1 })];
      RoomInvites.advanceClock();
      compare(RoomInvites.invitations.length, 0); compare(Cpp.calls.length, 0);
      RoomInvites.handle("RoomInvitation", notification("three"));
      RoomInvites.setRoom(true);
      compare(RoomInvites.invitations.length, 0);
      RoomInvites.handle("RoomInvitation", notification("four"));
      compare(RoomInvites.invitations.length, 0);
    }
    function test_05_block_setting_authority_and_reset() {
      RoomInvites.handle("RoomInvitation", notification("blocked"));
      RoomInvites.setBlocked(true);
      compare(Cpp.calls[0].command, "SetRoomInviteBlocked"); compare(Cpp.calls[0].data, true);
      compare(RoomInvites.blocked, false); verify(RoomInvites.settingPending);
      RoomInvites.handle("RoomInviteSettings", { supported: true, blocked: true });
      verify(RoomInvites.blocked); verify(!RoomInvites.settingPending);
      compare(RoomInvites.invitations.length, 0);
      RoomInvites.handle("RoomInvitation", notification("ignored")); compare(RoomInvites.invitations.length, 0);
      RoomInvites.setBlocked(false);
      RoomInvites.handle("RoomInviteSettings", { supported: true, blocked: false });
      RoomInvites.handle("RoomInvitation", notification("received")); compare(RoomInvites.invitations.length, 1);
      RoomInvites.reset(); verify(!RoomInvites.blocked); verify(!RoomInvites.supported);
      compare(RoomInvites.invitations.length, 0);
    }
    function test_06_network_guards() {
      RoomInvites.setRoom(true);
      Config.consoleStartRequested = true;
      RoomInvites.subscribe(true); RoomInvites.invite(11); RoomInvites.setBlocked(true);
      compare(Cpp.calls.length, 0);
      Config.consoleStartRequested = false; Config.replaying = true;
      RoomInvites.subscribe(true); RoomInvites.setBlocked(true);
      compare(Cpp.calls.length, 0);
      Config.replaying = false; RoomInvites.supported = false;
      RoomInvites.subscribe(true); compare(Cpp.calls.length, 0);
      RoomInvites.supported = true; Config.observing = true;
      RoomInvites.subscribe(true); compare(Cpp.calls.length, 0);
    }
    function test_07_drag_scroll_and_render() {
      openList();
      const header = findChild(listDialog, "roomInviteDragArea");
      const originalX = listDialog.x; const originalY = listDialog.y;
      mouseDrag(header, 60, 12, 120, 70);
      verify(listDialog.x > originalX + 50); verify(listDialog.y > originalY + 30);
      const many = [];
      for (let i = 0; i < 50; ++i) many.push({ id: 100 + i, name: "大厅玩家 " + (i + 1) });
      RoomInvites.handle("RoomInvitePlayers", { players: many });
      const list = findChild(listDialog, "roomInvitePlayerList");
      compare(list.count, 50); verify(list.contentHeight > list.height);
      list.contentY = 300; verify(list.contentY > 0);
      RoomInvites.handle("RoomInvitePlayers", { players: onlinePlayers() });
      list.contentY = 0; listDialog.x = 290; listDialog.y = 115;
      RoomInvites.handle("RoomInviteResult", { playerId: 11, ok: true, retryAfterMs: 5000 });
      wait(100);
      grabImage(scene).save("@OUTPUT@/invite-list.png");
      listDialog.close(); RoomInvites.setRoom(false);
      RoomInvites.handle("RoomInvitation", notification("preview"));
      tryCompare(prompt, "opened", true);
      wait(100); grabImage(scene).save("@OUTPUT@/invitation-prompt.png");
    }
    function test_08_replaced_invitation_during_pointer_press() {
      RoomInvites.handle("RoomInvitation", notification("old-token"));
      tryCompare(prompt, "opened", true);
      const button = findChild(prompt, "acceptRoomInvitation");
      mousePress(button);
      compare(button.invitationToken, "old-token");
      RoomInvites.handle("RoomInvitationClosed", { token: "old-token" });
      RoomInvites.handle("RoomInvitation", notification("replacement-token"));
      mouseRelease(button);
      compare(Cpp.calls.length, 0);
      compare(RoomInvites.currentInvitation.token, "replacement-token");
      mouseClick(button);
      compare(Cpp.calls[0].data.token, "replacement-token");
      compare(Cpp.calls[0].data.accept, true);
    }
    function test_09_settings_failure_and_timeout() {
      RoomInvites.setBlocked(true);
      RoomInvites.handle("RoomInviteSettings", { supported: true, blocked: false, ok: false, error: "数据库暂不可写" });
      verify(!RoomInvites.settingPending); verify(!RoomInvites.blocked);
      compare(App.toasts[0], "数据库暂不可写");
      RoomInvites.setBlocked(true);
      RoomInvites.settingDeadline = Date.now() - 1;
      RoomInvites.advanceClock();
      verify(!RoomInvites.settingPending); verify(!RoomInvites.blocked);
      compare(App.toasts.length, 2);
    }
    function test_10_mediator_login_room_and_disconnect() {
      // Force the actual Mediator singleton to connect to the isolated backend.
      verify(Mediator !== null);
      Backend.notifyUI("SetServerSettings", ["motd", [], ["RoomInvitations"]]);
      verify(RoomInvites.supported);
      Backend.notifyUI("Setup", [21, "Alice", "caocao"]);
      Backend.notifyUI("RoomInviteSettings", { supported: true, blocked: true });
      verify(RoomInvites.blocked);
      Backend.notifyUI("Setup", [21, "Alice", "caocao"]);
      verify(RoomInvites.supported); verify(RoomInvites.blocked);
      Backend.notifyUI("EnterRoom", []); verify(RoomInvites.inRoom);
      Backend.notifyUI("Setup", [21, "Alice", "caocao"]);
      verify(RoomInvites.inRoom); verify(RoomInvites.canInvite); verify(RoomInvites.blocked);
      Backend.notifyUI("EnterLobby", []); verify(!RoomInvites.inRoom);
      Backend.notifyUI("Setup", [22, "Bob", "liubei"]);
      verify(!RoomInvites.supported); verify(!RoomInvites.blocked);
      Backend.notifyUI("RoomInviteSettings", { supported: true, blocked: false });
      Backend.notifyUI("RoomInvitation", notification("disconnect"));
      compare(RoomInvites.invitations.length, 1);
      Mediator.notify(null, "BackToStart", []);
      verify(!RoomInvites.supported); verify(!RoomInvites.blocked);
      compare(RoomInvites.invitations.length, 0);
      Backend.notifyUI("SetServerSettings", ["old", [], []]);
      verify(!RoomInvites.supported);
      Backend.notifyUI("Setup", []); verify(!RoomInvites.supported);
    }
    function test_11_integrated_component_load() {
      for (const path of ["Fk/Base/RootPage.qml", "Fk/Pages/Common/RoomPage.qml", "Fk/Pages/Common/WaitingRoom.qml", "LunarLtk/Pages/Room.qml"]) {
        const component = Qt.createComponent("file:///@CORE@/" + path, Component.PreferSynchronous);
        if (component.status === Component.Loading) tryCompare(component, "status", Component.Ready);
        compare(component.status, Component.Ready, component.errorString());
      }
    }
    function test_12_card_relayout_for_ui_packages() {
      let cards = 0, expanded = 0;
      const room = { dashboard: { handcardArea: {
        updateCardPosition: function(animated) { verify(animated); cards++; },
        updateMiscExpandPosition: function(animated) { verify(animated); expanded++; }
      } } };
      RoomInvites.refreshHandcards(room);
      compare(cards, 1); compare(expanded, 1);
      RoomInvites.refreshHandcards(null);
      RoomInvites.refreshHandcards({});
      RoomInvites.refreshHandcards({ dashboard: { handcardArea: {} } });
      compare(cards, 1); compare(expanded, 1);
    }
    function test_13_control_setting_component() {
      const settings = createTemporaryObject(settingsComponent, scene, { x: 200, y: 40 });
      verify(settings !== null);
      const row = findChild(settings, "blockRoomInvitationsSetting");
      verify(row !== null); verify(row.enabled);
      settings.contentY = Math.max(0, settings.contentHeight - settings.height);
      wait(50);
      const toggle = row.suffixLoader.item;
      verify(toggle !== null);
      mouseClick(toggle);
      verify(RoomInvites.settingPending); compare(Cpp.calls[0].data, true);
      RoomInvites.handle("RoomInviteSettings", { supported: true, blocked: false, ok: false, error: "保存失败" });
      verify(!toggle.checked); verify(row.enabled);
      mouseClick(toggle);
      RoomInvites.handle("RoomInviteSettings", { supported: true, blocked: true });
      verify(row.enabled); verify(RoomInvites.blocked); verify(toggle.checked);
      wait(250); grabImage(scene).save("@OUTPUT@/control-setting.png");
    }
    function test_14_real_lobby_entry_keeps_authenticated_invites() {
      // Match asio's actual order: Setup -> settings -> preferences -> EnterLobby.
      verify(Mediator !== null);
      Backend.notifyUI("Setup", [21, "Alice", "caocao"]);
      Backend.notifyUI("SetServerSettings", ["motd", [], ["RoomInvitations"]]);
      Backend.notifyUI("RoomInviteSettings", { supported: true, blocked: true });
      Backend.notifyUI("EnterLobby", []);
      lobbyEntry.enterLobby(null, []);
      verify(RoomInvites.networkEnabled);
      verify(RoomInvites.blocked);
      compare(RoomInvites.accountId, 21);
      compare(Config.lastLoginServer, Config.serverAddr);
      const settings = createTemporaryObject(settingsComponent, scene);
      verify(findChild(settings, "blockRoomInvitationsSetting").enabled);
      Backend.notifyUI("EnterRoom", []);
      verify(RoomInvites.canInvite);
      // Leaving the account still clears all state through the real App helper.
      SessionApp.backToStart();
      verify(!RoomInvites.supported);
      verify(!RoomInvites.blocked);
      compare(RoomInvites.accountId, 0);
      Backend.notifyUI("RoomInviteSettings", { supported: true, blocked: false });
      Backend.notifyUI("BackToStart", []);
      verify(!RoomInvites.supported);
    }
  }
}
