// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Fk

Item {
  id: router
  required property var owner
  readonly property var room: owner.currentScene
  property var activeItem: null
  property var activeRequest: null
  property var queue: []
  property var manifests: null
  property var identityCache: ({})
  property string lastKey: ""
  property double lastAt: 0
  property var playerComponent: null
  property var pendingStates: ({})
  property var soundEvents: []
  property bool gameFinished: false
  property bool finalSceneReady: false
  property double finalSceneDeadline: 0
  property int finalSceneStableTicks: 0

  function reset() {
    queue = []; manifests = null; identityCache = ({}); lastKey = ""; lastAt = 0;
    pendingStates = ({}); soundEvents = [];
    gameFinished = false;
    finalSceneReady = false; finalSceneDeadline = 0; finalSceneStableTicks = 0;
    finalDeathTimer.stop(); activeRequest = null;
    entryTimer.stop();
    const old = activeItem; activeItem = null;
    if (old) { old.visible = false; old.destroy(); }
  }
  function finishGame() {
    if (gameFinished) return;
    gameFinished = true;
    entryTimer.stop(); pendingStates = ({}); soundEvents = [];
    // The stock victory presentation can cover an already-running death.
    // Replay that final death once the result dialog has settled, so its full
    // visible playback survives both the server judge and the victory overlay.
    queue = queue.filter(request => request.skill === "death");
    if (activeRequest && activeRequest.skill === "death") queue.unshift(activeRequest);
    activeRequest = null;
    if (activeItem) {
      const old = activeItem; activeItem = null;
      old.visible = false; old.destroy();
    }
    if (queue.length) {finalSceneDeadline=Date.now()+10000;finalSceneStableTicks=0;finalDeathTimer.restart();}
  }
  onRoomChanged: reset()
  Component.onDestruction: reset()
  Connections {
    target: Config
    function onEnabledResourcePacksChanged() { router.reset(); }
    function onBanChangeSkinChanged() { if (Config.banChangeSkin) router.reset(); }
  }
  Connections {
    target: router.room
    ignoreUnknownSignals: true
    function onVisibleChanged() { if (!router.room.visible) router.reset(); }
  }

  // Routes are bundled client code. Resource packs contain only images,
  // skeleton data and metadata, never executable expressions or callbacks.
  readonly property var roles: ({
    jiangwei: {name:"神姜维", signatures:["星魂","天涛","九伐","平襄"]},
    machao: {name:"神马超", signatures:["狩骊","横骛","寂灭","霆威","御历"]},
    weiyan: {name:"势魏延", signatures:["忠傲","豪夸"]},
    zhouyu: {name:"势周瑜", signatures:["雄姿","炽沄","瑾澜"]},
    caomao: {name:"曹髦", signatures:["绝进"]},
    taishici: {name:"势太史慈", signatures:["振锋"]},
    zhouqun: {name:"周群", signatures:["天算"]},
    simazhao: {name:"司马昭", signatures:["昭凶"]},
    lvbu: {name:"谋吕布", signatures:["谋无双"]},
    zerong: {name:"笮融", signatures:["浮图"]},
    zhaoyun: {name:"势赵云", signatures:["武翊"]}
  })
  function roleMatches(general, role) {
    const spec = roles[role];
    if (!spec || !general) return false;
    const key = general + ":" + role;
    if (identityCache[key] !== undefined) return identityCache[key];
    let matches = String(Lua.tr(general)) === spec.name;
    const variantPrefixes = {jiangwei:"god|shen",machao:"god|shen",weiyan:"shi|bingshi",
      zhouyu:"shi|bingshi",taishici:"shi|bingshi",simazhao:"js|xing|star",
      lvbu:"mou",zhaoyun:"shi|bingshi"};
    if (!matches && variantPrefixes[role])
      matches = new RegExp("(?:^|__)(?:" + variantPrefixes[role] + ")(?:__|_)?" + role + "$").test(String(general).toLowerCase());
    // Several extensions translate a divine/general variant to just its name.
    // Require both the base identity and an identifying skill in that case.
    if (!matches && String(general).toLowerCase().split("__").pop().endsWith(role)) {
      try {
        matches = Lua.ev('(function() local g=Fk.generals[' + JSON.stringify(general) + ']; if not g then return false end local ok,n=pcall(function() return g:getSkillNameList(true,true) end); if not ok then return false end local names=' +
          '{' + spec.signatures.map(s => '[' + JSON.stringify(s) + ']=true').join(',') +
          '}; for _,s in ipairs(n) do if names[Fk:translate(s)] then return true end end return false end)()') === true;
      } catch (_) {}
    }
    identityCache[key] = matches;
    return matches;
  }
  function skillName(name) {
    return typeof owner.canonicalSkillName==="function" ? owner.canonicalSkillName(name) : String(name);
  }
  function skillIs(name, keys) {
    name=skillName(name);
    const canonical = String(name).split("__").pop().replace(/^#/, "");
    const translated = String(Lua.tr(name));
    return keys.indexOf(canonical) >= 0 || keys.indexOf(translated) >= 0;
  }
  function actorModel(actor) {
    const players = room && room.dataModel && room.dataModel.players || [];
    return Array.from(players).find(p => String(p.playerid !== undefined ? p.playerid : p.id) === String(actor)) || null;
  }
  function actorGeneral(actor, role) {
    const model = actorModel(actor), photo = model && model.photoItem;
    if (!photo || !photo.visible) return "";
    return [photo.general || model.general || "", photo.deputyGeneral || model.deputyGeneral || ""]
      .map(g => String(g)).find(g => roleMatches(g,role)) || "";
  }
  function publicState(actor) {
    const id = Number(actor);
    if (!Number.isInteger(id)) return ({});
    try {
      // Only HP and the specific server-synchronized skill marks are read.
      // No hand/deck information or pending client reply enters this adapter.
      return Lua.ev('(function() local c=ClientInstance; if not c then return {} end local ok,p=pcall(c.getPlayerById,c,' +
        id + '); if not ok or not p then return {} end return {hp=p.hp, zhouyu=p:getMark("@xiongzi-noclear"), quest=p:getMark("__questPre_zhongao"), kuanggu=p:getMark("m_shi__kuanggu_upgrade")} end)()') || ({});
    } catch (_) { return ({}); }
  }
  function rememberState(actor, kind, general, skill) {
    const entries = Object.assign({}, pendingStates);
    const key = String(actor) + ":" + kind;
    entries[key] = {actor:actor, general:general, skill:skill, hp:publicState(actor).hp,
      expires:Date.now()+185000, seen:[]};
    // A single room can have several simultaneous public skill resolutions.
    if (Object.keys(entries).length > 32) delete entries[Object.keys(entries)[0]];
    pendingStates = entries;
    return true;
  }
  function takeState(actor, kind, remove) {
    const key = String(actor) + ":" + kind, entry = pendingStates[key];
    if (!entry || entry.expires < Date.now()) return null;
    if (remove) { const rest=Object.assign({},pendingStates); delete rest[key]; pendingStates=rest; }
    return entry;
  }
  function rememberSound(data) {
    if (!data.name || !data.general) return false;
    soundEvents = soundEvents.filter(s => Date.now()-s.at < 3000).slice(-15).concat([{
      name:String(data.name), general:String(data.general), deputy:String(data.deputy || ""),
      index:Number(data.i), at:Date.now()}]);
    if (skillIs(data.name,["tingwei","霆威"]) && (Number(data.i)===3 || Number(data.i)===4)) {
      const matches=Object.values(pendingStates).filter(e => skillIs(e.skill,["tingwei","霆威"]) &&
        e.general===String(data.general) && e.expires>Date.now());
      if (matches.length===1) {
        const entry=matches[0]; takeState(entry.actor,"tingwei",true);
        return playState(entry,"spell/tingwei/SS_2026smc_tiesuolianhuan","play1");
      }
    }
    return false;
  }
  function takeSound(general, skill) {
    const i=soundEvents.findIndex(s => Date.now()-s.at < 3000 &&
      (s.general===general || s.deputy===general) && skillName(s.name)===skillName(skill));
    if (i<0) return 0;
    const index=soundEvents[i].index;
    soundEvents=soundEvents.filter((s,n) => n!==i);
    return Number.isInteger(index) ? index : 0;
  }
  function playState(entry, stem, animation) {
    return enqueue(entry.general, entry.skill, "ui/anim/"+stem, animation || "play", entry.actor);
  }
  function routePublicMark(data) {
    const actor=data[0], mark=String(data[1] || ""), value=data[2];
    if (mark==="@xiongzi-noclear") {
      if (value!=="xiongzi_1" && value!=="xiongzi_2") return false;
      const entry=takeState(actor,"zhouyu",true);
      return entry ? playState(entry,"jinlan/SS_szy_jn_"+(value==="xiongzi_1" ? "shui" : "huo")) : false;
    }
    if (mark==="@mobile__zhenfeng_mobile__hanzhan" || mark==="@mobile__zhenfeng_zhanlie") {
      const entry=takeState(actor,"zhenfeng",false);
      const actions={mobile__zhenfeng_hp:"play4",mobile__zhenfeng_lostHp:"play3",mobile__zhenfeng_alives:"play5"};
      const animation=actions[String(value)];
      if (!entry || !animation || entry.seen.indexOf(animation)>=0) return false;
      entry.seen.push(animation);
      return playState(entry,"shiTaiShiCi/SS_taishici_jineng",animation);
    }
    return false;
  }
  function routeQuest(data) {
    const actor=data[0];
    if (!skillIs(data[1],["zhongao","忠傲"])) return false;
    const entry=takeState(actor,"zhongao",true), state=publicState(actor).quest;
    if (!entry || (state!=="succeed" && state!=="failed")) return false;
    return playState(entry,"spell/zhongao/SS_ShiWeiYanSkill",state==="succeed" ? "play2" : "play1");
  }
  function routePublicProperty(data) {
    if (data[1]!=="hp") return false;
    const entry=takeState(data[0],"zhenfeng",false);
    if (!entry || !Number.isFinite(Number(entry.hp)) || Number(data[2])<=Number(entry.hp)) return false;
    takeState(data[0],"zhenfeng",true);
    return playState(entry,"shiTaiShiCi/SS_taishici_jineng","play2");
  }
  function routePublicMoves(data) {
    let played=false;
    for (const move of Array.from(data.merged || [])) {
      if (!skillIs(move.skillName,["futu","浮图"])) continue;
      const gaining=move.specialName==="futu_ye";
      const spending=move.fromSpecialName==="futu_ye";
      if (!gaining && !spending) continue;
      const actor=gaining ? move.to : move.from;
      const general=actorGeneral(actor,"zerong");
      if (!general || !owner.generalOwnsSkill(general,move.skillName)) continue;
      if (spending) {
        played=enqueue(general,"futu-protect","ui/anim/spell/futu/SS_pjn_skill_zr","play3",actor) || played;
        continue;
      }
      const colours=new Set();
      for (const raw of Array.from(move.ids || [])) {
        const id=Number(raw);
        if (!Number.isInteger(id) || id<=0 || data[String(id)]!==true) continue;
        try {
          const colour=Lua.ev('(function() local c=Fk:getCardById('+id+',true); return c and (c.color==Card.Red and "red" or c.color==Card.Black and "black" or "") or "" end)()');
          if (colour==="red" || colour==="black") colours.add(colour);
        } catch (_) {}
      }
      for (const colour of colours)
        played=enqueue(general,"futu-"+colour,"ui/anim/spell/futu/SS_pjn_skill_zr",colour==="red" ? "play1" : "play2",actor) || played;
    }
    return played;
  }
  function libraries() {
    if (manifests !== null) return manifests;
    const found = [];
    for (const pack of Config.enabledResourcePacks || []) {
      const root = Cpp.path + "/resource_pak/" + pack + "/packages/freekill-core/image/xinyuesha-handkill/";
      const path = root + "manifest.json";
      if (!owner.visualFileExists(path)) continue;
      try {
        // Packs live under resource_pak, outside the restricted assets folder.
        const data = Backend.readJsonObjectFromFile(path);
        if (data.schema === 1 && Array.isArray(data.effects) && data.effects.length <= 128)
          found.push({root:root, effects:data.effects});
      } catch (_) { console.warn("[HandkillPerformance] manifest unreadable"); }
    }
    manifests = found;
    return found;
  }
  function resource(stem, animation) {
    // These two original exports crash the shipped native parser. They remain
    // archived for repair; even an altered manifest cannot enable them.
    if (/SS_CM_2025zhenwang$|SS_2026smc_leishashouji2$/.test(stem)) return null;
    for (const pack of libraries()) {
      const row = pack.effects.find(e => e.stem === stem && e.nativeCompatible === true);
      if (!row || !/^ui\/anim\/[A-Za-z0-9_/-]+$/.test(row.stem) || row.stem.indexOf("..") >= 0 ||
          !Array.isArray(row.animations) || !row.animations.some(a => a.name === animation)) continue;
      // Original exports stay blocked. Only explicitly adapted copies with
      // the two known source identities may opt into their repaired routes.
      if (/_atlasfix1$/.test(stem)) {
        const source = stem.slice(0, -10), repair = row.repair;
        const expected = originalGapRepairs[source];
        if (!expected || !repair || repair.repairId !== "explicit-transparent-region-v1" ||
            repair.sourceStem !== source || repair.missingRegion !== expected.region ||
            repair.sourceSkeletonMD5 !== expected.md5 || repair.skeletonBytesChanged !== false ||
            repair.missingOriginalPixelsRecovered !== false) continue;
      }
      const base = pack.root + row.stem;
      if (owner.visualFileExists(base + ".atlas") && owner.visualFileExists(base + ".skel"))
        return {base:base, seconds:row.animations.find(a => a.name === animation).seconds};
    }
    return null;
  }
  readonly property var originalGapRepairs: ({
    "ui/anim/caomaozhengwang/SS_CM_2025zhenwang": {region:"texture/rwmhgx/rwmhgx_00059",md5:"2bc64fbcc8cfc0ebf03aad7447b7402b"},
    "ui/anim/spell/yuli/SS_2026smc_leishashouji2": {region:"shouji2/shouji2_ad_00012",md5:"9aabb28d98bc2e231d73dcd8a5af6bd7"}
  })
  function adaptedOriginalOrFallback(original, fallback) {
    const adapted = "ui/anim/" + original + "_atlasfix1";
    return resource(adapted, "play") ? original + "_atlasfix1" : fallback;
  }
  function enqueue(general, skill, stem, animation, actor, next) {
    const source = resource(stem, animation);
    if (!source) return false;
    const key = actor + ":" + general + ":" + skill + ":" + stem + ":" + animation;
    const now = Date.now();
    if (key === lastKey && now - lastAt < 250) return true;
    lastKey = key; lastAt = now;
    if (queue.length >= 4) return true;
    queue.push({general:general, skill:skill, stem:stem, animation:animation, actor:actor, next:next || []});
    startNext(); return true;
  }
  function startNext() {
    if (activeItem || !queue.length) return;
    if (gameFinished && !finalSceneReady) return;
    if (!room || !room.visible || Config.banChangeSkin) { reset(); return; }
    const request = queue.shift();
    const source = resource(request.stem, request.animation);
    if (!source) { Qt.callLater(startNext); return; }
    if (!playerComponent) playerComponent = Qt.createComponent("HandkillPerformance.qml");
    if (playerComponent.status !== Component.Ready) {
      console.warn(playerComponent.errorString()); queue = []; return;
    }
    const model=actorModel(request.actor);
    const portraitEffect=/\/spell\/(shizhouyu|kuanggu|yuli|tingwei)\//.test(request.stem);
    const jiangweiStage=/\/shenJiangWei\/SS_Sjw_skill[12]$/.test(request.stem);
    const frame=jiangweiStage ? resource("ui/anim/shenJiangWei/SS_Sjw_mask","play1") : null;
    if (jiangweiStage && !frame) {
      console.warn("[HandkillPerformance] Jiangwei companion frame unavailable");
      Qt.callLater(startNext); return;
    }
    const item = playerComponent.createObject(room, {resourceBase:source.base, general:request.general,
      skillName:request.skill, animationName:request.animation, followupAnimations:request.next,
      originalJiangweiLayout:jiangweiStage, frameBase:frame ? frame.base : "",
      anchorPhoto:portraitEffect && model ? model.photoItem : null});
    if (!item) { Qt.callLater(startNext); return; }
    activeItem = item;
    activeRequest = request;
    item.finished.connect(function(ok) {
      if (router.activeItem !== item) return;
      router.activeItem = null; router.activeRequest = null; item.destroy(); Qt.callLater(router.startNext);
    });
  }
  function route(command, data) {
    if (["EnterRoom","EnterLobby","BackToStart"].indexOf(command) >= 0) { reset(); return false; }
    if (command === "GameOver") { finishGame(); return false; }
    if (!room || !room.visible || Config.banChangeSkin) return false;
    if (command === "Fk.HandkillGameStart") { if (gameFinished) reset(); entryTimer.restart(); return false; }
    if (gameFinished) return false;
    if (!data) return false;
    if (!libraries().length) return false;
    if (command === "SetPlayerMark") return routePublicMark(data);
    if (command === "PropertyUpdate") return routePublicProperty(data);
    if (command === "Fk.HandkillQuest" || command === "UpdateQuestSkillUI") return routeQuest(data);
    if (command === "MoveCards") return routePublicMoves(data);
    if (command === "LogEvent" && data.type === "PlaySkillSound") return rememberSound(data);
    if (command === "Fk.HandkillPublicLog" && data.type === "#TiansuanResult") {
      const general=actorGeneral(data.player,"zhouqun");
      if (!general || ["tiansuanSSR","tiansuanS","tiansuanA","tiansuanB","tiansuanC"].indexOf(data.result)<0) return false;
      return enqueue(general,"tiansuan-result","ui/anim/spell/tiansuan/SSXF_PJN_zhongqian","play",data.player);
    }
    const death = (command === "Animate" || command === "LogEvent") && data.type === "Death";
    const skill = command === "Animate" && (data.type === "InvokeSkill" || data.type === "InvokeUltSkill");
    const card = command === "Fk.HandkillCard";
    if (!death && !skill && !card) return false;
    const actor = death ? data.to : data.player;
    if (actor == null || skill && !data.name) return false;
    const players = room.dataModel && room.dataModel.players || [];
    const model = Array.from(players).find(p => String(p.playerid !== undefined ? p.playerid : p.id) === String(actor));
    const photo = model && model.photoItem;
    if (!photo || !photo.visible) return false;
    const main = String(photo.general || model.general || "");
    const deputy = String(photo.deputyGeneral || model.deputyGeneral || "");
    const generals = skill && data.type === "InvokeUltSkill" ? [data.deputy ? deputy : main] : [main,deputy];
    for (const general of generals.filter(Boolean)) {
      if (skill && !owner.generalOwnsSkill(general, data.name)) continue;
      const play = function(stem, animation, next) {
        return router.enqueue(general, String(data.name || (death ? "death" : data.cardName)),
          "ui/anim/" + stem, animation || "play", actor, next);
      };
      if (death) {
        if (roleMatches(general,"jiangwei")) return play("shenJiangWei/SS_Sjw_dead");
        if (roleMatches(general,"caomao")) return play(adaptedOriginalOrFallback(
          "caomaozhengwang/SS_CM_2025zhenwang", "caomaozhengwang/SS_CM_zhenwang"));
        continue;
      }
      if (card) {
        if (!roleMatches(general,"zhaoyun")) continue;
        const files = {slash:"sha/SS_szy_sha",fire__slash:"sha/SS_szy_huosha",thunder__slash:"sha/SS_szy_leisha",jink:"shan/SS_szy_shan"};
        if (files[data.cardName]) return play("spell/ShiZhaoYun/" + files[data.cardName]);
        continue;
      }
      if (roleMatches(general,"jiangwei")) {
        if (skillIs(data.name,["xinghun","星魂","jiufa","九伐"])) return play("shenJiangWei/SS_Sjw_skill1");
        if (skillIs(data.name,["tiantao","天涛","pingxiang","平襄"])) return play("shenJiangWei/SS_Sjw_skill2");
      }
      if (roleMatches(general,"machao")) {
        if (skillIs(data.name,["jimie","寂灭"])) return play("spell/jimie/SS_smc_dazhao");
        if (skillIs(data.name,["tingwei","霆威"])) return rememberState(actor,"tingwei",general,data.name);
        if (skillIs(data.name,["yuli","驭雳"])) return play(data.skill_type==="defensive" ?
          adaptedOriginalOrFallback("spell/yuli/SS_2026smc_leishashouji2", "spell/yuli/SS_2026smc_huixue") :
          "spell/yuli/SS_2026smc_leishashouji1");
      }
      if (roleMatches(general,"weiyan")) {
        if (skillIs(data.name,["zhongao","忠傲"])) {
          // Audio 1 is the initial grant of Kuanggu, not quest success/failure.
          if (takeSound(general,data.name)===1) return false;
          return rememberState(actor,"zhongao",general,data.name);
        }
        if (skillIs(data.name,["kuanggu","狂骨"])) {
          const index=takeSound(general,data.name);
          const animation=index>=5 ? "play3" : index>=3 || Number(publicState(actor).kuanggu)>0 ? "play2" : "play1";
          return play("spell/kuanggu/SS_ShiWeiyanFaDongSkill",animation);
        }
        if (skillIs(data.name,["haokua","豪夸"])) return play("spell/haokua/SS_SWY_tongchang");
        if (skillIs(data.name,["yinzhan","饮战"])) return play("spell/haokua/SS_SWY_yinzhan");
      }
      if (roleMatches(general,"zhouyu")) {
        if (skillIs(data.name,["xiongzi","雄姿","jinlan","瑾澜"])) return rememberState(actor,"zhouyu",general,data.name);
        const actions={chiyun:"play1",chiyi:"play1",yanhui:"play3",yanling:"play3",fentao:"play2"};
        const name=skillName(data.name).split("__").pop(), animation=actions[name];
        const scheme=publicState(actor).zhouyu;
        if (animation && (scheme==="xiongzi_1" || scheme==="xiongzi_2"))
          return play("spell/shizhouyu/SS_jn_szyskill"+(scheme==="xiongzi_1" ? "blue" : "red"),animation);
      }
      if (roleMatches(general,"caomao") && skillIs(data.name,["juejin","绝进"])) return play("juejin/SS_cmskill");
      if (roleMatches(general,"taishici") && skillIs(data.name,["zhenfeng","振锋"])) return rememberState(actor,"zhenfeng",general,data.name);
      if (roleMatches(general,"zhouqun") && skillIs(data.name,["tiansuan","天算"])) return play("spell/tiansuan/SSXF_PJN_qiuqian");
      if (roleMatches(general,"simazhao") && skillIs(data.name,["zhaoxiong","昭凶"])) return play("xingSiMaZhao/SS_smz_fadongjineng");
      if (roleMatches(general,"lvbu") && skillIs(data.name,["wushuang","mouwushuang","无双","谋无双"])) return play("game/mouWuShuang/SS_MoulvbuSkill","play1",["play2"]);
    }
    return false;
  }
  Timer {
    id: finalDeathTimer
    interval: 80
    repeat: true
    onTriggered: {
      if (!router.room || !router.room.visible || Config.banChangeSkin) {router.reset();return;}
      const popup=router.room.popupItem;
      const big=router.room.bigAnim;
      const ready=popup && popup.visible && popup.opacity>=0.99 && popup.dataModel &&
        typeof popup.dataModel.winner==="string" && !(big && big.item && big.item.visible);
      router.finalSceneStableTicks=ready ? router.finalSceneStableTicks+1 : 0;
      if (router.finalSceneStableTicks>=3) {
        stop();router.finalSceneReady=true;router.startNext();
      } else if (Date.now()>=router.finalSceneDeadline) {
        stop();router.queue=[];
      }
    }
  }
  Timer {
    interval: 1000
    repeat: true
    running: Object.keys(router.pendingStates).length>0 || router.soundEvents.length>0
    onTriggered: {
      const live=({}), now=Date.now();
      for (const key of Object.keys(router.pendingStates))
        if (router.pendingStates[key].expires>now) live[key]=router.pendingStates[key];
      router.pendingStates=live;
      router.soundEvents=router.soundEvents.filter(e => now-e.at<3000);
    }
  }
  Timer {
    id: entryTimer
    interval: 700
    onTriggered: {
      if (!router.room || !router.room.visible || Config.banChangeSkin) return;
      for (const model of Array.from(router.room.dataModel && router.room.dataModel.players || [])) {
        const photo = model && model.photoItem;
        if (!photo || !photo.visible) continue;
        for (const g of [photo.general || model.general, photo.deputyGeneral || model.deputyGeneral]) {
          if (router.roleMatches(g,"zhouyu")) router.enqueue(String(g),"game-start",
            "ui/anim/shizhouyuenter/Ss_zy_ruchangzhanshi","play",model.playerid !== undefined ? model.playerid : model.id);
        }
      }
    }
  }
}
