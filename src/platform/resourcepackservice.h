// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <QThread>
#include <QUrl>

// File bridge shared with Android. All network and extraction work stays off
// the GUI thread; the QML owner alone applies enabledResourcePacks.
class ResourcePackService final : public QThread {
public:
    explicit ResourcePackService(const QString &root, QObject *parent=nullptr,
        const QUrl &origin=QUrl("https://gujianyi-xinyuesha-resources.pages.dev"));
    ~ResourcePackService() override;
protected:
    void run() override;
private:
    QString m_root;
    QUrl m_origin;
};
