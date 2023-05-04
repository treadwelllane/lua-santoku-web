// TODO: tests
// TODO: are we leaking memory with all of the
// "new val(...)" calls

extern "C" {
  #include "lua.h"
  #include "lauxlib.h"
  int luaopen_santoku_web_val (lua_State *L);
}

#include "emscripten.h"
#include "emscripten/val.h"

using namespace std;
using namespace emscripten;

#define MT "santoku_web_val"
#define debug(...) printf("%s:%d\t", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n");

EM_JS(EM_VAL, jscall, (void *objp, const char *propp, void *argsp), {
  var obj = Emval.toValue(objp);
  var prop = UTF8ToString(propp);
  var args = Emval.toValue(argsp);
  return obj[prop](...args);
})

EM_JS(EM_VAL, jsnew, (void *objp, void *argsp), {
  var obj = Emval.toValue(objp);
  var args = Emval.toValue(argsp);
  return new obj(...args);
})

void push_val (lua_State *L, val *v) {
  lua_newuserdatauv(L, 0, 1);
  lua_pushlightuserdata(L, v);
  lua_setiuservalue(L, -1, 1);
  luaL_setmetatable(L, MT);
}

val *args_to_iterable (lua_State *L, int start) {
  return NULL;
}

int l_global (lua_State *L) {
  const char *str = luaL_checkstring(L, -1);
  push_val(L, new val(val::global(str)));
  return 1;
}

int l_array (lua_State *L) {
  push_val(L, new val(val::array()));
  return 1;
}

int l_object (lua_State *L) {
  push_val(L, new val(val::object()));
  return 1;
}

int l_u8string (lua_State *L) {
  const char *str = luaL_checkstring(L, -1);
  push_val(L, new val(val::u8string(str)));
  return 1;
}

int l_undefined (lua_State *L) {
  push_val(L, new val(val::undefined()));
  return 1;
}

int l_null (lua_State *L) {
  push_val(L, new val(val::null()));
  return 1;
}

int l_as_handle (lua_State *L) {
  lua_getiuservalue(L, -1, 1);
  val *v = (val *)lua_touserdata(L, -1);
  lua_pushlightuserdata(L, v->as_handle());
  return 1;
}

int l_take_ownership (lua_State *L) {
  EM_VAL v = (EM_VAL)lua_touserdata(L, -1);
  push_val(L, new val(val::take_ownership(v)));
  return 1;
}

int l_module_property (lua_State *L) {
  const char *str = luaL_checkstring(L, -1);
  push_val(L, new val(val::module_property(str)));
  return 1;
}

int l_get (lua_State *L) {
  lua_getiuservalue(L, -1, 1);
  val *v = (val *)lua_touserdata(L, -1);
  const char *prop = luaL_checkstring(L, -2);
  push_val(L, new val((*v)[prop]));
  return 1;
}

int l_set (lua_State *L) {
  lua_getiuservalue(L, -1, 1);
  val *k = (val *)lua_touserdata(L, -1);
  lua_getiuservalue(L, -2, 1);
  val *v = (val *)lua_touserdata(L, -1);
  lua_getiuservalue(L, -3, 1);
  val *o = (val *)lua_touserdata(L, -1);
  o->set(*k, *v);
  return 0;
}

int l_typeof (lua_State *L) {
  lua_getiuservalue(L, -1, 1);
  val *v = (val *)lua_touserdata(L, -1);
  val *t = new val(v->typeof());
  push_val(L, t);
  return 1;
}

// TODO: is ASYNCIFY the right definition? How
// does -sASYNCIFY get passed to the
// preprocessor?
#ifdef ASYNCIFY
int l_await (lua_State *L) {
  lua_getiuservalue(L, -1, 1);
  val *v = (val *)lua_touserdata(L, -1);
  val *a = new val(v->await());
  push_val(L, a);
  return 1;
}
#endif

int l_call (lua_State *L) {
  lua_getiuservalue(L, -1, 1);
  val *v = (val *)lua_touserdata(L, -1);
  const char *prop = luaL_checkstring(L, -2);
  val *argi = args_to_iterable(L, -3);
  EM_VAL r = jscall(v->as_handle(), prop, argi->as_handle());
  val *s = new val(val::take_ownership(r));
  push_val(L, s);
  return 1;
}

int l_new (lua_State *L) {
  lua_getiuservalue(L, -1, 1);
  val *v = (val *)lua_touserdata(L, -1);
  val *argi = args_to_iterable(L, -2);
  EM_VAL r = jsnew(v->as_handle(), argi->as_handle());
  val *s = new val(val::take_ownership(r));
  push_val(L, s);
  return 1;
}

luaL_Reg mt_fns[] = {
  { "as_handle", l_as_handle },
  { "get", l_get },
  { "set", l_set },
  { "typeof", l_typeof },
#ifdef ASYNCIFY
  { "await", l_await },
#endif
  { "call", l_call },
  { "new", l_new },
  { NULL, NULL }
};

luaL_Reg fns[] = {
  { "global", l_global },
  { "array", l_array },
  { "object", l_object },
  { "u8string", l_u8string },
  { "undefined", l_undefined },
  { "null", l_null },
  { "take_ownership", l_take_ownership },
  { "module_property", l_module_property },
  { NULL, NULL }
};

int luaopen_santoku_web_val (lua_State *L) {
  lua_newtable(L);
  luaL_setfuncs(L, fns, 0);
  luaL_newmetatable(L, MT);
  lua_newtable(L);
  luaL_setfuncs(L, mt_fns, 0);
  lua_setfield(L, -2, "__index");
  lua_pop(L, 1);
  return 1;
}
