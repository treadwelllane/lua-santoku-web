extern "C" {
  #include "lua.h"
  #include "lauxlib.h"
  int luaopen_santoku_web_wasm (lua_State *L);
}

int pointer (lua_State *L) {
  int ptr = luaL_checkinteger(L, -1);
  lua_pushlightuserdata(L, (void *)ptr);
  return 1;
}

luaL_Reg fns[] = {
  { "pointer", pointer },
  { NULL, NULL }
};

int luaopen_santoku_web_wasm (lua_State *L) {
  lua_newtable(L);
  luaL_setfuncs(L, fns, 0);
  return 1;
}
