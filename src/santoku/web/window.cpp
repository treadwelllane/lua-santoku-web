extern "C" {
  #include "lua.h"
  #include "lauxlib.h"
}

#include "emscripten.h"
#include "emscripten/val.h"

using namespace emscripten;

int alert (lua_State *L) {
  val win = val::global("window");
  win.call<val>("alert", val(luaL_checkstring(L, -1)));
  return 1;
}

static luaL_Reg const fns[] = {
  { "alert", alert },
  { NULL, NULL }
};

extern "C" {
  int luaopen_santoku_web_window (lua_State *L) {
    lua_newtable(L);
    luaL_setfuncs(L, fns, 0);
    return 1;
  }
}
