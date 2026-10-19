// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <QCryptographicHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QPasswordDigestor>
namespace fkSocialAccount {
inline QString deriveKey(const QString &server, const QString &username, const QString &password) {
  if (server.isEmpty() || username.isEmpty() || password.isEmpty()) return {};
  const QByteArray salt = QJsonDocument(QJsonArray{
    "freekill-social-account-v1", server, username}).toJson(QJsonDocument::Compact);
  auto secret = password.toUtf8();
  const auto key = QPasswordDigestor::deriveKeyPbkdf2(
    QCryptographicHash::Sha256, secret, salt, 210000, 32);
  secret.fill('\0');
  return QString::fromLatin1(key.toHex());
}
}
