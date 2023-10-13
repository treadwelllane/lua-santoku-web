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
  int luaopen_santoku_web_val (lua_State *);
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

// Proxy to JS, with :val(), :typeof(), instanceof(), string()
#define MTA "santoku_web_object"

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
int MTA_FNS;
int MTF_FNS;

int lua_to_val (lua_State *, int, bool);
int mtv_typeof (lua_State *);
int mtv_instanceof (lua_State *);
int mtv_new (lua_State *);
int mtv_call (lua_State *);
int mtv_set (lua_State *);
bool unmap_lua (lua_State *, int);
bool unmap_js (lua_State *, val);
void map_js (lua_State *, val, int, int);

void args_to_vals (lua_State *L, int n) {
  int argc = n < 0 ? lua_gettop(L) : n;
  for (int i = -argc; i < 0; i ++) {
    lua_to_val(L, i, false);
    lua_replace(L, i - 1);
  }
}

val *peek_valp (lua_State *L, int i) {
  if (lua_getiuservalue(L, i, 1) == LUA_TNONE)
    return NULL;
  val *v = (val *)lua_touserdata(L, -1);
  lua_pop(L, 1);
  return v;
}

val peek_val (lua_State *L, int i) {
  bool pop = false;
  int i0;
  if (unmap_lua(L, i)) {
    i0 = -1;
    pop = true;
  } else {
    i0 = i;
    luaL_checktype(L, i, LUA_TUSERDATA);
  }
  void *vp = NULL;
  if (((vp = luaL_testudata(L, i0, MTO)) == NULL) &&
      ((vp = luaL_testudata(L, i0, MTP)) == NULL) &&
      ((vp = luaL_testudata(L, i0, MTF)) == NULL))
    vp = luaL_checkudata(L, i0, MTV);
  val *v = peek_valp(L, i0);
  if (v == NULL)
    luaL_typeerror(L, i, MTV);
  if (pop)
    lua_pop(L, 1);
  return *v;
}

int mtv_gc (lua_State *L) {
  val *v = peek_valp(L, -1);
  delete v;
  return 0;
}

int mtv_eq (lua_State *L) {
  val v0 = peek_val(L, -1);
  val v1 = peek_val(L, -2);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    var v1 = Emval.toValue($1);
    return v0 == v1;
  }, v0.as_handle(), v1.as_handle()));
  return 1;
}

int mtv_lt (lua_State *L) {
  val v0 = peek_val(L, -1);
  val v1 = peek_val(L, -2);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    var v1 = Emval.toValue($1);
    return v0 < v1;
  }, v0.as_handle(), v1.as_handle()));
  return 1;
}

int mtv_le (lua_State *L) {
  val v0 = peek_val(L, -1);
  val v1 = peek_val(L, -2);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    var v1 = Emval.toValue($1);
    return v0 <= v1;
  }, v0.as_handle(), v1.as_handle()));
  return 1;
}

int mtv_sub (lua_State *L) {
  val v0 = peek_val(L, -1);
  val v1 = peek_val(L, -2);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    var v1 = Emval.toValue($1);
    return v0 - v1;
  }, v0.as_handle(), v1.as_handle()));
  return 1;
}

int mtv_mul (lua_State *L) {
  val v0 = peek_val(L, -1);
  val v1 = peek_val(L, -2);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    var v1 = Emval.toValue($1);
    return v0 * v1;
  }, v0.as_handle(), v1.as_handle()));
  return 1;
}

int mtv_div (lua_State *L) {
  val v0 = peek_val(L, -1);
  val v1 = peek_val(L, -2);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    var v1 = Emval.toValue($1);
    return v0 / v1;
  }, v0.as_handle(), v1.as_handle()));
  return 1;
}

int mtv_mod (lua_State *L) {
  val v0 = peek_val(L, -1);
  val v1 = peek_val(L, -2);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    var v1 = Emval.toValue($1);
    return v0 % v1;
  }, v0.as_handle(), v1.as_handle()));
  return 1;
}

int mtv_pow (lua_State *L) {
  val v0 = peek_val(L, -1);
  val v1 = peek_val(L, -2);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    var v1 = Emval.toValue($1);
    return v0 ^ v1;
  }, v0.as_handle(), v1.as_handle()));
  return 1;
}

int mtv_band (lua_State *L) {
  val v0 = peek_val(L, -1);
  val v1 = peek_val(L, -2);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    var v1 = Emval.toValue($1);
    return v0 & v1;
  }, v0.as_handle(), v1.as_handle()));
  return 1;
}

int mtv_bor (lua_State *L) {
  val v0 = peek_val(L, -1);
  val v1 = peek_val(L, -2);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    var v1 = Emval.toValue($1);
    return v0 | v1;
  }, v0.as_handle(), v1.as_handle()));
  return 1;
}

int mtv_bxor (lua_State *L) {
  val v0 = peek_val(L, -1);
  val v1 = peek_val(L, -2);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    var v1 = Emval.toValue($1);
    return v0 ^ v1;
  }, v0.as_handle(), v1.as_handle()));
  return 1;
}

int mtv_unm (lua_State *L) {
  val v0 = peek_val(L, -1);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    return - v0;
  }, v0.as_handle()));
  return 1;
}

int mtv_bnot (lua_State *L) {
  val v0 = peek_val(L, -1);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    return ~ v0;
  }, v0.as_handle()));
  return 1;
}

int mtv_shl (lua_State *L) {
  val v0 = peek_val(L, -1);
  val v1 = peek_val(L, -2);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    var v1 = Emval.toValue($1);
    return v0 << v1;
  }, v0.as_handle(), v1.as_handle()));
  return 1;
}

int mtv_shr (lua_State *L) {
  val v0 = peek_val(L, -1);
  val v1 = peek_val(L, -2);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    var v1 = Emval.toValue($1);
    return v0 >> v1;
  }, v0.as_handle(), v1.as_handle()));
  return 1;
}

/* TODO: Is there a way to avoid heap allocation of */
/* the val? */
void push_val (lua_State *L, val v) {
  lua_newuserdatauv(L, 0, 1);
  lua_pushlightuserdata(L, new val(v));
  lua_setiuservalue(L, -2, 1);
  luaL_setmetatable(L, MTV);
}

bool unmap_lua (lua_State *L, int i) {
  lua_pushvalue(L, i);
  lua_rawgeti(L, LUA_REGISTRYINDEX, IDX_TBL_VAL);
  lua_insert(L, -2);
  int t = lua_gettable(L, -2);
  if (t == LUA_TNIL) {
    lua_pop(L, 2);
    return false;
  } else {
    lua_remove(L, -2);
    return true;
  }
}

bool unmap_js (lua_State *L, val key) {
  int ref = EM_ASM_INT(({
    var v = Emval.toValue($0);
    if (v == null || v == undefined)
      return -1;
    if (Module.IDX_VAL_REF.has(v)) {
      return Module.IDX_VAL_REF.get(v) || -1;
    } else {
      return -1;
    }
  }), key.as_handle());
  if (ref != -1) {
    lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
    return true;
  } else {
    return false;
  }
}

void map_js (lua_State *L, val v, int i, int ref) {
  lua_pushvalue(L, i);
  if (ref == LUA_NOREF)
    ref = luaL_ref(L, LUA_REGISTRYINDEX);
  else
    lua_pop(L, 1);
  lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
  int rc = EM_ASM_INT(({
    var v = Emval.toValue($0);
    if (v == null || v == undefined)
      return 1;
    Module.IDX_VAL_REF.set(v, $1);
    return 0;
  }), v.as_handle(), ref);
  if (rc == 1) {
    lua_pop(L, 1);
    return;
  }
  lua_rawgeti(L, LUA_REGISTRYINDEX, IDX_TBL_VAL);
  lua_insert(L, -2);
  push_val(L, v);
  lua_settable(L, -3);
  lua_pop(L, 1);
}

void push_new_uv (lua_State *L, int uv) {
  if (uv != INT_MIN) {
    lua_pushvalue(L, uv); // uv_old
    lua_newuserdatauv(L, 0, 1); // uv_old uv_new
    lua_insert(L, -2); // uv_new uv_old
    lua_setiuservalue(L, -2, 1); // uv_new
  } else {
    lua_newuserdatauv(L, 0, 0); // uv_new
  }
}

void push_val_lua_uv (lua_State *L, val v, bool recurse, int uv) {
  string type = v.typeof().as<string>();
  if (type == "string") {
    string x = v.as<string>();
    lua_pushstring(L, x.c_str());
  } else if (type == "number") {
    bool isInteger = EM_ASM_INT(({
      try {
        var v = Emval.toValue($0);
        return Number.isInteger(v);
      } catch (_) {
        return false;
      }
    }), v.as_handle());
    if (isInteger) {
      // TODO: Should be int64_t?
      long x = v.as<long>();
      lua_pushinteger(L, x);
    } else {
      double x = v.as<double>();
      lua_pushnumber(L, x);
    }
  } else if (type == "bigint") {
    // TODO: Needs to be thoroughly tested to
    // support 64 bit integers.
    int64_t n = EM_ASM_INT(({
      var bi = Emval.toValue($1);
      if (bi > Number.MAX_SAFE_INTEGER ||
          bi < Number.MIN_SAFE_INTEGER)
        Module.error($0, Emval.toHandle("Conversion from bigint to number failed: too large or too small"));
      return Number(bi);
    }), L, v.as_handle());
    lua_pushinteger(L, n);
  } else if (type == "boolean") {
    bool x = v.as<bool>();
    lua_pushboolean(L, x);
  } else if (type == "object") {
    if (!unmap_js(L, v)) {
      bool isNull = EM_ASM_INT(({
        return Emval.toValue($0) == null
          ? 1 : 0;
      }), v.as_handle());
      if (isNull) {
        lua_pushnil(L);
      } else {
        bool isUInt8Array = EM_ASM_INT(({
          return Emval.toValue($0) instanceof Uint8Array
            ? 1 : 0;
        }), v.as_handle());
        if (isUInt8Array) {
          push_new_uv(L, uv);
          luaL_setmetatable(L, MTA);
          map_js(L, v, -1, LUA_NOREF);
        } else {
          bool isPromise = EM_ASM_INT(({
            return Emval.toValue($0) instanceof Promise
              ? 1 : 0;
          }), v.as_handle());
          push_new_uv(L, uv);
          luaL_setmetatable(L, isPromise ? MTP : MTO);
          map_js(L, v, -1, LUA_NOREF);
        }
      }
    }
  } else if (type == "function") {
    if (!unmap_js(L, v)) {
      push_new_uv(L, uv);
      luaL_setmetatable(L, MTF);
      map_js(L, v, -1, LUA_NOREF);
    }
  } else if (type == "undefined") {
    lua_pushnil(L);
  } else {
    printf("Unhandled JS type, pushing nil: %s\n", type.c_str());
    lua_pushnil(L);
  }
}

void push_val_lua (lua_State *L, val v, bool recurse) {
  push_val_lua_uv(L, v, recurse, INT_MIN);
}

int lua_to_val (lua_State *L, int i, bool recurse) {
  if (unmap_lua(L, i))
    return 1;
  int type = lua_type(L, i);
  if (type == LUA_TSTRING) {
    push_val(L, val(lua_tostring(L, i)));
  } else if (type == LUA_TNUMBER) {
    push_val(L, val(lua_tonumber(L, i)));
  } else if (type == LUA_TBOOLEAN) {
    push_val(L, val(lua_toboolean(L, i) ? true : false));
  } else if (type == LUA_TTABLE) {
    lua_pushvalue(L, i);
    lua_pushvalue(L, -1);
    lua_getglobal(L, "require");
    lua_pushstring(L, "santoku.compat");
    lua_call(L, 1, 1);
    lua_pushstring(L, "isarray");
    lua_gettable(L, -2);
    lua_insert(L, -3);
    lua_pop(L, 1);
    lua_call(L, 1, 1);
    bool isarray = lua_toboolean(L, -1);
    lua_pop(L, 1);
    if (!recurse) {
      int tblref = luaL_ref(L, LUA_REGISTRYINDEX);
      push_val(L, val::take_ownership((EM_VAL) EM_ASM_PTR(({
        var obj = $2 ? [] : {};
        return Emval.toHandle(new Proxy(obj, {
          get(o, k) {
            var isnumber;
            try { isnumber = !isNaN(+k); }
            catch (_) { isnumber = false; }
            if (o instanceof Array && k == "length")
              return Module.len($0, $1);
            if (o instanceof Array && isnumber)
              return Emval.toValue(Module.get($0, $1, Emval.toHandle(+k + 1), 0));
            if (typeof k == "string")
              return Emval.toValue(Module.get($0, $1, stringToNewUTF8(k), 1));
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
            var keys = [];
            Module.ownKeys($0, $1, Emval.toHandle(keys));
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
      }), L, tblref, isarray)));
      val v = peek_val(L, -1);
      lua_rawgeti(L, LUA_REGISTRYINDEX, tblref);
      map_js(L, v, -1, tblref);
      lua_pop(L, 1);
    } else if (isarray) {
      lua_pushvalue(L, -1);
      lua_getglobal(L, "require");
      lua_pushstring(L, "santoku.table");
      lua_call(L, 1, 1);
      lua_pushstring(L, "len");
      lua_gettable(L, -2);
      lua_insert(L, -3);
      lua_pop(L, 1);
      lua_call(L, 1, 1);
      int len = lua_tointeger(L, -1);
      lua_pop(L, 1);
      val arr = val::array();
      for (int j = 1; j <= len; j ++) {
        lua_pushinteger(L, j);
        lua_gettable(L, -2);
        lua_to_val(L, -1, true);
        val el = peek_val(L, -1);
        arr.set(j - 1, el);
        lua_pop(L, 2);
      }
      lua_pop(L, 1);
      push_val(L, arr);
    } else {
      val obj = val::object();
      lua_pushnil(L);
      while (lua_next(L, -2) != 0) {
        lua_to_val(L, -2, true);
        lua_to_val(L, -2, true);
        val kk = peek_val(L, -2);
        val vv = peek_val(L, -1);
        obj.set(kk, vv);
        lua_pop(L, 3);
      }
      lua_pop(L, 1);
      push_val(L, obj);
    }
  } else if (type == LUA_TFUNCTION) {
    lua_pushvalue(L, i);
    int fnref = luaL_ref(L, LUA_REGISTRYINDEX);
    push_val(L, val::take_ownership((EM_VAL) EM_ASM_PTR(({
      return Emval.toHandle(new Proxy(function () {}, {
        apply(_, this_, args) {
          args.unshift(this_);
          return Emval.toValue(Module.call($0, $1, Emval.toHandle(args)));
        }
      }))
    }), L, fnref)));
    val v = peek_val(L, -1);
    lua_rawgeti(L, LUA_REGISTRYINDEX, fnref);
    map_js(L, v, -1, fnref);
    lua_pop(L, 1);
  } else if (type == LUA_TUSERDATA) {
    // TODO: Should this really just be passed
    // through?
    lua_pushvalue(L, i);
  } else if (type == LUA_TNIL) {
    push_val(L, val::undefined());
  } else {
    /* LUA_TLIGHTUSERDATA: */
    /* LUA_TTHREAD: */
    printf("Unhandled Lua type, pushing undefined: %d\n", type);
    push_val(L, val::undefined());
  }
  return 1;
}

int j_arg (int Lp, int i) {
  lua_State *L = (lua_State *)Lp;
  lua_to_val(L, i, false);
  EM_VAL v = peek_val(L, -1).as_handle();
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

int j_ownKeys (int Lp, int tblref, int keysp) {
  lua_State *L = (lua_State *)Lp;
  val keys = val::take_ownership((EM_VAL)keysp);
  lua_rawgeti(L, LUA_REGISTRYINDEX, tblref);
  lua_pushnil(L);
  while (lua_next(L, -2) != 0) {
    lua_to_val(L, -2, false);
    val v = peek_val(L, -1);
    EM_ASM(({
      var ks = Emval.toValue($0);
      var v = Emval.toValue($1);
      if (ks instanceof Array && typeof v == "number") {
        ks.push(String(v - 1));
      } else {
        ks.push(String(v));
      }
    }), keys.as_handle(), v.as_handle());
    lua_pop(L, 2);
  }
  return (int) keys.as_handle();
}

int j_get (int Lp, int tblref, int k, int is_str) {
  lua_State *L = (lua_State *)Lp;
  lua_rawgeti(L, LUA_REGISTRYINDEX, tblref);
  if (is_str) {
    char *kk = (char*)k;
    lua_pushstring(L, kk);
    free(kk);
  } else {
    val kk = val::take_ownership((EM_VAL)k);
    push_val_lua(L, kk, false);
  }
  lua_gettable(L, -2);
  lua_to_val(L, -1, false);
  val vv = peek_val(L, -1);
  return (int) vv.as_handle();
}

void j_set (int Lp, int tblref, int k, int v) {
  lua_State *L = (lua_State *)Lp;
  val kk = val::take_ownership((EM_VAL)k);
  val vv = val::take_ownership((EM_VAL)v);
  lua_rawgeti(L, LUA_REGISTRYINDEX, tblref);
  push_val_lua(L, vv, false);
  push_val_lua(L, kk, false);
  lua_settable(L, -3);
}

int j_call (int Lp, int fnp, int argsp) {
  lua_State *L = (lua_State *)Lp;
  lua_rawgeti(L, LUA_REGISTRYINDEX, fnp);
  val args = val::take_ownership((EM_VAL)argsp);
  int argc = args["length"].as<int>();
  for (int i = 0; i < argc; i ++)
    push_val_lua(L, args[val(i)], false);
  int t = lua_gettop(L) - argc - 1;
  int rc = lua_pcall(L, argc, LUA_MULTRET, 0);
  if (rc != LUA_OK) {
    lua_to_val(L, -1, false);
    val v = peek_val(L, -1);
    EM_ASM_PTR(({
      var v = Emval.toValue($0);
      throw v;
    }), v.as_handle());
    return 0;
  } else if (lua_gettop(L) > t) {
    args_to_vals(L, lua_gettop(L) - t);
    val v = peek_val(L, -1);
    return (int) v.as_handle();
  } else {
    return (int) val::undefined().as_handle();
  }
}

void j_error (int Lp, int ep) {
  lua_State *L = (lua_State *)Lp;
  val e = val::take_ownership((EM_VAL)ep);
  push_val_lua(L, e, false);
  lua_error(L);
}

int j_len (int Lp, int tblref) {
  lua_State *L = (lua_State *)Lp;
  lua_getglobal(L, "require");
  lua_pushstring(L, "santoku.table");
  lua_call(L, 1, 1);
  lua_pushstring(L, "len");
  lua_gettable(L, -2);
  lua_rawgeti(L, LUA_REGISTRYINDEX, tblref);
  lua_call(L, 1, 1);
  int len = lua_tointeger(L, -1);
  lua_pop(L, 2);
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
  push_val(L, val::global(str));
  return 1;
}

int mt_bytes (lua_State *L) {
  size_t size;
  const char *str = luaL_checklstring(L, -1, &size);
  push_val_lua_uv(L, val(typed_memory_view(size, (uint8_t *) str)), false, -1);
  return 1;
}

int mto_index (lua_State *L) {
  lua_rawgeti(L, LUA_REGISTRYINDEX, MTO_FNS);
  lua_pushvalue(L, -2);
  if (lua_gettable(L, -2) != LUA_TNIL)
    return 1;
  lua_pop(L, 2);
  lua_rawgeti(L, LUA_REGISTRYINDEX, IDX_TBL_VAL);
  lua_pushvalue(L, -3);
  lua_gettable(L, -2);
  val v = peek_val(L, -1);
  lua_to_val(L, -3, false);
  val k = peek_val(L, -1);
  val n = val::take_ownership((EM_VAL)EM_ASM_PTR(({
    var v = Emval.toValue($0);
    var k = Emval.toValue($1);
    if (v instanceof Array && typeof k == "number")
      k = k - 1;
    return Emval.toHandle(v[k]);
  }), v.as_handle(), k.as_handle()));
  push_val_lua(L, n, false);
  return 1;
}

int mto_newindex (lua_State *L) {
  return mtv_set(L);
}

int mto_instanceof (lua_State *L) {
  mtv_instanceof(L);
  val v = peek_val(L, -1);
  push_val_lua(L, v, false);
  return 1;
}

int mto_typeof (lua_State *L) {
  mtv_typeof(L);
  val v = peek_val(L, -1);
  push_val_lua(L, v, false);
  return 1;
}

int mtp_index (lua_State *L) {
  lua_rawgeti(L, LUA_REGISTRYINDEX, MTP_FNS);
  lua_pushvalue(L, -2);
  if (lua_gettable(L, -2) != LUA_TNIL)
    return 1;
  lua_pop(L, 2);
  return mto_index(L);
}

int mtp_await (lua_State *L) {
  args_to_vals(L, -1);
  val v = peek_val(L, -2);
  val f = peek_val(L, -1);
  EM_ASM(({
    var v = Emval.toValue($1);
    var f = Emval.toValue($2);
    v.then((...args) => {
      args.unshift(true);
      var r = f(...args);
      return r;
    }).catch((...args) => {
      try {
        args.unshift(false);
        var r = f(...args);
        return r;
      } catch (e) {
        return setTimeout(() => {
          throw e;
        });
      }
    });
  }), L, v.as_handle(), f.as_handle());
  return 0;
}

int mta_index (lua_State *L) {
  lua_rawgeti(L, LUA_REGISTRYINDEX, MTA_FNS);
  lua_pushvalue(L, -2);
  if (lua_gettable(L, -2) != LUA_TNIL)
    return 1;
  lua_pop(L, 2);
  return mto_index(L);
}

int mta_str (lua_State *L) {
  args_to_vals(L, -1);
  val v = peek_val(L, -1);
  vector<uint8_t> vec = convertJSArrayToNumberVector<uint8_t>(v);
  lua_pushlstring(L, (char *) vec.data(), vec.size());
  return 1;
}

int mtf_index (lua_State *L) {
  lua_rawgeti(L, LUA_REGISTRYINDEX, MTF_FNS);
  lua_pushvalue(L, -2);
  if (lua_gettable(L, -2) != LUA_TNIL)
    return 1;
  lua_pop(L, 2);
  return mto_index(L);
}

int mtf_call (lua_State *L) {
  mtv_call(L);
  val v = peek_val(L, -1);
  push_val_lua(L, v, false);
  return 1;
}

int mtf_new (lua_State *L) {
  mtv_new(L);
  val v = peek_val(L, -1);
  push_val_lua(L, v, false);
  return 1;
}

int mtv_val (lua_State *L) {
  int n = lua_gettop(L);
  if (n > 1) {
    val v = peek_val(L, -n);
    bool recurse = lua_toboolean(L, -n + 1);
    if (unmap_js(L, v)) {
      lua_to_val(L, -1, recurse);
    } else {
      push_val(L, v);
    }
    return 1;
  } else {
    val v = peek_val(L, -1);
    push_val(L, v);
    return 1;
  }
}

int mtv_lua (lua_State *L) {
  int n = lua_gettop(L);
  if (n > 1) {
    val v = peek_val(L, -n);
    push_val_lua(L, v, lua_toboolean(L, -n + 1));
    lua_remove(L, -2);
    return 1;
  } else {
    val v = peek_val(L, -1);
    push_val_lua(L, v, false);
    lua_remove(L, -2);
    return 1;
  }
}

int mtv_get (lua_State *L) {
  args_to_vals(L, -1);
  val k = peek_val(L, -1);
  val o = peek_val(L, -2);
  push_val(L, o[k]);
  return 1;
}

int mtv_set (lua_State *L) {
  args_to_vals(L, -1);
  val v = peek_val(L, -1);
  val k = peek_val(L, -2);
  val o = peek_val(L, -3);
  o.set(k, v);
  return 0;
}

int mto_pairs_closure (lua_State *L) {
  val ep = peek_val(L, lua_upvalueindex(1));
  int i = lua_tointeger(L, lua_upvalueindex(2));
  int m = lua_tointeger(L, lua_upvalueindex(3));
  if (i >= m) {
    lua_pushnil(L);
    lua_pushnil(L);
    return 2;
  } else {
    val kv = ep[i];
    push_val_lua(L, kv[0], false);
    push_val_lua(L, kv[1], false);
    lua_pushinteger(L, i + 1);
    lua_replace(L, lua_upvalueindex(2));
    return 2;
  }
}

int mto_pairs (lua_State *L) {
  args_to_vals(L, -1);
  val v = peek_val(L, -1);
  val ep = val::take_ownership((EM_VAL)EM_ASM_PTR(({
    var v = Emval.toValue($0);
    var entries = Object.entries(v);
    return Emval.toHandle(entries);
  }), v.as_handle()));
  push_val(L, ep);
  lua_pushinteger(L, 0);
  lua_pushinteger(L, ep["length"].as<int>());
  lua_pushcclosure(L, mto_pairs_closure, 3);
  lua_pushnil(L);
  lua_pushnil(L);
  return 3;
}

int mto_len (lua_State *L) {
  args_to_vals(L, -1);
  val v = peek_val(L, -1);
  lua_pushinteger(L, EM_ASM_INT(({
    var v = Emval.toValue($0);
    return v instanceof Array
      ? v.length
      : 0;
  }), v.as_handle()));
  return 1;
}

int mtv_typeof (lua_State *L) {
  args_to_vals(L, -1);
  val v = peek_val(L, -1);
  val t = v.typeof();
  push_val(L, t);
  return 1;
}

int mtv_instanceof (lua_State *L) {
  args_to_vals(L, -1);
  val v = peek_val(L, -2);
  val c = peek_val(L, -1);
  lua_pushboolean(L, EM_ASM_INT(({
    var v = Emval.toValue($0);
    var c = Emval.toValue($1);
    return v instanceof c ? 1 : 0;
  }), v.as_handle(), c.as_handle()));
  lua_to_val(L, -1, false);
  return 1;
}

int mtv_call (lua_State *L) {
  args_to_vals(L, -1);
  int n = lua_gettop(L);
  val v = peek_val(L, -n);
  val t = lua_type(L, -n + 1) == LUA_TNIL
    ? val::undefined()
    : peek_val(L, -n + 1);
  val r = val::take_ownership((EM_VAL)EM_ASM_PTR(({
    try {
      var fn = Emval.toValue($1);
      var ths = Emval.toValue($2);
      if (ths != undefined)
        fn = fn.bind(ths);
      var args = Emval.toValue(Module.args($0, $3, $4));
      var args = [ ...args ];
      return Emval.toHandle(fn(...args));
    } catch (e) {
      return Module.error($0, Emval.toHandle(e));
    }
  }), L, v.as_handle(), t.as_handle(), -n + 2, n - 2));
  push_val(L, r);
  return 1;
}

int mtv_new (lua_State *L) {
  args_to_vals(L, -1);
  int n = lua_gettop(L);
  val v = peek_val(L, -n);
  val r = val::take_ownership((EM_VAL)EM_ASM_PTR(({
    var obj = Emval.toValue($1);
    var args = Emval.toValue(Module.args($0, $2, $3));
    return Emval.toHandle(new obj(...args));
  }), L, v.as_handle(), -n + 1, n - 1));
  push_val(L, r);
  return 1;
}

luaL_Reg mtp_fns[] = {
  { "await", mtp_await },
  { NULL, NULL }
};

luaL_Reg mta_fns[] = {
  { "str", mta_str },
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
  { "lua", mtv_lua },
  { NULL, NULL }
};

luaL_Reg mtv_fns[] = {
  { "val", mtv_val },
  { "lua", mtv_lua },
  { "get", mtv_get },
  { "set", mtv_set },
  { "typeof", mtv_typeof },
  { "instanceof", mtv_instanceof },
  { "call", mtv_call },
  { "new", mtv_new },
  { NULL, NULL }
};

luaL_Reg mt_fns[] = {
  { "global", mt_global },
  { "bytes", mt_bytes },
  { NULL, NULL }
};

void set_common_obj_mtfns (lua_State *L) {
  lua_pushcfunction(L, mtv_gc);
  lua_setfield(L, -2, "__gc");
  lua_pushcfunction(L, mto_newindex);
  lua_setfield(L, -2, "__newindex");
  lua_pushcfunction(L, mto_len);
  lua_setfield(L, -2, "__len");
  lua_pushcfunction(L, mto_pairs);
  lua_setfield(L, -2, "__pairs");
  lua_pushcfunction(L, mtv_eq);
  lua_setfield(L, -2, "__eq");
  lua_pushcfunction(L, mtv_lt);
  lua_setfield(L, -2, "__lt");
  lua_pushcfunction(L, mtv_le);
  lua_setfield(L, -2, "__le");
  lua_pushcfunction(L, mtv_sub);
  lua_setfield(L, -2, "__sub");
  lua_pushcfunction(L, mtv_mul);
  lua_setfield(L, -2, "__mul");
  lua_pushcfunction(L, mtv_div);
  lua_setfield(L, -2, "__div");
  lua_pushcfunction(L, mtv_mod);
  lua_setfield(L, -2, "__mod");
  lua_pushcfunction(L, mtv_pow);
  lua_setfield(L, -2, "__pow");
  lua_pushcfunction(L, mtv_unm);
  lua_setfield(L, -2, "__unm");
  lua_pushcfunction(L, mtv_band);
  lua_setfield(L, -2, "__band");
  lua_pushcfunction(L, mtv_bor);
  lua_setfield(L, -2, "__bor");
  lua_pushcfunction(L, mtv_bxor);
  lua_setfield(L, -2, "__bxor");
  lua_pushcfunction(L, mtv_bnot);
  lua_setfield(L, -2, "__bnot");
  lua_pushcfunction(L, mtv_shl);
  lua_setfield(L, -2, "__shl");
  lua_pushcfunction(L, mtv_shr);
  lua_setfield(L, -2, "__shr");
  lua_pop(L, 1);
}

int luaopen_santoku_web_val (lua_State *L) {

  lua_newtable(L);

  lua_newtable(L);
  lua_pushcfunction(L, mt_call);
  lua_setfield(L, -2, "__call");
  lua_setmetatable(L, -2);

  luaL_setfuncs(L, mt_fns, 0);

  luaL_newmetatable(L, MTV);
  lua_newtable(L);
  luaL_setfuncs(L, mtv_fns, 0);
  lua_setfield(L, -2, "__index");
  set_common_obj_mtfns(L);

  luaL_newmetatable(L, MTO);
  lua_pushcfunction(L, mto_index);
  lua_setfield(L, -2, "__index");
  set_common_obj_mtfns(L);

  luaL_newmetatable(L, MTA);
  lua_pushcfunction(L, mta_index);
  lua_setfield(L, -2, "__index");
  set_common_obj_mtfns(L);

  luaL_newmetatable(L, MTP);
  lua_pushcfunction(L, mtp_index);
  lua_setfield(L, -2, "__index");
  set_common_obj_mtfns(L);

  luaL_newmetatable(L, MTF);
  lua_pushcfunction(L, mtf_index);
  lua_setfield(L, -2, "__index");
  lua_pushcfunction(L, mtf_call);
  lua_setfield(L, -2, "__call");
  set_common_obj_mtfns(L);

  EM_ASM(({
    Module.IDX_VAL_REF = new WeakMap();
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
  luaL_setfuncs(L, mta_fns, 0);
  MTA_FNS = luaL_ref(L, LUA_REGISTRYINDEX);

  lua_newtable(L);
  luaL_setfuncs(L, mtf_fns, 0);
  MTF_FNS = luaL_ref(L, LUA_REGISTRYINDEX);

  return 1;
}
