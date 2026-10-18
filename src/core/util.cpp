// SPDX-License-Identifier: GPL-3.0-or-later

#include "core/util.h"

#include <QSettings>
#include <QElapsedTimer>
#include "core/packagechecksum.h"
#include <QUuid>
#include "core/packman.h"
#include <QSysInfo>
#include <git2.h>

QString calcFileMD5() {
  QElapsedTimer checksumTimer; checksumTimer.start();
  // First, generate flist.txt
  // flist.txt is a file contains all md5sum for code files
  QFile flist("flist.txt");
  if (!flist.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
    qFatal("Cannot open flist.txt. Quitting.");
  }

  const auto files = fkPackageChecksum::packageFiles("packages", Pacman->getDisabledPacks());
  for (const auto &group : files)
    for (const auto &name : group)
      flist.write(fkPackageChecksum::record(name));

  // then, return flist.txt's md5
  flist.close();
  if (!flist.open(QIODevice::ReadOnly)) {
    qFatal("Cannot open flist.txt. Quitting.");
  }
  auto ret = QCryptographicHash::hash(flist.readAll(), QCryptographicHash::Md5);

  flist.close();
  qInfo("[Startup] package checksum: %lld ms", static_cast<long long>(checksumTimer.elapsed()));
  return ret.toHex();
}

QByteArray JsonArray2Bytes(const QJsonArray &arr) {
  auto doc = QJsonDocument(arr);
  return doc.toJson(QJsonDocument::Compact);
}

QJsonDocument String2Json(const QString &str) {
  auto bytes = str.toUtf8();
  return QJsonDocument::fromJson(bytes);
}

QString GetDeviceUuid() {
  QString ret;
#ifdef Q_OS_ANDROID
  QJniObject string = QJniObject::callStaticObjectMethod("org/notify/FreeKill/Helper", "GetSerial", "()Ljava/lang/String;");
  ret = string.toString();
#elif defined(Q_OS_IOS)
  // iOS forbids hardware serials. A per-install UUID kept in the app's
  // preferences is stable across launches and app updates, and resets only
  // when the app is deleted, matching the lifetime of the sandbox.
  QSettings settings("cui.freekill", "FreeKill");
  ret = settings.value("deviceUuid").toString();
  if (ret.isEmpty()) {
    ret = QUuid::createUuid().toString(QUuid::WithoutBraces);
    settings.setValue("deviceUuid", ret);
  }
#else
  ret = QSysInfo::machineUniqueId();
#endif
  return ret;
}

QString GetDisabledPacks() {
  return JsonArray2Bytes(QJsonArray::fromStringList(Pacman->getDisabledPacks()));
}

QString Color(const QString &raw, fkShell::TextColor color,
              fkShell::TextType type) {
#ifdef Q_OS_LINUX
  static const char *suffix = "\e[0;0m";
  int col = 30 + color;
  int t = type == fkShell::Bold ? 1 : 0;
  auto prefix = QString("\e[%2;%1m").arg(col).arg(t);

  return prefix + raw + suffix;
#else
  return raw;
#endif
}

/*
static QJsonDocument variantToJson(QVariant data) {
  QJsonDocument jsonDoc;

  switch (data.typeId()) {
    case QMetaType::Int:
      jsonDoc.setObject(QJsonObject{{"value", data.toInt()}});
      break;
    case QMetaType::Double:
      jsonDoc.setObject(QJsonObject{{"value", data.toDouble()}});
      break;
    case QMetaType::Bool:
      jsonDoc.setObject(QJsonObject{{"value", data.toBool()}});
      break;
    case QMetaType::QString: {
      // 转义特殊字符并包裹在引号中
      QString str = data.toString();
      jsonDoc.setObject(QJsonObject{{"value", str}});
      break;
    }
    case QMetaType::QVariantList: {
      QJsonArray jsonArray;
      QVariantList list = data.toList();
      for (const auto &item : list) {
        QJsonDocument itemDoc = variantToJson(item);
        jsonArray.append(itemDoc.array()[0]); // 假设每个元素已经转换为适当的JSON类型
      }
      jsonDoc.setArray(jsonArray);
      break;
    }
    case QMetaType::QVariantMap: {
      QJsonObject jsonObj;
      QVariantMap map = data.toMap();
      for (const auto &key : map.keys()) {
        QJsonDocument valueDoc = variantToJson(map[key]);
        jsonObj.insert(key, valueDoc.object().value("value")); // 根据具体转换方式调整
      }
      jsonDoc.setObject(jsonObj);
      break;
    }
    default:
      // 处理未知类型，返回空字节数组或抛出异常
      return QJsonDocument();
  }

  return jsonDoc;
}

QVariant AskOllama(const QString &apiEndpoint, const QVariant &body) {
  QNetworkAccessManager manager;
  QNetworkRequest request(apiEndpoint);

  // 构造JSON请求体
  QByteArray requestData = variantToJson(body).toJson(QJsonDocument::Compact);

  request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

  // 发送POST请求
  QNetworkReply *reply = manager.post(request, requestData);

  // 创建事件循环，阻塞直到响应完成
  QEventLoop loop;
  QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
  loop.exec();

  // 检查是否有错误发生
  if (reply->error() != QNetworkReply::NoError) {
    // 处理错误情况，例如记录日志或抛出异常
    qWarning() << "Network error occurred: " << reply->errorString();
    delete reply;
    return QByteArray();
  }

  // 读取响应数据
  QByteArray responseData = reply->readAll();

  // 删除回复对象以释放资源
  delete reply;

  return QJsonDocument::fromJson(responseData).toVariant();
}
*/

