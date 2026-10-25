// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Fk
import Fk.Widgets as W
import Fk.Components.Common

import LunarLtk

W.PageBase {
  id: root
  objectName: "SkinSetting"
  property var skins: []
  property bool scanning: true
  property int scanIndex: 0
  property int scanFileIndex: 0
  property var missingSkins: []
  property var pathHashes: ({})
  property var pendingDownloads: ({})
  property var unsolvedSkins: []
  property var currentDownloadArr: []
  property bool pause: false

  property var downloadPool: []
  property int poolIdx: 0
  property int activeCount: 0
  property int maxConcurrent: 5
  property var skinResults: []

  signal downloaded(bool ok, string path)
  signal allFinished()

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 30
    spacing: 20
    RowLayout {
      Layout.alignment: Qt.AlignTop
      Text {
        id: skinCount
        text: root.scanning ? "正在检查皮肤… " + root.scanIndex + "/" + root.skins.length : Lua.tr("Skins Count: ")
        font.bold: true
        color: '#979797'
        font.pixelSize: 30
      }
      Text {
        text: {
          return `${root.skins.length - root.unsolvedSkins.length} / ${root.skins.length}`
        }
        font.bold: true
        color: '#979797'
        font.pixelSize: 30
      }
      Text {
        Layout.leftMargin: 50
        text: Lua.tr("Download Threads: ") + String(root.maxConcurrent)
        font.bold: true
        color: '#585858'
        font.pixelSize: 22
      }
    }
    Rectangle {
      Layout.fillHeight: true
      Layout.fillWidth: true
      color: "transparent"
      border.width: 2
      border.color: '#535353'
      radius: 5

      LogEdit {
        id: log
        anchors.fill: parent
        anchors.margins: 20
      }
    }
  }

  Button {
    anchors {
      top: parent.top
      topMargin: 30
      right: parent.right
      rightMargin: 30
    }
    text: Lua.tr(currentDownloadArr.length > 0 ? (root.pause ? "Continue Download" : "Pause Download") : "Start Download")
    enabled: !root.scanning && root.unsolvedSkins.length > 0
    onClicked: {
      if (currentDownloadArr.length === 0) {
        root.startDownloadArray()
      } else if (root.pause) {
        root.pause = false;
        root.addLog(Lua.tr("Continue Skin Downloading"))
        root.pumpDownload();
        if (root.activeCount === 0 && root.poolIdx >= root.downloadPool.length) {
          root.allFinished();
        }
      } else root.pause = true;
    }
  }

  Connections {
    target: Backend
    function onAssetsDownloadFinished(ok, path, error) {
      // Other pages use this global signal too. Count only our outstanding
      // downloads, once each, so unrelated/duplicate events cannot over-pump.
      if (!root.pendingDownloads[path]) return;
      delete root.pendingDownloads[path];
      const doneIdx = downloadPool.findIndex(f => f.dest === path);
      const idx = doneIdx >= 0 ? doneIdx + 1 : poolIdx + 1;
      if (ok) {
        const spl = path.split("/")
        root.addLog(`<font color='green'><b>${Lua.tr("Download Success")}[${idx}/${downloadPool.length}]</b></font>: ${Lua.tr(spl[spl.length - 1] ?? path)}  ${spl}`)
      } else {
        root.addLog(`<font color='red'><b>${Lua.tr("Download Fail")}[${idx}/${downloadPool.length}]</b>: ${error}`)
      }
      downloaded(ok, path)
    }
  }

  onDownloaded: (ok, path) => {
    activeCount--;
    const doneIdx = downloadPool.findIndex(f => f.dest === path);
    if (doneIdx >= 0 && !ok) {
      skinResults[downloadPool[doneIdx].skinIdx] = false;
    }
    if (pause) {
      addLog(Lua.tr("Skin Downloading Paused"));
      // 暂停期间所有在飞下载都已收尾且池已排空时，也要正常收尾
      if (activeCount === 0 && poolIdx >= downloadPool.length) {
        allFinished()
      }
      return;
    }
    pumpDownload();
    if (activeCount === 0 && poolIdx >= downloadPool.length) {
      allFinished()
    }
  }

  onAllFinished: {
    const failed = skinResults.filter(r => !r).length;
    addLog(Lua.tr("All skins downloaded: success: %1; fail: %2; total: %3").arg(currentDownloadArr.length - failed).arg(failed).arg(currentDownloadArr.length));
    currentDownloadArr = [];
    pause = false;
    beginScan();
  }

  function startDownloadArray() {
    addLog(Lua.tr("Start Downloading Skins"));
    currentDownloadArr = [...unsolvedSkins];
    skinResults = currentDownloadArr.map(() => true);
    poolIdx = 0;
    activeCount = 0;

    downloadPool = generateFiles();
    for (let i = 0; i < Math.min(maxConcurrent, downloadPool.length); i++) {
      pumpDownload();
    }
  }

  function downloadFile(file) {
    root.addLog(`${Lua.tr("Downloading: ")}${file.path + file.fileName}`);
    pendingDownloads[file.dest] = true;
    Fs.downloadFileToAssets(file.path + file.fileName, file.dest);
  }

  function generateFiles() {
    const files = [];
    for (let i = 0; i < currentDownloadArr.length; i++) {
      const skin = currentDownloadArr[i];
      const hash = Ltk.urlToBase62(skin.path)
      if (skin.is_skel) {
        skin.files.forEach(f => files.push({
          path: skin.path,
          fileName: f,
          dest: `lunarltk/skel/${hash}/${f}`,
          skinIdx: i
        }))
      } else {
        files.push({
          path: skin.path,
          fileName: skin.name,
          dest: `lunarltk/skins/${hash}/${skin.name}`,
          skinIdx: i
        })
      }
    }
    return files
  }

  function pumpDownload() {
    if (pause || activeCount >= maxConcurrent || poolIdx >= downloadPool.length) return;
    const file = downloadPool[poolIdx];
    poolIdx++;
    activeCount++;
    downloadFile(file);
  }

  function getSkins() {
    return Lua.evaluate(`(function()
      local skins, seen = {}, {}
      for _, group in pairs(Fk.skin_packages or {}) do
        for _, data in pairs(group) do
          if type(data) == "table" and type(data.path) == "string" and type(data.name) == "string" then
            local key = data.path .. "\\0" .. data.name
            if not seen[key] and data.path:match("^https?://") then
              seen[key] = true
              skins[#skins + 1] = data
            end
          end
        end
      end
      return skins
    end)()`) ?? [];
  }
  function beginScan() {
    scanning=true; scanIndex=0; scanFileIndex=0; missingSkins=[]; pathHashes={}; scanStep.restart();
  }
  Timer {
    id:scanStep; interval:1; repeat:false
    onTriggered: {
      // Bound file-system calls per event-loop turn, including skeletal skins
      // with hundreds of files. The page can paint and respond to Back meanwhile.
      const end=Date.now()+4;
      let checked=0;
      while (root.scanIndex < root.skins.length && checked < 16 && Date.now() <= end) {
        const skin=root.skins[root.scanIndex];
        let hash=root.pathHashes[skin.path];
        if (!hash) { hash=Ltk.urlToBase62(skin.path); root.pathHashes[skin.path]=hash; }
        const files=skin.is_skel ? (skin.files || []) : [skin.name];
        if (!files.length) { root.scanIndex++;root.scanFileIndex=0;continue; }
        const dir=skin.is_skel ? "skel" : "skins";
        const exists=Fs.resolveFile(`${Cpp.path}/assets/lunarltk/${dir}/${hash}/${files[root.scanFileIndex]}`);
        checked++;
        if (!exists) {
          root.missingSkins.push(skin);root.scanIndex++;root.scanFileIndex=0;
        } else if (++root.scanFileIndex >= files.length) {root.scanIndex++;root.scanFileIndex=0;}
      }
      if (root.scanIndex < root.skins.length) restart();
      else {
        root.unsolvedSkins=root.missingSkins.slice();root.scanning=false;
        root.addLog(Lua.tr("Total skins %1, %2 skins waiting for downloading").arg(root.skins.length).arg(root.unsolvedSkins.length));
      }
    }
  }
  Timer {id:initialize;interval:1;onTriggered:{root.skins=root.getSkins();root.beginScan();}}
  function addLog(msg) {
    log.append({
      logText: msg
    })
  }

  Component.onCompleted: initialize.start()
}
