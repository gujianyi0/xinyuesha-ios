// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <QObject>
#include <QString>
class PickerBridge : public QObject {
  Q_OBJECT
  Q_PROPERTY(QString status READ status NOTIFY statusChanged)
public:
  QString status() const { return m_status; }
  Q_INVOKABLE void choose();
  Q_INVOKABLE void pickBackground(const QString &key);
  Q_INVOKABLE void save(const QString &lobby, const QString &room, const QString &portrait);
  Q_INVOKABLE void showDialog(const QString &, const QString &error);
signals:
  void statusChanged();
  void backgroundPicked(QString key, QString file, QString error);
private:
  QString m_status = QStringLiteral("Ready");
  int callbacks = 0;
  bool busy = false;
};
