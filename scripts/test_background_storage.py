from pathlib import Path
import subprocess,tempfile,shlex
C=Path(__file__).resolve().parents[1]
s=(C/'src/ui/qmlbackend.cpp').read_text(encoding='utf8')
s=s[s.index('QString QmlBackend::importBackground('):s.index('\n#ifndef FK_SERVER_ONLY')]
with tempfile.TemporaryDirectory() as t:
 p=Path(t);source=p/'test.cpp'
 source.write_text('''#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QCryptographicHash>
#include <QTemporaryDir>
#include <QDebug>
#include "platform/localfileurl.h"
class QmlBackend {public:QString importBackground(const QString &source);};
'''+s+'''
int main(int argc,char**argv) {
 QCoreApplication app(argc,argv);QTemporaryDir temp;QDir::setCurrent(temp.path());
 QFile a("a.png");Q_ASSERT(a.open(QIODevice::WriteOnly));a.write("photo bytes");a.close();QFile::copy("a.png","different-picker-uuid.png");
 QmlBackend backend;auto first=backend.importBackground(QUrl::fromLocalFile(QDir::currentPath()+"/a.png").toString());
 auto second=backend.importBackground(QUrl::fromLocalFile(QDir::currentPath()+"/different-picker-uuid.png").toString());
 Q_ASSERT(!first.isEmpty() && first==second);Q_ASSERT(QDir("assets/backgrounds").entryList(QDir::Files).size()==1);
 Q_ASSERT(backend.importBackground("missing.png").isEmpty());QFile saved(QUrl(first).toLocalFile());Q_ASSERT(saved.open(QIODevice::ReadOnly));Q_ASSERT(saved.readAll()=="photo bytes");
 qInfo()<<"Content-addressed imports reuse one file across different picker URLs; failed import preserves background";
}''',encoding='utf8')
 flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','Qt6Core'],text=True))
 subprocess.run(['c++','-std=c++17','-fPIC',str(source),'-I'+str(C/'src'),*flags,'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
