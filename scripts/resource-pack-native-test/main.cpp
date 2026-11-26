#include "resourcepackservice.h"
#include <QCoreApplication>
#include <QTimer>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <cstdio>
int main(int argc,char **argv) {
    QCoreApplication app(argc,argv);if(argc!=3)return 2;
    const auto root=QString::fromLocal8Bit(argv[1]);ResourcePackService service(root,nullptr,QUrl(QString::fromLocal8Bit(argv[2])));service.start();
    QTimer poll;QObject::connect(&poll,&QTimer::timeout,&app,[&](){QFile f(root+"/assets/resource-pack-download/reply.json");if(!f.open(QIODevice::ReadOnly))return;const auto data=f.readAll();if(!QJsonDocument::fromJson(data).isObject())return;fwrite(data.constData(),1,size_t(data.size()),stdout);fflush(stdout);app.quit();});poll.start(50);
    QTimer::singleShot(120000,&app,[&](){app.exit(9);});const int code=app.exec();service.requestInterruption();service.wait();return code;
}
