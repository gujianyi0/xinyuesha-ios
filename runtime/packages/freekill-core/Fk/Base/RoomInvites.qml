// SPDX-License-Identifier: GPL-3.0-or-later
pragma Singleton
import QtQuick

QtObject {
  id: root
  // Account preferences are authoritative on the server, never saved in Config.conf.
  property int accountId: 0
  property bool supported: false
  property bool blocked: false
  property bool settingPending: false
  property bool inRoom: false
  property bool subscribed: false
  property var players: []
  property var cooldowns: ({})
  property var pendingPlayers: ({})
  property var invitations: []
  property string listError: ""
  property double clock: Date.now()
  readonly property bool networkEnabled: supported && !Config.consoleStartRequested && !Config.replaying
  readonly property bool canInvite: networkEnabled && inRoom && !Config.observing
  readonly property var currentInvitation: invitations.length ? invitations[0] : null

  property Timer tick: Timer {
    interval: 200
    repeat: true
    running: root.subscribed || root.invitations.length > 0 || root.settingPending
    onTriggered: root.advanceClock()
  }
  property double settingDeadline: 0

  function reset() {
    accountId = 0; supported = false; blocked = false; settingPending = false;
    inRoom = false; subscribed = false; players = []; invitations = [];
    cooldowns = ({}); pendingPlayers = ({}); listError = "";
  }

  function advanceClock() {
    clock = Date.now();
    const active = invitations.filter(item => item.expiresAt > clock);
    if (active.length !== invitations.length) invitations = active;
    const pending = Object.assign({}, pendingPlayers);
    let changed = false;
    for (const id of Object.keys(pending)) {
      if (pending[id] <= clock) { delete pending[id]; changed = true; }
    }
    if (changed) pendingPlayers = pending;
    if (settingPending && clock >= settingDeadline) {
      settingPending = false;
      App.showToast(Lua.tr("Room invitation settings timed out"));
    }
  }

  function setRoom(value) {
    if (!value) subscribe(false);
    inRoom = value;
    invitations = [];
  }

  function subscribe(value) {
    if (value && !canInvite) return;
    if (subscribed === value) return;
    subscribed = value;
    if (value) advanceClock();
    if (networkEnabled) Cpp.notifyServer("SubscribeRoomInvites", value);
    if (!value) { players = []; listError = ""; }
  }

  function remaining(id) {
    return Math.max(0, Math.ceil(((cooldowns[String(id)] || 0) - clock) / 1000));
  }

  function refreshHandcards(room) {
    // Some UI packages parent card objects to the scene instead of their hand area.
    const hand = room?.dashboard?.handcardArea;
    if (!hand) return;
    if (typeof hand.updateCardPosition === "function") hand.updateCardPosition(true);
    if (typeof hand.updateMiscExpandPosition === "function") hand.updateMiscExpandPosition(true);
  }

  function invite(id) {
    advanceClock();
    id = Math.floor(id);
    if (!canInvite || remaining(id) || pendingPlayers[String(id)] ||
        !players.some(player => player.id === id)) return;
    clock = Date.now();
    pendingPlayers = Object.assign({}, pendingPlayers, { [String(id)]: clock + 10000 });
    Cpp.notifyServer("InviteRoomPlayer", id);
  }

  function setBlocked(value) {
    if (!networkEnabled || settingPending || value === blocked) return;
    settingPending = true;
    settingDeadline = Date.now() + 10000;
    Cpp.notifyServer("SetRoomInviteBlocked", value);
  }

  function respond(accept, token) {
    const invitation = currentInvitation;
    // Capture the token at pointer press; a replacement must never be accepted by the old click.
    if (!invitation || token !== invitation.token) return;
    invitations = invitations.slice(1);
    if (networkEnabled && !inRoom && !blocked && invitation.expiresAt > Date.now())
      Cpp.notifyServer("RespondRoomInvitation", { token: invitation.token, accept: accept });
  }

  function handle(command, rawData) {
    const data = rawData ? JSON.parse(JSON.stringify(rawData)) : {};
    if (command === "RoomInviteSettings") {
      if (Config.consoleStartRequested || Config.replaying) return;
      supported = data.supported === true;
      blocked = data.blocked === true;
      settingPending = false;
      if (data.ok === false) App.showToast(data.error || Lua.tr("Room invitation settings failed"));
      if (blocked) invitations = [];
    } else if (command === "RoomInvitePlayers") {
      if (!subscribed || !canInvite) return;
      players = Array.isArray(data.players) ? data.players : [];
      listError = data.error || "";
    } else if (command === "RoomInviteResult") {
      const id = String(data.playerId);
      const pending = Object.assign({}, pendingPlayers);
      delete pending[id]; pendingPlayers = pending;
      clock = Date.now();
      if (data.retryAfterMs > 0)
        cooldowns = Object.assign({}, cooldowns, { [id]: clock + data.retryAfterMs });
      if (data.ok !== true) App.showToast(data.error || Lua.tr("Room invitation failed"));
    } else if (command === "RoomInvitation") {
      if (!networkEnabled || blocked || inRoom || !data.token ||
          invitations.some(item => item.token === data.token)) return;
      const expiresIn = Math.max(0, Math.min(60000, Number(data.expiresInMs) || 0));
      if (!expiresIn) return;
      invitations = invitations.concat([Object.assign({}, data, { expiresAt: Date.now() + expiresIn })]);
    } else if (command === "RoomInvitationClosed") {
      invitations = invitations.filter(item => item.token !== data.token);
    }
  }
}
