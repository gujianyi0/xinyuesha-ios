#include "platform/localfileurl.h"
#include <QCoreApplication>
#include <QTemporaryDir>
#include <QFile>
#include <QDebug>
#include <cstdlib>
static void require(bool ok) { if (!ok) std::exit(1); }
int main(int argc,char **argv) {
  QCoreApplication app(argc,argv);QTemporaryDir tmp;
  QString path=tmp.path()+"/中文 space#percent%.fk.rep";
  QFile f(path);require(f.open(QIODevice::WriteOnly));f.write("recording fixture");f.close();
  require(fkLocalFile::path(QUrl::fromLocalFile(path).toString())==path);
  QFile read(fkLocalFile::path(QUrl::fromLocalFile(path).toString()));
  require(read.open(QIODevice::ReadOnly));require(read.readAll()=="recording fixture");
  require(fkLocalFile::path("content://provider/document/primary%3ARecording%2Fdemo.fk.rep")=="content://provider/document/primary%3ARecording%2Fdemo.fk.rep");
  require(fkLocalFile::path("recording/中文.fk.rep")=="recording/中文.fk.rep");
  require(fkLocalFile::path("C:\\Recordings\\demo.fk.rep")=="C:\\Recordings\\demo.fk.rep");
  qInfo()<<"File URL decoding, Unicode and provider preservation passed";
}
