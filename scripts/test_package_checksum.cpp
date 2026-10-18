// SPDX-License-Identifier: GPL-3.0-or-later
#include "core/packagechecksum.h"
#include <QCoreApplication>
#include <QTemporaryDir>
#include <QRegularExpression>
#include <QDebug>
#include <cstdlib>
static void require(bool ok) { if (!ok) std::exit(1); }
static void oldDir(QByteArray &out,const QString &dir,const QString &filter) {
  auto re=QRegularExpression::fromWildcard(filter);
  for (const QFileInfo &info : QDir(dir).entryInfoList(QDir::Files|QDir::Dirs|QDir::NoDotAndDotDot,QDir::Name)) {
    if (info.isDir()) oldDir(out,info.filePath(),filter);
    else if (re.match(info.fileName()).hasMatch()) out+=fkPackageChecksum::record(info.filePath());
  }
}
static QByteArray old(const QString &dir,const QStringList &disabled) {
  QByteArray out;
  for (const auto &filter : {"*.lua","*.qml","*.js"}) {
    for (const QFileInfo &info : QDir(dir).entryInfoList(QDir::Dirs|QDir::NoDotAndDotDot,QDir::Name)) {
      const auto name=info.fileName();
      if (name.endsWith(".disabled") || disabled.contains(name) || QStringList{"standard","standard_cards","maneuvering","test"}.contains(name)) continue;
      oldDir(out,info.filePath(),filter);
    }
  }
  return out;
}
static QByteArray updated(const QString &dir,const QStringList &disabled) {
  QByteArray out;
  for (const auto &group : fkPackageChecksum::packageFiles(dir,disabled))
    for (const auto &path : group) out+=fkPackageChecksum::record(path);
  return out;
}
int main(int argc,char **argv) {
  QCoreApplication app(argc,argv);QTemporaryDir tmp;
  const auto base=tmp.path()+"/packages";
  for (const auto &pack : {"alpha","Zulu","中文","standard","standard_cards","maneuvering","test","excluded","old.disabled"})
    for (const auto &file : {"z.lua","A.qml","nested/zz.js","nested/a.lua","nested/ignore.LUA","file.txt","nested/.hidden.lua","中文.qml"}) {
      const auto name=base+'/'+pack+'/'+file;QDir().mkpath(QFileInfo(name).absolutePath());
      QFile f(name);require(f.open(QIODevice::WriteOnly));f.write("abc\r\ndef\n");
    }
  require(old(base,{"excluded"})==updated(base,{"excluded"}));
  auto previous=updated(base,{"excluded"});
  QFile change(base+"/alpha/z.lua");require(change.open(QIODevice::WriteOnly));change.write("changed");change.close();
  require(previous!=updated(base,{"excluded"}));
  require(old(base,{"excluded"})==updated(base,{"excluded"}));
  if (argc>1) require(old(argv[1],{})==updated(argv[1],{}));
  qInfo()<<"Package checksum byte parity and file-change detection passed";
}
