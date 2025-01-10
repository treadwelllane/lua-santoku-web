// TODO: val(<table>) should allow second "val"
// argument which becomes the proxy target

// TODO: abstract some of the common patterns
// here into a library. Like requiring a santoku
// library and calling a function defined in lua
// from c. Perhaps using macros like L(require,
// "santoku.compat") or similar.

// TODO: Refactor mapping
//
// - MTVs are userdatas with user value #1 set
//   to a "new val(...)" and user value #2
//   potentially set to a lua value
//
// - MTOs (etc) are userdatas with uservalue #1
//   set to an MTV
//
// - When an MTV is created with a lua value set
//   as user value #2, the lua user value us
//   strongly ref'd and the MTV is registered for
//   finalization with the ref as the held
//   value
//
// - When an MTV is garbage collected, the
//   associated val is deleted.
//
// - When an MTV is finalized, the strong ref is
//   deleted.

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
#define MTA "santoku_web_array"

// Same as MTO, with __call and :new(...)
#define MTF "santoku_web_function"

// Same as MTO, with :await(<fn>)
#define MTP "santoku_web_promise"

static int IDX_REF_TBL;

static int MTO_FNS;
static int MTP_FNS;
static int MTA_FNS;
static int MTF_FNS;

static int TK_WEB_EPHEMERON_IDX;
static inline void tk_web_set_ephemeron (lua_State *, int, int);
static inline int tk_web_get_ephemeron (lua_State *, int, int);

static inline bool mtx_to_mtv (lua_State *, int);
static inline int lua_to_val (lua_State *, int, bool);
static inline void val_to_lua (lua_State *, int, bool, bool);
static inline int val_ref (lua_State *, int);
static inline bool val_unref (lua_State *, int);

static inline int mtv_call (lua_State *);
static inline int mtv_instanceof (lua_State *);
static inline int mtv_lua (lua_State *);
static inline int mtv_new (lua_State *);
static inline int mtv_set (lua_State *);
static inline int mtv_typeof (lua_State *);

static inline void tk_web_set_ephemeron (lua_State *L, int iu, int ie)
{
  // eph
  luaL_checktype(L, iu, LUA_TUSERDATA);
  lua_pushvalue(L, iu); // eph val
  lua_insert(L, -2); // val eph
  lua_rawgeti(L, LUA_REGISTRYINDEX, TK_WEB_EPHEMERON_IDX); // val eph idx
  lua_pushvalue(L, -3); // val eph idx val
  lua_gettable(L, -2); // val eph idx epht
  if (lua_type(L, -1) == LUA_TNIL) {
    lua_pop(L, 1); // val eph idx
    lua_pushvalue(L, -3); // val eph idx val
    lua_newtable(L); // val eph idx val epht
    lua_settable(L, -3); // val eph idx
    lua_pushvalue(L, -3); // val eph idx val
    lua_gettable(L, -2); // val eph idx epht
  }
  lua_pushinteger(L, ie); // val eph idx epht ie
  lua_pushvalue(L, -4); // val eph idx epht ie eph
  lua_settable(L, -3); // val eph idx epht
  lua_pop(L, 4); //
}

static inline int tk_web_get_ephemeron (lua_State *L, int iu, int ie)
{
  lua_pushvalue(L, iu); // val
  lua_rawgeti(L, LUA_REGISTRYINDEX, TK_WEB_EPHEMERON_IDX); // val idx
  lua_insert(L, -2); // idx val
  lua_gettable(L, -2); // idx epht
  if (lua_type(L, -1) == LUA_TNIL) {
    lua_remove(L, -2); // eph
    return LUA_TNIL;
  } else {
    lua_pushinteger(L, ie); // idx epht ie
    lua_gettable(L, -2); // idx epht eph
    lua_remove(L, -2); // idx eph
    lua_remove(L, -2); // eph
    return lua_type(L, -1);
  }
}

// Source: https://github.com/lunarmodules/lua-compat-5.3
static inline void *tk_web_testudata (lua_State *L, int i, const char *tname) {
  void *p = lua_touserdata(L, i);
  luaL_checkstack(L, 2, "not enough stack slots");
  if (p == NULL || !lua_getmetatable(L, i))
    return NULL;
  else {
    int res = 0;
    luaL_getmetatable(L, tname);
    res = lua_rawequal(L, -1, -2);
    lua_pop(L, 2);
    if (!res)
      p = NULL;
  }
  return p;
}

static inline int tk_lua_absindex (lua_State *L, int i) {
  if (i < 0 && i > LUA_REGISTRYINDEX)
    i += lua_gettop(L) + 1;
  return i;
}

static inline void args_to_vals (lua_State *L, int n) {
  int argc = n < 0 ? lua_gettop(L) : n;
  for (int i = -argc; i < 0; i ++) {
    lua_to_val(L, i, false);
    lua_replace(L, i - 1);
  }
}

static inline val *peek_valp (lua_State *L, int i) {
  if (!mtx_to_mtv(L, i))
    return NULL;
  assert(tk_web_get_ephemeron(L, -1, 1) == LUA_TLIGHTUSERDATA);
  val *vp = (val *) lua_touserdata(L, -1);
  lua_pop(L, 2);
  return vp;
}

static inline val peek_val (lua_State *L, int i) {
  val *vp = peek_valp(L, i);
  if (vp == NULL)
    return val::undefined();
  else
    return *vp;
}

static inline int mtv_gc (lua_State *L) {
  val *v = peek_valp(L, -1);
  delete v;
  return 0;
}

static inline int mtv_eq (lua_State *L) {
  val v0 = peek_val(L, -1);
  val v1 = peek_val(L, -2);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    var v1 = Emval.toValue($1);
    return v0 == v1;
  }, v0.as_handle(), v1.as_handle()));
  return 1;
}

static inline int mtv_lt (lua_State *L) {
  val v0 = peek_val(L, -1);
  val v1 = peek_val(L, -2);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    var v1 = Emval.toValue($1);
    return v0 < v1;
  }, v0.as_handle(), v1.as_handle()));
  return 1;
}

static inline int mtv_le (lua_State *L) {
  val v0 = peek_val(L, -1);
  val v1 = peek_val(L, -2);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    var v1 = Emval.toValue($1);
    return v0 <= v1;
  }, v0.as_handle(), v1.as_handle()));
  return 1;
}

static inline int mtv_add (lua_State *L) {
  val v0 = peek_val(L, -1);
  val v1 = peek_val(L, -2);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    var v1 = Emval.toValue($1);
    return v0 + v1;
  }, v0.as_handle(), v1.as_handle()));
  return 1;
}

static inline int mtv_sub (lua_State *L) {
  val v0 = peek_val(L, -1);
  val v1 = peek_val(L, -2);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    var v1 = Emval.toValue($1);
    return v0 - v1;
  }, v0.as_handle(), v1.as_handle()));
  return 1;
}

static inline int mtv_mul (lua_State *L) {
  val v0 = peek_val(L, -1);
  val v1 = peek_val(L, -2);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    var v1 = Emval.toValue($1);
    return v0 * v1;
  }, v0.as_handle(), v1.as_handle()));
  return 1;
}

static inline int mtv_div (lua_State *L) {
  val v0 = peek_val(L, -1);
  val v1 = peek_val(L, -2);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    var v1 = Emval.toValue($1);
    return v0 / v1;
  }, v0.as_handle(), v1.as_handle()));
  return 1;
}

static inline int mtv_mod (lua_State *L) {
  val v0 = peek_val(L, -1);
  val v1 = peek_val(L, -2);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    var v1 = Emval.toValue($1);
    return v0 % v1;
  }, v0.as_handle(), v1.as_handle()));
  return 1;
}

static inline int mtv_pow (lua_State *L) {
  val v0 = peek_val(L, -1);
  val v1 = peek_val(L, -2);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    var v1 = Emval.toValue($1);
    return v0 ^ v1;
  }, v0.as_handle(), v1.as_handle()));
  return 1;
}

static inline int mtv_unm (lua_State *L) {
  val v0 = peek_val(L, -1);
  lua_pushboolean(L, EM_ASM_INT({
    var v0 = Emval.toValue($0);
    return - v0;
  }, v0.as_handle()));
  return 1;
}

static inline int mtv_tostring (lua_State *L) {
  val v0 = peek_val(L, -1);
  val v1 = val::take_ownership((EM_VAL) EM_ASM_PTR(({
    var v0 = Emval.toValue($0);
    v0 = v0 instanceof Error ? v0.stack : v0.toString();
    return Emval.toHandle(v0);
  }), v0.as_handle()));
  lua_pushstring(L, v1.as<string>().c_str());
  return 1;
}

static inline void push_val (lua_State *L, val v, int uv) {

  int n = lua_gettop(L);

  if (uv == INT_MIN)
    lua_pushnil(L); // nil
  else
    lua_pushvalue(L, uv); // uv

  lua_newuserdata(L, 0); // uv udv
  lua_insert(L, -2); // udv uv
  tk_web_set_ephemeron(L, -2, 2); // udv

  lua_pushlightuserdata(L, new val(v)); // udv v
  tk_web_set_ephemeron(L, -2, 1); // udv

  luaL_getmetatable(L, MTV); // udv mt
  lua_setmetatable(L, -2); // udv

  assert(lua_gettop(L) == n + 1);

}

static inline bool mtx_to_mtv (lua_State *L, int iv) {

  int n = lua_gettop(L);
  int i_val = tk_lua_absindex(L, iv);

  if (tk_web_testudata(L, i_val, MTV) != NULL) {
    lua_pushvalue(L, i_val);
    return true;
  }

  if ((tk_web_testudata(L, i_val, MTO) != NULL) ||
      (tk_web_testudata(L, i_val, MTF) != NULL) ||
      (tk_web_testudata(L, i_val, MTP) != NULL) ||
      (tk_web_testudata(L, i_val, MTA) != NULL)) {
    assert(tk_web_get_ephemeron(L, i_val, 1) == LUA_TUSERDATA);
    assert(mtx_to_mtv(L, -1));
    lua_remove(L, -2);
    assert(lua_gettop(L) == n + 1);
    return true;
  } else {
    assert(lua_gettop(L) == n);
    return false;
  }
}

static inline bool mtx_to_lua (lua_State *L, int iv) {

  int t = lua_type(L, iv);
  if (t != LUA_TLIGHTUSERDATA && t != LUA_TUSERDATA) {
    lua_pushvalue(L, iv);
    return true;
  }

  if (!mtx_to_mtv(L, iv)) {
    return false;
  }

  if (tk_web_get_ephemeron(L, -1, 2) <= LUA_TNIL) {
    lua_pop(L, 2);
    return false;
  } else {
    lua_remove(L, -2);
    return true;
  }

}

static inline void tk_web_increment_refn (lua_State *L) {
  lua_rawgeti(L, LUA_REGISTRYINDEX, IDX_REF_TBL); // idx
  lua_getfield(L, -1, "n"); // idx n
  int n = lua_type(L, -1) == LUA_TNIL ? 1 : lua_tointeger(L, -1) + 1;
  lua_pop(L, 1); // idx
  lua_pushinteger(L, n); // idx n
  lua_setfield(L, -2, "n"); // idx
  lua_pop(L, 1); //
}

static inline void tk_web_decrement_refn (lua_State *L) {
  lua_rawgeti(L, LUA_REGISTRYINDEX, IDX_REF_TBL); // idx
  lua_getfield(L, -1, "n"); // idx n
  int n = lua_type(L, -1) == LUA_TNIL ? 1 : lua_tointeger(L, -1) - 1;
  lua_pop(L, 1); // idx
  lua_pushinteger(L, n); // idx n
  lua_setfield(L, -2, "n"); // idx
  lua_pop(L, 1); //
}

static inline int val_ref (lua_State *L, int it) {
  it = tk_lua_absindex(L, it);
  lua_rawgeti(L, LUA_REGISTRYINDEX, IDX_REF_TBL);
  lua_pushvalue(L, it);
  int ref = luaL_ref(L, -2);
  lua_pop(L, 1);
  tk_web_increment_refn(L);
  return ref;
}

static inline bool val_unref (lua_State *L, int ref) {
  lua_rawgeti(L, LUA_REGISTRYINDEX, IDX_REF_TBL); // idx
  lua_pushinteger(L, ref); // idx ref
  lua_gettable(L, -2); // idx val
  int t = lua_type(L, -1);
  lua_remove(L, -2); // val
  return t != LUA_TNIL;
}

static inline void push_mtx (lua_State *L, int iv, const char *mtx) {
  lua_pushvalue(L, iv); // mtv
  lua_newuserdata(L, 0); // mtv mtx
  lua_insert(L, -2); // mtx mtv
  tk_web_set_ephemeron(L, -2, 1); // mtx
  luaL_getmetatable(L, mtx); // mtx mt
  lua_setmetatable(L, -2); // mtx
}

static inline void object_to_lua (lua_State *L, val v, int iv, bool recurse) {

  iv = tk_lua_absindex(L, iv);

  bool isNull = EM_ASM_INT(({
    return Emval.toValue($0) == null
      ? 1 : 0;
  }), v.as_handle());

  if (isNull) {
    lua_pushnil(L);
    return;
  }

  bool isUInt8Array = EM_ASM_INT(({
    return Emval.toValue($0) instanceof Uint8Array
      ? 1 : 0;
  }), v.as_handle());

  if (isUInt8Array) {
    push_mtx(L, iv, MTA);
    return;
  }

  bool isPromise = EM_ASM_INT(({
    return Emval.toValue($0) instanceof Promise
      ? 1 : 0;
  }), v.as_handle());

  if (isPromise)  {
    push_mtx(L, iv, MTP);
  } else if (!recurse) {
    push_mtx(L, iv, MTO);
  } else {
    bool isArray = EM_ASM_INT(({
      return Emval.toValue($0) instanceof Array
        ? 1 : 0;
    }), v.as_handle());
    bool isPlainObject = EM_ASM_INT(({
      const value = Emval.toValue($0);
      return value && typeof value == "object" && [undefined, Object].includes(value.constructor)
        ? 1 : 0;
    }), v.as_handle());
    if (isArray) {
      lua_newtable(L); // t
      int64_t m = v["length"].as<int64_t>();
      for (int64_t i = 0; i < m; i ++) {
        lua_pushinteger(L, i + 1); // t i
        push_val(L, v[i], INT_MIN); // t i v
        val_to_lua(L, -1, true, false); // t i v l
        lua_remove(L, -2); // t i v
        lua_settable(L, -3); // t
      }
    } else if (isPlainObject) {
      lua_newtable(L); // t
      val ks = val::global("Object").call<val>("keys", v);
      int64_t m = ks["length"].as<int64_t>();
      for (int64_t i = 0; i < m; i ++) {
        val k = ks[i];
        push_val(L, k, INT_MIN); // t kv
        val_to_lua(L, -1, true, false); // t kv kl
        push_val(L, v[k], INT_MIN); // t kv kl vv
        val_to_lua(L, -1, true, false); // t kv kl vv vl
        lua_remove(L, -2); // t kv kl vl
        lua_remove(L, -3); // t kl vl
        lua_settable(L, -3); // t
      }
    } else {
      lua_pushvalue(L, iv);
    }
  }
}

static inline void number_to_lua (lua_State *L, val v) {

  bool isInteger = EM_ASM_INT(({
    try {
      var v = Emval.toValue($0);
      return Number.isInteger(v);
    } catch (_) {
      return false;
    }
  }), v.as_handle());

  if (isInteger) {

    int64_t x = v.as<int64_t>();
    lua_pushinteger(L, x);

  } else {

    double x = v.as<double>();
    lua_pushnumber(L, x);

  }

}

static inline void bigint_to_lua (lua_State *L, val v) {

  // TODO: Needs to be thoroughly tested to
  // support 64 bit integers.
  int64_t n = EM_ASM_INT(({
    var bi = Emval.toValue($1);
    if (bi > Number.MAX_SAFE_INTEGER ||
        bi < Number.MIN_SAFE_INTEGER)
      Module["error"]($0, Emval.toHandle("Conversion from bigint to number failed: too large or too small"));
    return Number(bi);
  }), L, v.as_handle());

  lua_pushinteger(L, n);

}

static inline void function_to_lua (lua_State *L, val v, int iv) {

  iv = tk_lua_absindex(L, iv);
  push_mtx(L, iv, MTF);

}

static inline int mt_lua (lua_State *L)
{
  lua_settop(L, 2);
  bool recurse = lua_toboolean(L, 2);
  val_to_lua(L, 1, recurse, false);
  return 1;
}

static inline void val_to_lua (lua_State *L, int iv, bool recurse, bool force_wrap)
{
  if (!force_wrap && mtx_to_lua(L, iv))
    return;

  val v = peek_val(L, iv);
  string type = v.typeOf().as<string>();

  if (type == "string") {
    string x = v.as<string>();
    lua_pushstring(L, x.c_str());

  } else if (type == "boolean") {
    bool x = v.as<bool>();
    lua_pushboolean(L, x);

  } else if (type == "number") {
    number_to_lua(L, v);

  } else if (type == "bigint") {
    bigint_to_lua(L, v);

  } else if (type == "object") {
    object_to_lua(L, v, iv, recurse);

  } else if (type == "function") {
    function_to_lua(L, v, iv);

  } else if (type == "undefined") {
    lua_pushnil(L);

  } else {
    lua_pushnil(L);
  }

}

static inline void val_to_lua (lua_State *L, int iv, bool recurse) {
  val_to_lua(L, iv, recurse, false);
}

static inline bool tk_web_isarray (lua_State *L, int i) {
  size_t tlen = lua_objlen(L, i);
  if (tlen > 0) {
    return true;
  } else {
    lua_pushvalue(L, i); // t
    lua_pushnil(L); // t k
    if (lua_next(L, -2) == 0) { // t
      lua_pop(L, 1); //
      return true; //
    } else { // t k v
      lua_pop(L, 3); //
      return false; //
    }
  }
}

static inline void table_to_val (lua_State *L, int i, bool recurse) {

  int i_tbl = tk_lua_absindex(L, i);

  bool isarray = tk_web_isarray(L, i);

  if (!recurse) {

    int tblref = val_ref(L, i_tbl); // val

    push_val(L, val::take_ownership((EM_VAL) EM_ASM_PTR(({
      var obj = $2 ? [] : {};
      return Emval.toHandle(new Proxy(obj, {

        get(o, k, r) {
          if (k == Module.isProxy)
            return true;
          var isnumber;
          try { isnumber = !isNaN(+k); }
          catch (_) { isnumber = false; }
          if (r[Module.isProxy] && k == "toString") {
            return () => Emval.toValue(Module["tostring"]($0, $1));
          }
          if (r[Module.isProxy] && k == "valueOf") {
            return () => Emval.toValue(Module["valueof"]($0, $1));
          }
          if (o instanceof Array && k == "length") {
            var l = Module["len"]($0, $1);
            return l;
          }
          if (o instanceof Array && isnumber) {
            var e = Module["get"]($0, $1, Emval.toHandle(+k + 1), 0);
            return Emval.toValue(e);
          }
          if (typeof k == "string") {
            var e = Module["get"]($0, $1, stringToNewUTF8(k), 1);
            return Emval.toValue(e);
          }
          if (k == Symbol.iterator) {
            // TODO: This creates an
            // intermediary array, which is not
            // likely necessary
            return Object.values(o)[k];
          }
          return Reflect.get(o, k, r);
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
          Module["own_keys"]($0, $1, Emval.toHandle(keys));
          return keys;
        },

        set(o, k, v) {
          var isnumber;
          try { isnumber = !isNaN(+k); }
          catch (_) { isnumber = false; }
          if (o instanceof Array && isnumber)
            Module["set"]($0, $1, Emval.toHandle(+k + 1), Emval.toHandle(v));
          else
            Module["set"]($0, $1, Emval.toHandle(k), Emval.toHandle(v));
        }

      }))
    }), L, tblref, isarray)), i_tbl); // val

    val v = peek_val(L, -1);

    EM_ASM(({
      var v = Emval.toValue($0);
      Module["FINALIZERS"].register(v, $1);
    }), v.as_handle(), tblref);

  } else if (isarray) {

    int len = lua_objlen(L, i_tbl);

    val arr = val::array();
    lua_pushvalue(L, i_tbl); // tbl

    for (int j = 1; j <= len; j ++) {
      lua_pushinteger(L, j); // tbl int
      lua_gettable(L, -2); // tbl lua
      lua_to_val(L, -1, true); // tbl lua val
      val el = peek_val(L, -1);
      arr.set(j - 1, el);
      lua_pop(L, 2); // tbl
    }

    lua_pop(L, 1); //
    push_val(L, arr, INT_MIN); // val

  } else {

    lua_pushvalue(L, i_tbl); // tbl
    val obj = val::object();

    lua_pushnil(L); // tbl nil
    while (lua_next(L, -2) != 0) { // tbl k v
      lua_to_val(L, -2, true); // tbl k v kv
      lua_to_val(L, -2, true); // tbl k v kv vv
      val kk = peek_val(L, -2);
      val vv = peek_val(L, -1);
      obj.set(kk, vv);
      lua_pop(L, 3); // tbl k
    }

    lua_pop(L, 1); // tbl
    push_val(L, obj, INT_MIN);

  }

}

static inline void function_to_val (lua_State *L, int i) {

  int i_fn = tk_lua_absindex(L, i);

  int fnref = val_ref(L, i_fn);

  push_val(L, val::take_ownership((EM_VAL) EM_ASM_PTR(({
    return Emval.toHandle(new Proxy(function () {}, {
      apply(_, this_, args) {
        args.unshift(this_);
        return Emval.toValue(Module["call"]($0, $1, Emval.toHandle(args)));
      }
    }));
  }), L, fnref)), i_fn);

  val v = peek_val(L, -1);

  EM_ASM(({
    var v = Emval.toValue($0);
    Module["FINALIZERS"]["register"](v, $1);
  }), v.as_handle(), fnref);

}

static inline int lua_to_val (lua_State *L, int i, bool recurse) {

  int type = lua_type(L, i);

  if (type == LUA_TSTRING) {
    push_val(L, val::u8string(lua_tostring(L, i)), INT_MIN);

  } else if (type == LUA_TNUMBER) {
    push_val(L, val(lua_tonumber(L, i)), INT_MIN);

  } else if (type == LUA_TBOOLEAN) {
    push_val(L, val(lua_toboolean(L, i) ? true : false), INT_MIN);

  } else if (type == LUA_TUSERDATA || type == LUA_TLIGHTUSERDATA || type == LUA_TTHREAD) {
    // TODO: Should this really just be passed
    // through?
    lua_pushvalue(L, i);

  } else if (type == LUA_TNIL) {
    push_val(L, val::undefined(), INT_MIN);

  } else if (type == LUA_TTABLE) {
    table_to_val(L, i, recurse);

  } else if (type == LUA_TFUNCTION) {
    function_to_val(L, i);

  } else {
    push_val(L, val::undefined(), INT_MIN);
  }

  return 1;
}

static inline int j_arg (int Lp, int i) {
  lua_State *L = (lua_State *) Lp;
  lua_to_val(L, i, false);
  EM_VAL v = peek_val(L, -1).as_handle();
  lua_pop(L, 1);
  return (int) v;
}

static inline int j_args (int Lp, int arg0, int argc) {
  // lua_State *L = (lua_State *) Lp;
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
              var arg = Module["arg"]($0, i + $1 - 1);
              var val = Emval.toValue(arg);
              return { done: false, value: val };
            }
          }
        };
      }
    })
  }), Lp, arg0, argc);
}

static inline void j_own_keys (int Lp, int it, int keysp) {

  lua_State *L = (lua_State *) Lp;

  assert(val_unref(L, it)); // tbl
  bool isarray = tk_web_isarray(L, -1); // tbl
  lua_pop(L, 1); // tbl

  if (isarray)
    EM_ASM(({
      var keys = Emval.toValue($0);
      keys.push("length");
    }), keysp);

  assert(val_unref(L, it)); // tbl
  lua_pushnil(L); // tbl nil
  while (lua_next(L, -2) != 0) { // tbl k v
    lua_to_val(L, -2, false); // tbl k v k
    val k = peek_val(L, -1);
    EM_ASM(({
      var keys = Emval.toValue($0);
      var key = Emval.toValue($1);
      if ($2 && typeof key == "number")
        keys.push(String(key - 1));
      else
        keys.push(String(key));
    }), keysp, k.as_handle(), isarray);
    lua_pop(L, 2); // tbl k
  }

}

static inline int j_get (int Lp, int i, int k, int is_str) {

  lua_State *L = (lua_State *) Lp;

  assert(val_unref(L, i));

  if (is_str) {
    char *kk = (char *) k;
    lua_pushstring(L, kk);
    free(kk);
  } else {
    val kk = val::take_ownership((EM_VAL) k);
    push_val(L, kk, INT_MIN);
    val_to_lua(L, -1, false);
    lua_remove(L, -2);
  }

  lua_gettable(L, -2);
  lua_to_val(L, -1, false);
  val vv = peek_val(L, -1);

  return (int) vv.as_handle();
}

static inline void j_set (int Lp, int i, int k, int v) {
  lua_State *L = (lua_State *) Lp;
  val kk = val::take_ownership((EM_VAL) k);
  val vv = val::take_ownership((EM_VAL) v);
  push_val(L, kk, INT_MIN); // kv
  push_val(L, vv, INT_MIN); // kv vv
  val_to_lua(L, -2, false); // kv vv kl
  val_to_lua(L, -2, false); // kv vv kl vl
  assert(val_unref(L, i)); // kv vv kl vl t
  lua_insert(L, -3); // kv vv t kl vl
  lua_settable(L, -3); // kv vv t
  lua_pop(L, 3); //
}

static inline int j_call (int Lp, int i, int argsp) {

  lua_State *L = (lua_State *) Lp;

  assert(val_unref(L, i));

  val args = val::take_ownership((EM_VAL) argsp);
  int argc = args["length"].as<int>();

  for (int i = 0; i < argc; i ++) {
    push_val(L, args[val(i)], INT_MIN);
    val_to_lua(L, -1, false);
    lua_remove(L, -2);
  }

  int t = lua_gettop(L) - argc - 1;
  int rc = lua_pcall(L, argc, LUA_MULTRET, 0);

  if (rc != 0) {

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

static inline void j_error (int Lp, int ep) {
  lua_State *L = (lua_State *) Lp;
  val e = val::take_ownership((EM_VAL) ep);
  push_val(L, e, INT_MIN);
  val_to_lua(L, -1, false);
  lua_remove(L, -2);
  lua_error(L);
}

static inline int j_len (int Lp, int i) {
  lua_State *L = (lua_State *) Lp;
  assert(val_unref(L, i)); // val
  lua_Integer len = lua_objlen(L, -1);
  lua_pop(L, 1); //
  return len;
}

static inline int j_tostring (int Lp, int i) {
  lua_State *L = (lua_State *) Lp;
  lua_getglobal(L, "tostring"); // ts
  assert(val_unref(L, i)); // ts val
  lua_call(L, 1, 1); // s
  const char *str = lua_tostring(L, -1); // s
  lua_pop(L, 1); //
  push_val(L, val(str), INT_MIN);
  return (int) peek_val(L, -1).as_handle();
}

static inline int j_valueof (int Lp, int i) {
  lua_State *L = (lua_State *) Lp;
  assert(val_unref(L, i)); // ts val
  lua_to_val(L, -1, true); // ts val val
  return (int) peek_val(L, -1).as_handle();
}

static inline void j_val_ref_delete (int Lp, int ref) {
  lua_State *L = (lua_State *) Lp;
  lua_rawgeti(L, LUA_REGISTRYINDEX, IDX_REF_TBL);
  luaL_unref(L, -1, ref);
  lua_pop(L, 1);
  tk_web_decrement_refn(L);
}

EMSCRIPTEN_BINDINGS(santoku_web_val) {
  emscripten::function("error", &j_error, allow_raw_pointers());
  emscripten::function("arg", &j_arg, allow_raw_pointers());
  emscripten::function("args", &j_args, allow_raw_pointers());
  emscripten::function("get", &j_get, allow_raw_pointers());
  emscripten::function("set", &j_set, allow_raw_pointers());
  emscripten::function("call", &j_call, allow_raw_pointers());
  emscripten::function("own_keys", &j_own_keys, allow_raw_pointers());
  emscripten::function("tostring", &j_tostring, allow_raw_pointers());
  emscripten::function("valueof", &j_valueof, allow_raw_pointers());
  emscripten::function("len", &j_len, allow_raw_pointers());
  emscripten::function("val_ref_delete", &j_val_ref_delete, allow_raw_pointers());
}

static inline int mt_call (lua_State *L) {

  int n = lua_gettop(L);

  if (n == 3) {
    lua_remove(L, -3);
    bool recurse = lua_toboolean(L, -1);
    lua_pop(L, 1);
    lua_to_val(L, -1, recurse);
    return 1;
  } else if (n == 2) {
    lua_remove(L, -2);
    lua_to_val(L, -1, false);
    return 1;
  } else {
    luaL_error(L, "expected 1 or 2 arguments to val(...)");
    return 0;
  }

}

static inline int mt_global (lua_State *L) {
  const char *str = luaL_checkstring(L, -1);
  push_val(L, val::global(str), INT_MIN);
  lua_remove(L, -2);
  return 1;
}

// NOTE: We copy the uint8array by calling slice
// because as the WASM memory grows, the memory
// view backing the uint8array will be
// invalidated, resulting in "detached array
// buffer" errors. Is it somehow possible to
// update the pointer when this happens? Maybe..
static inline int mt_bytes (lua_State *L) {
  size_t size;
  const char *str = luaL_checklstring(L, -1, &size); // str
  val v = val(typed_memory_view(size, (uint8_t *) str));
  push_val(L, v.call<val>("slice"), -1); // str val
  val_to_lua(L, -1, false, true); // str val lua
  return 1;
}

static inline int mt_class (lua_State *L) {
  lua_settop(L, 2);
  lua_to_val(L, 1, false);
  lua_to_val(L, 2, false);
  val config = peek_val(L, 3);
  val parent = peek_val(L, 4);
  val clss = val::take_ownership((EM_VAL) EM_ASM_PTR(({
    var config = Emval.toValue($0) || (() => {});
    var parent = Emval.toValue($1);
    var clss = parent
      ? class extends parent { }
      : class { };
    config.call(clss.prototype);
    return Emval.toHandle(clss);
  }), config.as_handle(), parent.as_handle()));
  push_val(L, clss, INT_MIN);
  return 1;
}

static inline int mto_index (lua_State *L) { // lo lk
  lua_pushvalue(L, -1); // lo lk lk
  lua_rawgeti(L, LUA_REGISTRYINDEX, MTO_FNS); // lo lk lk fns
  lua_insert(L, -2); // lo lk fns lk
  lua_gettable(L, -2);
  if (lua_type(L, -1) != LUA_TNIL) // lo lk fns lv
    return 1;
  lua_pop(L, 2); // lo lk
  lua_to_val(L, -1, false); // lo lk vk
  lua_remove(L, -2); // lo vk
  val k = peek_val(L, -1);
  val v = peek_val(L, -2);
  val n = val::take_ownership((EM_VAL) EM_ASM_PTR(({
    var v = Emval.toValue($0);
    var k = Emval.toValue($1);
    if (v instanceof Array && typeof k == "number")
      k = k - 1;
    return Emval.toHandle(v[k]);
  }), v.as_handle(), k.as_handle()));
  lua_pop(L, 2); //
  push_val(L, n, INT_MIN); // val
  val_to_lua(L, -1, false); // val lua
  return 1;
}

static inline int mto_newindex (lua_State *L) {
  return mtv_set(L);
}

static inline int mto_instanceof (lua_State *L) {
  mtv_instanceof(L);
  val_to_lua(L, -1, false);
  return 1;
}

static inline int mto_typeof (lua_State *L) {
  mtv_typeof(L);
  val_to_lua(L, -1, false);
  return 1;
}

static inline int mtp_index (lua_State *L) {
  lua_rawgeti(L, LUA_REGISTRYINDEX, MTP_FNS);
  lua_pushvalue(L, -2);
  lua_gettable(L, -2);
  if (lua_type(L, -1) != LUA_TNIL)
    return 1;
  lua_pop(L, 2);
  return mto_index(L);
}

static inline int mtp_await (lua_State *L) {
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

static inline int mta_index (lua_State *L) {
  lua_rawgeti(L, LUA_REGISTRYINDEX, MTA_FNS);
  lua_pushvalue(L, -2);
  lua_gettable(L, -2);
  if (lua_type(L, -1) != LUA_TNIL)
    return 1;
  lua_pop(L, 2);
  return mto_index(L);
}

static inline int mta_str (lua_State *L) {
  args_to_vals(L, -1);
  val v = peek_val(L, -1);
  vector<uint8_t> vec = convertJSArrayToNumberVector<uint8_t>(v);
  lua_pushlstring(L, (char *) vec.data(), vec.size());
  return 1;
}

static inline int mtf_index (lua_State *L) {
  lua_rawgeti(L, LUA_REGISTRYINDEX, MTF_FNS);
  lua_pushvalue(L, -2);
  lua_gettable(L, -2);
  if (lua_type(L, -1) != LUA_TNIL)
    return 1;
  lua_pop(L, 2);
  return mto_index(L);
}

static inline int mtf_call (lua_State *L) {
  mtv_call(L);
  val_to_lua(L, -1, false);
  return 1;
}

static inline int mtf_new (lua_State *L) {
  mtv_new(L);
  val_to_lua(L, -1, false);
  return 1;
}

static inline int mto_val (lua_State *L) {
  assert(mtx_to_mtv(L, -1));
  return 1;
}

static inline int mtv_lua (lua_State *L) {
  int n = lua_gettop(L);
  if (n == 2) {
    bool recurse = lua_toboolean(L, -1);
    val_to_lua(L, -2, recurse);
    return 1;
  } else if (n == 1) {
    val_to_lua(L, -1, false);
    lua_remove(L, -2);
    return 1;
  } else {
    luaL_error(L, "expected 1 or 2 arguments to val:lua(...)");
    return 0;
  }
}

static inline int mtv_get (lua_State *L) {
  args_to_vals(L, -1);
  val k = peek_val(L, -1);
  val o = peek_val(L, -2);
  push_val(L, o[k], INT_MIN);
  return 1;
}

static inline int mtv_set (lua_State *L) {
  args_to_vals(L, -1);
  val v = peek_val(L, -1);
  val k = peek_val(L, -2);
  val o = peek_val(L, -3);
  o.set(k, v);
  return 0;
}

static inline int mto_len (lua_State *L) {
  args_to_vals(L, -1);
  val v = peek_val(L, 1);
  lua_pushinteger(L, EM_ASM_INT(({
    var v = Emval.toValue($0);
    return v instanceof Array
      ? v.length
      : 0;
  }), v.as_handle()));
  return 1;
}

static inline int mtv_typeof (lua_State *L) {
  args_to_vals(L, -1);
  val v = peek_val(L, -1);
  val t = v.typeOf();
  push_val(L, t, INT_MIN);
  return 1;
}

static inline int mtv_instanceof (lua_State *L) {
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

static inline int mtv_call (lua_State *L) {
  args_to_vals(L, -1);
  int n = lua_gettop(L);
  val v = peek_val(L, -n);
  val t = lua_type(L, -n + 1) == LUA_TNIL
    ? val::undefined()
    : peek_val(L, -n + 1);
  val r = val::take_ownership((EM_VAL) EM_ASM_PTR(({
    try {
      var fn = Emval.toValue($1);
      var ths = Emval.toValue($2);
      if (ths != undefined)
        fn = fn.bind(ths);
      var args = Emval.toValue(Module["args"]($0, $3, $4));
      var args = [ ...args ];
      var r = fn(...args);
      return Emval.toHandle(r);
    } catch (e) {
      return Module["error"]($0, Emval.toHandle(e));
    }
  }), L, v.as_handle(), t.as_handle(), -n + 2, n - 2));
  push_val(L, r, INT_MIN);
  return 1;
}

static inline int mtv_new (lua_State *L) {
  args_to_vals(L, -1);
  int n = lua_gettop(L);
  val v = peek_val(L, -n);
  val r = val::take_ownership((EM_VAL) EM_ASM_PTR(({
    var obj = Emval.toValue($1);
    var args = Emval.toValue(Module["args"]($0, $2, $3));
    return Emval.toHandle(new obj(...args));
  }), L, v.as_handle(), -n + 1, n - 1));
  push_val(L, r, INT_MIN);
  return 1;
}

static inline luaL_Reg mtp_fns[] = {
  { "await", mtp_await },
  { NULL, NULL }
};

static inline luaL_Reg mta_fns[] = {
  { "str", mta_str },
  { NULL, NULL }
};

static inline luaL_Reg mtf_fns[] = {
  { "new", mtf_new },
  { NULL, NULL }
};

static inline luaL_Reg mto_fns[] = {
  { "typeof", mto_typeof },
  { "instanceof", mto_instanceof },
  { "val", mto_val },
  { NULL, NULL }
};

static inline luaL_Reg mtv_fns[] = {
  { "lua", mtv_lua },
  { "get", mtv_get },
  { "set", mtv_set },
  { "typeof", mtv_typeof },
  { "instanceof", mtv_instanceof },
  { "call", mtv_call },
  { "new", mtv_new },
  { NULL, NULL }
};

static inline luaL_Reg mt_fns[] = {
  { "global", mt_global },
  { "lua", mt_lua },
  { "bytes", mt_bytes },
  { "class", mt_class },
  { NULL, NULL }
};

// TODO: Review which are available in Lua 5.1. __pairs at least should be
// removed.
static inline void set_common_obj_mtfns (lua_State *L) {

  lua_pushcfunction(L, mto_len);
  lua_setfield(L, -2, "__len");

  lua_pushcfunction(L, mto_newindex);
  lua_setfield(L, -2, "__newindex");

  lua_pushcfunction(L, mtv_add); // No difference between concat and add in JS
  lua_setfield(L, -2, "__concat");

  lua_pushcfunction(L, mtv_tostring);
  lua_setfield(L, -2, "__tostring");

  lua_pushcfunction(L, mtv_eq);
  lua_setfield(L, -2, "__eq");
  lua_pushcfunction(L, mtv_lt);
  lua_setfield(L, -2, "__lt");
  lua_pushcfunction(L, mtv_le);
  lua_setfield(L, -2, "__le");

  lua_pushcfunction(L, mtv_add);
  lua_setfield(L, -2, "__add");
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

  lua_pop(L, 1);
}

int luaopen_santoku_web_val (lua_State *L)
{
  lua_newtable(L);

  lua_newtable(L);
  lua_pushcfunction(L, mt_call);
  lua_setfield(L, -2, "__call");
  lua_setmetatable(L, -2);

  luaL_register(L, NULL, mt_fns);

  luaL_newmetatable(L, MTV);
  lua_newtable(L);
  luaL_register(L, NULL, mtv_fns);
  lua_setfield(L, -2, "__index");
  lua_pushcfunction(L, mtv_gc);
  lua_setfield(L, -2, "__gc");
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

  lua_newtable(L);
  lua_pushinteger(L, 0);
  lua_setfield(L, -2, "n");
  IDX_REF_TBL = luaL_ref(L, LUA_REGISTRYINDEX);
  lua_rawgeti(L, LUA_REGISTRYINDEX, IDX_REF_TBL);
  lua_setfield(L, -2, "IDX_REF_TBL");

  EM_ASM(({
    Module.isProxy = Symbol("isProxy");
  }));

  EM_ASM(({
    Module["FINALIZERS"] = new FinalizationRegistry(ref => {
      Module["val_ref_delete"]($0, ref);
    })
  }), L);

  lua_newtable(L);
  luaL_register(L, NULL, mto_fns);
  MTO_FNS = luaL_ref(L, LUA_REGISTRYINDEX);

  lua_newtable(L);
  luaL_register(L, NULL, mtp_fns);
  MTP_FNS = luaL_ref(L, LUA_REGISTRYINDEX);

  lua_newtable(L);
  luaL_register(L, NULL, mta_fns);
  MTA_FNS = luaL_ref(L, LUA_REGISTRYINDEX);

  lua_newtable(L);
  luaL_register(L, NULL, mtf_fns);
  MTF_FNS = luaL_ref(L, LUA_REGISTRYINDEX);

  lua_newtable(L); // t
  lua_newtable(L); // t mt
  lua_pushstring(L, "k"); // t mt v
  lua_setfield(L, -2, "__mode"); // t mt
  lua_setmetatable(L, -2); // t
  TK_WEB_EPHEMERON_IDX = luaL_ref(L, LUA_REGISTRYINDEX); //
  lua_rawgeti(L, LUA_REGISTRYINDEX, TK_WEB_EPHEMERON_IDX); // t
  lua_setfield(L, -2, "EPHEMERON_IDX"); //

  return 1;
}
