// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls

import Fk
import Fk.Widgets as W
import LunarLtk
import LunarLtk.Components

Item {
  id: root

  property alias currentIndex: logView.currentIndex
  property string selectedLogSeat: ""

  clip: true

  ListModel { id: logModel }
  ListModel { id: filteredLogModel }
  ListModel { id: filterModel }

  function escapeRegExp(value) {
    return String(value ?? "").replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  }

  function stripRichText(value) {
    return String(value ?? "").replace(/<[^>]*>/g, "");
  }

  function getSelfId() {
    try {
      return Self.id;
    } catch (e) {
      return 0;
    }
  }

  function getParticipants() {
    try {
      return Lua.getPlayersAndObservers();
    } catch (e) {
      return [];
    }
  }

  function logMatchesFilter(logEntry) {
    return root.selectedLogSeat === ""
      || logEntry.fixedFlow
      || logEntry.playerSeats.indexOf("," + root.selectedLogSeat + ",") !== -1;
  }

  function appendFilteredLog(logEntry) {
    if (logMatchesFilter(logEntry)) {
      filteredLogModel.append(logEntry);
    }
  }

  function rebuildFilteredLogs() {
    filteredLogModel.clear();
    for (let index = 0; index < logModel.count; index++) {
      appendFilteredLog(logModel.get(index));
    }
    Qt.callLater(() => logView.positionViewAtEnd());
  }

  function buildPossiblePlayerNames(player) {
    const names = [];
    const seat = player.seat;
    const selfSuffix = player.id === getSelfId() ? Lua.tr("playerstr_self") : "";
    names.push(Lua.tr("seat#" + seat) + selfSuffix);

    const general = player.general ?? "";
    const deputy = player.deputy ?? "";
    if (general !== "" && general !== "anjiang") {
      let translated = Lua.tr(general);
      if (deputy !== "" && deputy !== "anjiang") {
        translated += "/" + Lua.tr(deputy);
      }
      names.push(translated + selfSuffix);
      names.push(translated + "[" + seat + "]" + selfSuffix);
    }

    return names;
  }

  function extractLogSeats(rawContent) {
    const referencedNames = [];
    const playerTag = new RegExp(
      "<font\\s+color\\s*=\\s*['\"](?:#0C8F0C|#CC3131)['\"]\\s*>"
      + "\\s*<b>(.*?)</b>\\s*</font>", "gi");
    let playerMatch;
    while ((playerMatch = playerTag.exec(rawContent)) !== null) {
      referencedNames.push(stripRichText(playerMatch[1]));
    }
    if (referencedNames.length === 0) return [];

    const seats = [];
    const participants = getParticipants();
    for (const player of participants) {
      if (player.observing || player.seat <= 0) continue;

      const possibleNames = buildPossiblePlayerNames(player);
      const matched = possibleNames.some(name => referencedNames.indexOf(name) !== -1);
      if (matched) {
        const seat = String(player.seat);
        if (seats.indexOf(seat) === -1) {
          seats.push(seat);
        }
      }
    }
    return seats;
  }

  function isFixedFlowLog(rawContent) {
    const fixedLogKeys = [
      "$AppendSeparator",
      "$GameStart",
      "$GameEnd",
      "$TurnStart",
      "$ExtraTurnStart",
      "$TurnEnd",
      "$ExtraTurnEnd",
      "$RoundStart",
      "$RoundEnd",
    ];
    const plainContent = stripRichText(rawContent);
    return fixedLogKeys.some(key => {
      const plainTemplate = stripRichText(Lua.tr(key) ?? "");
      const pattern = escapeRegExp(plainTemplate)
        .replace(/%from|%to|%card|%arg[2-9]?/g, ".*?");
      return new RegExp("^" + pattern + "$").test(plainContent);
    });
  }

  function refreshFilterModel() {
    const oldSeat = root.selectedLogSeat;
    filterModel.clear();
    filterModel.append({
      seat: "",
      label: Lua.tr("All").slice(0, 1),
      avatar: "",
    });

    const players = getParticipants()
      .filter(player => !player.observing && player.seat > 0)
      .sort((a, b) => a.seat - b.seat);
    for (const player of players) {
      filterModel.append({
        seat: String(player.seat),
        label: Lua.tr("seat#" + player.seat).slice(0, 1),
        avatar: player.general ?? player.avatar ?? "",
      });
    }

    if (oldSeat !== "" && !players.find(player => String(player.seat) === oldSeat)) {
      root.selectedLogSeat = "";
    }
  }

  onSelectedLogSeatChanged: rebuildFilteredLogs()
  Component.onCompleted: refreshFilterModel()

  Row {
    id: filterBar
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: 46
    spacing: 4
    readonly property bool needsScrollButtons: filterList.contentWidth > filterBar.width

    W.ButtonContent {
      width: 25
      height: parent.height
      text: "‹"
      visible: filterBar.needsScrollButtons
      enabled: filterList.contentX > 0
      onClicked: filterList.contentX = Math.max(0, filterList.contentX - filterList.width * 0.8)
    }

    ListView {
      id: filterList
      width: filterBar.needsScrollButtons ? parent.width - 55 : parent.width
      height: parent.height
      orientation: ListView.Horizontal
      spacing: 4
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: filterModel
      onContentWidthChanged: {
        if (!filterBar.needsScrollButtons) {
          contentX = 0;
        }
      }

      delegate: W.ButtonContent {
        required property string seat
        required property string label
        required property string avatar
        readonly property bool allPlayers: seat === ""

        height: filterList.height
        width: allPlayers ? 39 : 46
        checkable: true
        checked: root.selectedLogSeat === seat
        backgroundColor: checked ? "#6B9BB4" : "#E6E6E7"
        onClicked: root.selectedLogSeat = seat

        contentItem: Item {
          Text {
            visible: parent.parent.allPlayers
            anchors.fill: parent
            text: parent.parent.label
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            color: parent.parent.checked ? "#ffffff" : "#202020"
            font.pixelSize: 14
          }

          CompactGeneralCardItem {
            visible: !parent.parent.allPlayers
            enabled: false
            anchors.centerIn: parent
            width: 40
            height: 40
            onClicked: root.selectedLogSeat = parent.parent.seat
            dataModel: Ltk.createGeneralCardModel(parent.parent.avatar || "0", {
              prefix: parent.parent.label,
              showIsFavorite: false,
            })
          }
        }
      }
    }

    W.ButtonContent {
      width: 25
      height: parent.height
      text: "›"
      visible: filterBar.needsScrollButtons
      enabled: filterList.contentX < filterList.contentWidth - filterList.width
      onClicked: filterList.contentX = Math.min(
        Math.max(0, filterList.contentWidth - filterList.width),
        filterList.contentX + filterList.width * 0.8)
    }
  }

  ListView {
    id: logView
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: filterBar.bottom
    anchors.bottom: parent.bottom
    anchors.topMargin: 4
    clip: true

    highlight: Rectangle { color: "#EEEEEE"; radius: 5 }
    highlightMoveDuration: 500

    ScrollBar.vertical: ScrollBar {
      parent: logView.parent
      anchors.top: logView.top
      anchors.right: logView.right
      anchors.bottom: logView.bottom
    }

    model: filteredLogModel
    delegate: Rectangle {
      width: logView.width
      height: childrenRect.height
      color: "transparent"

      W.TapHandler {
        onTapped: {
          logView.currentIndex = index;
        }
      }

      TextEdit {
        z: -1 // 挡住我taphandler了
        text: logText
        width: parent.width
        clip: true
        readOnly: true
        selectByKeyboard: true
        selectByMouse: false
        wrapMode: TextEdit.WrapAnywhere
        textFormat: TextEdit.RichText
        font.pixelSize: 16
      }
    }
  }

  Button {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    text: Lua.tr("Return to Bottom")
    visible: !logView.atYEnd && filteredLogModel.count > 0
    onClicked: logView.positionViewAtEnd()
  }

  function clear() {
    logModel.clear();
    filteredLogModel.clear();
    refreshFilterModel();
    logView.currentIndex = 0;
  }

  function append(data) {
    refreshFilterModel();
    const rawContent = String(data?.logText ?? data?.content ?? data ?? "");
    const logEntry = {
      logText: rawContent,
      playerSeats: "," + extractLogSeats(rawContent).join(",") + ",",
      fixedFlow: isFixedFlowLog(rawContent),
    };
    const followBottom = logView.atYEnd || filteredLogModel.count === 0;
    logModel.append(logEntry);
    appendFilteredLog(logEntry);
    if (followBottom && logMatchesFilter(logEntry)) {
      Qt.callLater(() => logView.positionViewAtEnd());
    }
  }
}
