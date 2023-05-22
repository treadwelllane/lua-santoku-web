// TODO: Tests

// TODO: Are we leaking memory with all of the
// "new val(...)" and luaL_ref calls?

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
#define MTL "santoku_web_lua"

#define debug(...) printf("%s:%d\t", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n");

int IDX_TBL_VAL;

int wrapfn (lua_State *);
int lua_to_val (lua_State *, int);

void args_to_vals (lua_State *L) {
  int argc = lua_gettop(L);
  for (int i = -argc; i < 0; i ++) {
    lua_to_val(L, i);
    lua_replace(L, i - 1);
  }
}

val *peek_val (lua_State *L, int i) {
  val **vp = (val **)luaL_checkudata(L, i, MTV);
  val *v = *vp;
  return v;
}

void push_val (lua_State *L, val *v) {
  val **vp = (val **)lua_newuserdatauv(L, sizeof(v), 0);
  *vp = v;
  luaL_setmetatable(L, MTV);
}

void map_lua (lua_State *L, val *v, int ref) {
  lua_rawgeti(L, LUA_REGISTRYINDEX, IDX_TBL_VAL); // map
  lua_rawgeti(L, LUA_REGISTRYINDEX, ref); // map lua
  lua_pushlightuserdata(L, v); // map lua val
  lua_settable(L, -3); // map
  lua_pop(L, 1); //
  EM_ASM(({
    var v = Emval.toValue($0);
    Module.IDX_VAL_REF.set(v, $1);
  }), v->as_handle(), ref);
}

bool unmap_lua (lua_State *L, int i) {
  lua_pushvalue(L, i); // tbl
  lua_rawgeti(L, LUA_REGISTRYINDEX, IDX_TBL_VAL); // tbl map
  lua_insert(L, -2); // map tbl
  int t = lua_gettable(L, -2);
  if (t == LUA_TNIL) { // map val
    lua_pop(L, 2); //
    return false;
  } else { // map lu
    push_val(L, (val *)lua_touserdata(L, -1)); // map lu val
    lua_remove(L, -3); // lu val
    lua_remove(L, -2); // val
    return true;
  }
}

void map_js (lua_State *L, val *v, int i) {
  lua_pushvalue(L, i); // lua
  int ref = luaL_ref(L, LUA_REGISTRYINDEX); //
  lua_rawgeti(L, LUA_REGISTRYINDEX, ref); // lua
  EM_ASM(({
    var v = Emval.toValue($0);
    Module.IDX_VAL_REF.set(v, $1);
  }), v->as_handle(), ref);
  lua_rawgeti(L, LUA_REGISTRYINDEX, IDX_TBL_VAL); // lua map
  lua_insert(L, -2); // map lua
  lua_pushlightuserdata(L, v); // map lua val
  lua_settable(L, -3); // map
  lua_pop(L, 1); //
}

bool unmap_js (lua_State *L, val *key) {
  int ref = EM_ASM_INT(({
    var v = Emval.toValue($0);
    if (Module.IDX_VAL_REF.has(v)) {
      return Module.IDX_VAL_REF.get(v) || -1;
    } else {
      return -1;
    }
  }), key->as_handle());
  if (ref != -1) {
    lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
    return true;
  } else {
    return false;
  }
}

void push_val_lua (lua_State *L, val *v) {
  string type = v->typeof().as<string>();
  if (type == "string") {
    string x = v->as<string>();
    lua_pushstring(L, x.c_str());
  } else if (type == "number") {
    float x = v->as<float>();
    lua_pushnumber(L, x);
  } else if (type == "object") {
    if (!unmap_js(L, v)) { // val
      lua_newtable(L); // ret
      luaL_setmetatable(L, MTL);
      map_js(L, v, -1);
    }
  } else if (type == "function") {
    if (!unmap_js(L, v)) {
      lua_pushlightuserdata(L, v);
      lua_pushcclosure(L, wrapfn, 1);
      map_js(L, v, -1);
    }
  } else if (type == "undefined") {
    lua_pushnil(L);
  } else {
    debug("Unhandled JS type, pushing nil: %s", type.c_str());
    lua_pushnil(L);
  }
}

int wrapfn (lua_State *L) {
  int argc = lua_gettop(L);
  int fni = lua_upvalueindex(1);
  val *vp = (val *)lua_touserdata(L, fni);
  lua_to_val(L, -argc);
  val *this_ = peek_val(L, -1);
  lua_pop(L, 1);
  push_val_lua(L, new val(val::take_ownership((EM_VAL)EM_ASM_PTR(({
    var this_ = Emval.toValue($1);
    var fn = Emval.toValue($2);
    fn = fn.bind(this_);
    var args = Emval.toValue(Module.args($0, $3, $4));
    var ret = fn(...args);
    return Emval.toHandle(ret);
  }), L, this_->as_handle(), vp->as_handle(), -argc + 1, argc - 1))));
  return 1;
}

int lua_to_val (lua_State *L, int i) {
  int type = lua_type(L, i);
  if (type == LUA_TSTRING) {
    push_val(L, new val(lua_tostring(L, i)));
  } else if (type == LUA_TNUMBER) {
    push_val(L, new val(lua_tonumber(L, i)));
  } else if (type == LUA_TBOOLEAN) {
    push_val(L, new val(lua_toboolean(L, i)));
  } else if (type == LUA_TTABLE) {
    if (!unmap_lua(L, i)) {
      lua_pushvalue(L, i); // val
      int tblref = luaL_ref(L, LUA_REGISTRYINDEX); //
      push_val(L, new val(val::take_ownership((EM_VAL) EM_ASM_PTR(({
        return Emval.toHandle(new Proxy({}, {
          get(o, k) {
            var val = Emval.toValue(Module.get($0, $1, Emval.toHandle(k)));
            return val;
          },
          getOwnPropertyDescriptor(o, k) {
            return { configurable: true, enumerable: true, value: o[k] };
          },
          ownKeys(o) {
            var keys = Emval.toValue(Module.ownKeys($0, $1));
            return keys;
          },
          set(o, v, k) {
            Module.set($0, $1, Emval.toHandle(k), Emval.toHandle(v));
          }
        }))
      }), L, tblref)))); // val
      val *v = peek_val(L, -1);
      map_lua(L, v, tblref);
    }
  } else if (type == LUA_TFUNCTION) {
    if (!unmap_lua(L, i)) {
      lua_pushvalue(L, i); // val
      int fnref = luaL_ref(L, LUA_REGISTRYINDEX); //
      push_val(L, new val(val::take_ownership((EM_VAL) EM_ASM_PTR(({
        return Emval.toHandle(new Proxy(function () {}, {
          get(o, k) {
            return o[k];
          },
          apply(_, this_, args) {
            args.unshift(this_);
            return Emval.toValue(Module.call($0, $1, Emval.toHandle(args)));
          }
        }))
      }), L, fnref)))); // val
      val *v = peek_val(L, -1);
      map_lua(L, v, fnref);
    }
  } else if (type == LUA_TUSERDATA) {
    // TODO: Should this really just be passed
    // through?
    lua_pushvalue(L, i);
  } else if (type == LUA_TNIL) {
    push_val(L, new val(val::undefined()));
  } else {
    debug("Unhandled Lua type, pushing undefined: %d", type);
    push_val(L, new val(val::undefined()));
  }
  // TODO:
  /* LUA_TLIGHTUSERDATA: */
  /* LUA_TTHREAD: */
  return 1;
}

int j_arg (int Lp, int i) {
  lua_State *L = (lua_State *)Lp;
  lua_to_val(L, i);
  EM_VAL v = peek_val(L, -1)->as_handle();
  lua_pop(L, 1);
  return (int)v;
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
              var arg = Module.arg($0, i + $1 - 1);
              var val = Emval.toValue(arg);
              return { done: false, value: val };
            }
          }
        };
      }
    })
  }), Lp, arg0, argc);
}

int j_ownKeys (int Lp, int tblref) {
  lua_State *L = (lua_State *)Lp;
  val *keys = new val(val::array());
  lua_rawgeti(L, LUA_REGISTRYINDEX, tblref);
  lua_pushnil(L);
  while (lua_next(L, -2) != 0) {
    lua_to_val(L, -2);
    val *v = peek_val(L, -1);
    keys->call<val>("push", *v);
    lua_pop(L, 2);
  }
  return (int) keys->as_handle();
}

int j_get (int Lp, int tblref, int k) {
  lua_State *L = (lua_State *)Lp;
  lua_rawgeti(L, LUA_REGISTRYINDEX, tblref);
  val *kk = new val(val::take_ownership((EM_VAL)k));
  push_val_lua(L, kk);
  lua_gettable(L, -2);
  lua_to_val(L, -1);
  val *vv = peek_val(L, -1);
  return (int) vv->as_handle();
}

void j_set (int Lp, int tblref, int k, int v) {
  lua_State *L = (lua_State *)Lp;
  val *kk = new val(val::take_ownership((EM_VAL)k));
  val *vv = new val(val::take_ownership((EM_VAL)v));
  lua_rawgeti(L, LUA_REGISTRYINDEX, tblref);
  push_val_lua(L, vv);
  push_val_lua(L, kk);
  lua_settable(L, -3);
}

int j_call (int Lp, int fnp, int argsp) {
  lua_State *L = (lua_State *)Lp;
  lua_rawgeti(L, LUA_REGISTRYINDEX, fnp);
  val *args = new val(val::take_ownership((EM_VAL)argsp));
  int argc = (*args)["length"].as<int>();
  for (int i = 0; i < argc; i ++)
    push_val_lua(L, new val((*args)[val(i)]));
  int t = lua_gettop(L) - argc - 1;
  lua_call(L, argc, LUA_MULTRET);
  if (lua_gettop(L) > t) {
    val *v = peek_val(L, -1);
    return (int)v->as_handle();
  } else {
    return (int)(new val(val::undefined()))->as_handle();
  }
}

EMSCRIPTEN_BINDINGS(santoku_web_val) {
  emscripten::function("arg", &j_arg, allow_raw_pointers());
  emscripten::function("args", &j_args, allow_raw_pointers());
  emscripten::function("get", &j_get, allow_raw_pointers());
  emscripten::function("set", &j_set, allow_raw_pointers());
  emscripten::function("call", &j_call, allow_raw_pointers());
  emscripten::function("ownKeys", &j_ownKeys, allow_raw_pointers());
}

int mtl_index (lua_State *L) {
  // tbl key
  lua_rawgeti(L, LUA_REGISTRYINDEX, IDX_TBL_VAL); // tbl key map
  lua_pushvalue(L, -3); // tbl key map tbl
  lua_gettable(L, -2); // tbl key map val
  val *v = (val *)lua_touserdata(L, -1);
  lua_to_val(L, -3); // tbl key map val keyl
  val *k = peek_val(L, -1);
  val n = (*v)[*k];
  push_val_lua(L, new val(n));
  return 1;
}

int mt_call (lua_State *L) {
  lua_remove(L, 1);
  return lua_to_val(L, lua_gettop(L));
}

int mt_global (lua_State *L) {
  const char *str = luaL_checkstring(L, -1);
  push_val(L, new val(val::global(str)));
  return 1;
}

int mt_array (lua_State *L) {
  push_val(L, new val(val::array()));
  return 1;
}

int mt_object (lua_State *L) {
  push_val(L, new val(val::object()));
  return 1;
}

int mt_undefined (lua_State *L) {
  push_val(L, new val(val::undefined()));
  return 1;
}

int mt_null (lua_State *L) {
  push_val(L, new val(val::null()));
  return 1;
}

int mtv_lua (lua_State *L) {
  val *v = peek_val(L, -1);
  push_val_lua(L, v);
  return 1;
}

int mtv_get (lua_State *L) {
  args_to_vals(L);
  val *k = peek_val(L, -1);
  val *o = peek_val(L, -2);
  push_val(L, new val((*o)[*k]));
  return 1;
}

int mtv_set (lua_State *L) {
  args_to_vals(L);
  val *v = peek_val(L, -1);
  val *k = peek_val(L, -2);
  val *o = peek_val(L, -3);
  o->set(*k, *v);
  return 0;
}

int mtv_typeof (lua_State *L) {
  val *v = peek_val(L, -1);
  val *t = new val(v->typeof());
  push_val(L, t);
  return 1;
}

int mtv_call (lua_State *L) {
  int n = lua_gettop(L);
  val *v = peek_val(L, -n);
  val *t = lua_type(L, -n + 1) == LUA_TNIL
    ? new val(val::undefined())
    : peek_val(L, -n + 1);
  val *r = new val(val::take_ownership((EM_VAL)EM_ASM_PTR(({
    var fn = Emval.toValue($1);
    var ths = Emval.toValue($2);
    fn = fn.bind(ths);
    var args = Emval.toValue(Module.args($0, $3, $4));
    return Emval.toHandle(fn(...args));
  }), L, v->as_handle(), t->as_handle(), -n + 2, n - 2)));
  push_val(L, r);
  return 1;
}

int mtv_new (lua_State *L) {
  int n = lua_gettop(L);
  val *v = peek_val(L, -n);
  val *r = new val(val::take_ownership((EM_VAL)EM_ASM_PTR(({
    var obj = Emval.toValue($1);
    var args = Emval.toValue(Module.args($0, $2, $3));
    return Emval.toHandle(new obj(...args));
  }), L, v->as_handle(), -n + 1, n - 1)));
  push_val(L, r);
  return 1;
}

/* int mt_new (lua_State *L) { */
/*   args_to_vals(L); */
/*   mtv_new(L); */
/*   /1* mtv_lua(L); *1/ */
/*   return 1; */
/* } */

luaL_Reg mtv_fns[] = {

  { "lua", mtv_lua },
  { "get", mtv_get },
  { "set", mtv_set },

  { "typeof", mtv_typeof },
  { "call", mtv_call },
  { "new", mtv_new },

  { NULL, NULL }

};

luaL_Reg mt_fns[] = {

  { "global", mt_global },
  { "array", mt_array },
  { "object", mt_object },
  { "undefined", mt_undefined },
  { "null", mt_null },

  /* { "new", mt_new }, */

  { NULL, NULL }

};

int luaopen_santoku_web_val (lua_State *L) {

  lua_newtable(L);

  luaL_newmetatable(L, MT);
  lua_pushcfunction(L, mt_call);
  lua_setfield(L, -2, "__call");
  lua_pop(L, 1);

  luaL_setmetatable(L, MT);
  luaL_setfuncs(L, mt_fns, 0);

  luaL_newmetatable(L, MTV);
  lua_newtable(L);
  luaL_setfuncs(L, mtv_fns, 0);
  lua_setfield(L, -2, "__index");
  lua_pop(L, 1);

  luaL_newmetatable(L, MTL);
  lua_pushcfunction(L, mtl_index);
  lua_setfield(L, -2, "__index");
  lua_pop(L, 1);

  EM_ASM(({
    Module.IDX_VAL_REF = new WeakMap();
  }));

  lua_newtable(L);
  lua_newtable(L);
  lua_pushstring(L, "k");
  lua_setfield(L, -2, "__mode");
  lua_setmetatable(L, -2);

  IDX_TBL_VAL = luaL_ref(L, LUA_REGISTRYINDEX);

  return 1;
}
