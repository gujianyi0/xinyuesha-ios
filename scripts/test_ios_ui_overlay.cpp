// SPDX-License-Identifier: GPL-3.0-or-later
#include "platform/iosuioverlay.h"
#include "core/socialaccountkey.h"
#include <QCoreApplication>
#include <QTemporaryDir>
#include <QDebug>
#include <QPasswordDigestor>
#include <QJsonArray>
#include <QJsonDocument>
#include <cstdlib>
static void require(bool ok, const char *label) { if (!ok) { qCritical() << label; std::exit(1); } }
int main(int argc, char **argv) {
  QCoreApplication app(argc,argv); QTemporaryDir temp;
  require(argc >= 2, "runtime directory argument");
  const QString source = QFileInfo(argv[1]).absoluteFilePath();
  const QString output = argc > 2 ? QFileInfo(argv[2]).absoluteFilePath() : temp.path()+"/ui";
  const QString original = source+"/LunarLtk/Models/PhotoModel.qml";
  const auto before = fkIosRuntimePayload::read(original);
  QString error;
  require(fkIosUiOverlay::prepare(source,output,&error) == output, qPrintable(error));
  require(fkIosRuntimePayload::read(original) == before, "source and checksum inputs unchanged");
  require(fkIosUiOverlay::prepare(source,output,&error) == output, "repeat build succeeds");
  require(QFile::remove(output+"/Fk/Widgets/PopupItem.qml"), "remove cached popup fixture");
  require(fkIosUiOverlay::prepare(source,output,&error) == output, "incomplete cache is repaired");
  require(QFile::exists(output+"/Fk/Widgets/PopupItem.qml"), "cached popup restored");
  require(QFile::remove(output+"/revision"), "simulate interrupted cache write");
  require(fkIosUiOverlay::prepare(source,output,&error) == output, "interrupted first build can retry");
  const auto model = fkIosRuntimePayload::read(output+"/LunarLtk/Models/PhotoModel.qml");
  require(model.contains("limitSkills = next;"), "skill updates notify the model");
  require(model.contains("targetTip = Array.from(dataList || []"), "target tips publish translated map copies");
  const auto cardModel = fkIosRuntimePayload::read(output+"/LunarLtk/Models/CardModel.qml");
  require(cardModel.contains("cardTip = Array.from(dataList || []"), "card tips publish translated map copies");
  const auto util = fkIosRuntimePayload::read(output+"/LunarLtk/LtkLuaUtil.qml");
  require(util.contains("marks.splice(elemIdx, 1, Object.assign({}, elem"), "repeated mark updates replace the typed list element");
  require(!util.contains("elem.value = textValue;"), "do not mutate a temporary mark wrapper");
  const auto description = fkIosRuntimePayload::read(output+"/LunarLtk/Pages/InfoPopups/GeneralDetail.qml");
  require(description.contains("width: Math.max(1, root.width - 40)"), "skill description follows the popup viewport width");
  require(description.contains("contentHeight: skillDesc.height + 24"), "long descriptions remain scrollable");
  require(!description.contains("ColumnLayout"), "no nested implicit-size layout in the mark description popup");
  const auto roomBase = fkIosRuntimePayload::read(output+"/LunarLtk/Pages/RoomBase.qml");
  require(roomBase.contains("roomBackgroundChatShortcut"), "background double-click shortcut installed");
  require(roomBase.contains("Mediator.notify(roomScene, Command.IWantToChat)"), "shortcut reuses the existing chat action");
  const auto server = fkIosRuntimePayload::read(output+"/Fk/Pages/Common/JoinServer.qml");
  require(server.contains("String(misMatchMsg).replace"), "HTML version size normalization");
  require(!server.contains("font.pixelSize: 26"), "bounded server count font");
  const auto room = fkIosRuntimePayload::read(output+"/Fk/Pages/Common/RoomPage.qml");
  require(room.contains("offlineQuitConfirmation"), "offline quit uses an in-scene confirmation");
  require(!room.contains("MessageDialog {\n    id: quitDialog"), "native quit confirmation replaced");
  require(room.contains("surrenderDialogConfirmation"), "surrender uses the game overlay");
  require(room.contains("Lua.checkSurrenderAvailable()"), "surrender eligibility remains enforced");
  require(room.contains("parent: Overlay.overlay"), "confirmations have a stable game overlay parent");
  const auto bg = fkIosRuntimePayload::read(output+"/Fk/Pages/Lobby/BGSetting.qml");
  require(bg.contains("Backend.pickBackground(fdialog.configKey)"), "background image buttons use system photo picker");
  require(bg.contains("function onBackgroundPicked") && bg.contains("Config[key] = file"), "native picker result reaches the selected background config");
  const auto replay = fkIosRuntimePayload::read(output+"/Fk/Pages/Replay/ReplayRecordingFile.qml");
  require(replay.contains("replayNoteField") && !replay.contains("placeholderText: Lua.tr(\"Note\")"), "replay note uses an inline placeholder");
  const auto key = fkSocialAccount::deriveKey("test:9527", QString::fromUtf8("测试用户"), "test-only-password");
  require(key == "d41c77099501cd4af9ba643cc6c3b42fb3f83718eed69248e0bdab3c3abe2a8c", "native social identity matches Python and shipped WorkerScript");
  qInfo() << "iOS UI overlay, unchanged source core and social identity compatibility passed";
}
