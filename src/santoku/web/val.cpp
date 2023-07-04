// TODO: Are we leaking memory with all of the
// "new val(...)" and luaL_ref calls?

// TODO: val(<table>) should allow second "val"
// argument which becomes the proxy target

// TODO: abstract some of the common patterns
// here into a library. Like requiring a santoku
// library and calling a function defined in lua
// from c. Perhaps using macros like L(require,
// "santoku.compat") or similar.

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

// Base metatable for JS values
#define MTV "santoku_web_val"

// Proxy to JS, with :val(), :typeof(), instanceof()
#define MTO "santoku_web_object"

// Same as MTO, with __call and :new(...)
#define MTF "santoku_web_function"

// Same as MTO, with :await(<fn>)
#define MTP "santoku_web_promise"

#define debug(...) \
  printf("%s:%d\t", __FILE__, __LINE__); \
  printf(__VA_ARGS__); \
  printf("\n");

int IDX_TBL_VAL;

int MTO_FNS;
int MTP_FNS;
int MTF_FNS;

int lua_to_val (lua_State *, int, bool);
int mtv_typeof (lua_State *);
int mtv_instanceof (lua_State *);
int mtv_new (lua_State *);
int mtv_call (lua_State *);
int mtv_set (lua_State *);

void args_to_vals (lua_State *L) {
  int argc = lua_gettop(L);
  for (int i = -argc; i < 0; i ++) {
    lua_to_val(L, i, false);
    lua_replace(L, i - 1);
  }
}

val *peek_val (lua_State *L, int i) {
  void *vp = NULL;
  if (((vp = luaL_testudata(L, i, MTO)) == NULL) &&
      ((vp = luaL_testudata(L, i, MTP)) == NULL) &&
      ((vp = luaL_testudata(L, i, MTF)) == NULL))
    vp = luaL_checkudata(L, i, MTV);
  return *(val **)vp;
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
    if (v == null || v == undefined)
      return;
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
  int rc = EM_ASM_INT(({
    var v = Emval.toValue($0);
    if (v == null || v == undefined)
      return 1;
    Module.IDX_VAL_REF.set(v, $1);
    return 0;
  }), v->as_handle(), ref);
  if (rc == 1)
    return;
  lua_rawgeti(L, LUA_REGISTRYINDEX, IDX_TBL_VAL); // lua map
  lua_insert(L, -2); // map lua
  lua_pushlightuserdata(L, v); // map lua val
  lua_settable(L, -3); // map
  lua_pop(L, 1); //
}

bool unmap_js (lua_State *L, val *key) {
  int ref = EM_ASM_INT(({
    var v = Emval.toValue($0);
    if (v == null || v == undefined)
      return -1;
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

// TODO: Implement recurse
void push_val_lua (lua_State *L, val *v, bool recurse) {
  string type = v->typeof().as<string>();
  if (type == "string") {
    string x = v->as<string>();
    lua_pushstring(L, x.c_str());
  } else if (type == "number") {
    bool isInteger = EM_ASM_INT(({
      try {
        var v = Emval.toValue($0);
        return Number.isInteger(v);
      } catch (_) {
        return false;
      }
    }), v->as_handle());
    if (isInteger) {
      // TODO: Should be int64_t?
      long x = v->as<long>();
      lua_pushinteger(L, x);
    } else {
      double x = v->as<double>();
      lua_pushnumber(L, x);
    }
  } else if (type == "bigint") {
    // TODO: Needs to be thoroughly tested to
    // support 64 bit integers.
    int64_t n = EM_ASM_INT(({
      var bi = Emval.toValue($1);
      if (bi > Number.MAX_SAFE_INTEGER ||
          bi < Number.MIN_SAFE_INTEGER)
        Module.error($0, "Conversion from bigint to number failed: too large or too small");
      return Number(bi);
    }), L, v->as_handle());
    lua_pushinteger(L, n);
  } else if (type == "boolean") {
    bool x = v->as<bool>();
    lua_pushboolean(L, x);
  } else if (type == "object") {
    if (!unmap_js(L, v)) { // val
      bool isNull = EM_ASM_INT(({
        return Emval.toValue($0) == null
          ? 1 : 0;
      }), v->as_handle());
      if (isNull) {
        lua_pushnil(L);
      } else {
        bool isPromise = EM_ASM_INT(({
          return Emval.toValue($0) instanceof Promise
            ? 1 : 0;
        }), v->as_handle());
        lua_newtable(L); // ret
        luaL_setmetatable(L, isPromise ? MTP : MTO);
        map_js(L, v, -1);
      }
    }
  } else if (type == "function") {
    if (!unmap_js(L, v)) {
      lua_newtable(L); // ret
      luaL_setmetatable(L, MTF);
      map_js(L, v, -1);
    }
  } else if (type == "undefined") {
    lua_pushnil(L);
  } else {
    printf("Unhandled JS type, pushing nil: %s\n", type.c_str());
    lua_pushnil(L);
  }
}

void set_islua (val *v) {
  EM_ASM(({
    var v = Emval.toValue($0);
    Module.IDX_IS_LUA.add(v);
  }), v->as_handle());
}

bool get_islua (val *v) {
  return (bool) EM_ASM_INT(({
    var v = Emval.toValue($0);
    return Module.IDX_IS_LUA.has(v);
  }), v->as_handle());
}

int lua_to_val (lua_State *L, int i, bool recurse) {
  if (unmap_lua(L, i))
    return 1;
  int type = lua_type(L, i);
  if (type == LUA_TSTRING) {
    push_val(L, new val(lua_tostring(L, i)));
  } else if (type == LUA_TNUMBER) {
    push_val(L, new val(lua_tonumber(L, i)));
  } else if (type == LUA_TBOOLEAN) {
    push_val(L, new val(lua_toboolean(L, i) ? true : false));
  } else if (type == LUA_TTABLE) {
    lua_pushvalue(L, i); // val
    lua_pushvalue(L, -1); // val val
    lua_getglobal(L, "require"); // val val req
    lua_pushstring(L, "santoku.compat"); // val val req str
    lua_call(L, 1, 1); // val val lib
    lua_pushstring(L, "isarray"); // val val lib prop
    lua_gettable(L, -2); // val val lib fn
    lua_insert(L, -3); // val fn val lib
    lua_pop(L, 1); // val fn val
    lua_call(L, 1, 1); // val bool
    bool isarray = lua_toboolean(L, -1);
    lua_pop(L, 1); // val
    if (!recurse) {
      int tblref = luaL_ref(L, LUA_REGISTRYINDEX); //
      push_val(L, new val(val::take_ownership((EM_VAL) EM_ASM_PTR(({
        try {
          var obj = $2 ? [] : {};
          return Emval.toHandle(new Proxy(obj, {
            get(o, k) {
              var isnumber;
              try { isnumber = !isNaN(+k); }
              catch (_) { isnumber = false; }
              if (o instanceof Array && k == "length")
                return Module.len($0, $1);
              if (o instanceof Array && isnumber)
                return Emval.toValue(Module.get($0, $1, Emval.toHandle(+k + 1)));
              if (typeof k == "string")
                return Emval.toValue(Module.get($0, $1, Emval.toHandle(k)));
              if (k == Symbol.iterator) {
                // TODO: This creates an
                // intermediary array, which is not
                // likely necessary
                return Object.values(o)[k];
              }
              return Reflect.get(o, k);
            },
            // TODO: Should we extend this and
            // ownKeys to support __index
            // properties?
            getOwnPropertyDescriptor(o, k) {
              return Object.getOwnPropertyDescriptor(o, k) || {
                configurable: true,
                enumerable: true,
                value: o[k]
              };
            },
            ownKeys(o) {
              var keys = Emval.toValue(Module.ownKeys($0, $1));
              if (o instanceof Array)
                keys.push("length");
              return keys;
            },
            set(o, v, k) {
              if (o instanceof Array && typeof k == "number")
                Module.set($0, $1, Emval.toHandle(k + 1), Emval.toHandle(v));
              else
                Module.set($0, $1, Emval.toHandle(k), Emval.toHandle(v));
            }
          }))
        } catch (e) {
          Module.error($0, Emval.toHandle(e));
          return undefined;
        }
      }), L, tblref, isarray))));
      val *v = peek_val(L, -1);
      map_lua(L, v, tblref);
      set_islua(peek_val(L, -1));
    } else if (isarray) {
      lua_pushvalue(L, -1); // val val
      lua_getglobal(L, "require"); // val val req
      lua_pushstring(L, "santoku.table"); // val val req str
      lua_call(L, 1, 1); // val val lib
      lua_pushstring(L, "len"); // val val lib prop
      lua_gettable(L, -2); // val val lib fn
      lua_insert(L, -3); // val fn val lib
      lua_pop(L, 1); // val fn val
      lua_call(L, 1, 1); // val int
      int len = lua_tointeger(L, -1);
      lua_pop(L, 1); // val
      val *arr = new val(val::array());
      for (int j = 1; j <= len; j ++) {
        lua_pushinteger(L, j); // val idx
        lua_gettable(L, -2); // val prop
        lua_to_val(L, -1, true); // val prop val
        val *el = peek_val(L, -1); // val prop val
        arr->set(j - 1, *el);
        lua_pop(L, 2);
      }
      lua_pop(L, 1);
      push_val(L, arr);
    } else {
      val *obj = new val(val::object()); // val
      lua_pushnil(L); // val nil
      while (lua_next(L, -2) != 0) { // val k v
        lua_to_val(L, -2, true); // val k v kk
        lua_to_val(L, -2, true); // val k v kk vv
        val *kk = peek_val(L, -2); // val k v kk vv
        val *vv = peek_val(L, -1); // val k v kk vv
        obj->set(*kk, *vv);
        lua_pop(L, 3); // val k
      }
      lua_pop(L, 1);
      push_val(L, obj);
    }
  } else if (type == LUA_TFUNCTION) {
    lua_pushvalue(L, i); // val
    int fnref = luaL_ref(L, LUA_REGISTRYINDEX); //
    push_val(L, new val(val::take_ownership((EM_VAL) EM_ASM_PTR(({
      try {
        return Emval.toHandle(new Proxy(function () {}, {
          apply(_, this_, args) {
            args.unshift(this_);
            return Emval.toValue(Module.call($0, $1, Emval.toHandle(args)));
          }
        }))
      } catch (e) {
        Module.error($0, Emval.toHandle(e));
        return undefined;
      }
    }), L, fnref)))); // val
    val *v = peek_val(L, -1);
    map_lua(L, v, fnref);
    set_islua(v);
  } else if (type == LUA_TUSERDATA) {
    // TODO: Should this really just be passed
    // through?
    lua_pushvalue(L, i);
  } else if (type == LUA_TNIL) {
    push_val(L, new val(val::undefined()));
  } else {
    /* LUA_TLIGHTUSERDATA: */
    /* LUA_TTHREAD: */
    printf("Unhandled Lua type, pushing undefined: %d\n", type);
    push_val(L, new val(val::undefined()));
  }
  return 1;
}

int j_arg (int Lp, int i) {
  lua_State *L = (lua_State *)Lp;
  lua_to_val(L, i, false);
  EM_VAL v = peek_val(L, -1)->as_handle();
  lua_pop(L, 1);
  return (int)v;
}

int j_args (int Lp, int arg0, int argc) {
  lua_State *L = (lua_State *)Lp;
  return (int) EM_ASM_PTR(({
    try {
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
    } catch (e) {
      Module.error($0, Emval.toHandle(e));
      return undefined;
    }
  }), Lp, arg0, argc);
}

int j_ownKeys (int Lp, int tblref) {
  lua_State *L = (lua_State *)Lp;
  val *keys = new val(val::array());
  lua_rawgeti(L, LUA_REGISTRYINDEX, tblref);
  lua_pushnil(L);
  while (lua_next(L, -2) != 0) {
    lua_to_val(L, -2, false);
    val *v = peek_val(L, -1);
    val *s = new val(val::take_ownership((EM_VAL)EM_ASM_PTR(({
      try {
        var ks = Emval.toValue($0);
        var v = Emval.toValue($1);
        if (ks instanceof Array && typeof v == "number") {
          return Emval.toHandle(String(v - 1));
        } else {
          return Emval.toHandle(String(v));
        }
      } catch (e) {
        Module.error($0, Emval.toHandle(e));
        return undefined;
      }
    }), keys->as_handle(), v->as_handle())));
    keys->call<val>("push", *s);
    lua_pop(L, 2);
  }
  return (int) keys->as_handle();
}

int j_get (int Lp, int tblref, int k) {
  lua_State *L = (lua_State *)Lp;
  lua_rawgeti(L, LUA_REGISTRYINDEX, tblref);
  val *kk = new val(val::take_ownership((EM_VAL)k));
  push_val_lua(L, kk, false);
  lua_gettable(L, -2);
  lua_to_val(L, -1, false);
  val *vv = peek_val(L, -1);
  return (int) vv->as_handle();
}

void j_set (int Lp, int tblref, int k, int v) {
  lua_State *L = (lua_State *)Lp;
  val *kk = new val(val::take_ownership((EM_VAL)k));
  val *vv = new val(val::take_ownership((EM_VAL)v));
  lua_rawgeti(L, LUA_REGISTRYINDEX, tblref);
  push_val_lua(L, vv, false);
  push_val_lua(L, kk, false);
  lua_settable(L, -3);
}

int j_call (int Lp, int fnp, int argsp) {
  lua_State *L = (lua_State *)Lp;
  lua_rawgeti(L, LUA_REGISTRYINDEX, fnp);
  val *args = new val(val::take_ownership((EM_VAL)argsp));
  int argc = (*args)["length"].as<int>();
  for (int i = 0; i < argc; i ++)
    push_val_lua(L, new val((*args)[val(i)]), false);
  int t = lua_gettop(L) - argc - 1;
  lua_call(L, argc, LUA_MULTRET);
  if (lua_gettop(L) > t) {
    val *v = peek_val(L, -1);
    return (int)v->as_handle();
  } else {
    return (int)(new val(val::undefined()))->as_handle();
  }
}

void j_error (int Lp, int ep) {
  lua_State *L = (lua_State *)Lp;
  val *e = new val(val::take_ownership((EM_VAL)ep));
  push_val_lua(L, e, false);
  lua_error(L);
}

int j_len (int Lp, int tblref) {
  lua_State *L = (lua_State *)Lp;
  lua_getglobal(L, "require"); // fn
  lua_pushstring(L, "santoku.table"); // fn mod
  lua_call(L, 1, 1); // lib
  lua_pushstring(L, "len"); // lib str
  lua_gettable(L, -2); // lib fn
  lua_rawgeti(L, LUA_REGISTRYINDEX, tblref); // lib fn val
  lua_call(L, 1, 1); // lib len
  int len = lua_tointeger(L, -1);
  lua_pop(L, 2); //
  return len;
}

EMSCRIPTEN_BINDINGS(santoku_web_val) {
  emscripten::function("error", &j_error, allow_raw_pointers());
  emscripten::function("arg", &j_arg, allow_raw_pointers());
  emscripten::function("args", &j_args, allow_raw_pointers());
  emscripten::function("get", &j_get, allow_raw_pointers());
  emscripten::function("set", &j_set, allow_raw_pointers());
  emscripten::function("call", &j_call, allow_raw_pointers());
  emscripten::function("ownKeys", &j_ownKeys, allow_raw_pointers());
  emscripten::function("len", &j_len, allow_raw_pointers());
}

int mt_call (lua_State *L) {
  lua_remove(L, 1);
  int n = lua_gettop(L);
  if (n > 1) {
    return lua_to_val(L, -n, lua_toboolean(L, -n + 1));
  } else {
    return lua_to_val(L, lua_gettop(L), false);
  }
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

int mto_index (lua_State *L) {
  lua_rawgeti(L, LUA_REGISTRYINDEX, MTO_FNS); // tbl key fns
  lua_pushvalue(L, -2); // tbl key fns key
  if (lua_gettable(L, -2) != LUA_TNIL) // tbl key fns fn
    return 1;
  lua_pop(L, 2); // tbl key
  lua_rawgeti(L, LUA_REGISTRYINDEX, IDX_TBL_VAL); // tbl key map
  lua_pushvalue(L, -3); // tbl key map tbl
  lua_gettable(L, -2); // tbl key map val
  val *v = (val *)lua_touserdata(L, -1);
  lua_to_val(L, -3, false); // tbl key map val keyl
  val *k = peek_val(L, -1);
  val *n = new val(val::take_ownership((EM_VAL)EM_ASM_PTR(({
    var v = Emval.toValue($0);
    var k = Emval.toValue($1);
    if (v instanceof Array && typeof k == "number")
      k = k - 1;
    return Emval.toHandle(v[k]);
  }), v->as_handle(), k->as_handle())));
  push_val_lua(L, n, false);
  return 1;
}

int mto_newindex (lua_State *L) {
  // tbl key value
  return mtv_set(L);
}

int mto_instanceof (lua_State *L) {
  mtv_instanceof(L);
  val *v = peek_val(L, -1);
  push_val_lua(L, v, false);
  return 1;
}

int mto_typeof (lua_State *L) {
  mtv_typeof(L);
  val *v = peek_val(L, -1);
  push_val_lua(L, v, false);
  return 1;
}

int mtp_index (lua_State *L) {
  lua_rawgeti(L, LUA_REGISTRYINDEX, MTP_FNS); // tbl key fns
  lua_pushvalue(L, -2); // tbl key fns key
  if (lua_gettable(L, -2) != LUA_TNIL) // tbl key fns fn
    return 1;
  lua_pop(L, 2); // tbl key
  return mto_index(L);
}

int mtp_await (lua_State *L) {
  args_to_vals(L);
  val *v = peek_val(L, -2);
  val *f = peek_val(L, -1);
  EM_ASM(({
    var v = Emval.toValue($0);
    var f = Emval.toValue($1);
    v.then((...args) => {
      args.unshift(true);
      var r = f(...args);
      return r;
    });
    v.catch((...args) => {
      args.unshift(false);
      var r = f(...args);
      return r;
    });
  }), v->as_handle(), f->as_handle());
  return 0;
}

int mtf_index (lua_State *L) {
  lua_rawgeti(L, LUA_REGISTRYINDEX, MTF_FNS); // tbl key fns
  lua_pushvalue(L, -2); // tbl key fns key
  if (lua_gettable(L, -2) != LUA_TNIL) // tbl key fns fn
    return 1;
  lua_pop(L, 2); // tbl key
  return mto_index(L);
}

int mtf_call (lua_State *L) {
  mtv_call(L);
  val *v = peek_val(L, -1);
  push_val_lua(L, v, false);
  return 1;
}

int mtf_new (lua_State *L) {
  mtv_new(L);
  val *v = peek_val(L, -1);
  push_val_lua(L, v, false);
  return 1;
}

int mtv_val (lua_State *L) {
  int n = lua_gettop(L);
  if (n > 1) {
    val *v = peek_val(L, -n);
    bool recurse = lua_toboolean(L, -n + 1);
    if (unmap_js(L, v)) {
      lua_to_val(L, -1, recurse);
    } else {
      push_val(L, new val(*v));
    }
    return 1;
  } else {
    val *v = peek_val(L, -1);
    push_val(L, new val(*v));
    return 1;
  }
}

int mtv_lua (lua_State *L) {
  int n = lua_gettop(L);
  if (n > 1) {
    val *v = peek_val(L, -n);
    push_val_lua(L, v, lua_toboolean(L, -n + 1));
    return 1;
  } else {
    val *v = peek_val(L, -1);
    push_val_lua(L, v, false);
    return 1;
  }
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

int mtv_isval (lua_State *L) {
  lua_pushboolean(L, !get_islua(peek_val(L, -1)));
  return 1;
}

int mtv_islua (lua_State *L) {
  lua_pushboolean(L, get_islua(peek_val(L, -1)));
  return 1;
}

int mto_pairs_closure (lua_State *L) {
  val *ep = peek_val(L, lua_upvalueindex(1));
  int i = lua_tointeger(L, lua_upvalueindex(2));
  int m = lua_tointeger(L, lua_upvalueindex(3));
  if (i >= m) {
    lua_pushnil(L);
    lua_pushnil(L);
    return 2;
  } else {
    val kv = (*ep)[i];
    push_val_lua(L, new val(kv[0]), false);
    push_val_lua(L, new val(kv[1]), false);
    lua_pushinteger(L, i + 1);
    lua_replace(L, lua_upvalueindex(2));
    return 2;
  }
}

int mto_pairs (lua_State *L) {
  args_to_vals(L);
  val *v = peek_val(L, -1);
  val *ep = new val(val::take_ownership((EM_VAL)EM_ASM_PTR(({
    var v = Emval.toValue($0);
    var entries = Object.entries(v);
    return Emval.toHandle(entries);
  }), v->as_handle())));
  push_val(L, ep);
  lua_pushinteger(L, 0);
  lua_pushinteger(L, (*ep)["length"].as<int>());
  lua_pushcclosure(L, mto_pairs_closure, 3);
  lua_pushnil(L);
  lua_pushnil(L);
  return 3;
}

int mto_len (lua_State *L) {
  args_to_vals(L);
  val *v = peek_val(L, -1);
  lua_pushinteger(L, EM_ASM_INT(({
    var v = Emval.toValue($0);
    return v instanceof Array
      ? v.length
      : 0;
  }), v->as_handle()));
  return 1;
}

int mtv_typeof (lua_State *L) {
  args_to_vals(L);
  val *v = peek_val(L, -1);
  val *t = new val(v->typeof());
  push_val(L, t);
  return 1;
}

int mtv_instanceof (lua_State *L) {
  args_to_vals(L);
  val *v = peek_val(L, -2);
  val *c = peek_val(L, -1);
  lua_pushboolean(L, EM_ASM_INT(({
    var v = Emval.toValue($0);
    var c = Emval.toValue($1);
    return v instanceof c ? 1 : 0;
  }), v->as_handle(), c->as_handle()));
  lua_to_val(L, -1, false);
  return 1;
}

int mtv_call (lua_State *L) {
  args_to_vals(L);
  int n = lua_gettop(L);
  val *v = peek_val(L, -n);
  val *t = lua_type(L, -n + 1) == LUA_TNIL
    ? new val(val::undefined())
    : peek_val(L, -n + 1);
  val *r = new val(val::take_ownership((EM_VAL)EM_ASM_PTR(({
    try {
      var fn = Emval.toValue($1);
      var ths = Emval.toValue($2);
      if (ths != undefined)
        fn = fn.bind(ths);
      var args = Emval.toValue(Module.args($0, $3, $4));
      var args = [ ...args ];
      return Emval.toHandle(fn(...args));
    } catch (e) {
      Module.error($0, Emval.toHandle(e));
      return undefined;
    }
  }), L, v->as_handle(), t->as_handle(), -n + 2, n - 2)));
  push_val(L, r);
  return 1;
}

int mtv_new (lua_State *L) {
  args_to_vals(L);
  int n = lua_gettop(L);
  val *v = peek_val(L, -n);
  val *r = new val(val::take_ownership((EM_VAL)EM_ASM_PTR(({
    try {
      var obj = Emval.toValue($1);
      var args = Emval.toValue(Module.args($0, $2, $3));
      return Emval.toHandle(new obj(...args));
    } catch (e) {
      Module.error($0, Emval.toHandle(e));
      return undefined;
    }
  }), L, v->as_handle(), -n + 1, n - 1)));
  push_val(L, r);
  return 1;
}

luaL_Reg mtp_fns[] = {
  { "await", mtp_await },
  { NULL, NULL }
};

luaL_Reg mtf_fns[] = {
  { "new", mtf_new },
  { NULL, NULL }
};

luaL_Reg mto_fns[] = {
  { "typeof", mto_typeof },
  { "instanceof", mto_instanceof },
  { "val", mtv_val },
  { NULL, NULL }
};

luaL_Reg mtv_fns[] = {
  { "val", mtv_val },
  { "lua", mtv_lua },
  { "get", mtv_get },
  { "set", mtv_set },
  { "islua", mtv_islua },
  { "isval", mtv_isval },
  { "typeof", mtv_typeof },
  { "instanceof", mtv_instanceof },
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
  { NULL, NULL }
};

int luaopen_santoku_web_val (lua_State *L) {

  lua_newtable(L); // tbl

  lua_newtable(L); // tbl mt
  lua_pushcfunction(L, mt_call); // tbl mt ffn
  lua_setfield(L, -2, "__call"); // tbl mt
  lua_setmetatable(L, -2); // tbl

  luaL_setfuncs(L, mt_fns, 0); // tbl

  luaL_newmetatable(L, MTV); // .. mtv
  lua_newtable(L); // mtv idx
  luaL_setfuncs(L, mtv_fns, 0); // mtv idx
  lua_setfield(L, -2, "__index"); // mtv
  lua_pushcfunction(L, mto_newindex);
  lua_setfield(L, -2, "__newindex"); // mtv
  lua_pop(L, 1); // ..

  luaL_newmetatable(L, MTO); // .. mto
  lua_pushcfunction(L, mto_index); // mto ifn
  lua_setfield(L, -2, "__index"); // mto
  lua_pushcfunction(L, mto_newindex);
  lua_setfield(L, -2, "__newindex"); // mtv
  lua_pushcfunction(L, mto_len);
  lua_setfield(L, -2, "__len"); // mtv
  lua_pushcfunction(L, mto_pairs);
  lua_setfield(L, -2, "__pairs"); // mtv
  lua_pop(L, 1); // ..

  luaL_newmetatable(L, MTP); // .. mtp
  lua_pushcfunction(L, mtp_index); // mtp ifn
  lua_setfield(L, -2, "__index"); // mtp
  lua_pushcfunction(L, mto_newindex);
  lua_setfield(L, -2, "__newindex"); // mtv
  lua_pop(L, 1); // ..

  luaL_newmetatable(L, MTF); // .. mtf
  lua_pushcfunction(L, mtf_index); // mtp ifn
  lua_setfield(L, -2, "__index"); // mtp
  lua_pushcfunction(L, mto_newindex);
  lua_setfield(L, -2, "__newindex"); // mtv
  lua_pushcfunction(L, mtf_call); // mtp cfn
  lua_setfield(L, -2, "__call"); // mtp
  lua_pop(L, 1); // ..

  EM_ASM(({
    Module.IDX_VAL_REF = new WeakMap();
    Module.IDX_IS_LUA = new WeakSet();
  }));

  lua_newtable(L);
  lua_newtable(L);
  lua_pushstring(L, "k");
  lua_setfield(L, -2, "__mode");
  lua_setmetatable(L, -2);
  IDX_TBL_VAL = luaL_ref(L, LUA_REGISTRYINDEX);

  lua_newtable(L);
  luaL_setfuncs(L, mto_fns, 0);
  MTO_FNS = luaL_ref(L, LUA_REGISTRYINDEX);

  lua_newtable(L);
  luaL_setfuncs(L, mtp_fns, 0);
  MTP_FNS = luaL_ref(L, LUA_REGISTRYINDEX);

  lua_newtable(L);
  luaL_setfuncs(L, mtf_fns, 0);
  MTF_FNS = luaL_ref(L, LUA_REGISTRYINDEX);

  return 1;
}
