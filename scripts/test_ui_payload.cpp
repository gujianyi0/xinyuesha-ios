// SPDX-License-Identifier: GPL-3.0-or-later
#include "platform/iosruntimepayload.h"
#include <QCoreApplication>
#include <QTemporaryDir>
#include <QDebug>
#include <cstdlib>
static void require(bool ok, const char *s) { if (!ok) { qCritical()<<s; std::exit(1); } }
int main(int argc,char **argv) {
  QCoreApplication app(argc,argv); QTemporaryDir tmp;
  using namespace fkIosRuntimePayload;
  const QString src=tmp.path()+"/bundle", dest=tmp.path()+"/user";
  require(writeAtomic(src+"/client-ui-revision",QByteArray(64,'a')),"revision fixture");
  for (const auto &name : {"Fk","LunarLtk","card-counter"})
    require(writeAtomic(src+'/'+name+"/fixture.qml","updated UI"),"UI fixture");
  for (const auto &name : {"packages/freekill-core/fixture.lua","client/client.db","assets/social-private/profiles.json","freekill.client.config.json"})
    require(writeAtomic(dest+'/'+name,"private sentinel"),"private fixture");
  QString error;
  require(refresh(src,dest,&error),qPrintable(error));
  require(read(dest+"/Fk/fixture.qml")=="updated UI","UI applied");
  for (const auto &name : {"packages/freekill-core/fixture.lua","client/client.db","assets/social-private/profiles.json","freekill.client.config.json"})
    require(read(dest+'/'+name)=="private sentinel","private data preserved");
  require(writeAtomic(src+"/Fk/fixture.qml","should not copy again"),"change fixture");
  require(refresh(src,dest,&error),"same revision");
  require(read(dest+"/Fk/fixture.qml")=="updated UI","same revision skips traversal");
  require(writeAtomic(src+"/client-ui-revision",QByteArray(64,'b')),"next revision");
  // A directory where a managed file should be causes a safe write failure.
  require(QFile::remove(dest+"/Fk/fixture.qml"),"remove fixture");
  require(QDir().mkpath(dest+"/Fk/fixture.qml"),"blocking directory");
  require(!refresh(src,dest,&error),"failed copy must be reported");
  require(read(dest+"/client-ui-revision").trimmed()==QByteArray(64,'a'),"failure preserves old revision for retry");
  qInfo()<<"UI payload update, preservation, skip and retry tests passed";
}
