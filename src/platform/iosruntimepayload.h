// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>

namespace fkIosRuntimePayload {
inline bool writeAtomic(const QString &path, const QByteArray &data) {
  if (!QDir().mkpath(QFileInfo(path).absolutePath())) return false;
  QSaveFile file(path);
  return file.open(QIODevice::WriteOnly) && file.write(data) == data.size() && file.commit();
}
inline QByteArray read(const QString &path) {
  QFile file(path);
  return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
}
inline bool copyManagedTree(const QString &src, const QString &dest) {
  const QFileInfo info(src);
  if (info.isSymLink() || QFileInfo(dest).isSymLink()) return false;
  if (!info.isDir()) {
    QFile file(src);
    if (!file.open(QIODevice::ReadOnly)) return false;
    return writeAtomic(dest, file.readAll());
  }
  if (!QDir().mkpath(dest)) return false;
  for (const auto &entry : QDir(src).entryInfoList(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot)) {
    if (!copyManagedTree(entry.filePath(), dest + '/' + entry.fileName())) return false;
  }
  return true;
}
inline bool refresh(const QString &bundle, const QString &data, QString *error) {
  const QString marker = "/client-ui-revision";
  const QByteArray revision = read(bundle + marker).trimmed();
  if (revision.size() != 64) {
    if (error) *error = "安装包缺少有效的界面版本记录";
    return false;
  }
  if (read(data + marker).trimmed() == revision) return true;
  // Never replace downloaded packages, databases, account/friend settings,
  // imported images, or other files in the user's sandbox on a UI update.
  for (const QString &name : {QString("Fk"), QString("LunarLtk"), QString("card-counter")}) {
    if (!copyManagedTree(bundle + '/' + name, data + '/' + name)) {
      if (error) *error = "无法更新界面文件：" + name;
      return false;
    }
  }
  if (!writeAtomic(data + marker, revision + '\n')) {
    if (error) *error = "无法保存界面版本记录";
    return false;
  }
  return true;
}
}
