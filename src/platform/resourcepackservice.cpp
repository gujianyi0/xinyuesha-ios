// SPDX-License-Identifier: GPL-3.0-or-later
#include "resourcepackservice.h"
#include "zipreader_compat.h"
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QNetworkProxy>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QStorageInfo>
#include <QTemporaryDir>
#include <QTimer>
#include <cmath>
#include <array>
#include <stdexcept>
#include <memory>
#ifdef Q_OS_WIN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <winhttp.h>
#endif

namespace {
constexpr qint64 MiB=1024*1024, MaxPart=192*MiB, MaxPack=2048*MiB;
struct Failure:std::runtime_error {explicit Failure(const QString &s):std::runtime_error(s.toUtf8().constData()){};};
void require(bool condition,const QString &why){if(!condition)throw Failure(why);}
bool match(const QString &pattern,const QString &value){return QRegularExpression("\\A(?:"+pattern+")\\z").match(value).hasMatch();}
qint64 number(const QJsonObject &v,const char *key,qint64 max) {
    const auto value=v.value(QLatin1String(key));const double n=value.toDouble(-1);
    require(value.isDouble()&&std::isfinite(n)&&n>=0&&n<=max&&std::floor(n)==n,"Invalid resource limits");return qint64(n);
}
QString safe(const QString &root,const QString &relative) {
    require(!QDir::isAbsolutePath(relative)&&!relative.split('/').contains(".."),"Invalid resource path");
    const auto path=QDir::cleanPath(root+"/"+relative);require(path.startsWith(root+"/"),"Invalid resource path");
    for(auto part=path;part!=root;part=QFileInfo(part).path()) {
        const QFileInfo info(part);
        require(!info.isSymLink()&&!info.isJunction(),"Linked resource path");
        require(part.startsWith(root+"/"),"Invalid resource path");
    }
    return path;
}
QJsonObject readJson(const QString &path,qint64 limit=65536) {
    QFile f(path);require(f.open(QIODevice::ReadOnly)&&f.size()<=limit,"无法读取资源请求或清单");
    QJsonParseError error;const auto doc=QJsonDocument::fromJson(f.readAll(),&error);
    require(error.error==QJsonParseError::NoError&&doc.isObject(),"资源清单格式错误");return doc.object();
}
void writeJson(const QString &path,const QJsonObject &value) {
    require(QDir().mkpath(QFileInfo(path).path()),"无法创建资源目录");QSaveFile f(path);
    require(f.open(QIODevice::WriteOnly),"无法写入资源状态");const auto data=QJsonDocument(value).toJson(QJsonDocument::Compact);
    require(f.write(data)==data.size()&&f.commit(),"无法保存资源状态");
}
QString hash(const QString &file) {
    QFile f(file);require(f.open(QIODevice::ReadOnly),"无法读取缓存");QCryptographicHash digest(QCryptographicHash::Sha256);
    require(digest.addData(&f),"缓存读取失败");return QString::fromLatin1(digest.result().toHex());
}
quint32 crc32(const QByteArray &data) {
    static const auto table=[](){std::array<quint32,256> values{};for(quint32 i=0;i<256;i++){quint32 c=i;for(int j=0;j<8;j++)c=(c&1)?0xedb88320u^(c>>1):c>>1;values[i]=c;}return values;}();
    quint32 crc=0xffffffffu;for(const auto byte:data)crc=table[(crc^quint8(byte))&255]^(crc>>8);return crc^0xffffffffu;
}
QJsonArray validate(const QJsonObject &catalog) {
    require(catalog["schema"].toInt()==2&&catalog["packs"].isArray(),"Unsupported resource catalog");
    const auto packs=catalog["packs"].toArray();require(packs.size()<=32,"Too many resource packs");QSet<QString> ids;
    for(const auto &value:packs) {
        const auto pack=value.toObject();const auto id=pack["id"].toString();
        require(match("[A-Za-z0-9_\\-\\p{Han}]{1,64}",id)&&!ids.contains(id)&&pack["title"].isString()&&pack["title"].toString().size()<=80&&pack["version"].isString()&&pack["version"].toString().size()<=32,"Invalid resource metadata");ids.insert(id);
        const auto parts=pack["parts"].toArray();require(!parts.isEmpty()&&parts.size()<=32,"Invalid resource parts");qint64 bytes=0,expanded=0,files=0;QSet<QString> archives;
        for(const auto &p:parts) {
            const auto part=p.toObject();const auto archive=part["archive"].toString();const auto size=number(part,"bytes",MaxPart);
            require(size>0&&match("[A-Za-z0-9_-]{1,96}\\.zip",archive)&&!archives.contains(archive)&&match("[a-f0-9]{64}",part["sha256"].toString()),"Invalid resource part");archives.insert(archive);
            bytes+=size;expanded+=number(part,"expandedBytes",256*MiB);files+=number(part,"fileCount",4096);
        }
        require(bytes==number(pack,"bytes",MaxPack)&&expanded==number(pack,"expandedBytes",MaxPack)&&files==number(pack,"fileCount",4096),"Resource limits exceeded");
    }
    return packs;
}
struct Job {
    QString root,bridge,id;QUrl origin;QThread *thread;
#ifndef Q_OS_WIN
    QNetworkAccessManager network{nullptr};
#endif
    qint64 before=0,total=0,lastProgress=0;int part=0,parts=0;
    void cancel() {
        if(thread->isInterruptionRequested())throw Failure("Download paused");
        const auto file=bridge+"/cancel.json";
        if(QFileInfo::exists(file)) {QJsonObject value;try{value=readJson(file,1024);}catch(const Failure &){}if(value["id"]==id)throw Failure("下载已取消，可重新下载并继续已缓存部分。");}
    }
    void progress(const QString &stage,qint64 done,bool force=false) {
        cancel();const auto now=QDateTime::currentMSecsSinceEpoch();if(!force&&now-lastProgress<300)return;lastProgress=now;
        writeJson(bridge+"/progress.json",{{"id",id},{"stage",stage},{"done",double(done)},{"total",double(total)},{"part",part},{"parts",parts}});
    }
    void fetch(const QUrl &url,const QString &path,qint64 expected,const QString &checksum={}) {
        qint64 offset=checksum.isEmpty()?0:QFileInfo(path).size();if(offset>expected){QFile::remove(path);offset=0;}
        if(!checksum.isEmpty()&&offset==expected)return;
        QFile output(path);require(output.open(QIODevice::ReadWrite),"无法写入下载缓存");require(output.seek(offset),"缓存定位失败");
#ifdef Q_OS_WIN
        // WinHTTP keeps Windows proxy/TLS/timer handling outside the Qt worker
        // event loop, including failed CDN responses and cancelled transfers.
        struct Internet {HINTERNET handle;~Internet(){if(handle)WinHttpCloseHandle(handle);}};
        const bool local=url.host()=="127.0.0.1"||url.host()=="localhost";
        auto configured=qEnvironmentVariable(url.scheme()=="https"?"HTTPS_PROXY":"HTTP_PROXY");if(configured.isEmpty())configured=qEnvironmentVariable(url.scheme()=="https"?"https_proxy":"http_proxy");
        const QUrl proxy(configured);QString proxyServer;
        if(!local&&proxy.scheme()=="http"&&!proxy.host().isEmpty())proxyServer=proxy.host()+":"+QString::number(proxy.port(80));
        const auto proxyW=proxyServer.toStdWString();
        Internet session{WinHttpOpen(L"FreeKill Resource Download",local?WINHTTP_ACCESS_TYPE_NO_PROXY:proxyServer.isEmpty()?WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY:WINHTTP_ACCESS_TYPE_NAMED_PROXY,proxyServer.isEmpty()?WINHTTP_NO_PROXY_NAME:proxyW.c_str(),WINHTTP_NO_PROXY_BYPASS,0)};
        require(session.handle,"无法启动系统下载器");WinHttpSetTimeouts(session.handle,12000,12000,18000,18000);
        const auto host=url.host().toStdWString();const bool tls=url.scheme()=="https";
        Internet connection{WinHttpConnect(session.handle,host.c_str(),INTERNET_PORT(url.port(tls?443:80)),0)};require(connection.handle,"无法连接资源服务器");
        auto resource=url.path(QUrl::FullyEncoded);if(!url.query().isEmpty())resource+='?'+url.query(QUrl::FullyEncoded);const auto resourceW=resource.toStdWString();
        Internet request{WinHttpOpenRequest(connection.handle,L"GET",resourceW.c_str(),nullptr,WINHTTP_NO_REFERER,WINHTTP_DEFAULT_ACCEPT_TYPES,tls?WINHTTP_FLAG_SECURE:0)};require(request.handle,"无法创建下载请求");
        DWORD policy=WINHTTP_OPTION_REDIRECT_POLICY_NEVER;require(WinHttpSetOption(request.handle,WINHTTP_OPTION_REDIRECT_POLICY,&policy,sizeof(policy)),"无法设置下载策略");
        QString headers="Accept-Encoding: identity\r\n";if(offset>0)headers+="Range: bytes="+QString::number(offset)+"-\r\n";const auto headersW=headers.toStdWString();
        const bool connected=WinHttpSendRequest(request.handle,headersW.c_str(),DWORD(headersW.size()),WINHTTP_NO_REQUEST_DATA,0,0,0)&&WinHttpReceiveResponse(request.handle,nullptr);
        require(connected,QString("下载连接中断（%1），请重试。").arg(connected?0:GetLastError()));
        DWORD status=0,size=sizeof(status);require(WinHttpQueryHeaders(request.handle,WINHTTP_QUERY_STATUS_CODE|WINHTTP_QUERY_FLAG_NUMBER,WINHTTP_HEADER_NAME_BY_INDEX,&status,&size,WINHTTP_NO_HEADER_INDEX),"无法读取下载状态");
        if(status==200){offset=0;require(output.resize(0)&&output.seek(0),"缓存重置失败");}
        else {
            require(status==206&&offset>0,QString("资源服务返回 %1，请稍后重试。").arg(status));DWORD length=0;
            WinHttpQueryHeaders(request.handle,WINHTTP_QUERY_CONTENT_RANGE,WINHTTP_HEADER_NAME_BY_INDEX,nullptr,&length,WINHTTP_NO_HEADER_INDEX);std::wstring value(length/sizeof(wchar_t),L'\0');
            require(length>0&&WinHttpQueryHeaders(request.handle,WINHTTP_QUERY_CONTENT_RANGE,WINHTTP_HEADER_NAME_BY_INDEX,value.data(),&length,WINHTTP_NO_HEADER_INDEX),"下载范围缺失");
            require(QString::fromWCharArray(value.c_str())==QString("bytes %1-%2/%3").arg(offset).arg(expected-1).arg(expected),"下载范围校验失败");
        }
        qint64 received=offset;QElapsedTimer overall;overall.start();char buffer[65536];
        while(true){cancel();require(overall.elapsed()<1800000,"下载超时，可重试继续。");DWORD count=0;require(WinHttpReadData(request.handle,buffer,sizeof(buffer),&count),"下载中断，可重试继续。");if(!count)break;received+=count;require(received<=expected,"下载大小不匹配");require(output.write(buffer,count)==count,"存储写入失败");if(!checksum.isEmpty())progress("downloading",before+received);}
        output.close();if(!checksum.isEmpty())require(received==expected,"下载中断，可重试继续。");
#else
        auto configured=qEnvironmentVariable(url.scheme()=="https"?"HTTPS_PROXY":"HTTP_PROXY");if(configured.isEmpty())configured=qEnvironmentVariable(url.scheme()=="https"?"https_proxy":"http_proxy");const QUrl proxy(configured);
        if(url.host()!="127.0.0.1"&&url.host()!="localhost"&&proxy.scheme()=="http"&&!proxy.host().isEmpty())network.setProxy(QNetworkProxy(QNetworkProxy::HttpProxy,proxy.host(),quint16(proxy.port(80))));
        QNetworkRequest request(url);request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,QNetworkRequest::ManualRedirectPolicy);
        // Parts use serial HTTP/1.1 transfers.
        request.setAttribute(QNetworkRequest::Http2AllowedAttribute,false);
        request.setHeader(QNetworkRequest::UserAgentHeader,"FreeKill Resource Download");
        request.setRawHeader("Accept-Encoding","identity");
        if(offset>0)request.setRawHeader("Range","bytes="+QByteArray::number(offset)+"-");
        auto *reply=network.get(request);
        const std::unique_ptr<QNetworkReply,void(*)(QNetworkReply*)> cleanup(reply,[](QNetworkReply *r){r->deleteLater();});
        QEventLoop loop;QTimer watchdog;QElapsedTimer activity,overall;activity.start();overall.start();QString failure;bool headers=false;qint64 length=offset;
        const auto drain=[&]() {
            if(!failure.isEmpty())return;
            if(!headers){const auto status=reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();if(!status)return;
                if(status==200){offset=0;length=0;if(!output.resize(0)||!output.seek(0))failure="缓存重置失败";}
                else if(status!=206||offset<=0||reply->rawHeader("Content-Range")!="bytes "+QByteArray::number(offset)+"-"+QByteArray::number(expected-1)+"/"+QByteArray::number(expected))failure="下载范围校验失败";
                headers=true;
            }
            while(failure.isEmpty()&&reply->bytesAvailable()>0){const auto data=reply->read(65536);length+=data.size();if(length>expected)failure="下载大小不匹配";else if(output.write(data)!=data.size())failure="存储写入失败";activity.restart();if(!checksum.isEmpty())try{progress("downloading",before+length);}catch(const Failure &e){failure=QString::fromUtf8(e.what());}}
            if(!failure.isEmpty())reply->abort();
        };
        QObject::connect(reply,&QNetworkReply::readyRead,&loop,drain);QObject::connect(reply,&QNetworkReply::finished,&loop,&QEventLoop::quit);
        QObject::connect(&watchdog,&QTimer::timeout,&loop,[&](){try{cancel();}catch(const Failure &e){failure=QString::fromUtf8(e.what());reply->abort();return;}if(activity.elapsed()>18000||overall.elapsed()>1800000){failure="网络超时，请重试，已缓存部分会继续下载。";reply->abort();}});watchdog.start(250);
        loop.exec();drain();const auto error=reply->error();const auto message=reply->errorString();output.close();
        require(failure.isEmpty(),failure);require(error==QNetworkReply::NoError,"下载中断："+message);
        if(!checksum.isEmpty())require(length==expected,"下载中断，请重试，已缓存部分会继续下载。");
#endif
    }
    QJsonArray catalog() {
        QJsonObject data;const auto temp=bridge+"/catalog.download.json";
        try {fetch(origin.resolved(QUrl("/catalog.json")),temp,65536);data=readJson(temp);validate(data);}
        catch(const Failure &){if(thread->isInterruptionRequested())throw;data=readJson(root+"/card-counter/resource-catalog.json");}
        return validate(data);
    }
    void extract(const QString &archive,const QString &target,qint64 &remaining,int &count,QSet<QString> &seen) {
        QZipReader zip(archive);require(zip.isReadable()&&zip.count()<=4096,"Invalid resource archive");
        for(const auto &file:zip.fileInfoList()) {
            cancel();require(!file.isSymLink,"Linked resource file");if(file.isDir)continue;const auto name=file.filePath;
            require(file.isFile&&name.size()<=320&&match("[\\p{L}\\p{N}_ ./-]+",name)&&match("(?i:icon\\.png|packages/.+\\.(png|jpe?g|webp|gif|mp4|webm|ogg|wav|mp3|atlas|skel|json))",name)&&!seen.contains(name.toCaseFolded()),"Unsupported resource file");
            for(const auto &segment:name.split('/'))require(!segment.isEmpty()&&!segment.startsWith('.'),"Invalid resource path");
            require(++count<=4096&&file.size>=0&&file.size<=128*MiB&&file.size<=remaining,"Resource extraction limits exceeded");seen.insert(name.toCaseFolded());
            const auto path=safe(target,name);require(QDir().mkpath(QFileInfo(path).path())&&!QFileInfo::exists(path),"Duplicate resource file");
            auto data=zip.fileData(name);bool valid=data.size()==file.size&&crc32(data)==file.crc;
            // Qt's fileInfo decodes UTF-8, but fileData still compares a
            // locale-decoded ZIP name on Windows. Keep output paths Unicode;
            // use the matching lookup spelling and verify its bytes by CRC.
            if(!valid){const auto lookup=QString::fromLocal8Bit(name.toUtf8());if(lookup!=name){data=zip.fileData(lookup);valid=data.size()==file.size&&crc32(data)==file.crc;}}
            require(valid&&zip.status()==QZipReader::NoError,"Incomplete resource file: "+name);QFile output(path);require(output.open(QIODevice::WriteOnly|QIODevice::NewOnly)&&output.write(data)==data.size(),"资源展开写入失败");remaining-=data.size();
        }
    }
    void install(const QJsonObject &pack) {
        const auto destination=safe(root,"resource_pak/"+pack["id"].toString());require(QDir().mkpath(QFileInfo(destination).path()),"无法创建资源目录");if(QFileInfo(destination).isDir())return;
        const auto cache=safe(root,"assets/resource-pack-download/cache");require(QDir().mkpath(cache),"无法创建缓存目录");total=number(pack,"bytes",MaxPack);const auto pieces=pack["parts"].toArray();parts=pieces.size();
        qint64 needed=number(pack,"expandedBytes",MaxPack)+64*MiB;
        for(const auto &value:pieces){const auto p=value.toObject();const auto key=p["sha256"].toString();const auto cached=cache+"/"+key+".zip",partial=cache+"/"+key+".partial";needed+=qMax<qint64>(0,number(p,"bytes",MaxPart)-(QFileInfo::exists(cached)?QFileInfo(cached).size():QFileInfo(partial).size()));}
        require(QStorageInfo(root).bytesAvailable()>=needed,QString("存储空间不足，请至少腾出 %1 MB 后重试。").arg((needed+MiB-1)/MiB));
        QTemporaryDir stage(bridge+"/install-XXXXXX");require(stage.isValid(),"无法创建安装暂存目录");const auto output=stage.path()+"/pack";require(QDir().mkpath(output),"无法展开资源");qint64 remaining=number(pack,"expandedBytes",MaxPack);int count=0;QSet<QString> seen;QStringList completed;
        for(const auto &value:pieces) {
            ++part;const auto p=value.toObject();const auto key=p["sha256"].toString();const auto size=number(p,"bytes",MaxPart);const auto archive=safe(root,"assets/resource-pack-download/cache/"+key+".zip"),partial=safe(root,"assets/resource-pack-download/cache/"+key+".partial");
            if(QFileInfo::exists(archive)&&(QFileInfo(archive).size()!=size||hash(archive)!=key))require(QFile::remove(archive),"缓存清理失败");
            if(!QFileInfo::exists(archive)) {
                progress("downloading",before+QFileInfo(partial).size(),true);fetch(origin.resolved(QUrl("/download/"+p["archive"].toString())),partial,size,key);
                if(QFileInfo(partial).size()!=size||hash(partial)!=key){QFile::remove(partial);throw Failure("资源校验失败，请重新下载。");}
                require(QFile::rename(partial,archive),"无法保存缓存");
            }
            before+=size;progress("extracting",before,true);extract(archive,output,remaining,count,seen);completed.append(archive);
        }
        require(remaining==0&&count==pack["fileCount"].toInt(),"资源展开清单不匹配");cancel();require(QDir().rename(output,destination),"资源安装未提交，请重试。");for(const auto &file:completed)QFile::remove(file);
    }
    void uninstall(const QString &key) {
        require(match("[A-Za-z0-9_\\-\\p{Han}]{1,64}",key),"Invalid resource id");
        const auto config=readJson(root+"/freekill.client.config.json",4*MiB);for(const auto &value:config["enabledResourcePacks"].toArray())require(value.toString()!=key,"请先停用资源包再删除");
        const auto path=safe(root,"resource_pak/"+key);if(!QFileInfo::exists(path))return;require(QFileInfo(path).isDir()&&QDir(path).removeRecursively(),"资源包删除失败");
    }
    void process() {
        const auto active=bridge+"/active.json",request=bridge+"/request.json";const auto source=QFileInfo::exists(active)?active:request;if(!QFileInfo::exists(source))return;
        QJsonObject input;try{input=readJson(source,1024);}catch(const Failure &){return;}
        id=input["id"].toString();require(match("[0-9_-]{1,48}",id),"Invalid request id");const auto operation=input["operation"].toString();if(operation=="install")writeJson(active,input);if(source==request)QFile::remove(request);
        QJsonObject reply{{"id",id},{"operation",operation},{"ok",false}};
        try {
            if(operation=="catalog")reply["packs"]=catalog();
            else if(operation=="uninstall"){uninstall(input["pack"].toString());reply["pack"]=input["pack"];}
            else if(operation=="install"){const auto rows=catalog();QJsonObject pack;for(const auto &v:rows)if(v.toObject()["id"]==input["pack"])pack=v.toObject();require(!pack.isEmpty(),"资源包不可用");install(pack);reply["pack"]=input["pack"];}
            else throw Failure("Invalid resource operation");reply["ok"]=true;
        }catch(const Failure &error){if(thread->isInterruptionRequested())return;const auto text=QString::fromUtf8(error.what());reply["error"]=text;reply["cancelled"]=text.startsWith("下载已取消");}
        writeJson(bridge+"/reply.json",reply);if(operation=="install")QFile::remove(active);
    }
};
}
ResourcePackService::ResourcePackService(const QString &root,QObject *parent,const QUrl &origin):QThread(parent),m_root(QDir(root).canonicalPath()),m_origin(origin){}
ResourcePackService::~ResourcePackService(){requestInterruption();wait();}
void ResourcePackService::run() {
    if(m_root.isEmpty())return;
    while(!isInterruptionRequested()) {
        try{const auto bridge=safe(m_root,"assets/resource-pack-download");if(QFileInfo::exists(bridge)){Job job{m_root,bridge,{},m_origin,this};job.process();}}
        catch(const std::exception &error){qWarning("Resource package request: %s",error.what());}
        for(int i=0;i<4&&!isInterruptionRequested();i++)msleep(100);
    }
}
