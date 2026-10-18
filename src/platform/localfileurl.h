// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <QUrl>
#include <QString>
namespace fkLocalFile {
inline QString path(const QString &value) {
  const QUrl url(value);
  // A content:// URI is a complete Android document-provider identifier.
  // Removing its scheme/authority loses the provider and its permission.
  return url.isLocalFile() ? url.toLocalFile() : value;
}
}
