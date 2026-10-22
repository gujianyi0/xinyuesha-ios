// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <QObject>
#include <QString>
#include <functional>
#include <memory>

// Foundation types stay out of the shared C++/QML interface. An optional
// NSURLSessionConfiguration can be injected by the native protocol tests.
class IosFriendTransport final : public QObject {
public:
  using Completion = std::function<void(qint64, int, const QString &, int, const QString &)>;
  explicit IosFriendTransport(QObject *parent = nullptr, void *configuration = nullptr);
  ~IosFriendTransport() override;
  void send(qint64 id, const QString &method, const QString &url,
            const QString &bearer, const QString &body, Completion completed);
  void cancel(qint64 id);
private:
  struct Impl;
  std::unique_ptr<Impl> impl;
};
