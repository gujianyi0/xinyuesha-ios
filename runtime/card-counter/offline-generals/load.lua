-- SPDX-License-Identifier: GPL-3.0-or-later
-- Called by native code ONLY for an explicitly local SinglePlayer connection.
-- Downloaded packs contain artwork/JSON, never executable Lua. Rule code lives
-- in the reviewed client payload, outside the server's packages/checksum tree.
-- Qt's native QFile reader validates the JSON and enabled-pack list (including
-- Unicode paths on Windows) before supplying this one-shot permission.
-- Lua::setGlobal carries a UTF-8 string, rather than decoding JSON values.
if __XinyueshaOfflineLusu ~= "true" then return end
__XinyueshaOfflineLusu = nil
if Fk.packages.xinyuesha_offline_lusu then return end
local extension = dofile("card-counter/offline-generals/lusu.lua")
extension:install(Fk)
table.insertIfNeed(Fk.extension_names, "xinyuesha_offline_lusu")
Fk.extensions.xinyuesha_offline_lusu = { extension.name }
Fk:loadDisabled()
fk.qInfo("[OfflineGenerals] loaded local 九雷震鼓鲁肃")
