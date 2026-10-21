// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Templates as T
import QtQuick.Layouts
import Fk

Control {
  id: host
  anchors.fill: parent
  z: 400
  font.family: Qt.platform.os === "android" ? (systemFont.status === FontLoader.Ready ? systemFont.name : "Noto Sans CJK SC") : "Microsoft YaHei"
  FontLoader {
    id: systemFont
    source: Qt.platform.os === "android" ? "file:///system/fonts/NotoSansCJK-Regular.ttc" : ""
  }
  palette.windowText: "#e5ded0"
  palette.text: "#e5ded0"
  palette.buttonText: "#e5ded0"
  palette.button: "#315054"
  palette.base: "#20383e"
  palette.highlight: "#9f8757"
  palette.highlightedText: "#fff5dc"
  readonly property var clientPreferences: {
    const window = host.Window.window;
    return window ? window.contentItem.children.find(c => c.objectName === "fkCounterHost") || null : null;
  }
  property bool expanded: false
  property var navigationStack: null
  property int utilityPageDepth: 0
  readonly property bool nativeBasePageVisible: navigationStack
    ? navigationStack.visible && !navigationStack.busy && isSocialBasePage(navigationStack.currentItem)
    : utilityPageDepth === 0
  Connections {
    target: host.navigationStack
    ignoreUnknownSignals: true
    function onCurrentItemChanged() { host.scheduleLauncherUpdate(); Qt.callLater(host.refreshRoomBridge); Qt.callLater(host.finishJoin); }
    function onBusyChanged() { if (host.navigationStack && !host.navigationStack.busy) { Qt.callLater(host.refreshRoomBridge); Qt.callLater(host.finishJoin); } }
  }
  readonly property var bridgePage: navigationStack ? navigationStack.currentItem : null
  readonly property var bridgeRoomModel: bridgePage && "roomModel" in bridgePage ? bridgePage.roomModel : null
  Connections {
    target: host.bridgeRoomModel
    ignoreUnknownSignals: true
    function onCountChanged() { Qt.callLater(host.refreshRoomBridge); }
  }
  property var roomGrid: null
  Connections {
    target: host.roomGrid ? host.roomGrid.contentItem : null
    ignoreUnknownSignals: true
    function onChildrenChanged() { Qt.callLater(host.refreshRoomBridge); }
  }
  property var readyReminders: []
  property bool gameOnline: false
  property int gameAccount: 0
  property string gameName: ""
  // The profile page writes Self.avatar. Read the game model reactively so a
  // successful profile edit is uploaded even when no navigation event follows.
  readonly property string gameAvatar: selectedGameAvatar()
  onGameAvatarChanged: Qt.callLater(updateContext)
  property int avatarResourceRevision: 0
  onExpandedChanged: if (expanded) avatarResourceRevision++
  property string gameState: "offline"
  // GameOver leaves the table/results page open. Only an explicit return to
  // the waiting room or lobby makes the social UI available again.
  property bool matchViewActive: false
  property int roomId: 0
  property bool roomIdProvided: false
  property int selectedRoomId: 0
  property string selectedRoomName: ""
  property double selectedRoomDeadline: 0
  property bool nativeInvitesSupported: false
  property var nativeInvites: typeof RoomInvites === "undefined" ? null : RoomInvites
  property bool observerMarkHookInstalled: false
  property var originalNativePrompt: null
  property var originalNativePromptStyle: null
  property bool originalNativePromptSuppressed: false
  readonly property bool nativeFriendInviteVisible: friendNativeDialog.visible
  property bool nativeSettingsKnown: false
  property bool nativeBlocked: false
  property var nativePolicyExpected: null
  property var pendingPolicy: null
  property double policyRetryAt: 0
  property double nativePolicyRetryAt: 0
  property bool friendsExceptionRequested: false
  readonly property string invitationMode: pendingPolicy ? pendingPolicy.mode : social.inviteMode || (social.enabled && !social.policyReady ? "pending" : "original")
  readonly property bool allInvitationsBlocked: invitationMode === "none" || invitationMode === "pending" ||
    (invitationMode === "original" && nativeSettingsKnown && nativeBlocked)
  readonly property int socialInvitationCount: allInvitationsBlocked ? 0 : social.invitations.length
  property bool nativeFailureNeedsRoomId: false
  property var nativePending: ({})
  property var nativeCooldowns: ({})
  property double invitationClock: Date.now()
  property var inviteAnchor: null
  property bool launcherRightOfAnchor: false
  property bool roomLauncherReady: false
  readonly property var roomContent: bridgePage && "gameContent" in bridgePage ? bridgePage.gameContent : null
  onRoomContentChanged: {
    roomLauncherReady = false; inviteAnchor = null;
    gameContentItem = roomContent ? roomContent.parent : null;
    if (roomContent && "isOwner" in roomContent && "isAllReady" in roomContent)
      matchViewActive = false;
    Qt.callLater(host.refreshRoomBridge);
  }
  Connections {
    target: host.inviteAnchor
    ignoreUnknownSignals: true
    function onXChanged() { host.scheduleLauncherUpdate(); }
    function onYChanged() { host.scheduleLauncherUpdate(); }
    function onWidthChanged() { host.scheduleLauncherUpdate(); }
    function onHeightChanged() { host.scheduleLauncherUpdate(); }
    function onVisibleChanged() { host.scheduleLauncherUpdate(); }
  }
  onWidthChanged: scheduleLauncherUpdate()
  onHeightChanged: scheduleLauncherUpdate()
  property var roomLauncher: ({x: 0, y: 0, width: 60, height: 35})
  // The room page animates gameLoader's x/y/scale for the drawer transition.
  // Follow those changes so the launcher moves with the other room buttons.
  property var gameContentItem: null
  property bool launcherUpdatePending: false
  Connections {
    target: host.gameContentItem
    ignoreUnknownSignals: true
    function onXChanged() { host.scheduleLauncherUpdate(); }
    function onYChanged() { host.scheduleLauncherUpdate(); }
    function onScaleChanged() { host.scheduleLauncherUpdate(); }
    function onWidthChanged() { host.scheduleLauncherUpdate(); }
    function onHeightChanged() { host.scheduleLauncherUpdate(); }
  }
  property var hookedButtons: []
  property string roomName: ""
  property var pendingJoin: null
  property double joinDeadline: 0
  property string notice: ""
  property var profiles: ({})
  property bool profilesLoaded: false
  property bool profileStorageWritable: true
  property string profileStorageError: ""
  property bool profileWritePending: false
  property alias socialClient: social
  readonly property bool networkGame: gameOnline && !Config.consoleStartRequested && !Config.replaying
  // The stock client can retain observing=true after returning to the lobby.
  // Use confirmed navigation events for the page; the flag only gates rooms.
  // An unstarted room is still a room whether we entered or observe it, so the
  // friends launcher must stay available until the match actually starts.
  readonly property bool socialUiAvailable: networkGame && !matchViewActive && nativeBasePageVisible &&
    (gameState === "lobby" || gameState === "waiting" || gameState === "observing")
  readonly property string gameServer: String(Config.serverAddr || "").toLowerCase() + ":" + Config.serverPort
  visible: socialUiAvailable
  onSocialUiAvailableChanged: { if (!socialUiAvailable) dismissSocialUi(); else Qt.callLater(remindReservations); }

  // Use explicit control delegates: Android's Material defaults otherwise draw
  // black input/checkbox text over this panel, regardless of the host palette.
  component SocialButton: T.Button {
    id: actionButton
    implicitHeight: 38
    implicitWidth: Math.max(76, buttonText.implicitWidth + 28)
    leftPadding: 14; rightPadding: 14; topPadding: 8; bottomPadding: 8
    contentItem: Text {
      id: buttonText
      text: actionButton.text; color: actionButton.enabled ? "#fff0d2" : "#9cabad"
      font.family: host.font.family; font.pixelSize: 15
      horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
    }
    background: Rectangle {
      radius: 7
      color: !actionButton.enabled ? "#293a3e" : actionButton.down ? "#526b69" : actionButton.hovered ? "#405b5c" : "#314b50"
      border.width: actionButton.visualFocus ? 2 : 1
      border.color: actionButton.enabled ? "#a18e65" : "#526366"
    }
  }
  component SocialAvatar: Rectangle {
    id: avatarTile
    property string avatar: ""
    property string nickname: ""
    implicitWidth: 42; implicitHeight: 42; radius: 8; clip: true
    color: "#365357"; border.color: "#9e8b65"
    Text { anchors.centerIn: parent; text: avatarTile.nickname.slice(0,1) || "友"; color: "#f5e6c5"; font.pixelSize: 21; font.family: host.font.family }
    Image {
      objectName: "socialAvatarImage"
      anchors.fill: parent; anchors.margins: 1; fillMode: Image.PreserveAspectCrop
      property var resolvedAvatar: host.avatarPicture(avatarTile.avatar, host.avatarResourceRevision)
      sourceClipRect: resolvedAvatar.extra ? undefined : Qt.rect(61,20,128,128)
      source: resolvedAvatar.source
      visible: status === Image.Ready
    }
  }
  function selectedGameAvatar() {
    let player = typeof Self !== "undefined" ? Self : null;
    if (!player || Number(player.id) !== gameAccount) player = Cpp.self;
    // Spectating may change Self. Never publish the watched player's avatar
    // under the logged-in account's identity.
    if (!player || Number(player.id) !== gameAccount) return "";
    const value = String(player.avatar || "");
    return /^[A-Za-z0-9_\u4e00-\u9fff#-]{1,128}$/.test(value) ? value : "";
  }
  function avatarPicture(value, revision) {
    if (!/^[A-Za-z0-9_\u4e00-\u9fff#-]{1,128}$/.test(value) || typeof SkinBank === "undefined")
      return {source:"",extra:false};
    try {
      const extra = SkinBank.getGeneralExtraPic(value,"avatar/");
      return {source:extra || SkinBank.getGeneralPicture(value) || "",extra:!!extra};
    } catch (_) { return {source:"",extra:false}; }
  }
  function refreshPublicAvatars() {
    if (!networkGame || typeof Lua === "undefined" || typeof Lua.getPlayersAndObservers !== "function") return;
    try { social.observeGameAvatars(gameServer, Lua.getPlayersAndObservers() || []); }
    catch (_) { /* No room/player model has been delivered yet. */ }
  }
  function isSocialBasePage(page) {
    return !!page && (("roomModel" in page && "lobbyPlayerNum" in page && "serverPlayerNum" in page) ||
      ("gameComponent" in page && "gameContent" in page));
  }
  function findNavigationStack() {
    // RootPage owns the real StackView. Inspect it without changing any core
    // QML file covered by the game server's MD5 check.
    const children = host.parent ? host.parent.children : [];
    for (let i=0; i<children.length; i++) {
      const child = children[i];
      if (child !== host && "currentItem" in child && "depth" in child &&
          typeof child.get === "function" && typeof child.push === "function") {
        if (navigationStack !== child) navigationStack = child; return;
      }
    }
  }
  function hasReservation(friendId) {
    return social.reservations.some(r => r.friend.id === friendId);
  }
  function canReserve(friend) {
    const p = friend.presence || {};
    return social.visibility !== "invisible" && p.server === gameServer &&
      (p.state === "playing" || p.state === "observing");
  }
  function remindReservations() {
    if (!socialUiAvailable) return;
    const fresh = social.reservations.filter(r => r.status === "ready" && readyReminders.indexOf(r.id) < 0);
    if (!fresh.length) return;
    readyReminders = readyReminders.concat(fresh.map(r => r.id));
    notice = fresh.map(r => "预约就绪：" + r.friend.name + " 现在可以一起玩了").join("；");
    if (typeof App !== "undefined" && App.showToast) App.showToast(notice);
  }
  component SocialField: T.TextField {
    id: entry
    implicitHeight: 40
    color: "#f5eee0"; placeholderTextColor: "#bbc9cc"
    selectionColor: "#677b65"; selectedTextColor: "#ffffff"
    font.family: host.font.family; font.pixelSize: 15
    leftPadding: 12; rightPadding: 12; topPadding: 9; bottomPadding: 9
    Text {
      x: entry.leftPadding; y: entry.topPadding
      width: entry.width - entry.leftPadding - entry.rightPadding
      height: entry.height - entry.topPadding - entry.bottomPadding
      text: entry.placeholderText; color: entry.placeholderTextColor; font: entry.font
      verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
      visible: !entry.length && !entry.preeditText
    }
    background: Rectangle {
      radius: 7; color: "#102126"
      border.width: entry.activeFocus ? 2 : 1
      border.color: entry.activeFocus ? "#e3c78e" : "#667f83"
    }
  }
  component SocialDialog: Dialog {
    id: themedDialog
    padding: 18
    background: Rectangle { color: "#1b3035"; radius: 12; border.color: "#b69c66" }
    header: Text {
      text: themedDialog.title; color: "#fff0d2"; font.family: host.font.family; font.pixelSize: 20; font.bold: true
      leftPadding: 18; topPadding: 18; bottomPadding: 12
    }
  }

  function loadProfiles() {
    if (profilesLoaded) return;
    profilesLoaded = true;
    const primary = Backend.readFileFromAssets("social-private/profiles.json") || "";
    const backup = Backend.readFileFromAssets("social-private/profiles.backup.json") || "";
    function parse(value) {
      if (!value) return null;
      try { const data = JSON.parse(value); return data && typeof data === "object" && !Array.isArray(data) ? data : null; }
      catch (_) { return null; }
    }
    const mainData = parse(primary), backupData = parse(backup);
    if (mainData && (Object.keys(mainData).length || !backupData || !Object.keys(backupData).length)) profiles = mainData;
    else if (backupData) {
      profiles = backupData;
      Backend.writeFileToAssets("social-private/profiles.json", JSON.stringify(profiles));
    } else if (!primary && !backup) profiles = ({});
    else {
      profiles = ({}); profileStorageWritable = false;
      profileStorageError = "好友登录资料损坏，已保留原文件。登录游戏账号后可自动恢复，也可使用备用恢复码。";
    }
  }
  function prepareRecoveredProfile() {
    if (!profileStorageWritable) {
      const old = Backend.readFileFromAssets("social-private/profiles.json") || "";
      if (old) Backend.writeFileToAssets("social-private/profiles.unreadable.json", old);
      profileStorageWritable = true; profileStorageError = "";
    }
    social.persist();
  }
  function updateContext() {
    loadProfiles();
    social.bind({valid: networkGame && gameAccount > 0, server: gameServer,
      gameId: gameAccount, name: gameName, state: matchViewActive ? (gameState === "observing" ? "observing" : "playing") : gameState,
      roomId: roomId, roomName: roomName, avatar: gameAvatar});
    if (social.context.valid) social.setCredentials(gameServer, String(Config.screenName || ""), String(Config.password || ""));
    if (!observerMarkHookInstalled && networkGame) observerMarkHookInstalled = installObserverMarkCount();
  }
  // Keep private list-mark counts readable while spectating or replaying.
  // The stock helper only prints the count for the mark owner (Self), so an
  // observer following someone else saw the mark name without "看破 N".
  function installObserverMarkCount() {
    if (typeof ClientInstance === "undefined" || !ClientInstance) return false;
    try {
      Lua.ev('(function() ' +
        'if not (Fk and Fk.qml_marks and Fk.qml_marks["private"]) then return false end ' +
        'local spec = Fk.qml_marks["private"] ' +
        'if spec.__observeCount then return true end ' +
        'local original = spec.how_to_show ' +
        'spec.how_to_show = function(name, value, player) ' +
        '  local text = original(name, value, player) ' +
        '  local watching = ClientInstance and (ClientInstance.observing or ClientInstance.replaying) ' +
        '  if watching and (text == nil or text == "" or text == " ") and type(value) == "table" and type(value.value) == "table" then ' +
        '    local ch = name and name:sub(11, 11) ' +
        '    if ch == "$" or ch == "&" or ch == ":" then return tostring(#value.value) end ' +
        '  end ' +
        '  return text ' +
        'end ' +
        'spec.__observeCount = true ' +
        'return true end)()');
      return true;
    } catch(e) { return false; }
  }
  function resetInvitationPolicyBridge() {
    pendingPolicy = null; nativePolicyExpected = null; nativeSettingsKnown = false;
    nativeBlocked = false; policyRetryAt = 0; nativePolicyRetryAt = 0;
    friendsExceptionRequested = false;
  }
  function chooseInvitationMode(mode, originalBlocked) {
    if (["original","friends","none"].indexOf(mode) < 0 || !networkGame) return;
    friendsExceptionRequested = mode === "friends";
    pendingPolicy = {mode:mode, blocked:mode === "none" || (mode === "original" && originalBlocked === true)};
    policyRetryAt = 0; nativePolicyRetryAt = 0;
    filterNativeInvitations(); synchronizeInvitationPolicy();
  }
  function isFriendNativeInvitation(invitation) {
    if (!social.policyReady || !social.enabled || !social.token) return false;
    const rawId = Number(invitation.inviterId || invitation.playerId || 0);
    const name = String(invitation.inviterName || "");
    const candidates = social.friends.filter(function(friend) {
      const presence = friend.presence || {};
      if (presence.server !== host.gameServer || presence.state === "offline" || !(presence.gameId > 0)) return false;
      // Prefer server-provided numeric identity. Older servers only return the
      // unique game account name; ambiguity or missing data must fail closed.
      return rawId > 0 ? presence.gameId === rawId : name !== "" && friend.name === name;
    });
    return candidates.length === 1;
  }
  function nativeInvitationAllowed(invitation) {
    if (!networkGame || gameState !== "lobby" || allInvitationsBlocked) return false;
    return invitationMode !== "friends" || isFriendNativeInvitation(invitation);
  }
  function findOriginalNativePrompt() {
    if (originalNativePrompt) return;
    const seen = [];
    function visit(node, depth) {
      if (!node || node === host || depth > 7 || seen.indexOf(node) >= 0 || seen.length > 600) return null;
      seen.push(node);
      if (node.objectName === "roomInvitationPrompt") return node;
      // Popup objects live in QML data, rather than the visual children list.
      const lists = [node.data || [], node.children || []];
      for (const list of lists) for (let i=0; i<list.length; i++) {
        const result = visit(list[i], depth+1); if (result) return result;
      }
      return null;
    }
    const prompt = visit(host.parent, 0);
    if (prompt) {
      originalNativePrompt = prompt;
      originalNativePromptStyle = {opacity:prompt.opacity, enabled:prompt.enabled, modal:prompt.modal, dim:prompt.dim};
    }
  }
  function synchronizeNativeInvitationUi() {
    if (!friendNativeDialog) return;
    findOriginalNativePrompt();
    const suppress = invitationMode !== "original";
    if (originalNativePrompt) {
      if (suppress) {
        originalNativePrompt.opacity = 0; originalNativePrompt.enabled = false;
        originalNativePrompt.modal = false; originalNativePrompt.dim = false;
        // Material animates Popup.opacity during open/close. Hide both visual
        // branches as well so that animation cannot reveal a stranger's prompt.
        if (originalNativePrompt.contentItem) originalNativePrompt.contentItem.visible = false;
        if (originalNativePrompt.background) originalNativePrompt.background.visible = false;
        originalNativePrompt.close(); originalNativePromptSuppressed = true;
      } else if (originalNativePromptSuppressed) {
        const style = originalNativePromptStyle;
        originalNativePrompt.opacity = style.opacity; originalNativePrompt.enabled = style.enabled;
        originalNativePrompt.modal = style.modal; originalNativePrompt.dim = style.dim;
        if (originalNativePrompt.contentItem) originalNativePrompt.contentItem.visible = true;
        if (originalNativePrompt.background) originalNativePrompt.background.visible = true;
        originalNativePromptSuppressed = false;
        if (nativeInvites && nativeInvites.currentInvitation && nativeInvitationAllowed(nativeInvites.currentInvitation)) originalNativePrompt.open();
      }
    }
    const current = nativeInvites ? nativeInvites.currentInvitation : null;
    if (invitationMode === "friends" && current && socialUiAvailable && nativeInvitationAllowed(current)) {
      friendNativeDialog.invitation = current;
      if (!friendNativeDialog.visible) friendNativeDialog.open();
    } else friendNativeDialog.close();
  }
  function respondNativeInvitation(accept, token) {
    const current = nativeInvites ? nativeInvites.currentInvitation : null;
    if (!current || current.token !== token || invitationMode !== "friends" || !socialUiAvailable || !nativeInvitationAllowed(current)) return;
    nativeInvites.respond(accept, token);
  }
  function filterNativeInvitations() {
    if (!nativeInvites || !Array.isArray(nativeInvites.invitations)) return;
    const original = nativeInvites.invitations;
    const allowed = original.filter(function(invitation) { return host.nativeInvitationAllowed(invitation); });
    if (allowed.length !== original.length) nativeInvites.invitations = allowed;
    Qt.callLater(host.synchronizeNativeInvitationUi);
  }
  function synchronizeInvitationPolicy() {
    if (!networkGame) return;
    synchronizeNativeInvitationUi();
    filterNativeInvitations();
    if (!pendingPolicy && nativeSettingsKnown && nativeBlocked && social.policyReady && invitationMode === "friends" && !friendsExceptionRequested && !nativePolicyExpected) {
      // A block set in another client must not be silently undone on reconnect.
      pendingPolicy = {mode:"original", blocked:true}; policyRetryAt = 0;
    }
    if (!pendingPolicy && nativeSettingsKnown && social.policyReady && invitationMode === "original" && social.me.blocked !== Number(nativeBlocked)) {
      pendingPolicy = {mode:"original", blocked:nativeBlocked}; policyRetryAt = 0;
    }
    if (pendingPolicy && social.enabled && social.token && !social.busy && Date.now() >= policyRetryAt) {
      const desired = pendingPolicy;
      const key = social.profileKey;
      policyRetryAt = Date.now() + 15000;
      social.setInvitationMode(desired.mode, desired.blocked, function() {
        if (social.profileKey !== key || host.pendingPolicy !== desired) return;
        host.pendingPolicy = null; host.notice = "邀请权限已保存";
        Qt.callLater(host.synchronizeInvitationPolicy);
      });
    }
    if (!nativeInvitesSupported || !nativeSettingsKnown || nativePolicyExpected || Date.now() < nativePolicyRetryAt) return;
    let desired = null;
    if (invitationMode === "none") desired = true;
    // Unblock the server only after the user's opt-in is saved to the cloud.
    else if (invitationMode === "friends" && !pendingPolicy && social.policyReady && social.inviteMode === "friends") {
      desired = !originalNativePrompt;
      if (!originalNativePrompt) host.notice = "当前界面无法启用原版邀请过滤，已保留屏蔽；可使用已知房间号的好友邀请。";
    }
    if (desired === null || desired === nativeBlocked || (nativeInvites && nativeInvites.settingPending)) return;
    nativePolicyExpected = {blocked:desired, deadline:Date.now() + 10000};
    if (nativeInvites && typeof nativeInvites.setBlocked === "function") nativeInvites.setBlocked(desired);
    else Cpp.notifyServer("SetRoomInviteBlocked", desired);
  }
  function receiveNativeSettings(data) {
    const known = nativeSettingsKnown, previous = nativeBlocked, expected = nativePolicyExpected;
    nativeSettingsKnown = data.supported === true; nativeBlocked = data.blocked === true;
    if (!nativeSettingsKnown) { nativePolicyExpected = null; return; }
    if (expected) {
      nativePolicyExpected = null;
      if (data.ok === false || nativeBlocked !== expected.blocked) {
        nativePolicyRetryAt = Date.now() + 30000;
        social.error = data.error || "游戏服务器未能保存邀请权限，请稍后重试";
      }
    } else if (known && nativeBlocked !== previous) {
      // The original settings page remains authoritative for explicit user changes.
      chooseInvitationMode("original", nativeBlocked);
    } else if (social.policyReady && invitationMode === "original" && social.me.blocked !== Number(nativeBlocked)) {
      chooseInvitationMode("original", nativeBlocked);
    }
    synchronizeInvitationPolicy();
  }
  Connections {
    target: host.nativeInvites
    function onInvitationsChanged() { host.filterNativeInvitations(); }
    function onCurrentInvitationChanged() { Qt.callLater(host.synchronizeNativeInvitationUi); }
  }
  onInvitationModeChanged: { filterNativeInvitations(); synchronizeNativeInvitationUi(); }
  Component.onCompleted: { host.findNavigationStack(); Qt.callLater(host.synchronizeNativeInvitationUi); }
  function dismissSocialUi() {
    expanded = false;
    if (invitePolicy) invitePolicy.popup.close();
    if (friendNativeDialog) friendNativeDialog.close();
    // A temporary StackView transition hides the launcher while QuitRoom is
    // acknowledged. Preserve that transaction until the real lobby is ready.
    if (!networkGame || matchViewActive || gameState === "playing" ||
        (pendingJoin && (pendingJoin.server !== gameServer || pendingJoin.profileKey !== social.profileKey || Date.now() >= joinDeadline)))
      pendingJoin = null;
    if (joinDialog) joinDialog.close();
    if (linkDialog) linkDialog.close();
    if (removeDialog) removeDialog.close();
    if (backupDialog) backupDialog.close();
    if (serviceSettings) serviceSettings.close();
    if (roomPassword) roomPassword.text = "";
  }
  function joinTarget(target, observe) {
    updateContext();
    if (!target || target.profileKey !== social.profileKey || target.server !== gameServer || !networkGame) {
      social.error = "账号或服务器已改变，请重新接收邀请"; return;
    }
    // Recheck the last received presence when confirming the dialog. Never
    // silently enter an old room after the friend moves or starts a match.
    if (target.friendId) {
      const friend = social.friends.find(f => f.id === target.friendId);
      const p = friend && friend.presence;
      if (!p || p.server !== target.server || Math.floor(p.roomId || 0) !== target.roomId ||
          ["waiting", "playing", "observing"].indexOf(p.state) < 0) {
        social.error = "好友的房间状态已改变，请重新跟随"; return;
      }
      if (!observe && p.state !== "waiting") {
        social.error = "好友已开局，请关闭窗口后重新选择跟随观战"; return;
      }
    }
    if (gameState === "playing") { social.error = "当前对局尚未结束，无法切换房间"; return; }
    if (!socialUiAvailable) { social.error = "请返回大厅或等待房间后再加入好友房间"; return; }
    if (target.roomId === roomId && roomId > 0) { social.error = "已经在这个房间中"; return; }
    pendingJoin = Object.assign({}, target, {password: roomPassword.text, observe: observe});
    joinDeadline = Date.now() + 10000;
    joinDialog.close();
    if (gameState === "lobby") finishJoin();
    else Cpp.notifyServer("QuitRoom", "");
  }
  function canFollowObserve(friend) {
    const presence = (friend && friend.presence) || {};
    return networkGame && presence.server === gameServer &&
      (presence.state === "waiting" || presence.state === "playing" || presence.state === "observing") &&
      Math.floor(presence.roomId || 0) > 0;
  }
  function followObserve(friend) {
    updateContext();
    const presence = (friend && friend.presence) || {};
    if (!social.enabled || !social.token) { social.error = "先连接好友服务"; return; }
    if (!networkGame) { social.error = "请先登录游戏服务器"; return; }
    if (presence.server !== gameServer) { social.error = "好友在其他服务器，暂时无法跟随观战"; return; }
    if (["waiting", "playing", "observing"].indexOf(presence.state) < 0) { social.error = "好友当前不在房间中"; return; }
    const targetRoom = Math.floor(presence.roomId || 0);
    if (targetRoom <= 0) { social.error = "好友未上报房间号，暂时无法跟随观战"; return; }
    if (targetRoom === roomId && roomId > 0) { social.error = "已经在这个房间中"; return; }
    if (gameState === "playing") { social.error = "当前对局尚未结束，无法切换房间"; return; }
    if (!socialUiAvailable) { social.error = "请返回大厅或等待房间后再跟随观战"; return; }
    joinDialog.targetRoom = {roomId: targetRoom, roomName: presence.roomName || "",
      server: gameServer, profileKey: social.profileKey, friendId: friend.id, observe: presence.state !== "waiting"};
    joinDialog.observeOnly = presence.state !== "waiting";
    roomPassword.text = "";
    joinDialog.open();
  }
  function finishJoin() {
    const target = pendingJoin;
    if (!target) return;
    if (!networkGame || target.server !== gameServer || target.profileKey !== social.profileKey || Date.now() >= joinDeadline) {
      pendingJoin = null; return;
    }
    if (gameState !== "lobby" || !nativeBasePageVisible) return;
    const page = navigationStack && navigationStack.currentItem;
    if (navigationStack && (!page || !("roomModel" in page) || !("lobbyPlayerNum" in page))) return;
    pendingJoin = null;
    if (target.friendId) {
      const friend = social.friends.find(f => f.id === target.friendId);
      const p = friend && friend.presence;
      if (!p || p.server !== target.server || Math.floor(p.roomId || 0) !== target.roomId ||
          ["waiting", "playing", "observing"].indexOf(p.state) < 0 || (!target.observe && p.state !== "waiting")) {
        social.error = "好友的房间状态已改变，请重新跟随"; return;
      }
    }
    host.selectedRoomId = target.roomId;
    host.selectedRoomName = target.roomName || "";
    host.selectedRoomDeadline = Date.now() + 10000;
    // Match Lobby.enterRoom: a stale observing flag would make the client
    // treat a normal join as spectating and hide the friends launcher.
    Config.replaying = false;
    Config.observing = !!target.observe;
    Cpp.notifyServer(target.observe ? "ObserveRoom" : "EnterRoom", [target.roomId, target.password]);
    notice = "已请求加入房间 #" + target.roomId + "，结果以游戏服务器提示为准";
  }
  function statusLabel(value) {
    return ({offline:"离线", lobby:"大厅", waiting:"等待开局", playing:"对局中", observing:"旁观中"})[value] || "未知";
  }

  function invitationReason(friend) {
    if (social.visibility === "invisible") return "隐身中";
    if (!social.enabled || !social.token) return "先连接好友服务";
    if (social.busy) return "同步中";
    if (host.gameState !== "waiting" || !host.socialUiAvailable) return "先进入等待房间";
    const presence = friend.presence || {};
    if (presence.state === "offline") return "好友离线";
    if (presence.server !== host.gameServer) return "不同服务器";
    if (presence.state === "playing") return "好友对局中";
    if (host.roomId > 0 && presence.roomId === host.roomId) return "已在本房间";
    const id = String(presence.gameId || 0);
    if (nativePending[id] > invitationClock) return "发送中";
    const remaining = Math.ceil(((nativeCooldowns[id] || 0) - invitationClock) / 1000);
    if (remaining > 0) return remaining + " 秒后再邀";
    return "";
  }
  function inviteFriend(friend) {
    invitationClock = Date.now();
    const reason = invitationReason(friend);
    if (reason) { social.error = reason; return; }
    if (host.roomId > 0) { social.invite(friend.id); return; }
    if (nativeInvitesSupported && friend.presence.gameId > 0) {
      const id = Math.floor(friend.presence.gameId);
      nativePending = Object.assign({}, nativePending, {[String(id)]: Date.now() + 10000});
      social.error = ""; host.notice = "正在通过游戏服务器发送邀请…";
      Cpp.notifyServer("InviteRoomPlayer", id);
    } else {
      host.notice = "此服务器未返回当前房间号，也未提供原版邀请接口，请先补充实际房间号。";
      manualRoom.forceActiveFocus();
    }
  }
  function scheduleLauncherUpdate() {
    if (launcherUpdatePending) return;
    launcherUpdatePending = true;
    Qt.callLater(host.updateLauncherPosition);
  }
  function updateLauncherPosition() {
    launcherUpdatePending = false;
    const anchor = inviteAnchor;
    if (host.gameState === "lobby") { roomLauncherReady = false; return; }
    if (anchor && anchor.visible && anchor.width > 0 && anchor.height > 0 && host.gameState !== "offline") {
      const point = anchor.mapToItem(host, 0, 0);
      const end = anchor.mapToItem(host, 0, anchor.height);
      const h = Math.abs(end.y - point.y);
      const w = h * 1.72;
      if (h < 8) { roomLauncherReady = false; return; }
      if (launcherRightOfAnchor) {
        const right = anchor.mapToItem(host, anchor.width, 0);
        roomLauncher = {x: Math.min(host.width - w - 8, right.x + 6), y: point.y, width: w, height: h};
      } else {
        roomLauncher = {x: Math.max(8, point.x - w - 6), y: point.y, width: w, height: h};
      }
      roomLauncherReady = true;
    } else {
      // A newly created waiting room has not laid out its buttons yet.
      // Do not expose an old/fallback position over the original interface.
      roomLauncherReady = false;
    }
  }
  function refreshRoomBridge() {
    host.findNavigationStack();
    if (!host.socialUiAvailable) return;
    if (host.gameState !== "lobby" && host.roomContent &&
        !("isAllReady" in host.roomContent || "roomInviteButton" in host.roomContent)) {
      roomLauncherReady = false; inviteAnchor = null; return;
    }
    let anchor = null;
    let inviteNode = null;
    let content = host.roomContent ? host.roomContent.parent : null;
    function scan(node, depth, delegate) {
      if (!node || node === host || depth > 18) return;
      if (host.bridgeRoomModel && "model" in node && node.model === host.bridgeRoomModel && "contentItem" in node) host.roomGrid = node;
      if (node.objectName === "waitingRoomInviteButton") inviteNode = node;
      if (node.objectName === "roomGameLoader") content = node;
      if (node.objectName === "waitingRoomInviteButton" && node.visible) anchor = node;
      if ("roomInviteButton" in node && node.roomInviteButton) {
        inviteNode = node.roomInviteButton;
        if (node.roomInviteButton.visible) anchor = node.roomInviteButton;
      }
      if (!inviteNode && host.roomContent && "clicked" in node && "text" in node &&
          (node.text === Lua.tr("Invite Players") || node.text === Lua.tr("Invite Player"))) inviteNode = node;
      const choice = "roomId" in node && "capacity" in node && "hasPassword" in node ? node : delegate;
      if (choice && node.clicked && hookedButtons.indexOf(node) < 0) {
        const roomChoice = choice;
        const clicked = function() {
          if (host.gameState !== "lobby") return;
          host.selectedRoomId = Math.floor(roomChoice.roomId || 0);
          host.selectedRoomName = roomChoice.roomName || "";
          host.selectedRoomDeadline = Date.now() + 10000;
        };
        node.clicked.connect(clicked);
        hookedButtons.push(node);
      }
      const children = node.children || [];
      for (let i = 0; i < children.length; i++) scan(children[i], depth + 1, choice);
    }
    hookedButtons = hookedButtons.filter(button => button && button.parent);
    scan(host.bridgePage || host.parent, 0, null);
    // Prefer the room's Chat button and sit immediately to its right, like the
    // other bottom-row actions. Observers cannot invite, so the invite button
    // is hidden; its sibling Chat button is still the stable anchor.
    let chatNode = null;
    if (!inviteNode && host.roomContent) {
      const pending = [host.roomContent];
      while (pending.length) {
        const node = pending.pop();
        if (node && node.visible && "clicked" in node && "text" in node && node.text === Lua.tr("Chat")) { chatNode = node; break; }
        if (node && !("model" in node) && node.children) pending.push(...Array.from(node.children));
      }
    }
    if (inviteNode && inviteNode.parent) {
      const siblings = inviteNode.parent.children || [];
      for (let i = 0; i < siblings.length; i++) {
        const s = siblings[i];
        if (s && s.visible && s.text === Lua.tr("Chat")) { chatNode = s; break; }
      }
    }
    // Hosts / players who can invite keep the friend button on the left of
    // "邀请玩家". Only when that button is unavailable (observer) fall back to
    // the right side of "聊天".
    if (inviteNode && inviteNode.visible) { inviteAnchor = inviteNode; launcherRightOfAnchor = false; }
    else if (chatNode) { inviteAnchor = chatNode; launcherRightOfAnchor = true; }
    else { inviteAnchor = anchor; launcherRightOfAnchor = false; }
    gameContentItem = content;
    updateLauncherPosition();
  }

  SocialClient {
    id: social
    readProfile: function(key) { return host.profiles[key] || {}; }
    writeProfile: function(key, value) {
      if (!host.profileStorageWritable) { social.error = host.profileStorageError; return; }
      if (!host.profileWritePending && JSON.stringify(host.profiles[key]) === JSON.stringify(value)) return;
      host.profiles = Object.assign({}, host.profiles, {[key]: value});
      const payload = JSON.stringify(host.profiles);
      host.profileWritePending = true;
      if (!Backend.writeFileToAssets("social-private/profiles.json", payload) || Backend.readFileFromAssets("social-private/profiles.json") !== payload)
        social.error = "好友登录信息未能保存，请保存恢复码后再退出。";
      else if (!Backend.writeFileToAssets("social-private/profiles.backup.json", payload) || Backend.readFileFromAssets("social-private/profiles.backup.json") !== payload)
        social.error = "好友身份已保存，但备份写入失败，请保存恢复码。";
      else host.profileWritePending = false;
    }
    onRoomAccepted: function(target) {
      if (host.allInvitationsBlocked) { social.error = "已屏蔽全部房间邀请"; return; }
      if (!host.socialUiAvailable) return;
      joinDialog.targetRoom = target; joinDialog.observeOnly = false; roomPassword.text = ""; joinDialog.open();
    }
    onMessage: function(text) { host.notice = text; }
    onIdentityCreated: { host.prepareRecoveredProfile(); if (host.socialUiAvailable) backupDialog.open(); }
    onIdentityRestored: host.prepareRecoveredProfile()
    onPolicyUpdated: Qt.callLater(host.synchronizeInvitationPolicy)
    onFriendsChanged: { host.filterNativeInvitations(); host.refreshPublicAvatars(); }
    onReservationsChanged: host.remindReservations()
    onMeChanged: if (social.me.id) host.readyReminders = host.readyReminders.filter(id => social.reservations.some(r => r.id === id));
  }

  Connections {
    target: Mediator
    function onCommandGot(sender, command, data) {
      // Card moves, skill animations and button updates do not change social
      // identity/presence. Do not rebind hidden social UI for each game packet.
      if (["Setup", "SetServerSettings", "EnterLobby", "EnterRoom", "ChangeRoom",
           "StartGame", "ChangeRoomPage", "GameOver", "BackToRoom", "RestartGame", "BackToStart",
           "RoomInviteSettings", "RoomInvitePlayers", "RoomInviteResult", "ErrorMsg",
           "ErrorDlg", "AddPlayer", "ArrangeSeats", "PushPage", "PopPage"].indexOf(command) < 0) return;
      if (command === "PushPage" && host.networkGame) {
        host.utilityPageDepth++; host.findNavigationStack();
      } else if (command === "PopPage") host.utilityPageDepth = Math.max(0, host.utilityPageDepth - 1);
      if (command === "Setup" && !Config.observing) {
        const id = Math.floor(data[0] || 0);
        if (id !== host.gameAccount) { host.resetInvitationPolicyBridge(); host.observerMarkHookInstalled = false; host.gameAccount = id; host.pendingJoin = null; host.notice = ""; }
        host.gameName = data[1] || "";
      } else if (command === "SetServerSettings") {
        host.resetInvitationPolicyBridge(); host.observerMarkHookInstalled = false;
        const features = data[2] || [];
        host.nativeInvitesSupported = features && typeof features.length === "number" && Array.from(features).indexOf("RoomInvitations") >= 0;
        host.gameAccount = Math.floor(Cpp.self.id || 0);
        host.gameName = Cpp.self.screenName || "";
        host.gameOnline = host.gameAccount > 0;
      } else if (command === "EnterLobby") {
        host.utilityPageDepth = 0; host.findNavigationStack();
        host.gameAccount = Math.floor(Cpp.self.id || 0);
        host.gameName = Cpp.self.screenName || host.gameName;
        host.gameOnline = true; host.gameState = "lobby"; host.roomId = 0; host.roomName = "";
        host.matchViewActive = false;
        host.roomIdProvided = false;
        host.nativeFailureNeedsRoomId = false;
        host.selectedRoomId = 0; host.selectedRoomName = "";
        host.updateContext(); Qt.callLater(host.finishJoin);
      } else if (command === "EnterRoom" || command === "ChangeRoom") {
        if (command === "EnterRoom") { host.utilityPageDepth = 0; host.findNavigationStack(); }
        if (command === "EnterRoom") { host.roomLauncherReady = false; host.inviteAnchor = null; host.matchViewActive = false; host.nativeFailureNeedsRoomId = false; }
        const settings = data[2] || {};
        host.roomId = Math.floor(settings.roomId || (command === "EnterRoom" ?
          (Date.now() < host.selectedRoomDeadline ? host.selectedRoomId : 0) : host.roomId) || 0);
        host.roomIdProvided = host.roomId > 0;
        host.roomName = settings.roomName || (command === "EnterRoom" ?
          (Date.now() < host.selectedRoomDeadline ? host.selectedRoomName : "") : host.roomName) || "";
        if (command === "EnterRoom") { host.selectedRoomId = 0; host.selectedRoomName = ""; }
        host.gameState = Config.observing ? "observing" : "waiting";
      } else if (command === "StartGame" || command === "ChangeRoomPage") {
        host.matchViewActive = true;
        host.gameState = Config.observing ? "observing" : "playing";
      } else if (command === "GameOver") {
        host.gameState = Config.observing ? "observing" : "waiting";
      } else if ((command === "BackToRoom" || command === "RestartGame")) {
        host.roomLauncherReady = false; host.inviteAnchor = null;
        host.utilityPageDepth = 0;
        host.matchViewActive = false;
        host.gameState = Config.observing ? "observing" : "waiting";
      } else if (command === "BackToStart" && !(data && data.preserveSession)) {
        host.utilityPageDepth = 0;
        host.resetInvitationPolicyBridge(); host.observerMarkHookInstalled = false;
        host.gameOnline = false; host.gameState = "offline"; host.pendingJoin = null;
        host.gameAccount = 0; host.expanded = false; joinDialog.close();
        host.nativeInvitesSupported = false; host.nativePending = ({}); host.nativeCooldowns = ({});
        host.selectedRoomId = 0; host.selectedRoomName = "";
      } else if (command === "RoomInviteSettings") {
        host.nativeInvitesSupported = data.supported === true;
        host.receiveNativeSettings(data);
      } else if (command === "RoomInvitePlayers" && data && data.players) {
        // Some servers include public avatars in the native invitation list.
        // Reuse them only when already delivered; do not create subscriptions
        // or extra game-server requests on behalf of the player.
        social.observeGameAvatars(host.gameServer, data.players);
      } else if (command === "RoomInviteResult") {
        const id = String(data.playerId);
        if (host.nativePending[id]) {
          const pending = Object.assign({}, host.nativePending); delete pending[id]; host.nativePending = pending;
          if (data.retryAfterMs > 0) host.nativeCooldowns = Object.assign({}, host.nativeCooldowns, {[id]: Date.now() + data.retryAfterMs});
          if (data.ok === true) { social.error = ""; host.notice = "游戏服务器已发送邀请，请好友查看房间邀请提示。"; }
          else {
            social.error = data.error || "游戏服务器未能发送邀请"; host.notice = "";
            host.nativeFailureNeedsRoomId = host.roomId <= 0;
          }
        }
      } else if (command === "ErrorMsg" || command === "ErrorDlg") {
        host.selectedRoomId = 0; host.selectedRoomName = ""; host.selectedRoomDeadline = 0;
      }
      host.updateContext();
      if (command === "AddPlayer" || command === "EnterRoom" || command === "BackToRoom" || command === "ArrangeSeats")
        Qt.callLater(host.refreshPublicAvatars);
      if (command === "EnterLobby" || command === "EnterRoom" || command === "BackToRoom" || command === "RestartGame") Qt.callLater(host.refreshRoomBridge);
    }
  }
  Connections {
    target: Config
    function onServerAddrChanged() { host.resetInvitationPolicyBridge(); host.pendingJoin = null; host.gameOnline = false; host.selectedRoomId = 0; host.selectedRoomDeadline = 0; host.updateContext(); }
    function onServerPortChanged() { host.resetInvitationPolicyBridge(); host.pendingJoin = null; host.gameOnline = false; host.selectedRoomId = 0; host.selectedRoomDeadline = 0; host.updateContext(); }
    function onObservingChanged() {
      host.updateContext();
    }
  }
  Timer {
    objectName: "socialRecoveryTimer"
    interval: 500; repeat: true; running: host.networkGame && !host.matchViewActive
    onTriggered: {
      host.invitationClock = Date.now();
      if (host.nativePolicyExpected && host.nativePolicyExpected.deadline <= Date.now()) {
        host.nativePolicyExpected = null; host.nativePolicyRetryAt = Date.now() + 30000;
        social.error = "游戏服务器保存邀请权限超时，请稍后重试";
      }
      host.synchronizeInvitationPolicy();
      for (const id of Object.keys(host.nativePending)) {
        if (host.nativePending[id] <= host.invitationClock) {
          const pending = Object.assign({}, host.nativePending); delete pending[id]; host.nativePending = pending;
          host.notice = "邀请请求超时，请稍后重试";
        }
      }
      const previousStack = host.navigationStack;
      host.findNavigationStack();
      if (host.navigationStack !== previousStack) Qt.callLater(host.refreshRoomBridge);
    }
  }
  Timer {
    interval: 1000; repeat: true; running: host.pendingJoin !== null
    onTriggered: if (Date.now() >= host.joinDeadline) {
      host.pendingJoin = null; social.error = "未能退出原房间，已取消自动加入";
    } else host.finishJoin();
  }

  Rectangle {
    objectName: "friendsLauncher"
    visible: host.socialUiAvailable && (host.gameState === "lobby" || host.roomLauncherReady)
    x: host.gameState === "lobby" ? 6 : host.roomLauncher.x
    y: host.gameState === "lobby" ? 112 : host.roomLauncher.y
    width: host.gameState === "lobby" ? 60 : host.roomLauncher.width
    height: host.gameState === "lobby" ? 38 : host.roomLauncher.height; radius: 7
    color: launchMouse.containsMouse ? "#304e50" : "#de182d30"
    border.color: "#b69c66"
    Text {
      anchors.centerIn: parent; width: parent.width - 8; horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight; color: "#f4e6c8"; font.family: host.font.family
      font.pixelSize: 16 * (host.gameContentItem ? host.gameContentItem.scale : 1)
      text: "好友" + (host.socialInvitationCount + social.requests.length + social.reservations.filter(r => r.status === "ready" || (r.status === "pending" && r.direction === "incoming")).length > 0 ? " · " + (host.socialInvitationCount + social.requests.length + social.reservations.filter(r => r.status === "ready" || (r.status === "pending" && r.direction === "incoming")).length) : "")
    }
    MouseArea { id: launchMouse; anchors.fill: parent; hoverEnabled: true
      onClicked: { host.expanded = !host.expanded; host.refreshRoomBridge(); host.updateContext(); social.refresh(); } }
  }

  Rectangle {
    objectName: "friendsPanel"
    anchors.fill: parent; color: "#8a050d10"; visible: host.expanded && host.socialUiAvailable
    MouseArea { anchors.fill: parent; onClicked: host.expanded = false }
    Rectangle {
      anchors.centerIn: parent
      width: Math.min(host.width - 28, 800); height: Math.min(host.height - 32, 510)
      color: "#17292d"; radius: 14; border.color: "#b69c66"; border.width: 1
      MouseArea { anchors.fill: parent }
      ColumnLayout {
        anchors.fill: parent; anchors.margins: 18; spacing: 9
        RowLayout {
          Text { text: "同游好友"; font.family: host.font.family; font.pixelSize: 24; font.bold: true; color: "#f2e3be" }
          Text { text: host.statusLabel(host.gameState) + (host.roomId ? " · 房间 #" + host.roomId : ""); color: "#a1b9bb"; font.family: host.font.family; font.pixelSize: 13 }
          Item { Layout.fillWidth: true }
          SocialButton { text: "设置"; onClicked: serviceSettings.open() }
          SocialButton { text: "关闭"; onClicked: host.expanded = false }
        }
        Text {
          Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#c5d2d4"; font.family: host.font.family; font.pixelSize: 13
          text: "好友随游戏账号保存在云端；重装后登录同一服务器、同一账号即可恢复。双方连接同一好友服务后可互邀。"
        }
        RowLayout {
          visible: social.token !== ""
          SocialAvatar { avatar: social.context.avatar || social.me.avatar || ""; nickname: host.gameName }
          Text { text: "我的好友码  " + (social.me.code || "…"); color: "#e1c98f"; font.family: host.font.family; font.pixelSize: 15 }
          SocialButton { text: "复制"; enabled: !!social.me.code; onClicked: Backend.copyToClipboard(social.me.code) }
          Item { Layout.fillWidth: true }
          SocialButton { objectName: "visibilityToggle"; text: social.visibility === "invisible" ? "隐身中 · 上线" : "在线 · 隐身"; enabled: !social.busy && !!social.me.id
            onClicked: social.setVisibility(social.visibility === "invisible" ? "online" : "invisible") }
        }
        Text { Layout.fillWidth: true; visible: !!social.token && !social.accountBound; wrapMode: Text.Wrap
          text: social.accountBound ? "已绑定游戏账号 · 重装自动恢复，好友仅在主动删除后移除" : social.deriving || social.authenticating ? "正在绑定游戏账号，请稍候…" : "尚未绑定游戏账号，请重新登录游戏完成绑定；也可先备份恢复码。"
          color: social.accountBound ? "#b6dacb" : "#e1c98f"; font.pixelSize: 13; font.family: host.font.family }
        RowLayout {
          Text { text: "添加好友"; color: "#d6e0df"; font.family: host.font.family; font.pixelSize: 14 }
          SocialField { id: friendCode; objectName: "friendCode"; Layout.fillWidth: true; maximumLength: 12; placeholderText: "输入对方的 12 位好友码" }
          SocialButton { text: "添加"; enabled: social.enabled && !!social.token && !social.busy; onClicked: social.addFriend(friendCode.text) }
          SocialButton { text: "恢复已有好友"; enabled: !social.busy; onClicked: linkDialog.open() }
        }
        RowLayout {
          visible: !host.roomIdProvided && (!host.nativeInvitesSupported || host.nativeFailureNeedsRoomId) && host.gameState !== "lobby" && host.gameState !== "offline"
          Text { text: "当前房间号"; color: "#adbec0"; font.family: host.font.family; font.pixelSize: 13 }
          SocialField { id: manualRoom; Layout.preferredWidth: 90; placeholderText: "如 123"; maximumLength: 10
            validator: IntValidator { bottom: 1; top: 2147483647 } }
          SocialButton { text: "确认"; enabled: manualRoom.acceptableInput
                    onClicked: { host.roomId = parseInt(manualRoom.text); host.roomIdProvided = true; host.updateContext(); social.refresh(); } }
          Text { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#bdcdd0"; font.family: host.font.family; font.pixelSize: 13
            text: host.nativeFailureNeedsRoomId ? "原版邀请未成功，可填写当前房间号，改用好友服务跨房间邀请。" : "服务器未提供房间号，发送邀请前请按实际房间填写。" }
        }
        Text { Layout.fillWidth: true; visible: text !== ""; text: host.profileStorageError || social.error || host.notice
          wrapMode: Text.Wrap; color: social.error ? "#f0a795" : "#b6dacb"; font.family: host.font.family; font.pixelSize: 13; textFormat: Text.PlainText }
        ScrollView {
          id: socialScroll
          Layout.fillWidth: true; Layout.fillHeight: true; clip: true
          contentWidth: availableWidth
          ColumnLayout {
            width: socialScroll.availableWidth; spacing: 8
            Repeater {
              model: host.allInvitationsBlocked ? [] : social.invitations
              delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true; implicitHeight: 64; radius: 7; color: "#30413d"; border.color: "#c0a76e"
                RowLayout {
                  anchors.fill: parent; anchors.margins: 9
                  Text { Layout.fillWidth: true; color: "#f4e6c8"; font.family: host.font.family; font.pixelSize: 14; wrapMode: Text.Wrap; textFormat: Text.PlainText
                    text: modelData.from.name + " 邀请你加入房间 #" + modelData.roomId + "\n好友码 " + modelData.from.code }
                  SocialButton { text: "拒绝"; enabled: !social.busy; onClicked: social.respondInvite(modelData.id, false) }
                  SocialButton { text: host.gameState === "playing" ? "对局中" : "接受"; enabled: !social.busy && host.gameState !== "playing"
                    onClicked: social.respondInvite(modelData.id, true) }
                }
              }
            }
            Repeater {
              model: social.requests
              delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; color: "#f1e6d0"; font.family: host.font.family; font.pixelSize: 15; wrapMode: Text.Wrap; text: modelData.from.name + " · " + modelData.from.code; textFormat: Text.PlainText }
                SocialButton { text: "忽略"; enabled: !social.busy; onClicked: social.respondRequest(modelData.id, false) }
                SocialButton { text: "同意好友"; enabled: !social.busy; onClicked: social.respondRequest(modelData.id, true) }
              }
            }
            Repeater {
              model: social.reservations
              delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true; implicitHeight: 70; radius: 8; color: modelData.status === "ready" ? "#34483d" : "#2c3944"; border.color: "#8c967e"
                RowLayout {
                  anchors.fill: parent; anchors.margins: 10
                  SocialAvatar { avatar: social.avatarFor(modelData.friend); nickname: modelData.friend.name }
                  Text { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#f3e9d5"; font.family: host.font.family; font.pixelSize: 14; textFormat: Text.PlainText
                    text: modelData.status === "ready" ? "预约就绪 · " + modelData.friend.name + "\n双方已空闲，可以邀请一起玩"
                      : modelData.status === "accepted" ? "已约好 · " + modelData.friend.name + "\n回到大厅或等待房间后提醒，不会自动跳房"
                      : modelData.friend.name + (modelData.direction === "incoming" ? " 想和你一起玩\n接受后，双方空闲时提醒" : " · 等待接受预约\n30 分钟内有效") }
                  SocialButton { visible: modelData.status === "pending" && modelData.direction === "incoming"; text: "婉拒"; enabled: !social.busy; onClicked: social.respondReservation(modelData.id,false) }
                  SocialButton { visible: modelData.status === "pending" && modelData.direction === "incoming"; text: "接受预约"; enabled: !social.busy; onClicked: social.respondReservation(modelData.id,true) }
                  SocialButton { visible: modelData.status !== "ready" && (modelData.direction === "outgoing" || modelData.status === "accepted"); text: "取消预约"; enabled: !social.busy; onClicked: social.cancelReservation(modelData.id) }
                  SocialButton { visible: modelData.status === "ready"; text: "知道了"; enabled: !social.busy; onClicked: social.acknowledgeReservation(modelData.id) }
                }
              }
            }
            Repeater {
              model: social.friends
              delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true; implicitHeight: 64; radius: 8; color: "#243b40"
                RowLayout {
                  anchors.fill: parent; anchors.margins: 10
                  SocialAvatar { avatar: social.avatarFor(modelData); nickname: modelData.name }
                  Rectangle { width: 8; height: 8; radius: 4; color: modelData.presence.state === "offline" ? "#6b8083" : "#7dcab0" }
                  ColumnLayout {
                    Layout.fillWidth: true; spacing: 3
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.name + " · " + modelData.code; color: "#f1e6d0"; font.family: host.font.family; font.pixelSize: 15; textFormat: Text.PlainText }
                    Text { text: host.statusLabel(modelData.presence.state) + (modelData.presence.roomId ? " · 房间 #" + modelData.presence.roomId : "") +
                        (social.friends.filter(friend => friend.name === modelData.name).length > 1 ? " · 同名不同好友码" : "")
                      color: "#c1d1d4"; font.family: host.font.family; font.pixelSize: 13 }
                  }
                  SocialButton {
                    objectName: "followObserveFriend_" + modelData.id
                    visible: host.canFollowObserve(modelData)
                    text: modelData.presence.state === "waiting" ? "跟随入房" : "跟随观战"
                    enabled: !social.busy
                    onClicked: host.followObserve(modelData)
                  }
                  SocialButton {
                    objectName: "inviteFriend_" + modelData.id
                    text: host.invitationReason(modelData) || "邀请"
                    enabled: host.invitationReason(modelData) === ""
                    onClicked: host.inviteFriend(modelData)
                  }
                  SocialButton {
                    objectName: "reserveFriend_" + modelData.id
                    visible: host.canReserve(modelData)
                    text: host.hasReservation(modelData.id) ? "已预约" : "预约一起玩"
                    enabled: !social.busy && !host.hasReservation(modelData.id)
                    onClicked: social.reserve(modelData.id)
                  }
                  SocialButton { text: "删除"; enabled: !social.busy
                    onClicked: { removeDialog.friendId = modelData.id; removeDialog.friendName = modelData.name; removeDialog.open(); } }
                }
              }
            }
            Text { visible: social.friends.length === 0 && social.requests.length === 0 && social.reservations.length === 0 && host.socialInvitationCount === 0
              Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; topPadding: 24; bottomPadding: 24
              text: social.deriving || social.authenticating ? "正在恢复账号好友，请稍候…" : social.enabled ? "还没有好友，把好友码发给一起玩的伙伴吧" : "连接好友服务后，查看好友和邀请"
              color: "#c1d1d4"; font.family: host.font.family; font.pixelSize: 15 }
          }
        }
        RowLayout {
          Text { text: "接收邀请"; color: "#d6e0df"; font.family: host.font.family; font.pixelSize: 14 }
          ComboBox {
            id: invitePolicy; objectName: "invitationPolicy"
            Layout.preferredWidth: 248; implicitHeight: 38
            model: ["跟随原版设置", "屏蔽陌生人，允许好友", "屏蔽全部邀请"]
            currentIndex: host.invitationMode === "friends" ? 1 : host.invitationMode === "none" ? 2 : 0
            enabled: social.enabled && !!social.token && social.policyReady && typeof social.me.inviteMode === "string" && !social.busy
            font.family: host.font.family; font.pixelSize: 14
            contentItem: Text {
              text: invitePolicy.displayText; color: invitePolicy.enabled ? "#fff0d2" : "#9cabad"
              font: invitePolicy.font; leftPadding: 12; rightPadding: 30; verticalAlignment: Text.AlignVCenter
              elide: Text.ElideRight
            }
            indicator: Canvas {
              x: invitePolicy.width - 22; y: (invitePolicy.height - height) / 2; width: 10; height: 6
              onPaint: {
                const ctx = getContext("2d"); ctx.fillStyle = "#e3c78e";
                ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(10, 0); ctx.lineTo(5, 6); ctx.closePath(); ctx.fill();
              }
            }
            background: Rectangle { color: "#102126"; radius: 7; border.color: invitePolicy.activeFocus ? "#e3c78e" : "#667f83" }
            delegate: ItemDelegate {
              width: invitePolicy.width
              contentItem: Text { text: modelData; font: invitePolicy.font; color: "#fff0d2"; verticalAlignment: Text.AlignVCenter }
              background: Rectangle { color: highlighted ? "#405b5c" : "#20383e" }
              highlighted: invitePolicy.highlightedIndex === index
            }
            popup: Popup {
              objectName: "invitationPolicyPopup"
              exit: Transition {}
              y: -implicitHeight - 4; width: invitePolicy.width
              implicitHeight: contentItem.implicitHeight + 8; padding: 4
              contentItem: ListView { clip: true; implicitHeight: contentHeight; model: invitePolicy.popup.visible ? invitePolicy.delegateModel : null; currentIndex: invitePolicy.highlightedIndex }
              background: Rectangle { color: "#20383e"; radius: 7; border.color: "#b69c66" }
            }
            onActivated: function(index) {
              host.chooseInvitationMode(["original","friends","none"][index], host.nativeBlocked);
              currentIndex = Qt.binding(function() { return host.invitationMode === "friends" ? 1 : host.invitationMode === "none" ? 2 : 0; });
            }
          }
          Item { Layout.fillWidth: true }
          SocialButton { text: social.busy ? "同步中…" : "刷新"; enabled: social.enabled && !social.busy; onClicked: social.refresh() }
        }
        Text {
          Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#bdcdd0"; font.family: host.font.family; font.pixelSize: 12
          text: host.pendingPolicy ? "正在保存邀请权限，请稍候…" : host.nativePolicyExpected ? "正在与游戏服务器同步邀请权限…" : host.invitationMode === "friends" && host.nativeSettingsKnown && host.nativeBlocked ? "游戏服务器仍屏蔽邀请，稍后会重试；保存成功后才能接收好友的原版邀请。" : host.invitationMode === "friends"
            ? "仅在记牌版中过滤陌生人；改用官方客户端时，请重新开启原版屏蔽。开启原版“屏蔽全部”可随时停止接收。"
            : host.invitationMode === "none" ? "已屏蔽原版和同游好友的全部房间邀请。" : host.nativeBlocked ? "原版“屏蔽全部”已开启，好友邀请也会被拦截。" : "按原版开关接收邀请；选择“屏蔽陌生人，允许好友”可仅接收好友。"
        }

      }
    }
  }
  SocialDialog {
    id: serviceSettings; objectName: "socialServiceSettings"
    title: "好友与显示设置 · 20261022.2"; anchors.centerIn: parent; modal: true; exit: Transition {}
    width: Math.min(host.width - 36, 650)
    contentItem: ColumnLayout {
      spacing: 14
      CheckBox {
        objectName: "hideServerTitles"
        text: "屏蔽称号（仅本机显示）"; palette.windowText: "#e5ded0"
        visible: host.clientPreferences !== null
        checked: host.clientPreferences ? host.clientPreferences.hideTitles : false
        onClicked: {
          if (!host.clientPreferences.setHideTitles(checked)) social.error = "显示设置保存失败，请检查存储空间";
        }
      }
      Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: "头像跟随游戏个人资料。隐身只隐藏同游好友服务中的在线和房间信息，不改变主力服的游戏状态。"; color: "#c5d2d4"; font.pixelSize: 14; font.family: host.font.family }
        RowLayout {
          Text { text: "好友服务"; color: "#d6e0df"; font.family: host.font.family; font.pixelSize: 14 }
          SocialField { id: serviceAddress; objectName: "serviceAddress"; Layout.fillWidth: true; text: social.endpoint; placeholderText: "输入好友服务地址"; maximumLength: 255 }
          SocialButton { objectName: "friendsConnectButton"; text: social.deriving ? "认证中…" : social.enabled && social.token ? "暂停" : "连接好友"; enabled: !social.busy && !social.deriving && host.networkGame
            onClicked: {
              host.notice = "";
              if (!social.configure(serviceAddress.text)) return;
              if (social.enabled && social.token) social.pauseService();
              else social.connectService();
            } }
        }
      RowLayout {
          SocialButton { text: "备份恢复码"; enabled: !social.busy && !!social.me.id; onClicked: { backupDialog.open(); social.ensureRecoveryCode(); } }
          SocialButton { text: "迁移到另一设备"; enabled: !social.busy; onClicked: social.deviceCode() }
        Item { Layout.fillWidth: true }
      }
      Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: social.error || host.notice; color: social.error ? "#f0a795" : "#b6dacb"; font.pixelSize: 13; font.family: host.font.family; textFormat: Text.PlainText }
      SocialButton { text: "关闭"; Layout.alignment: Qt.AlignRight; onClicked: serviceSettings.close() }
    }
  }
  SocialDialog {
    id: friendNativeDialog; objectName: "friendNativeInvitationDialog"
    exit: Transition {}
    property var invitation: ({})
    anchors.centerIn: parent; modal: true; closePolicy: Popup.NoAutoClose
    width: Math.min(host.width - 32, 440); title: "好友房间邀请"
    contentItem: ColumnLayout {
      spacing: 14
      Text { Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
        text: String(friendNativeDialog.invitation.inviterName || "好友") + " 邀请你加入房间"; color: "#f5eee0"; font.family: host.font.family; font.pixelSize: 17 }
      Text { Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
        text: "房间：" + String(friendNativeDialog.invitation.roomName || "好友房间"); color: "#c5d2d4"; font.family: host.font.family; font.pixelSize: 15 }
      RowLayout {
        Item { Layout.fillWidth: true }
        SocialButton { objectName: "declineFriendNativeInvite"; text: "拒绝"; property string pressedToken: ""
          onPressedChanged: if (pressed) pressedToken = friendNativeDialog.invitation.token || "";
          onClicked: host.respondNativeInvitation(false, pressedToken) }
        SocialButton { objectName: "acceptFriendNativeInvite"; text: "接受"; property string pressedToken: ""
          onPressedChanged: if (pressed) pressedToken = friendNativeDialog.invitation.token || "";
          onClicked: host.respondNativeInvitation(true, pressedToken) }
      }
    }
  }
  SocialDialog {
    id: backupDialog; objectName: "friendRecoveryBackupDialog"
    anchors.centerIn: parent; modal: true; title: "备份好友恢复码"
    width: Math.min(host.width - 32, 490)
    contentItem: ColumnLayout {
      Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#e4edeb"; font.family: host.font.family; font.pixelSize: 15
        text: "已绑定账号正常重装会自动恢复；恢复码可在更改密码、无法自动恢复时备用。请保存在本应用之外，它相当于好友账号的钥匙，请勿分享。" }
      SocialField { Layout.fillWidth: true; readOnly: true; selectByMouse: true
        text: social.recoveryCode; placeholderText: social.busy ? "正在生成…" : "点击下方生成恢复码" }
      Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#c5d2d4"; font.family: host.font.family; font.pixelSize: 13
        text: "恢复码长期有效；在另一设备重新生成后，请保存新的恢复码，旧码会失效。" }
      RowLayout {
        SocialButton { text: "生成恢复码"; visible: !social.recoveryCode; enabled: !social.busy; onClicked: social.ensureRecoveryCode() }
        SocialButton { text: "复制恢复码"; enabled: social.recoveryCode.length === 32; onClicked: { Backend.copyToClipboard(social.recoveryCode); host.notice = "恢复码已复制，请保存到本应用之外。"; } }
        SocialButton { text: "关闭"; onClicked: backupDialog.close() }
      }
    }
  }
  SocialDialog {
    id: joinDialog
    objectName: "friendJoinDialog"
    property var targetRoom: null
    property bool observeOnly: false
    anchors.centerIn: parent; modal: true
    title: observeOnly ? "跟随好友观战" : "加入好友房间"
    width: Math.min(host.width - 32, 450)
    contentItem: ColumnLayout {
      Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#e4edeb"; font.family: host.font.family; font.pixelSize: 15
        text: (joinDialog.observeOnly
          ? "好友正在房间 #" + (joinDialog.targetRoom ? joinDialog.targetRoom.roomId : "") + " 对局或观战，将以旁观身份进入。"
          : "确认离开当前等待房间或旁观，前往房间 #" + (joinDialog.targetRoom ? joinDialog.targetRoom.roomId : "") + "？") +
          "房间密码和准入限制仍由游戏服务器检查。" }
      SocialField { id: roomPassword; Layout.fillWidth: true; echoMode: TextInput.Password; maximumLength: 64; placeholderText: "房间密码（如需）" }
      RowLayout {
        SocialButton { text: "取消"; onClicked: joinDialog.close() }
        SocialButton { text: "旁观"; onClicked: host.joinTarget(joinDialog.targetRoom, true) }
        SocialButton { text: "加入"; visible: !joinDialog.observeOnly; onClicked: host.joinTarget(joinDialog.targetRoom, false) }
      }
    }
  }
  SocialDialog {
    id: linkDialog; anchors.centerIn: parent; modal: true; title: "恢复已有好友"
    objectName: "friendLinkDialog"
    width: Math.min(host.width - 32, 450)
    contentItem: ColumnLayout {
      Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#e4edeb"; font.family: host.font.family; font.pixelSize: 15; text: "输入你保存的 32 位长期恢复码，即可找回原好友身份；也可输入原设备生成的 16 位迁移码（5 分钟内有效）。" }
      SocialField { id: linkCode; Layout.fillWidth: true; maximumLength: 40; placeholderText: "32 位恢复码或 16 位迁移码" }
      RowLayout {
        SocialButton { text: "取消"; onClicked: linkDialog.close() }
        SocialButton { text: "恢复"; onClicked: { social.linkDevice(linkCode.text); linkDialog.close(); linkCode.text = ""; } }
      }
    }
  }
  SocialDialog {
    id: removeDialog; property string friendId; property string friendName
    objectName: "friendRemoveDialog"
    anchors.centerIn: parent; modal: true; title: "删除好友"
    width: Math.min(host.width - 32, 450)
    contentItem: ColumnLayout {
      Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#e4edeb"; font.family: host.font.family; font.pixelSize: 15; text: "确认删除好友「" + removeDialog.friendName + "」？"; textFormat: Text.PlainText }
      RowLayout {
        SocialButton { text: "取消"; onClicked: removeDialog.close() }
        SocialButton { text: "删除"; onClicked: { social.action("friends/remove", {id: removeDialog.friendId}); removeDialog.close(); } }
      }
    }
  }
}
