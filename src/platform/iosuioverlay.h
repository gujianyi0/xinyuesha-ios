// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "iosruntimepayload.h"
#include <QCryptographicHash>
#include <QDirIterator>
#include <QRegularExpression>
#include <QMap>

namespace fkIosUiOverlay {
// Build the frontend from the currently selected core, outside packages/. Lua,
// Git metadata and checksum inputs remain byte-for-byte unchanged. Rebuild from
// source on every core change, rather than pinning an old copy of the UI.
inline QString adapt(const QString &path, QString text) {
  if (path == "Fk/Pages/Common/JoinServer.qml") {
    text.replace("text: delay + \" ms \" + misMatchMsg",
      "text: delay + \" ms \" + String(misMatchMsg).replace(/\\s+size\\s*=\\s*[\\\"'][^\\\"']*[\\\"']/gi, '')");
    if (!text.contains("maximumLineCount: 1")) {
      text.replace("ColumnLayout {\n          Layout.fillWidth: true",
        "ColumnLayout {\n          Layout.minimumWidth: 0\n          Layout.fillWidth: true");
      text.replace("horizontalAlignment: Text.AlignLeft",
        "font.pixelSize: 14\n            elide: Text.ElideRight\n            maximumLineCount: 1\n            horizontalAlignment: Text.AlignLeft");
    }
    text.replace("font.pixelSize: 26", "font.pixelSize: 18");
    text.replace("spacing: 16", "spacing: 8");
  } else if (path == "Fk/Pages/Lobby/Lobby.qml") {
    // Custom ButtonContent.qml is an AbstractButton, not a native style delegate.
    text.replace("text: Lua.tr(\"Exit Lobby\")",
      "text: Lua.tr(\"Exit Lobby\")\n    contentItem: Text {\n      text: parent.text; color: parent.enabled ? 'black' : 'gray'\n      font: parent.font\n      horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter\n      elide: Text.ElideRight\n    }");
  } else if (path == "LunarLtk/Pages/InfoPopups/GeneralDetail.qml") {
    text.replace("property list<string> generals", "property var generals: []");
    // A Flickable has zero implicitHeight. Filling its ColumnLayout parent's
    // height creates a zero-height cycle, so skill text exists but is invisible.
    text.replace("height: parent.height\n      contentHeight: skillDesc.height",
      "Layout.fillWidth: true\n      Layout.preferredHeight: skillDesc.implicitHeight\n      contentHeight: skillDesc.height");
  } else if (path == "LunarLtk/Models/Popups/MoveCardInBoardModel.qml") {
    // A property map cannot initialize these primitive lists on Qt 6.8 iOS.
    // Keep the server-provided candidates/positions intact as JS arrays.
    text.replace("property list<int> cardIds", "property var cardIds: []");
    text.replace("property list<int> cardsPosition", "property var cardsPosition: []");
    text.replace("property list<int> playerIds", "property var playerIds: []");
  } else if (path == "LunarLtk/Pages/InfoPopups/ViewPile.qml" || path == "LunarLtk/Pages/InfoPopups/ViewGeneralPile.qml") {
    // Qt 6.8 does not consistently initialize/consume primitive QML list
    // properties as models when created with a JavaScript property map.
    text.replace("property list<int> ids", "property var ids: []");
    text.replace("property list<string> cardNames", "property var cardNames: []");
  } else if (path == "Fk/Widgets/PopupItem.qml") {
    text.replace("    item.destroy();\n    item = null;", "    if (item) item.destroy();\n    item = null;");
    text.replace("item = component.createObject(container, prop);",
      "item = component.createObject(container, prop || {});\n"
      "    if (!item) { console.warn('[iOS UI] Popup creation failed: ' + component.errorString()); close(); return; }\n"
      "    item.width = Qt.binding(function() { return container.width; });\n"
      "    item.height = Qt.binding(function() { return container.height; });");
  } else if (path == "LunarLtk/LtkLuaUtil.qml") {
    // list<var> exposes map values as QVariantMap copies in Qt 6.8. Mutating
    // the returned entry neither writes back nor notifies an existing delegate.
    // Replace the list element so count, popup data and description all update.
    const QRegularExpression markUpdate(
      "    if \\(elem\\) \\{\\s*elem\\.value = textValue;\\s*elem\\.origValue = value;"
      "\\s*elem\\.qml = qmlComponentSpec;\\s*elem\\.desc = desc;\\s*\\} else \\{");
    text.replace(markUpdate, R"QML(    if (elem) {
      marks.splice(elemIdx, 1, Object.assign({}, elem, {
        value: textValue, origValue: value, qml: qmlComponentSpec, desc: desc
      }));
    } else {)QML");
  } else if (path == "LunarLtk/Models/PhotoModel.qml") {
    // QVariantList iteration can expose temporary map wrappers in Qt 6.8.
    // Mutating each wrapper does not update the original list; publish copies.
    const QRegularExpression targetTips("  function updateTargetTip\\(\\) \\{.*?\\n  \\}", QRegularExpression::DotMatchesEverythingOption);
    text.replace(targetTips, R"QML(  function updateTargetTip() {
    const dataList = Ltk.getTargetTip(playerid);
    targetTip = Array.from(dataList || [], function(data) {
      return Object.assign({}, data, {content: Ltk.processPrompt(data.content)});
    });
  })QML");
    const QRegularExpression method("  function updateLimitSkill\\(skill, time\\) \\{.*?\\n  \\}", QRegularExpression::DotMatchesEverythingOption);
    text.replace(method, R"QML(  function updateLimitSkill(skill, time) {
    const next = Array.from(limitSkills);
    const index = next.findIndex(e => e.skill === skill);
    if (time < 0) { if (index >= 0) next.splice(index, 1); }
    else if (index >= 0) next[index] = { skill: skill, time: time };
    else next.push({ skill: skill, time: time });
    limitSkills = next;
  })QML");
  } else if (path == "LunarLtk/Models/CardModel.qml") {
    const QRegularExpression tip("  function updateCardTip\\(\\) \\{.*?\\n  \\}", QRegularExpression::DotMatchesEverythingOption);
    text.replace(tip, R"QML(  function updateCardTip() {
    const dataList = Ltk.getCardTip(cardId);
    cardTip = Array.from(dataList || [], function(data) {
      return Object.assign({}, data, {content: Ltk.processPrompt(data.content)});
    });
  })QML");
  } else if (path == "LunarLtk/Components/CardItem.qml") {
    // Lua-created/expanded cards can supply tip maps directly. Translate at
    // rendering as well, without depending on mutation of a QVariantMap.
    text.replace("text: parent.modelData.content",
      "text: Lua.tr(String(parent.modelData.content || ''))");
  } else if (path == "LunarLtk/Components/Photo/LimitSkillItem.qml") {
    text.replace("source: SkinBank.limitSkillDir + skilltype", R"QML(source: SkinBank.limitSkillDir +
      (root.skilltype === 'switch' ? (root.usedtimes > 0 ? 'switch-yin' : 'switch') :
       root.skilltype === 'limit' && root.usedtimes > 0 ? 'limit-used' : root.skilltype))QML");
    const QRegularExpression events("  onSkillnameChanged: \\{.*\\n\\}", QRegularExpression::DotMatchesEverythingOption);
    text.replace(events, R"QML(  function refreshSkill() {
    if (!skillname) { visible = false; return; }
    const info = Ltk.getSkillData(skillname);
    skilltype = info.switchSkillName ? 'switch' : (info.frequency || '');
    visible = !!skilltype && usedtimes >= 0 && (skilltype !== 'wake' || usedtimes > 0);
    x.visible = (skilltype === 'limit' && usedtimes > 0) || (skilltype === 'quest' && usedtimes > 1);
  }
  onSkillnameChanged: refreshSkill()
  onUsedtimesChanged: refreshSkill()
  Component.onCompleted: refreshSkill()
})QML");
  }
  if (path == "Fk/Pages/Common/RoomPage.qml") {
    // Keep confirmations on the same Qt Quick overlay as the game. Preserve
    // each core's callbacks, including surrender eligibility and reply IDs.
    const QRegularExpression dialogs(
      R"RX(^([ ]*)MessageDialog \{\s*id: (quitDialog|surrenderDialog|surrenderNegotiationDialog|surrenderNegotiationRequestDialog)\b.*?^\1\})RX",
      QRegularExpression::MultilineOption | QRegularExpression::DotMatchesEverythingOption);
    auto matches = dialogs.globalMatch(text);
    QList<QRegularExpressionMatch> replacements;
    while (matches.hasNext()) replacements.append(matches.next());
    for (auto it = replacements.crbegin(); it != replacements.crend(); ++it) {
      const QString indent = it->captured(1), id = it->captured(2);
      QString block = it->captured();
      block.replace("MessageDialog", "Dialog");
      block.replace("buttons:", "standardButtons:");
      block.replace("informativeText:", "property string informativeText:");
      const QString setup = "\n" + indent + "  objectName: \"" +
        (id == "quitDialog" ? QString("offlineQuitConfirmation") : id + "Confirmation") + "\"\n" +
        indent + "  parent: Overlay.overlay\n" +
        indent + "  anchors.centerIn: parent\n" +
        indent + "  width: Math.min(parent.width - 32, 460)\n" +
        indent + "  modal: true\n" +
        indent + "  closePolicy: Popup.NoAutoClose\n" +
        indent + "  exit: Transition {}\n" +
        indent + "  signal buttonClicked(var button, var role)\n" +
        indent + "  onAccepted: buttonClicked(Dialog.Ok, DialogButtonBox.AcceptRole)\n" +
        indent + "  onRejected: buttonClicked(Dialog.Cancel, DialogButtonBox.RejectRole)\n" +
        indent + "  contentItem: Label {text: " + id + ".informativeText; textFormat: Text.RichText; wrapMode: Text.Wrap; padding: 16}\n";
      const qsizetype position = block.indexOf('\n', block.indexOf("id: " + id));
      block.insert(position, setup);
      text.replace(it->capturedStart(), it->capturedLength(), block);
    }
  } else if (path == "Fk/Pages/Lobby/BGSetting.qml") {
    text.replace("*.mp4\"", "*.mp4)\"");
    text.replace("*.jpeg *.gif", "*.jpeg *.heic *.heif *.gif");
    text.replace("        fdialog.open();", R"QML(        if (typeof Backend.pickBackground === "function" && ["lobbyBg","roomBg","ladyImg"].indexOf(fdialog.configKey)>=0)
          Backend.pickBackground(fdialog.configKey);
        else fdialog.open();)QML");
  } else if (path == "Fk/Pages/Replay/ReplayRecordingFile.qml") {
    text.replace("placeholderText: Lua.tr(\"Note\")", R"QML(placeholderText: ""
          objectName: "replayNoteField"
          Layout.minimumHeight: 48
          topPadding: 0; bottomPadding: 0
          verticalAlignment: TextInput.AlignVCenter
          Text {
            anchors.fill: parent; anchors.leftMargin: parent.leftPadding
            anchors.rightMargin: parent.rightPadding
            verticalAlignment: Text.AlignVCenter
            text: Lua.tr("Note"); font: parent.font; color: "#687572"
            visible: !parent.text && !parent.preeditText
          })QML");
  }
  return text;
}

inline QString prepare(const QString &source, const QString &cache, QString *error) {
  QMap<QString, QByteArray> files;
  QCryptographicHash hash(QCryptographicHash::Sha256);
  for (const QString &module : {QString("Fk"), QString("LunarLtk")}) {
    if (!QFile::exists(source + '/' + module + "/qmldir")) {
      if (error) *error = "UI module is missing: " + module;
      return {};
    }
    QDirIterator it(source + '/' + module, QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (it.hasNext()) {
      const QString path = it.next();
      if (it.fileInfo().isSymLink()) { if (error) *error = "UI symlink rejected"; return {}; }
      const QString relative = QDir(source).relativeFilePath(path);
      QFile file(path);
      if (!file.open(QIODevice::ReadOnly)) { if (error) *error = "UI read failed"; return {}; }
      const QByteArray data = file.readAll();
      files.insert(relative, path.endsWith(".qml") ? adapt(relative, QString::fromUtf8(data)).toUtf8() : data);
    }
  }
  for (auto it = files.cbegin(); it != files.cend(); ++it) {
    hash.addData(it.key().toUtf8()); hash.addData("\0", 1); hash.addData(it.value());
  }
  const QByteArray revision = hash.result().toHex();
  bool current = fkIosRuntimePayload::read(cache + "/revision").trimmed() == revision;
  if (current) {
    for (auto it = files.cbegin(); it != files.cend(); ++it) {
      if (fkIosRuntimePayload::read(cache + '/' + it.key()) != it.value()) { current = false; break; }
    }
    if (current) return cache;
  }
  // Reject paths that could contain the source, or an unrelated existing tree.
  const QString target = QFileInfo(cache).absoluteFilePath();
  const QString origin = QFileInfo(source).absoluteFilePath();
  const QByteArray owner = "FreeKill generated iOS UI\n";
  if (target == origin || origin.startsWith(target + '/') ||
      (QFile::exists(cache) && !QFile::exists(cache + "/revision") &&
       fkIosRuntimePayload::read(cache + "/.generated") != owner)) {
    if (error) *error = "UI cache is not an owned generated directory"; return {};
  }
  // Only this generated, dedicated tree is removed. Never touch the source core.
  if (QFileInfo(cache).isSymLink() || (!QDir(cache).removeRecursively() && QFile::exists(cache))) {
    if (error) *error = "UI cache cannot be replaced"; return {};
  }
  // Establish ownership first, so an interrupted copy can be safely retried.
  if (!fkIosRuntimePayload::writeAtomic(cache + "/.generated", owner)) return {};
  for (auto it = files.cbegin(); it != files.cend(); ++it) {
    if (!fkIosRuntimePayload::writeAtomic(cache + '/' + it.key(), it.value())) {
      if (error) *error = "UI cache write failed"; return {};
    }
  }
  if (!fkIosRuntimePayload::writeAtomic(cache + "/revision", revision)) return {};
  return cache;
}
} // namespace fkIosUiOverlay
