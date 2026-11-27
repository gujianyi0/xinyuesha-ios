// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

namespace fkOfflineGenerals {
inline QJsonObject readObject(const QString &path) {
  QFile file(path);
  if (!file.open(QIODevice::ReadOnly) || file.size() > 4 * 1024 * 1024) return {};
  return QJsonDocument::fromJson(file.readAll()).object();
}
inline bool lusuEnabled(const QString &root) {
  const QString id = QStringLiteral("\u4e5d\u96f7\u9707\u9f13\u9c81\u8083-v1");
  const auto conf = readObject(root + "/freekill.client.config.json");
  if (!conf["enabledResourcePacks"].toArray().contains(id)) return false;
  const auto manifest = readObject(root + "/resource_pak/" + id +
      "/packages/freekill-core/image/xinyuesha-offline-lusu/manifest.json");
  return manifest["schema"].toInt() == 1 && manifest["id"].toString() == id &&
      manifest["rules"].toString() == "lusu-thunder-1";
}
}
