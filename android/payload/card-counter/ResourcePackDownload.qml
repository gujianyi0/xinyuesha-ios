// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Controls.Material
import Fk

// Adds download rows to the original left-hand ListView. The page owns all
// installed/enabled rows, priority controls, search and navigation.
Item {
  id: entry
  required property Item managerPage
  required property var client
  readonly property string requestId:client.requestId
  readonly property string operation:client.operation
  readonly property string installing:client.installing
  readonly property string status:client.status
  readonly property var packs:client.packs
  property var availableView: null
  property var searchField: null
  property var enabledModel: null
  readonly property var offers: packs.filter(pack =>
    !managerPage.fullAvailableList.includes(pack.id) && !managerPage.fullEnabledList.includes(pack.id) &&
    (!searchField || (pack.title + pack.version).toLowerCase().includes(searchField.text.trim().toLowerCase())))

  function attach() {
    const views = [];
    function walk(item) {
      if (!item || item === entry) return;
      if (typeof item.positionViewAtIndex === "function" && "header" in item && "delegate" in item)
        views.push(item);
      if ("placeholderText" in item && "text" in item) searchField = item;
      if ("text" in item && (item.text === "保存" || item.text === "Save") &&
          item.parent && item.parent.parent === managerPage) item.parent.visible = false;
      for (const child of item.children || []) walk(child);
    }
    walk(managerPage);
    views.sort((a, b) => a.mapToItem(managerPage, 0, 0).x - b.mapToItem(managerPage, 0, 0).x);
    if (views.length !== 2) { console.warn("[ResourcePacks] Unsupported manager layout"); return; }
    availableView = views[0];
    // Preserve the stock two-column layout, but anchor its top below the
    // actual toolbar height rather than the stock fixed 60px top margin.
    const leftBox = views[0].parent && views[0].parent.parent;
    const rightBox = views[1].parent && views[1].parent.parent;
    const columns = leftBox && leftBox.parent;
    const toolbar = Array.from(managerPage.children || []).find(c => String(c).indexOf("ToolBar_QMLTYPE") === 0);
    if (toolbar) styleToolbar(toolbar);
    if (toolbar && columns && rightBox && rightBox.parent === columns && "spacing" in columns) {
      columns.anchors.verticalCenter = undefined;
      columns.anchors.topMargin = Qt.binding(() => toolbar.height + 20);
      columns.anchors.bottomMargin = 24;
      for (const box of [leftBox, rightBox]) {
        box.Layout.minimumHeight = 0;
        box.Layout.preferredHeight = 420;
        box.Layout.fillHeight = true;
      }
    }
    availableView.header = downloadRows;
    availableView.delegate = installedAvailableRow;
    availableView.clip = true;
    enabledModel = views[1].model;
    views[1].delegate = enabledRow;
    views[1].clip = true;
    Qt.callLater(saveEnabled);
    request("catalog", "");
  }
  Component.onCompleted: Qt.callLater(attach)
  Component.onDestruction: if (availableView) availableView.header = null

  Component {
    id: toolbarBackground
    Rectangle {
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: "#193842" }
        GradientStop { position: 0.55; color: "#244651" }
        GradientStop { position: 1; color: "#182f39" }
      }
      Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: "#a99159"; opacity: 0.75 }
    }
  }
  Component {
    id: searchBackground
    Rectangle {
      implicitWidth: 220
      implicitHeight: 44
      radius: 9
      color: "#16ffffff"
      border.width: 1
      border.color: entry.searchField && entry.searchField.activeFocus ? "#d2bb7b" : "#6083979b"
    }
  }
  function styleToolbar(toolbar) {
    toolbar.Material.theme = Material.Dark;
    toolbar.Material.accent = "#ddc487";
    toolbar.implicitHeight = 64;
    toolbar.background = toolbarBackground.createObject(toolbar);
    const pending = Array.from(toolbar.children || []);
    while (pending.length) {
      const item = pending.pop();
      if (!item) continue;
      if (item === searchField) {
        item.background = searchBackground.createObject(item);
        item.color = "#f2eadb";
        item.placeholderTextColor = "#bed0cf";
        item.font.pixelSize = 15;
        item.leftPadding = 12;
        item.rightPadding = 12;
        item.topPadding = 10;
        item.bottomPadding = 10;
      } else if ("text" in item && "font" in item && String(item).indexOf("Label_QMLTYPE") === 0) {
        item.color = "#f2e5cb";
        item.font.pixelSize = 18;
        item.font.bold = true;
        item.font.letterSpacing = 1;
      }
      if ("clicked" in item && "icon" in item) {
        item.icon.color = "#e1c98e";
        if (item.text === "撤销更改" || item.text === "Undo Changes") {
          item.text = "刷新";
          item.clicked.connect(function() { if (!entry.requestId) entry.request("catalog", ""); });
        }
      }
      if (item.children) pending.push(...Array.from(item.children));
    }
  }

  function saveEnabled() {
    const list = managerPage.fullEnabledList.slice();
    if (JSON.stringify(Config.enabledResourcePacks || []) !== JSON.stringify(list)) {
      Config.enabledResourcePacks = list;
      Config.saveConf();
    }
    managerPage.currentEnabled = list.slice();
  }
  Connections {
    target: entry.enabledModel
    function onCountChanged() { Qt.callLater(entry.saveEnabled); }
  }

  Component {
    id: installedAvailableRow
    ItemDelegate {
      id: localEntry
      required property string name
      width: ListView.view ? ListView.view.width : 0
      height: 64
      enabled: entry.requestId === ""
      onClicked: entry.managerPage.enablePack(name)
      contentItem: RowLayout {
        spacing: 6
        Image {
          source: Cpp.path + "/resource_pak/" + localEntry.name + "/icon.png"
          Layout.preferredWidth: 36
          Layout.preferredHeight: 36
          fillMode: Image.PreserveAspectFit
        }
        Label {
          text: { const pack = entry.packs.find(p => p.id === localEntry.name); return pack ? pack.title : localEntry.name; }
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          font.bold: true
          elide: Text.ElideRight
        }
        ToolButton {
          text: "删除"
          font.pixelSize: 16
          implicitWidth: 62
          implicitHeight: 48
          onClicked: entry.request("uninstall", localEntry.name)
        }
      }
    }
  }

  Component {
    id: enabledRow
    ItemDelegate {
      id: enabledEntry
      required property string name
      required property int index
      width: ListView.view ? ListView.view.width : 0
      height: 64
      contentItem: RowLayout {
        spacing: 4
        Image {
          source: Cpp.path + "/resource_pak/" + enabledEntry.name + "/icon.png"
          Layout.preferredWidth: 36
          Layout.preferredHeight: 36
          fillMode: Image.PreserveAspectFit
        }
        Label {
          text: { const pack = entry.packs.find(p => p.id === enabledEntry.name); return pack ? pack.title : enabledEntry.name; }
          font.bold: true
          font.pixelSize: 15
          elide: Text.ElideRight
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          ToolTip.visible: pointer.hovered
          ToolTip.text: enabledEntry.name
          HoverHandler { id: pointer }
        }
        ToolButton {
          text: "↑"
          font.pixelSize: 24
          implicitWidth: 48
          implicitHeight: 48
          enabled: enabledEntry.index > 0
          onClicked: entry.managerPage.moveEnabledUp(enabledEntry.name)
          onPressAndHold: entry.managerPage.moveEnabledToTop(enabledEntry.name)
        }
        ToolButton {
          text: "↓"
          font.pixelSize: 24
          implicitWidth: 48
          implicitHeight: 48
          enabled: enabledEntry.index < entry.managerPage.fullEnabledList.length - 1
          onClicked: entry.managerPage.moveEnabledDown(enabledEntry.name)
          onPressAndHold: entry.managerPage.moveEnabledToBottom(enabledEntry.name)
        }
        ToolButton {
          text: "×"
          font.pixelSize: 24
          implicitWidth: 48
          implicitHeight: 48
          onClicked: entry.managerPage.disablePack(enabledEntry.name)
        }
      }
    }
  }

  Component {
    id: downloadRows
    Column {
      width: ListView.view ? ListView.view.width : 0
      spacing: 4
      Repeater {
        model: entry.offers
        delegate: ItemDelegate {
          required property var modelData
          width: parent ? parent.width : 0
          height: 64
          enabled: entry.requestId === ""
          contentItem: RowLayout {
            spacing: 10
            Label { text: "↓"; font.pixelSize: 24; Layout.preferredWidth: 36; horizontalAlignment: Text.AlignHCenter }
            ColumnLayout {
              Layout.fillWidth: true
              spacing: 1
              Label { text: modelData.title; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
              Label {
                text: entry.installing === modelData.id && entry.requestId !== "" ? "正在下载并校验…" : modelData.version + " · " + (Number(modelData.bytes)/1048576).toFixed(0) + " MB · 下载并启用"
                elide: Text.ElideRight
                font.pixelSize: 12
                Layout.fillWidth: true
              }
            }
          }
          onClicked: { entry.request("install", modelData.id); }
        }
      }
      Label {
        width: parent ? parent.width : 0
        visible: entry.status !== ""
        text: entry.status
        wrapMode: Text.WordWrap
      }
      ToolButton {
        visible:entry.requestId!=="" && entry.operation==="install"
        text:entry.client.cancelling?"正在取消…":"取消下载"
        enabled:!entry.client.cancelling
        onClicked:entry.client.cancel()
      }
      ToolButton {
        visible: entry.requestId === "" && entry.status !== ""
        text: "重试"
        onClicked: entry.request("catalog", "")
      }
    }
  }
  function request(action,pack){client.request(action,pack);}
  function syncInstalled(pack) {
    const page=managerPage;
    page.fullAvailableList=page.fullAvailableList.filter(name=>name!==pack);
    if(!page.fullEnabledList.includes(pack))page.fullEnabledList=[pack].concat(page.fullEnabledList);
    page.rebuildListModels();
  }
  Connections {
    target:entry.client
    function onInstalled(pack){entry.syncInstalled(pack);}
    function onRemoved(pack){entry.managerPage.fullAvailableList=entry.managerPage.fullAvailableList.filter(name=>name!==pack);entry.managerPage.rebuildListModels();}
    function onPacksChanged(){
      const retired=["轻特效v1-20261119-1","轻特效v1-20261119-2","轻特效v1-20261120-3"];
      entry.managerPage.fullAvailableList=entry.managerPage.fullAvailableList.filter(name=>!retired.includes(name));
      entry.managerPage.fullEnabledList=entry.managerPage.fullEnabledList.filter(name=>!retired.includes(name));
      entry.managerPage.rebuildListModels();
    }
  }
}
