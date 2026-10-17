// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <QObject>
#include <QUrl>
#include <QVariantMap>
#include <QStringList>

class SkeletonProbe : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
public:
    explicit SkeletonProbe(QObject *parent = nullptr) : QObject(parent) {}
    bool busy() const { return mBusy; }
    Q_INVOKABLE void inspect(const QUrl &skeleton, const QUrl &atlas,
                            const QStringList &animations, bool wholeAnimation, const QString &token);
Q_SIGNALS:
    void busyChanged();
    void completed(const QVariantMap &result);
private:
    quint64 mGeneration = 0;
    bool mBusy = false;
};
