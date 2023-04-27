extern "C" {
  #include "lua.h"
  #include "lauxlib.h"
}

#include "emscripten.h"
#include "emscripten/val.h"

using namespace emscripten;

int l_alert (lua_State *L) {
  val win = val::global("window");
  val query = val(luaL_checkstring(L, -1));
  win.call<val>("alert", query);
  return 1;
}

int l_el (lua_State *L) {
  val doc = val::global("document");
  val query = val(luaL_checkstring(L, -1));
  lua_newtable(L);
  lua_pushstring(L, "nodes");
  val *nodesp = (val *)lua_newuserdatauv(L, sizeof(val), 1);
  *nodesp = doc.call<val>("querySelectorAll", query);
  lua_pushlightuserdata(L, (void *)query);
  lua_setiuservalue(L, -1, 0);
  lua_settable(L, -2);
  return 1;
}

static luaL_Reg const fns[] = {
  { "alert", l_alert },
  { "el", l_el },
  { NULL, NULL }
};

extern "C" {
  int luaopen_santoku_web_window (lua_State *L) {
    lua_newtable(L);
    luaL_setfuncs(L, fns, 0);
    return 1;
  }
}
