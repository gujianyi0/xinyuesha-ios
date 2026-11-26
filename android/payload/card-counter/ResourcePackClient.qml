// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Fk

Item {
  id: client
  required property var owner
  readonly property string bridge:"resource-pack-download/"
  property string requestId:""
  property string operation:""
  property string installing:""
  property string status:""
  property var packs:[]
  property double activityAt:0
  property double startedAt:0
  property double progressDone:-1
  property string progressStage:""
  property bool cancelling:false
  signal installed(string pack)
  signal removed(string pack)
  function read(name) {
    try {
      if(typeof Backend.existsInAssets==="function"&&!Backend.existsInAssets(bridge+name))return null;
      return JSON.parse(Backend.readFileFromAssets(bridge+name)||"null");
    }catch(_){return null;}
  }
  function request(action,pack) {
    if(requestId)return false;
    const id=Date.now().toString()+"_"+Math.floor(Math.random()*1000000);
    operation=action;installing=pack;
    if(!Backend.writeFileToAssets(bridge+"request.json",JSON.stringify({id:id,operation:action,pack:pack}))) {status="无法写入下载请求";return false;}
    requestId=id;activityAt=Date.now();startedAt=activityAt;progressDone=-1;progressStage="";cancelling=false;
    status=action==="install"?"正在连接下载服务…":action==="uninstall"?"正在删除…":"正在读取资源列表…";
    return true;
  }
  function cancel() {
    if(operation!=="install"||!requestId)return;
    if(Backend.writeFileToAssets(bridge+"cancel.json",JSON.stringify({id:requestId}))) {cancelling=true;status="正在取消，已缓存部分会保留…";}
  }
  function loadFallback() {
    if(typeof Backend.readJsonObjectFromFile!=="function")return;
    const data=Backend.readJsonObjectFromFile("card-counter/resource-catalog.json");
    if(data && data.schema===2 && data.packs)packs=Array.from(data.packs);
  }
  function restore() {
    loadFallback();
    const ack=read("ack.json"),reply=read("reply.json"),pending=read("active.json")||read("request.json");
    if(pending && pending.id && pending.operation==="install") {
      requestId=pending.id;operation="install";installing=pending.pack||"";activityAt=Date.now();startedAt=activityAt;status="正在恢复资源下载…";
    }else if(reply && reply.id && reply.ok && reply.operation==="install" && (!ack || ack.id!==reply.id)) {
      requestId=reply.id;operation="install";installing=reply.pack||"";activityAt=Date.now();startedAt=activityAt;
    }
    poll();
  }
  function poll() {
    if(!requestId)return;
    const reply=read("reply.json");
    if(reply && reply.id===requestId) {
      // Configuration must finish loading before enabling a completed download.
      // This owner survives navigation away from the manager page.
      if(reply.ok && operation==="install" && !owner.settingsReady)return;
      if(!reply.ok)status=reply.error||"资源下载失败，请重试";
      else if(operation==="catalog") {packs=reply.packs||[];status="";}
      else if(operation==="install") {
        const enabled=Array.from(Config.enabledResourcePacks||[]);
        if(!enabled.includes(reply.pack)){Config.enabledResourcePacks=[reply.pack].concat(enabled);Config.saveConf();}
        status="";installed(reply.pack);
      }else if(operation==="uninstall"){status="";removed(reply.pack);}
      Backend.writeFileToAssets(bridge+"ack.json",JSON.stringify({id:reply.id}));requestId="";cancelling=false;return;
    }
    const progress=read("progress.json");
    if(progress && progress.id===requestId && (Number(progress.done)!==progressDone || progress.stage!==progressStage)) {
      activityAt=Date.now();progressDone=Number(progress.done);progressStage=progress.stage;
      if(!cancelling)status=(progress.stage==="extracting"?"正在校验并安装":"正在下载")+" · "+Math.floor(progressDone/1048576)+" / "+Math.ceil(Number(progress.total)/1048576)+" MB · "+progress.part+"/"+progress.parts;
    }
    const idleLimit=operation==="install"?120000:45000;
    if(Date.now()-activityAt>idleLimit || Date.now()-startedAt>21600000) {
      // Do not abandon an active job and then allow another request to race it.
      if(operation==="install"){if(!cancelling)cancel();status="下载长时间没有进度，正在停止；随后可重试继续下载。";}
      else {status="请求超时，请刷新重试";requestId="";}
    }
  }
  Connections {target:client.owner;ignoreUnknownSignals:true;function onSettingsReadyChanged(){client.poll();}}
  Component.onCompleted:restore()
  Timer {interval:400;repeat:true;running:client.requestId!=="";onTriggered:client.poll()}
}
