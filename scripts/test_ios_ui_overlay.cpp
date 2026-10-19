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
  const auto description = fkIosRuntimePayload::read(output+"/LunarLtk/Pages/InfoPopups/GeneralDetail.qml");
  require(description.contains("Layout.preferredHeight: skillDesc.implicitHeight"), "nonzero skill description layout");
  const auto server = fkIosRuntimePayload::read(output+"/Fk/Pages/Common/JoinServer.qml");
  require(server.contains("String(misMatchMsg).replace"), "HTML version size normalization");
  require(!server.contains("font.pixelSize: 26"), "bounded server count font");
  const auto key = fkSocialAccount::deriveKey("test:9527", QString::fromUtf8("测试用户"), "test-only-password");
  require(key == "d41c77099501cd4af9ba643cc6c3b42fb3f83718eed69248e0bdab3c3abe2a8c", "native social identity matches Python and shipped WorkerScript");
  qInfo() << "iOS UI overlay, unchanged source core and social identity compatibility passed";
}
