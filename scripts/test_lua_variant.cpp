// SPDX-License-Identifier: GPL-3.0-or-later
#include "core/luavariant.h"
#include <QCoreApplication>
#include <cstdlib>
static void require(bool ok, const char *label) { if (!ok) { qCritical() << label; std::exit(1); } }
int main(int argc, char **argv) {
  QCoreApplication app(argc, argv);
  lua_State *L = luaL_newstate(); luaL_openlibs(L);
  auto evaluate = [&](const char *code) {
    require(luaL_dostring(L, code) == LUA_OK, "fixture executes");
    const int top = lua_gettop(L);
    QVariant result = fkLuaVariant::read(L, -1);
    require(lua_gettop(L) == top, "reader preserves Lua stack");
    lua_pop(L, 1); return result;
  };
  for (int repeat = 0; repeat < 100; ++repeat) {
    auto value = evaluate("return {setmetatable({name='skill', time=1}, {}), {1,2,3}}").toList();
    require(value.size() == 2 && value[0].toMap()["time"].toInt() == 1, "metatable without CBOR does not corrupt siblings");
    require(value[1].toList().size() == 3, "card list survives recursive conversion");
  }
  auto map = evaluate("return {[0]='zero', [5]='five', title='玩家'}").toMap();
  require(map["0"] == "zero" && map["5"] == "five", "numeric dictionary keys remain valid for lua_next");
  const auto bytes = evaluate("return setmetatable({}, {__tocbor=function() return 'a'..string.char(0)..'b' end})").toByteArray();
  require(bytes == QByteArray("a\0b",3), "CBOR embedded NUL retained");
  require(!evaluate("return setmetatable({}, {__tocbor=function() error('test') end})").isValid(), "CBOR failure contained");
  require(!evaluate("return setmetatable({}, {__tocbor=function() return {} end})").isValid(), "invalid CBOR return contained");
  evaluate("local a={};a.self=a;return a");
  require(evaluate("return 'a'..string.char(0)..'b'").toString().size() == 3, "Lua string length preserved");
  require(evaluate("return {skill='switch',time=0}").toMap()["time"].toInt() == 0, "Yang value");
  require(evaluate("return {skill='switch',time=1}").toMap()["time"].toInt() == 1, "Yin value");
  require(lua_gettop(L) == 0, "no stack growth after repeated mixed conversions");
  lua_close(L); qInfo() << "Lua card/skill conversion, error recovery and stack preservation passed";
}
