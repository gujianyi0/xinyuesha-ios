#include "resourcepackservice.h"
#include <QCoreApplication>
#include <QTimer>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <cstdio>
#ifdef Q_OS_WIN
void installProbeCrashTrace();
#endif
int main(int argc,char **argv) {
#ifdef Q_OS_WIN
    installProbeCrashTrace();
#endif
    QCoreApplication app(argc,argv);if(argc!=3)return 2;
    const auto root=QString::fromLocal8Bit(argv[1]);const auto bridge=root+"/assets/resource-pack-download/";
    QFile input(QFile::exists(bridge+"active.json")?bridge+"active.json":bridge+"request.json");if(!input.open(QIODevice::ReadOnly))return 3;
    const auto expected=QJsonDocument::fromJson(input.readAll()).object()["id"].toString();
    ResourcePackService service(root,nullptr,QUrl(QString::fromLocal8Bit(argv[2])));service.start();
    QTimer poll;QObject::connect(&poll,&QTimer::timeout,&app,[&](){QFile f(bridge+"reply.json");if(!f.open(QIODevice::ReadOnly))return;const auto data=f.readAll();const auto doc=QJsonDocument::fromJson(data);if(!doc.isObject()||doc.object()["id"]!=expected)return;fwrite(data.constData(),1,size_t(data.size()),stdout);fflush(stdout);app.quit();});poll.start(50);
    const auto limit=qEnvironmentVariableIntValue("FK_RESOURCE_TEST_TIMEOUT_MS");
    QTimer::singleShot(limit>0?limit:120000,&app,[&](){app.exit(9);});const int code=app.exec();service.requestInterruption();service.wait();return code;
}
