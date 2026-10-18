// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <QtGlobal>
namespace fkRequestClock {
inline qint64 offset(qint64 server, qint64 sent, qint64 received) {
  return received - server - qMax<qint64>(0, received - sent) / 2;
}
}
