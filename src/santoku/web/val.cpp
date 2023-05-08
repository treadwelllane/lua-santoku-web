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
#include "emscripten/bind.h"

using namespace std;
using namespace emscripten;

#define MT "santoku_web_val"
#define debug(...) printf("%s:%d\t", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n");

val *peek_val (lua_State *L, int i) {
  val **vp = (val **)lua_touserdata(L, i);
  return *vp;
}

void push_val (lua_State *L, val *v) {
  val **vp = (val **)lua_newuserdatauv(L, sizeof(v), 0);
  *vp = v;
  luaL_setmetatable(L, MT);
}

EM_VAL js_arg (void *Lp, int argc) {
  lua_State *L = (lua_State *)Lp;
  return peek_val(L, argc)->as_handle();
}

EMSCRIPTEN_BINDINGS(santoku_web_val) {
  emscripten::function("arg", &js_arg, allow_raw_pointers());
}

/* EM_JS(EM_VAL, jscall, (void *objp, const char *propp, void *Lp, int top), { */
/*   var obj = Emval.toValue(objp); */
/*   var prop = UTF8ToString(propp); */
/*   var arg = Emval.toValue(Module.arg(Lp, top)); */
/*   return Emval.toHandle(obj[prop](arg)); */
/* }) */

/* EM_JS(EM_VAL, jsnew, (void *objp, void *Lp, int top), { */
/*   var obj = Emval.toValue(objp); */
/*   var args = Emval.toValue(argsp); */
/*   return Emval.toHandle(new obj(...args)); */
/* }) */

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
  val *v = peek_val(L, -1);
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
  val *v = peek_val(L, -2);
  const char *prop = luaL_checkstring(L, -1);
  push_val(L, new val((*v)[prop]));
  return 1;
}

int l_set (lua_State *L) {
  val *k = peek_val(L, -1);
  val *v = peek_val(L, -2);
  val *o = peek_val(L, -3);
  o->set(*k, *v);
  return 0;
}

int l_typeof (lua_State *L) {
  val *v = peek_val(L, -1);
  val *t = new val(v->typeof());
  push_val(L, t);
  return 1;
}

// TODO: is ASYNCIFY the right definition? How
// does -sASYNCIFY get passed to the
// preprocessor?
#ifdef ASYNCIFY
int l_await (lua_State *L) {
  val v = peek_val(L, -1);
  val a = v.await();
  push_val(L, a);
  return 1;
}
#endif

int l_call (lua_State *L) {
  int n = lua_gettop(L);
  val *v = peek_val(L, -n);
  const char *prop = luaL_checkstring(L, -n + 1);
  /* EM_VAL r = (EM_VAL)EM_ASM_PTR(({ */
  /*   var obj = Emval.toValue($0); */
  /*   var prop = UTF8ToString($1); */
  /*   var arg = Emval.toValue(Module.arg($2, $3)); */
  /*   return Emval.toHandle(obj[prop](arg)); */
  /* }), v->as_handle(), prop, L, -n + 2); */
  /* EM_VAL r = jscall(v->as_handle(), prop, (void *)L, -n + 2); */
  /* val *s = new val(val::take_ownership(r)); */
  val r = v->call<val>(prop);
  val *s = new val(r);
  push_val(L, s);
  return 1;
}

int l_new (lua_State *L) {
  int n = lua_gettop(L);
  val *v = peek_val(L, -n);
  /* EM_VAL r = (EM_VAL)EM_ASM_PTR(({ */
  /*   var obj = Emval.toValue(objp); */
  /*   var args = Emval.toValue(argsp); */
  /*   return Emval.toHandle(new obj(...args)); */
  /* }), v->as_handle(), L, -n + 1); */
  /* EM_VAL r = jsnew(v->as_handle(), (void *)L, -n + 1); */
  /* val *s = new val(val::take_ownership(r)); */
  val r = v->new_();
  val *s = new val(r);
  push_val(L, s);
  return 1;
}

int l_str (lua_State *L) {
  val *v = peek_val(L, -1);
  string s = v->as<string>();
  lua_pushstring(L, s.c_str());
  return 1;
}

int l_num (lua_State *L) {
  val *v = peek_val(L, -1);
  float n = v->as<float>();
  lua_pushnumber(L, n);
  return 1;
}

int l_bool (lua_State *L) {
  val *v = peek_val(L, -1);
  bool b = v->as<bool>();
  lua_pushboolean(L, b);
  return 1;
}

int l_from (lua_State *L) {
  int type = lua_type(L, -1);
  debug("type %d", type);
  switch (type) {
    case LUA_TBOOLEAN:
      push_val(L, new val(lua_toboolean(L, -1)));
      break;
    case LUA_TNUMBER:
      push_val(L, new val(lua_tonumber(L, -1)));
      break;
    case LUA_TSTRING:
      push_val(L, new val(lua_tostring(L, -1)));
      break;
    /* case LUA_TLIGHTUSER: */
    /*   break; */
    /* case LUA_TTABLE: */
    /*   break; */
    /* case LUA_TFUNCTION: */
    /*   break; */
    /* case LUA_TUSERDATA: */
    /*   break; */
    /* case LUA_TTHREAD: */
    /*   break; */
    case LUA_TNIL:
    default:
      lua_pushnil(L);
      break;
  }
  return 1;
}

luaL_Reg mt_fns[] = {
  { "str", l_str },
  { "num", l_num },
  { "bool", l_bool },
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
  { "from", l_from },
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
