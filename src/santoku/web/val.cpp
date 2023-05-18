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

// TODO: Add checkudata calls that use these
#define MT "santoku_web"
#define MTV "santoku_web_val"

#define debug(...) printf("%s:%d\t", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n");

int l_from (lua_State *);

val *peek_val (lua_State *L, int i) {
  val **vp = (val **)luaL_checkudata(L, i, MTV);
  val *v = *vp;
  return v;
}

void push_val_lua (lua_State *L, val *v) {
  string type = v->typeof().as<string>();
  if (type == "string") {
    string x = v->as<string>();
    lua_pushstring(L, x.c_str());
  } else if (type == "number") {
    float x = v->as<float>();
    lua_pushnumber(L, x);
  } else {
    debug("Unhandled JS type, pushing nil: %s", type.c_str());
    lua_pushnil(L);
  }
}

void push_val (lua_State *L, val *v, bool pushtop, int i) {
  val **vp = (val **)lua_newuserdatauv(L, sizeof(v), pushtop ? 1 : 0);
  *vp = v;
  luaL_setmetatable(L, MTV);
  if (!pushtop)
    return;
  lua_pushvalue(L, i - 1);
  lua_setiuservalue(L, -2, 1);
}

int j_arg (int Lp, int i) {
  lua_State *L = (lua_State *)Lp;
  return (int)peek_val(L, i)->as_handle();
}

int j_args (int Lp, int arg0, int argc) {
  lua_State *L = (lua_State *)Lp;
  return (int) EM_ASM_PTR(({
    return Emval.toHandle({
      [Symbol.iterator]() {
        var i = 0;
        return {
          next() {
            if (i == $2) {
              return { done: true };
            } else {
              i = i + 1;
              var val = Emval.toValue(Module.arg($0, i + $1 - 1));
              return { done: false, value: val };
            }
          }
        };
      }
    })
  }), Lp, arg0, argc);
}

// TODO: This is called with a parameter "i"
// which supposedly is the index of the userdata
// on which we called x:set(k, v). When using
// "i", in the getiuservalue call, the user
// value returned is nil. It works when "-5" is
// used instead. Why is this?
void j_set (int Lp, int i, int k, int v) {
  lua_State *L = (lua_State *)Lp;
  val *kk = new val(val::take_ownership((EM_VAL)k));
  val *vv = new val(val::take_ownership((EM_VAL)v));
  lua_getiuservalue(L, -5, 1);
  push_val_lua(L, vv);
  push_val_lua(L, kk);
  lua_settable(L, -3);
}

int j_call (int Lp, int fnp, int argsp) {
  lua_State *L = (lua_State *)Lp;
  lua_pushcfunction(L, l_from);
  lua_rawgeti(L, LUA_REGISTRYINDEX, fnp);
  val *args = new val(val::take_ownership((EM_VAL)argsp));
  int argc = (*args)["length"].as<int>();
  for (int i = 0; i < argc; i ++)
    push_val_lua(L, new val((*args)[val(i)]));
  lua_call(L, argc, 1);
  lua_call(L, 1, 1);
  return (int)peek_val(L, -1)->as_handle();
}

EMSCRIPTEN_BINDINGS(santoku_web_val) {
  emscripten::function("arg", &j_arg, allow_raw_pointers());
  emscripten::function("args", &j_args, allow_raw_pointers());
  emscripten::function("set", &j_set, allow_raw_pointers());
  emscripten::function("call", &j_call, allow_raw_pointers());
}

int l_global (lua_State *L) {
  const char *str = luaL_checkstring(L, -1);
  push_val(L, new val(val::global(str)), false, 0);
  return 1;
}

int l_array (lua_State *L) {
  push_val(L, new val(val::array()), false, 0);
  return 1;
}

int l_object (lua_State *L) {
  push_val(L, new val(val::object()), false, 0);
  return 1;
}

int l_u8string (lua_State *L) {
  const char *str = luaL_checkstring(L, -1);
  push_val(L, new val(val::u8string(str)), false, 0);
  return 1;
}

int l_undefined (lua_State *L) {
  push_val(L, new val(val::undefined()), false, 0);
  return 1;
}

int l_null (lua_State *L) {
  push_val(L, new val(val::null()), false, 0);
  return 1;
}

int l_take_ownership (lua_State *L) {
  // TODO: Can we use checkudata here?
  EM_VAL v = (EM_VAL)lua_touserdata(L, -1);
  push_val(L, new val(val::take_ownership(v)), false, 0);
  return 1;
}

int l_module_property (lua_State *L) {
  const char *str = luaL_checkstring(L, -1);
  push_val(L, new val(val::module_property(str)), false, 0);
  return 1;
}

int l_get (lua_State *L) {
  val *k = peek_val(L, -1);
  val *o = peek_val(L, -2);
  push_val(L, new val((*o)[*k]), false, 0);
  return 1;
}

int l_set (lua_State *L) {
  val *v = peek_val(L, -1);
  val *k = peek_val(L, -2);
  val *o = peek_val(L, -3);
  o->set(*k, *v);
  return 0;
}

int l_typeof (lua_State *L) {
  val *v = peek_val(L, -1);
  val *t = new val(v->typeof());
  push_val(L, t, false, 0);
  return 1;
}

// TODO: is ASYNCIFY the right definition? How
// does -sASYNCIFY get passed to the
// preprocessor?
#ifdef ASYNCIFY
int l_await (lua_State *L) {
  val v = peek_val(L, -1);
  val a = v.await();
  push_val(L, a, false, 0);
  return 1;
}
#endif

int l_call (lua_State *L) {
  int n = lua_gettop(L);
  val *v = peek_val(L, -n);
  const char *prop = luaL_checkstring(L, -n + 1);
  val *r = new val(val::take_ownership((EM_VAL)EM_ASM_PTR(({
    var obj = Emval.toValue($1);
    var prop = UTF8ToString($2);
    var args = Emval.toValue(Module.args($0, $3, $4));
    var ret = obj[prop](...args);
    return Emval.toHandle(ret);
  }), L, v->as_handle(), prop, -n + 2, n - 2)));
  push_val(L, r, false, 0);
  return 1;
}

int l_new (lua_State *L) {
  int n = lua_gettop(L);
  val *v = peek_val(L, -n);
  val *r = new val(val::take_ownership((EM_VAL)EM_ASM_PTR(({
    var obj = Emval.toValue($1);
    var args = Emval.toValue(Module.args($0, $2, $3));
    return Emval.toHandle(new obj(...args));
  }), L, v->as_handle(), -n + 1, n - 1)));
  push_val(L, r, false, 0);
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

int l_tbl (lua_State *L) {
  val *v = peek_val(L, -1);
  lua_getiuservalue(L, -1, 1);
  return 1;
}

int l_fn (lua_State *L) {
  val *v = peek_val(L, -1);
  lua_getiuservalue(L, -1, 1);
  return 1;
}

int l_from_mt (lua_State *L) {
  lua_remove(L, 1);
  return l_from(L);
}

int l_from (lua_State *L) {
  int t = lua_gettop(L);
  int type = lua_type(L, -t);
  if (type == LUA_TSTRING) {
    push_val(L, new val(lua_tostring(L, -t)), false, 0);
  } else if (type == LUA_TNUMBER) {
    push_val(L, new val(lua_tonumber(L, -t)), false, 0);
  } else if (type == LUA_TBOOLEAN) {
    push_val(L, new val(lua_toboolean(L, -t)), false, 0);
  } else if (type == LUA_TTABLE) {
    EM_VAL proto = t == 2
      ? peek_val(L, -t + 1)->as_handle()
      : val::undefined().as_handle();
    // TODO: Should we allow arguments passed to proto(...)?
    push_val(L, new val(val::take_ownership((EM_VAL) EM_ASM_PTR(({
      var proto = Emval.toValue($2);
      var obj = proto ? new proto() : {};
      return Emval.toHandle(new Proxy(obj, {
        get(o, k) {
          return o[k];
        },
        set(_, v, k) {
          Module.set($0, $1, Emval.toHandle(k), Emval.toHandle(v));
        }
      }))
    }), L, t, proto))), true, -t);
  } else if (type == LUA_TFUNCTION) {
    int fnref = luaL_ref(L, LUA_REGISTRYINDEX);
    lua_rawgeti(L, LUA_REGISTRYINDEX, fnref);
    push_val(L, new val(val::take_ownership((EM_VAL) EM_ASM_PTR(({
      return Emval.toHandle(function (...args) {
        return Emval.toValue(Module.call($0, $1, Emval.toHandle(args)));
      });
    }), L, fnref))), true, -t);
  } else {
    // type is LUA_TNIL or unknown
    lua_pushnil(L);
  }
  // TODO:
  /* LUA_TLIGHTUSER: */
  /* LUA_TUSERDATA: */
  /* LUA_TTHREAD: */
  return 1;
}

luaL_Reg mt_fns[] = {
  { "str", l_str },
  { "num", l_num },
  { "bool", l_bool },
  { "tbl", l_tbl },
  { "fn", l_fn },
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
  { "undefined", l_undefined },
  { "null", l_null },
  { "take_ownership", l_take_ownership },
  { "module_property", l_module_property },
  { NULL, NULL }
};

int luaopen_santoku_web_val (lua_State *L) {
  lua_newtable(L);
  luaL_newmetatable(L, MT);
  lua_pushcfunction(L, l_from_mt);
  lua_setfield(L, -2, "__call");
  lua_pop(L, 1);
  luaL_setmetatable(L, MT);
  luaL_setfuncs(L, fns, 0);
  luaL_newmetatable(L, MTV);
  lua_newtable(L);
  luaL_setfuncs(L, mt_fns, 0);
  lua_setfield(L, -2, "__index");
  lua_pop(L, 1);
  return 1;
}
