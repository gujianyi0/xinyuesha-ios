// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <QString>
#include <QUrl>
#include <functional>
// Explicit one-image system picker; no photo-library enumeration/permission.
void fkPickIosBackground(bool allowVideo, std::function<void(QUrl, QString)> completed);
// Called only on a new user request. Preserve active UI and in-flight imports.
bool fkReleaseClosedIosBackgroundPicker();
