// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQml.WorkerScript

QtObject {
  id: api
  readonly property string defaultEndpoint: "https://freekill-friends.pages.dev"
  property string endpoint: defaultEndpoint
  property string token: ""
  property string recoveryCode: ""
  property string accountKey: "" // Memory only: never persisted, displayed or logged.
  property string credentialScope: ""
  // Reuse the already issued bearer session; no password/KDF key is written.
  property bool usingSavedSession: false
  property var pendingCredentials: null // Memory only; cleared on account switch.
  property int credentialGeneration: 0
  property bool deriving: false
  property bool accountBound: false
  property bool accountConnected: false
  property bool authenticating: false
  property string inviteMode: ""
  property string visibility: "online"
  property var reservations: []
  property bool policyReady: false
  property string profileKey: ""
  property string generationKey: profileKey + "|" + endpoint + "|" + token
  property bool enabled: false
  property bool busy: false
  property bool presenceDirty: false
  onBusyChanged: if (!busy && enabled && context.valid) {
    if (accountKey && !accountConnected && !authenticating) Qt.callLater(connectService);
    else if (presenceDirty && token) Qt.callLater(refresh);
  }
  property string error: ""
  property var context: ({ valid: false, state: "offline", server: "", gameId: 0, roomId: 0, roomName: "" })
  property var me: ({})
  property var friends: []
  property var avatarCache: ({})
  property var requests: []
  property var invitations: []
  property var calls: []
  property var readProfile: function(key) { return {}; }
  property var writeProfile: function(key, value) {}
  signal roomAccepted(var target)
  signal message(string text)
  signal identityCreated()
  signal identityRestored()
  signal policyUpdated()

  function validEndpoint(value) {
    return /^http:\/\/(127\.0\.0\.1|localhost|\[::1\])(:[0-9]{1,5})?$/.test(value) ||
      /^https:\/\/[a-zA-Z0-9.\-\[\]:]+(\/[a-zA-Z0-9._~%\/-]*)?$/.test(value);
  }
  function clearSession() {
    presenceDirty = false;
    for (const entry of calls) entry.xhr.abort();
    calls = []; busy = false; token = ""; recoveryCode = ""; me = ({});
    credentialGeneration++; credentialScope = ""; accountKey = ""; deriving = false;
    usingSavedSession = false; pendingCredentials = null;
    accountBound = false; accountConnected = false; authenticating = false;
    inviteMode = ""; policyReady = false;
    friends = []; avatarCache = ({}); requests = []; invitations = []; reservations = []; visibility = "online"; error = "";
  }
  function bind(value) {
    const sameAccount = context.server === value.server && context.gameId === value.gameId;
    // A temporary dummy/observer game model is not an avatar removal request.
    if (sameAccount && !value.avatar && context.avatar)
      value = Object.assign({}, value, {avatar: context.avatar});
    if (sameAccount && context.valid === value.valid && context.name === value.name &&
        context.state === value.state && context.roomId === value.roomId &&
        context.roomName === value.roomName && context.avatar === value.avatar) return;
    const changed = context.server !== value.server || context.gameId !== value.gameId ||
      context.state !== value.state || context.roomId !== value.roomId || context.valid !== value.valid || context.avatar !== value.avatar;
    const key = value.valid ? value.server + "/" + value.gameId : "";
    if (key !== profileKey) {
      // Invalidate callbacks before aborting requests from the previous account.
      profileKey = key;
      clearSession(); enabled = false;
      if (key) {
        const saved = readProfile(key) || {};
        const previousEndpoint = saved.endpoint || "";
        // This published service contains the migrated local identities.
        // Preserve tokens only for that known migration; custom services stay separate.
        const migratedService = /^http:\/\/(127\.0\.0\.1|localhost):19528\/?$/.test(previousEndpoint) ||
          previousEndpoint === "https://freekill-friends.c2115259095.workers.dev";
        endpoint = !previousEndpoint || migratedService ? defaultEndpoint : previousEndpoint;
        token = saved.token || "";
        recoveryCode = saved.recoveryCode || "";
        enabled = saved.enabled !== false;
        accountBound = saved.accountBound === true;
        inviteMode = ["original","friends","none"].indexOf(saved.inviteMode) >= 0 ? saved.inviteMode : "";
        avatarCache = saved.avatarCache && typeof saved.avatarCache === "object" && !Array.isArray(saved.avatarCache) ? saved.avatarCache : ({});
      }
    }
    context = value;
    if (key && endpoint === defaultEndpoint) persist();
    if (changed) {
      presenceDirty = true;
      if (enabled && token && value.valid) Qt.callLater(refresh);
    }
  }
  function persist() {
    if (profileKey) writeProfile(profileKey, {endpoint: endpoint, token: token, recoveryCode: recoveryCode, enabled: enabled, accountBound: accountBound, inviteMode: inviteMode, avatarCache: avatarCache});
  }
  function validAvatar(value) {
    return typeof value === "string" && /^[A-Za-z0-9_\u4e00-\u9fff#-]{1,128}$/.test(value);
  }
  function avatarFor(friend) {
    if (validAvatar(friend.avatar)) return friend.avatar;
    const cached = avatarCache[friend.id];
    return cached && validAvatar(cached.avatar) ? cached.avatar : "";
  }
  // Reuse public game profile data already delivered by the server. Match by
  // server + player ID, never by nickname, and never upload someone else's
  // claimed picture to their cloud profile.
  function observeGameAvatars(server, players) {
    if (!context.valid || !token || !enabled || !players || profileKey !== context.server + "/" + context.gameId) return;
    // Engine notifications can expose a QVariantList rather than a JS Array.
    try { players = JSON.parse(JSON.stringify(players)); } catch (_) { return; }
    if (!Array.isArray(players)) return;
    const next = ({});
    for (const friend of friends) {
      const previous = avatarCache[friend.id] || {};
      const p = friend.presence || {};
      const identity = p.gameId > 0 && p.server ? {server:p.server,gameId:p.gameId} : previous;
      let avatar = validAvatar(friend.avatar) ? friend.avatar : (previous.avatar || "");
      if (identity.server === server && identity.gameId > 0) {
        const seen = players.find(player => Number(player.id) === Number(identity.gameId));
        if (seen && validAvatar(seen.avatar)) avatar = seen.avatar;
      }
      if (identity.server && identity.gameId > 0)
        next[friend.id] = {server:identity.server,gameId:identity.gameId,avatar:avatar};
    }
    if (JSON.stringify(next) !== JSON.stringify(avatarCache)) { avatarCache = next; persist(); }
  }
  function applyMe(value) {
    if (!value || !value.id) return;
    inviteMode = ["original","friends","none"].indexOf(value.inviteMode) >= 0 ? value.inviteMode : value.blocked === 1 ? "none" : "original";
    visibility = value.visibility === "invisible" ? "invisible" : "online";
    policyReady = true; me = value; persist(); policyUpdated();
  }
  function setVisibility(value) {
    action("profile", {visibility:value}, function(data) { applyMe(data.me); message(value === "invisible" ? "已隐身：好友看到离线，预约已取消" : "已恢复在线"); });
  }
  function reserve(friendId) { action("reservations", {friendId:friendId}, function() { message("预约已发送，等待对方接受；30 分钟内有效"); }); }
  function respondReservation(id,accept) { action("reservations/respond", {id:id,accept:accept}); }
  function cancelReservation(id) { action("reservations/cancel", {id:id}); }
  function acknowledgeReservation(id) { action("reservations/ack", {id:id}); }
  function setInvitationMode(mode, blocked, callback) {
    action("settings", {inviteMode:mode, blocked:blocked}, function(data) {
      if (data.me) applyMe(data.me);
      if (callback) callback();
    });
  }
  function setCredentials(server, username, password) {
    if (!context.valid || endpoint !== defaultEndpoint || !username || !password) return;
    // The authenticated game account ID also separates local profiles. Never use
    // a public nickname or game ID as a social authentication secret.
    pendingCredentials = {server:server, username:username, password:password};
    if (!enabled) return;
    const scope = profileKey + "|" + username;
    if (credentialScope === scope) return;
    if (accountBound && token) {
      credentialScope = scope; usingSavedSession = true;
      // The normal sync request validates the bearer token on the server.
      if (enabled) Qt.callLater(refresh);
      return;
    }
    usingSavedSession = false;
    credentialScope = scope; credentialGeneration++; deriving = true;
    if (typeof Backend !== "undefined" && typeof Backend.deriveSocialAccountKey === "function") {
      const generation = credentialGeneration;
      Qt.callLater(function() {
        if (generation !== api.credentialGeneration) return;
        const key = Backend.deriveSocialAccountKey(server, username, password);
        password = "";
        if (generation !== api.credentialGeneration) return;
        api.receiveAccountKey({generation:generation, key:key, error:!key});
      });
      return;
    }
    authWorker.sendMessage({generation:credentialGeneration, server:server,
      username:username, password:password});
  }
  function receiveAccountKey(message) {
    if (message.generation !== credentialGeneration) return;
    deriving = false;
    if (message.error) { error = "账号好友身份认证失败，请重试或使用恢复码"; credentialScope = ""; return; }
    accountKey = message.key;
    if (enabled) connectService();
  }
  property WorkerScript authWorker: WorkerScript {
    source: Qt.resolvedUrl("SocialAuth.js")
    onMessage: function(message) {
      api.receiveAccountKey(message);
    }
  }
  function configure(url) {
    url = url.trim().replace(/\/$/, "");
    if (!validEndpoint(url)) { error = "请输入 HTTPS 服务地址；本机测试可用 http://127.0.0.1:19528"; return false; }
    if (url !== endpoint) {
      endpoint = url; clearSession(); enabled = false; persist();
    }
    return true;
  }
  function call(method, path, payload, callback, anonymous) {
    if (!validEndpoint(endpoint)) { error = "好友服务地址不正确"; return; }
    const key = generationKey;
    const request = new XMLHttpRequest();
    const entry = {xhr: request, deadline: Date.now() + 10000};
    calls = calls.concat([entry]); busy = true;
    request.onreadystatechange = function() {
      if (request.readyState !== XMLHttpRequest.DONE) return;
      calls = calls.filter(item => item !== entry); busy = calls.length > 0;
      if (key !== generationKey) return;
      let data = {};
      try { data = JSON.parse(request.responseText || "{}"); } catch (_) {}
      if (request.status < 200 || request.status >= 300) {
        if (path === "/v1/accounts/login") authenticating = false;
        error = data.error || "暂时连不上好友服务，请检查地址或服务是否启动";
        if (request.status === 401) {
          token = ""; accountConnected = false; friends = []; requests = []; invitations = []; me = ({});
          if (usingSavedSession && pendingCredentials) {
            // An expired/revoked cached session falls back to the same account
            // derivation exactly once. The original protocol stays unchanged.
            usingSavedSession = false; accountBound = false; credentialScope = "";
            persist();
            Qt.callLater(function() {
              const c=api.pendingCredentials;
              if (api.enabled && api.context.valid && c) api.setCredentials(c.server,c.username,c.password);
            });
          } else {
            if (!accountKey) enabled = false;
            persist();
          }
        }
        return;
      }
      error = "";
      if (callback) callback(data);
    };
    request.open(method, endpoint + path);
    if (!anonymous && token) request.setRequestHeader("Authorization", "Bearer " + token);
    if (method === "POST") request.setRequestHeader("Content-Type", "application/json");
    request.send(method === "POST" ? JSON.stringify(payload || {}) : "");
  }
  function connectService() {
    if (!context.valid || busy || deriving) return;
    enabled = true;
    if (endpoint === defaultEndpoint && !accountKey && (!token || !accountBound) && pendingCredentials) {
      const c=pendingCredentials;
      setCredentials(c.server,c.username,c.password);
      return;
    }
    if (endpoint === defaultEndpoint && accountKey && !accountConnected) {
      authenticating = true;
      call("POST", "/v1/accounts/login", {key:accountKey, name:context.name || "新月杀玩家"}, function(data) {
        token = data.token; applyMe(data.me); accountBound = true; accountConnected = true; authenticating = false;
        persist(); identityRestored(); refresh();
      });
      return;
    }
    if (token) {
      if (endpoint === defaultEndpoint && accountBound && !accountKey) usingSavedSession = true;
      persist(); refresh(); return;
    }
    if (recoveryCode.length === 32) { linkDevice(recoveryCode); return; }
    if (endpoint === defaultEndpoint) { error = "请先登录游戏账号；也可使用已有恢复码恢复好友"; return; }
    call("POST", "/v1/register", {name: context.name || "新月杀玩家"}, function(data) {
      token = data.token; applyMe(data.me); recoveryCode = data.recoveryCode || ""; accountConnected = false;
      persist(); if (recoveryCode) identityCreated(); refresh();
    }, true);
  }
  function pauseService() {
    if (token && context.valid)
      call("POST", "/v1/presence", Object.assign({}, context, {state: "offline", roomId: 0}), null);
    enabled = false; friends = []; requests = []; invitations = []; reservations = []; persist();
  }
  function refresh() {
    if (!enabled || !token || !context.valid || busy) return;
    presenceDirty = false;
    const presence = {server: context.server, gameId: context.gameId, state: context.state,
      roomId: context.roomId, roomName: context.roomName};
    if (context.avatar) presence.avatar = context.avatar;
    const receive = function(data) {
      if (usingSavedSession) accountConnected = true;
      applyMe(data.me); friends = data.friends || []; requests = data.requests || [];
      invitations = data.invitations || []; reservations = data.reservations || [];
    };
    if (endpoint === defaultEndpoint) call("POST", "/v1/sync", presence, receive);
    else call("POST", "/v1/presence", presence, function() {
      call("GET", "/v1/state", null, receive);
    });
  }
  function action(path, payload, callback) {
    if (!enabled || !token || busy) return;
    const perform = function() {
      call("POST", "/v1/" + path, payload, function(data) {
        if (callback) callback(data);
        refresh();
      });
    };
    if (path.indexOf("invitations") === 0 || path.indexOf("reservations") === 0) {
      // Sync current room/game state before deciding where an invitation leads.
      presenceDirty = false;
      call("POST", "/v1/presence", {server:context.server, gameId:context.gameId,
        state:context.state, roomId:context.roomId, roomName:context.roomName, avatar:context.avatar || ""}, perform);
    } else perform();
  }
  function addFriend(code) {
    action("friends/request", {code: code.trim().toUpperCase()}, function() { message("好友申请已发送"); });
  }
  function respondRequest(id, accept) { action("friends/respond", {id: id, accept: accept}); }
  function invite(friendId) { action("invitations", {friendId: friendId}, function() { message("邀请已发送，有效期 60 秒"); }); }
  function respondInvite(id, accept) {
    if (accept && context.state === "playing") { error = "请结束当前对局后再加入，邀请不会中断当前游戏"; return; }
    action("invitations/respond", {id: id, accept: accept}, function(data) {
      if (accept) roomAccepted(Object.assign({}, data, {profileKey: profileKey}));
    });
  }
  function deviceCode() {
    action("devices/code", {}, function(data) { message("迁移码：" + data.code + "（5 分钟内使用，请勿发给他人）"); });
  }
  function ensureRecoveryCode() {
    if (recoveryCode || !token || busy) return;
    action("recovery/code", {}, function(data) { recoveryCode = data.code; persist(); });
  }
  function linkDevice(code) {
    if (busy || !context.valid) return;
    code = code.trim().replace(/[\s-]/g, "").toUpperCase();
    const permanent = /^[A-F0-9]{32}$/.test(code);
    call("POST", permanent ? "/v1/recovery/restore" : "/v1/devices/link", {code: code}, function(data) {
      token = data.token; applyMe(data.me); recoveryCode = data.recoveryCode || ""; accountConnected = false;
      enabled = true; persist(); identityRestored();
      if (accountKey && endpoint === defaultEndpoint) connectService(); else refresh();
    }, true);
  }
  property Timer poll: Timer {
    interval: api.endpoint === api.defaultEndpoint ? 15000 : 5000; repeat: true; running: api.enabled && api.token !== "" && api.context.valid
    onTriggered: api.refresh()
  }
  property Timer accountRetry: Timer {
    interval: 15000; repeat: true; running: api.enabled && api.context.valid && api.accountKey !== "" && !api.accountConnected
    onTriggered: api.connectService()
  }
  property Timer watchdog: Timer {
    interval: 500; repeat: true; running: api.calls.length > 0
    onTriggered: {
      const expired = api.calls.filter(item => item.deadline < Date.now());
      for (const entry of expired) entry.xhr.abort();
      api.calls = api.calls.filter(item => item.deadline >= Date.now());
      api.busy = api.calls.length > 0;
      if (expired.length) api.error = "好友服务请求超时，请稍后重试";
      if (expired.length) api.authenticating = false;
    }
  }
}
