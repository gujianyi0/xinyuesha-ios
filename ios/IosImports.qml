// SPDX-License-Identifier: GPL-3.0-or-later
//
// This file is not loaded at runtime. It exists so Qt's qmlimportscanner sees
// every Qt module imported by the loose QML tree in runtime/. On a static Qt
// build (iOS), that makes qt_import_qml_plugins link the matching QML plugins
// into the executable. Local modules (Fk, LunarLtk, Spine) live on disk in the
// writable runtime directory and are deliberately not listed here.
import QtQuick
import QtQuick.Window
import QtQuick.Templates
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Shapes
import Qt.labs.qmlmodels
import QtQml.WorkerScript
import QtMultimedia
import Qt5Compat.GraphicalEffects

Item {}
