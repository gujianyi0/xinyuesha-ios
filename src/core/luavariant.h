// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <QVariant>
#include <QHash>
#include <QDebug>
#include <lua.hpp>

namespace fkLuaVariant {
// Reading a value must never change its caller's stack, including error paths.
// Class tables can have a metatable without providing __tocbor.
struct StackRestore {
  lua_State *state;
  int top;
  explicit StackRestore(lua_State *L) : state(L), top(lua_gettop(L)) {}
  ~StackRestore() { lua_settop(state, top); }
};

inline QVariant read(lua_State *L, int index = 0,
                     QHash<const void *, bool> ancestors = {}) {
  StackRestore restore(L);
  index = lua_absindex(L, index == 0 ? -1 : index);
  switch (lua_type(L, index)) {
  case LUA_TNIL: return QVariant::fromValue(nullptr);
  case LUA_TBOOLEAN: return bool(lua_toboolean(L, index));
  case LUA_TNUMBER: return lua_tonumber(L, index);
  case LUA_TSTRING: {
    size_t size = 0;
    const char *text = lua_tolstring(L, index, &size);
    return QString::fromUtf8(text, qsizetype(size));
  }
  case LUA_TTABLE: {
    const void *identity = lua_topointer(L, index);
    if (ancestors.contains(identity) || ancestors.size() >= 128) {
      qWarning("Lua value contains a cycle or exceeds the nesting limit");
      return {};
    }
    ancestors.insert(identity, true);
    if (lua_getmetatable(L, index)) {
      lua_pushliteral(L, "__tocbor");
      lua_rawget(L, -2);
      if (!lua_isnil(L, -1)) {
        lua_pushvalue(L, index);
        if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
          qWarning("Lua __tocbor conversion failed: %s", lua_tostring(L, -1));
          return {};
        }
        if (lua_type(L, -1) != LUA_TSTRING) {
          qWarning("Lua __tocbor must return a string");
          return {};
        }
        size_t size = 0;
        const char *bytes = lua_tolstring(L, -1, &size);
        return QByteArray(bytes, qsizetype(size));
      }
      lua_pop(L, 2); // absent metamethod AND metatable
    }
    const lua_Integer length = lua_rawlen(L, index);
    if (length > 0) {
      QVariantList result;
      for (lua_Integer i = 1; i <= length; ++i) {
        lua_rawgeti(L, index, i);
        result.append(read(L, -1, ancestors));
        lua_pop(L, 1);
      }
      return result;
    }
    QVariantMap result;
    lua_pushnil(L);
    while (lua_next(L, index)) {
      if (lua_type(L, -2) != LUA_TSTRING && lua_type(L, -2) != LUA_TNUMBER) {
        qWarning("Lua object key must be a string or a number");
        return {};
      }
      // lua_tolstring mutates numeric keys; convert a copy to keep lua_next valid.
      lua_pushvalue(L, -2);
      size_t size = 0;
      const char *key = lua_tolstring(L, -1, &size);
      const QString name = QString::fromUtf8(key, qsizetype(size));
      lua_pop(L, 1);
      result.insert(name, read(L, -1, ancestors));
      lua_pop(L, 1);
    }
    return result.isEmpty() ? QVariant(QVariantList{}) : QVariant(result);
  }
  default:
    qWarning("Unsupported Lua value type: %s", luaL_typename(L, index));
    return {};
  }
}
} // namespace fkLuaVariant
