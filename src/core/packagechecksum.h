// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QStringList>
#include <array>

namespace fkPackageChecksum {
using Groups = std::array<QStringList,3>;
inline void collect(const QString &dir, Groups &files) {
  // The old protocol visits the same tree three times, sorted by QDir::Name.
  // Keep that exact per-extension order while enumerating each directory once.
  for (const QFileInfo &entry : QDir(dir).entryInfoList(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
    if (entry.isDir()) { collect(entry.filePath(), files); continue; }
    const QString name=entry.fileName();
    if (name.endsWith(".lua")) files[0].append(entry.filePath());
    else if (name.endsWith(".qml")) files[1].append(entry.filePath());
    else if (name.endsWith(".js")) files[2].append(entry.filePath());
  }
}
inline Groups packageFiles(const QString &dir, const QStringList &disabled) {
  Groups files;
  static const QStringList builtins={"standard","standard_cards","maneuvering","test"};
  for (const QFileInfo &entry : QDir(dir).entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
    const QString name=entry.fileName();
    if (name.endsWith(".disabled") || disabled.contains(name) || builtins.contains(name)) continue;
    collect(entry.filePath(),files);
  }
  return files;
}
inline QByteArray record(const QString &name) {
  QFile file(name);
  if (!file.open(QIODevice::ReadOnly)) return {};
  QByteArray data=file.readAll();
  data.replace(QByteArray("\r\n"),QByteArray("\n"));
  return name.toUtf8()+'='+QCryptographicHash::hash(data,QCryptographicHash::Md5).toHex()+';';
}
}
