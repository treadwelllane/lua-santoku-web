#include "lua.h"
#include "lauxlib.h"
#include "emscripten.h"

#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <limits.h>
#include <stdint.h>

int luaopen_santoku_web_val (lua_State *);

#define MTV "santoku_web_val"
#define MTO "santoku_web_object"
#define MTA "santoku_web_array"
#define MTF "santoku_web_function"
#define MTP "santoku_web_promise"

#define TK_UNDEFINED 0
#define TK_NULL 1

#define TK_TYPE_UNDEFINED 0
#define TK_TYPE_BOOLEAN   1
#define TK_TYPE_NUMBER    2
#define TK_TYPE_STRING    3
#define TK_TYPE_OBJECT    4
#define TK_TYPE_FUNCTION  5
#define TK_TYPE_BIGINT    6
#define TK_TYPE_SYMBOL    7

static int IDX_REF_TBL;
static int MTO_FNS;
static int MTP_FNS;
static int MTA_FNS;
static int MTF_FNS;
static int TK_WEB_EPHEMERON_IDX;
static lua_State *tk_web_main_L = NULL;

static inline void tk_web_set_ephemeron (lua_State *, int, int);
static inline int tk_web_get_ephemeron (lua_State *, int, int);
static inline int mtx_to_mtv (lua_State *, int);
static inline int lua_to_handle (lua_State *, int, int);
static inline void handle_to_lua (lua_State *, int, int, int);
static inline void push_handle (lua_State *, int, int);
static inline int handle_ref (lua_State *, int);
static inline int handle_get_ref (lua_State *, int);
static inline int lua_val_to_new_handle (lua_State *, int, int);

static inline int mtv_call (lua_State *);
static inline int mtv_instanceof (lua_State *);
static inline int mtv_lua (lua_State *);
static inline int mtv_new (lua_State *);
static inline int mtv_set (lua_State *);
static inline int mtv_typeof (lua_State *);

EM_JS(void, tk_js_init, (int Lp), {
  Module._tkh = [undefined, null];
  Module._tkf = [];
  Module._toH = function (v) {
    var i = Module._tkf.length ? Module._tkf.pop() : Module._tkh.length;
    Module._tkh[i] = v;
    return i;
  };
  Module._rel = function (h) {
    if (h < 2) return;
    Module._tkh[h] = undefined;
    Module._tkf.push(h);
  };
  Module._cloneH = function (h) {
    return Module._toH(Module._tkh[h]);
  };
  Module.isProxy = Symbol("isProxy");
  Module["FINALIZERS"] = new FinalizationRegistry(function (ref) {
    if (typeof ref === "number") {
      Module["_tk_val_ref_delete"](Lp, ref);
    } else {
      Module["_tk_val_ref_delete"](Lp, ref.ref);
      if (ref.thread_ref !== undefined) {
        Module["_tk_val_ref_delete"](Lp, ref.thread_ref);
      }
    }
  });
})

EM_JS(int, tk_js_typeof_id, (int h), {
  var v = Module._tkh[h];
  switch (typeof v) {
    case "undefined": return 0;
    case "boolean":   return 1;
    case "number":    return 2;
    case "string":    return 3;
    case "object":    return 4;
    case "function":  return 5;
    case "bigint":    return 6;
    case "symbol":    return 7;
    default:          return 0;
  }
})

EM_JS(int, tk_js_string_to_buf, (int h, char *buf, int bufsize), {
  var s = String(Module._tkh[h]);
  var len = lengthBytesUTF8(s);
  if (len + 1 <= bufsize) {
    stringToUTF8(s, buf, len + 1);
    return len;
  }
  return -(len + 1);
})

EM_JS(double, tk_js_to_double, (int h), {
  return Number(Module._tkh[h]);
})

EM_JS(int, tk_js_to_bool, (int h), {
  return Module._tkh[h] ? 1 : 0;
})

EM_JS(int, tk_js_is_integer, (int h), {
  return Number.isInteger(Module._tkh[h]) ? 1 : 0;
})

EM_JS(int, tk_js_is_null, (int h), {
  return Module._tkh[h] == null ? 1 : 0;
})

EM_JS(int, tk_js_is_uint8array, (int h), {
  return Module._tkh[h] instanceof Uint8Array ? 1 : 0;
})

EM_JS(int, tk_js_is_promise, (int h), {
  return Module._tkh[h] instanceof Promise ? 1 : 0;
})

EM_JS(int, tk_js_is_array, (int h), {
  return Module._tkh[h] instanceof Array ? 1 : 0;
})

EM_JS(int, tk_js_is_plain_object, (int h), {
  var value = Module._tkh[h];
  return (value && typeof value == "object" && [undefined, Object].includes(value.constructor)) ? 1 : 0;
})

EM_JS(int, tk_js_array_length, (int h), {
  return Module._tkh[h].length;
})

EM_JS(int, tk_js_array_get, (int h, int i), {
  return Module._toH(Module._tkh[h][i]);
})

EM_JS(int, tk_js_object_keys, (int h), {
  return Module._toH(Object.keys(Module._tkh[h]));
})

EM_JS(int, tk_js_object_get, (int h, int kh), {
  return Module._toH(Module._tkh[h][Module._tkh[kh]]);
})

EM_JS(int, tk_js_global, (const char *name), {
  return Module._toH(globalThis[UTF8ToString(name)]);
})

EM_JS(int, tk_js_lstring, (const char *s, int len), {
  return Module._toH(UTF8ToString(s, len));
})

EM_JS(int, tk_js_number, (double n), {
  return Module._toH(n);
})

EM_JS(int, tk_js_bool, (int b), {
  return Module._toH(b ? true : false);
})

EM_JS(int, tk_js_new_array, (void), {
  return Module._toH([]);
})

EM_JS(int, tk_js_new_object, (void), {
  return Module._toH({});
})

EM_JS(void, tk_js_array_set, (int ah, int i, int vh), {
  Module._tkh[ah][i] = Module._tkh[vh];
})

EM_JS(void, tk_js_object_set, (int oh, int kh, int vh), {
  Module._tkh[oh][Module._tkh[kh]] = Module._tkh[vh];
})

EM_JS(int, tk_js_get_prop, (int oh, int kh), {
  var v = Module._tkh[oh];
  var k = Module._tkh[kh];
  if (typeof k == "number" && v != null && typeof v === "object" && typeof v.length == "number")
    k = k - 1;
  return Module._toH(v[k]);
})

EM_JS(int, tk_js_get_prop_cstr, (int oh, const char *key), {
  return Module._toH(Module._tkh[oh][UTF8ToString(key)]);
})

EM_JS(void, tk_js_rel, (int h), {
  Module._rel(h);
})

EM_JS(void, tk_js_set_prop, (int oh, int kh, int vh), {
  Module._tkh[oh][Module._tkh[kh]] = Module._tkh[vh];
})

EM_JS(int, tk_js_len, (int h), {
  var v = Module._tkh[h];
  return (v != null && typeof v === "object" && typeof v.length == "number") ? v.length : 0;
})

EM_JS(int, tk_js_instanceof, (int vh, int ch), {
  return Module._tkh[vh] instanceof Module._tkh[ch] ? 1 : 0;
})

EM_JS(int, tk_js_typeof_string, (int h), {
  return Module._toH(typeof Module._tkh[h]);
})

EM_JS(int, tk_js_eq, (int a, int b), {
  return Module._tkh[a] == Module._tkh[b] ? 1 : 0;
})

EM_JS(int, tk_js_lt, (int a, int b), {
  return Module._tkh[a] < Module._tkh[b] ? 1 : 0;
})

EM_JS(int, tk_js_le, (int a, int b), {
  return Module._tkh[a] <= Module._tkh[b] ? 1 : 0;
})

EM_JS(int, tk_js_add, (int a, int b), {
  return Module._toH(Module._tkh[a] + Module._tkh[b]);
})

EM_JS(int, tk_js_sub, (int a, int b), {
  return Module._toH(Module._tkh[a] - Module._tkh[b]);
})

EM_JS(int, tk_js_mul, (int a, int b), {
  return Module._toH(Module._tkh[a] * Module._tkh[b]);
})

EM_JS(int, tk_js_div, (int a, int b), {
  return Module._toH(Module._tkh[a] / Module._tkh[b]);
})

EM_JS(int, tk_js_mod, (int a, int b), {
  return Module._toH(Module._tkh[a] % Module._tkh[b]);
})

EM_JS(int, tk_js_pow, (int a, int b), {
  return Module._toH(Module._tkh[a] ** Module._tkh[b]);
})

EM_JS(int, tk_js_unm, (int a), {
  return Module._toH(- Module._tkh[a]);
})

EM_JS(int, tk_js_tostring_val, (int h), {
  var v = Module._tkh[h];
  v = v instanceof Error ? v.stack : v.toString();
  return Module._toH(v);
})

EM_JS(int, tk_js_bigint_to_number, (int Lp, int h), {
  var bi = Module._tkh[h];
  if (bi > Number.MAX_SAFE_INTEGER || bi < Number.MIN_SAFE_INTEGER) {
    var eh = Module._toH("Conversion from bigint to number failed: too large or too small");
    Module["_tk_j_error"](Lp, eh);
  }
  return Number(bi);
})

EM_JS(int, tk_js_bytes, (const char *ptr, int size), {
  var view = new Uint8Array(Module.HEAPU8.buffer, ptr, size);
  var copy = view.slice();
  return Module._toH(copy);
})

EM_JS(int, tk_js_class, (int configH, int parentH), {
  var config = Module._tkh[configH] || (function () {});
  var parent = Module._tkh[parentH];
  var clss = parent
    ? class extends parent { }
    : class { };
  config.call(clss.prototype);
  return Module._toH(clss);
})

EM_JS(int, tk_js_uint8array_length, (int h), {
  return Module._tkh[h].length;
})

EM_JS(void, tk_js_uint8array_copy_to, (int h, char *buf), {
  var arr = Module._tkh[h];
  Module.HEAPU8.set(arr, buf);
})

EM_JS(int, tk_js_make_table_proxy, (int Lp, int tblref, int isarray), {
  var obj = isarray ? [] : {};
  return Module._toH(new Proxy(obj, {

    get: function (o, k, r) {
      if (k == Module.isProxy)
        return true;
      var isnumber;
      try { isnumber = !isNaN(+k); }
      catch (_) { isnumber = false; }
      if (r[Module.isProxy] && k == "toString") {
        return function () {
          var rh = Module["_tk_j_tostring"](Lp, tblref);
          var rv = Module._tkh[rh];
          Module._rel(rh);
          return rv;
        };
      }
      if (r[Module.isProxy] && k == "valueOf") {
        return function () {
          var rh = Module["_tk_j_valueof"](Lp, tblref);
          var rv = Module._tkh[rh];
          Module._rel(rh);
          return rv;
        };
      }
      if (o instanceof Array && k == "length") {
        var l = Module["_tk_j_len"](Lp, tblref);
        return l;
      }
      if (o instanceof Array && isnumber) {
        var eh = Module._toH(+k + 1);
        var e = Module["_tk_j_get"](Lp, tblref, eh, 0);
        var ev = Module._tkh[e];
        Module._rel(e);
        return ev;
      }
      if (typeof k == "string") {
        var e = Module["_tk_j_get"](Lp, tblref, stringToNewUTF8(k), 1);
        var ev = Module._tkh[e];
        Module._rel(e);
        return ev;
      }
      if (k == Symbol.iterator) {
        return Object.values(o)[k];
      }
      return Reflect.get(o, k, r);
    },

    getOwnPropertyDescriptor: function (o, k) {
      return Object.getOwnPropertyDescriptor(o, k) || {
        configurable: true,
        enumerable: true,
        value: o[k]
      };
    },

    ownKeys: function (o) {
      var keys = [];
      var kh = Module._toH(keys);
      Module["_tk_j_own_keys"](Lp, tblref, kh);
      Module._rel(kh);
      return keys;
    },

    set: function (o, k, v) {
      var isnumber;
      try { isnumber = !isNaN(+k); }
      catch (_) { isnumber = false; }
      if (o instanceof Array && isnumber)
        Module["_tk_j_set"](Lp, tblref, Module._toH(+k + 1), Module._toH(v));
      else
        Module["_tk_j_set"](Lp, tblref, Module._toH(k), Module._toH(v));
    }

  }));
})

EM_JS(void, tk_js_register_ref, (int vh, int tblref), {
  var v = Module._tkh[vh];
  Module["FINALIZERS"].register(v, tblref);
})

EM_JS(void, tk_js_register_ref_thread, (int vh, int tblref, int thread_ref), {
  var v = Module._tkh[vh];
  Module["FINALIZERS"].register(v, { ref: tblref, thread_ref: thread_ref });
})

EM_JS(int, tk_js_make_function_proxy, (int Lp, int fnref), {
  return Module._toH(new Proxy(function () {}, {
    apply: function (_, this_, args) {
      args.unshift(this_);
      var ah = Module._toH(args);
      var rh = Module["_tk_j_call"](Lp, fnref, ah);
      var rv = Module._tkh[rh];
      Module._rel(rh);
      return rv;
    }
  }));
})

EM_JS(void, tk_js_promise_then, (int mainLp, int fref, int vh, int fh), {
  var v = Module._tkh[vh];
  var f = Module._tkh[fh];
  var cleanup = function () { Module["_tk_val_ref_delete"](mainLp, fref); };
  v.then(
    function () {
      var args = Array.prototype.slice.call(arguments);
      args.unshift(true);
      try {
        var r = f.apply(null, args);
        cleanup();
        return r;
      } catch (e) {
        cleanup();
        throw e;
      }
    },
    function () {
      var args = Array.prototype.slice.call(arguments);
      args.unshift(false);
      try {
        var r = f.apply(null, args);
        cleanup();
        return r;
      } catch (e) {
        cleanup();
        setTimeout(function () { throw e; });
      }
    }
  );
})

static inline void tk_web_set_ephemeron (lua_State *L, int iu, int ie)
{
  luaL_checktype(L, iu, LUA_TUSERDATA);
  lua_pushvalue(L, iu);
  lua_insert(L, -2);
  lua_rawgeti(L, LUA_REGISTRYINDEX, TK_WEB_EPHEMERON_IDX);
  lua_pushvalue(L, -3);
  lua_gettable(L, -2);
  if (lua_type(L, -1) == LUA_TNIL) {
    lua_pop(L, 1);
    lua_pushvalue(L, -3);
    lua_newtable(L);
    lua_settable(L, -3);
    lua_pushvalue(L, -3);
    lua_gettable(L, -2);
  }
  lua_pushinteger(L, ie);
  lua_pushvalue(L, -4);
  lua_settable(L, -3);
  lua_pop(L, 4);
}

static inline int tk_web_get_ephemeron (lua_State *L, int iu, int ie)
{
  lua_pushvalue(L, iu);
  lua_rawgeti(L, LUA_REGISTRYINDEX, TK_WEB_EPHEMERON_IDX);
  lua_insert(L, -2);
  lua_gettable(L, -2);
  if (lua_type(L, -1) == LUA_TNIL) {
    lua_remove(L, -2);
    return LUA_TNIL;
  } else {
    lua_pushinteger(L, ie);
    lua_gettable(L, -2);
    lua_remove(L, -2);
    lua_remove(L, -2);
    return lua_type(L, -1);
  }
}

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

static inline int tk_web_isarray (lua_State *L, int i) {
  size_t tlen = lua_objlen(L, i);
  if (tlen > 0) {
    return 1;
  } else {
    lua_pushvalue(L, i);
    lua_pushnil(L);
    if (lua_next(L, -2) == 0) {
      lua_pop(L, 1);
      return 1;
    } else {
      lua_pop(L, 3);
      return 0;
    }
  }
}

static inline void tk_web_increment_refn (lua_State *L) {
  lua_rawgeti(L, LUA_REGISTRYINDEX, IDX_REF_TBL);
  lua_getfield(L, -1, "n");
  int n = lua_type(L, -1) == LUA_TNIL ? 1 : (int)lua_tointeger(L, -1) + 1;
  lua_pop(L, 1);
  lua_pushinteger(L, n);
  lua_setfield(L, -2, "n");
  lua_pop(L, 1);
}

static inline void tk_web_decrement_refn (lua_State *L) {
  lua_rawgeti(L, LUA_REGISTRYINDEX, IDX_REF_TBL);
  lua_getfield(L, -1, "n");
  int n = lua_type(L, -1) == LUA_TNIL ? 1 : (int)lua_tointeger(L, -1) - 1;
  lua_pop(L, 1);
  lua_pushinteger(L, n);
  lua_setfield(L, -2, "n");
  lua_pop(L, 1);
}

static inline int handle_ref (lua_State *L, int it) {
  it = tk_lua_absindex(L, it);
  lua_rawgeti(L, LUA_REGISTRYINDEX, IDX_REF_TBL);
  lua_pushvalue(L, it);
  int ref = luaL_ref(L, -2);
  lua_pop(L, 1);
  tk_web_increment_refn(L);
  return ref;
}

static inline int handle_get_ref (lua_State *L, int ref) {
  lua_rawgeti(L, LUA_REGISTRYINDEX, IDX_REF_TBL);
  lua_pushinteger(L, ref);
  lua_gettable(L, -2);
  int t = lua_type(L, -1);
  lua_remove(L, -2);
  return t != LUA_TNIL;
}

static inline int peek_handle (lua_State *L, int i) {
  if (!mtx_to_mtv(L, i))
    return TK_UNDEFINED;
  int *hp = (int *) lua_touserdata(L, -1);
  lua_pop(L, 1);
  return hp ? *hp : TK_UNDEFINED;
}

static inline void push_handle (lua_State *L, int h, int uv) {

  int n = lua_gettop(L);

  if (uv == INT_MIN)
    lua_pushnil(L);
  else
    lua_pushvalue(L, uv);

  int *hp = (int *) lua_newuserdata(L, sizeof(int));
  *hp = h;

  lua_insert(L, -2);
  tk_web_set_ephemeron(L, -2, 2);

  luaL_getmetatable(L, MTV);
  lua_setmetatable(L, -2);

  assert(lua_gettop(L) == n + 1);
}

static inline int mtx_to_mtv (lua_State *L, int iv) {

  int n = lua_gettop(L);
  int i_val = tk_lua_absindex(L, iv);

  if (tk_web_testudata(L, i_val, MTV) != NULL) {
    lua_pushvalue(L, i_val);
    return 1;
  }

  if ((tk_web_testudata(L, i_val, MTO) != NULL) ||
      (tk_web_testudata(L, i_val, MTF) != NULL) ||
      (tk_web_testudata(L, i_val, MTP) != NULL) ||
      (tk_web_testudata(L, i_val, MTA) != NULL)) {
    assert(tk_web_get_ephemeron(L, i_val, 1) == LUA_TUSERDATA);
    assert(mtx_to_mtv(L, -1));
    lua_remove(L, -2);
    assert(lua_gettop(L) == n + 1);
    return 1;
  } else {
    assert(lua_gettop(L) == n);
    return 0;
  }
}

static inline int mtx_to_lua (lua_State *L, int iv) {

  int t = lua_type(L, iv);
  if (t != LUA_TLIGHTUSERDATA && t != LUA_TUSERDATA) {
    lua_pushvalue(L, iv);
    return 1;
  }

  if (!mtx_to_mtv(L, iv)) {
    return 0;
  }

  if (tk_web_get_ephemeron(L, -1, 2) <= LUA_TNIL) {
    lua_pop(L, 2);
    return 0;
  } else {
    lua_remove(L, -2);
    return 1;
  }
}

static inline void push_mtx (lua_State *L, int iv, const char *mtx) {
  lua_pushvalue(L, iv);
  lua_newuserdata(L, 0);
  lua_insert(L, -2);
  tk_web_set_ephemeron(L, -2, 1);
  luaL_getmetatable(L, mtx);
  lua_setmetatable(L, -2);
}

static inline void args_to_handles (lua_State *L, int n) {
  int argc = n < 0 ? lua_gettop(L) : n;
  for (int i = -argc; i < 0; i ++) {
    lua_to_handle(L, i, 0);
    lua_replace(L, i - 1);
  }
}

#define TK_SCRATCH_INIT 1024
#define TK_SCRATCH_MAX (64 * 1024 * 1024)

static char *tk_scratch = NULL;
static int tk_scratch_size = 0;

static inline void tk_scratch_init (void) {
  if (!tk_scratch) {
    tk_scratch = (char *)malloc(TK_SCRATCH_INIT);
    tk_scratch_size = TK_SCRATCH_INIT;
  }
}

static inline char *tk_scratch_get (int needed) {
  tk_scratch_init();
  if (needed <= tk_scratch_size)
    return tk_scratch;
  if (needed <= TK_SCRATCH_MAX) {
    free(tk_scratch);
    tk_scratch = (char *)malloc(needed);
    tk_scratch_size = needed;
    return tk_scratch;
  }
  return (char *)malloc(needed);
}

static inline void tk_scratch_free (char *buf) {
  if (buf != tk_scratch)
    free(buf);
}

static inline void push_js_string (lua_State *L, int h) {
  tk_scratch_init();
  int len = tk_js_string_to_buf(h, tk_scratch, tk_scratch_size);
  if (len >= 0) {
    lua_pushlstring(L, tk_scratch, len);
    return;
  }
  int needed = -len;
  char *buf = tk_scratch_get(needed);
  len = tk_js_string_to_buf(h, buf, needed);
  lua_pushlstring(L, buf, len);
  tk_scratch_free(buf);
}

static inline void object_to_lua (lua_State *L, int h, int iv, int recurse) {

  iv = tk_lua_absindex(L, iv);

  if (tk_js_is_null(h)) {
    lua_pushnil(L);
    return;
  }

  if (tk_js_is_uint8array(h)) {
    push_mtx(L, iv, MTA);
    return;
  }

  if (tk_js_is_promise(h)) {
    push_mtx(L, iv, MTP);
  } else if (!recurse) {
    push_mtx(L, iv, MTO);
  } else {
    int isArray = tk_js_is_array(h);
    int isPlainObject = tk_js_is_plain_object(h);
    if (isArray) {
      lua_newtable(L);
      int m = tk_js_array_length(h);
      for (int i = 0; i < m; i ++) {
        int eh = tk_js_array_get(h, i);
        lua_pushinteger(L, i + 1);
        push_handle(L, eh, INT_MIN);
        handle_to_lua(L, -1, 1, 0);
        lua_remove(L, -2);
        lua_settable(L, -3);
      }
    } else if (isPlainObject) {
      lua_newtable(L);
      int ksh = tk_js_object_keys(h);
      int m = tk_js_array_length(ksh);
      for (int i = 0; i < m; i ++) {
        int kh = tk_js_array_get(ksh, i);
        int vh = tk_js_object_get(h, kh);
        push_handle(L, kh, INT_MIN);
        handle_to_lua(L, -1, 1, 0);
        push_handle(L, vh, INT_MIN);
        handle_to_lua(L, -1, 1, 0);
        lua_remove(L, -2);
        lua_remove(L, -3);
        lua_settable(L, -3);
      }
      tk_js_rel(ksh);
    } else {
      lua_pushvalue(L, iv);
    }
  }
}

static inline void number_to_lua (lua_State *L, int h) {
  if (tk_js_is_integer(h)) {
    lua_pushnumber(L, (lua_Number) tk_js_to_double(h));
  } else {
    lua_pushnumber(L, (lua_Number) tk_js_to_double(h));
  }
}

static inline void bigint_to_lua (lua_State *L, int h) {
  int64_t n = tk_js_bigint_to_number((int)(intptr_t)L, h);
  lua_pushinteger(L, (lua_Integer) n);
}

static inline void function_to_lua_proxy (lua_State *L, int iv) {
  iv = tk_lua_absindex(L, iv);
  push_mtx(L, iv, MTF);
}

static inline int mt_lua (lua_State *L)
{
  lua_settop(L, 2);
  int recurse = lua_toboolean(L, 2);
  handle_to_lua(L, 1, recurse, 0);
  return 1;
}

static inline void handle_to_lua (lua_State *L, int iv, int recurse, int force_wrap)
{
  if (!force_wrap && mtx_to_lua(L, iv)) {
    return;
  }

  int h = peek_handle(L, iv);
  int type = tk_js_typeof_id(h);

  if (type == TK_TYPE_STRING) {
    push_js_string(L, h);
  } else if (type == TK_TYPE_BOOLEAN) {
    lua_pushboolean(L, tk_js_to_bool(h));
  } else if (type == TK_TYPE_NUMBER) {
    number_to_lua(L, h);
  } else if (type == TK_TYPE_BIGINT) {
    bigint_to_lua(L, h);
  } else if (type == TK_TYPE_OBJECT) {
    object_to_lua(L, h, iv, recurse);
  } else if (type == TK_TYPE_FUNCTION) {
    function_to_lua_proxy(L, iv);
  } else {
    lua_pushnil(L);
  }
}

static inline void table_to_handle (lua_State *L, int i, int recurse) {

  int i_tbl = tk_lua_absindex(L, i);
  int isarray = tk_web_isarray(L, i);

  if (!recurse) {

    int tblref = handle_ref(L, i_tbl);

    int thread_ref = LUA_NOREF;
    int is_main = lua_pushthread(L);
    if (!is_main) {
      thread_ref = handle_ref(L, -1);
    }
    lua_pop(L, 1);

    int ph = tk_js_make_table_proxy((int)(intptr_t)L, tblref, isarray);
    push_handle(L, ph, i_tbl);

    int vh = peek_handle(L, -1);

    if (thread_ref == LUA_NOREF) {
      tk_js_register_ref(vh, tblref);
    } else {
      tk_js_register_ref_thread(vh, tblref, thread_ref);
    }

  } else if (isarray) {

    int len = (int)lua_objlen(L, i_tbl);
    int ah = tk_js_new_array();
    lua_pushvalue(L, i_tbl);

    for (int j = 1; j <= len; j ++) {
      lua_pushinteger(L, j);
      lua_gettable(L, -2);
      lua_to_handle(L, -1, 1);
      int eh = peek_handle(L, -1);
      int newh = EM_ASM_INT({ return Module._cloneH($0); }, eh);
      tk_js_array_set(ah, j - 1, newh);
      tk_js_rel(newh);
      lua_pop(L, 2);
    }

    lua_pop(L, 1);
    push_handle(L, ah, INT_MIN);

  } else {

    lua_pushvalue(L, i_tbl);
    int oh = tk_js_new_object();

    lua_pushnil(L);
    while (lua_next(L, -2) != 0) {
      lua_to_handle(L, -2, 1);
      lua_to_handle(L, -2, 1);
      int kh = peek_handle(L, -2);
      int vh = peek_handle(L, -1);
      int newkh = EM_ASM_INT({ return Module._cloneH($0); }, kh);
      int newvh = EM_ASM_INT({ return Module._cloneH($0); }, vh);
      tk_js_object_set(oh, newkh, newvh);
      tk_js_rel(newkh);
      tk_js_rel(newvh);
      lua_pop(L, 3);
    }

    lua_pop(L, 1);
    push_handle(L, oh, INT_MIN);
  }
}

static inline void function_to_handle (lua_State *L, int i) {

  int i_fn = tk_lua_absindex(L, i);
  int fnref = handle_ref(L, i_fn);

  int thread_ref = LUA_NOREF;
  int is_main = lua_pushthread(L);
  if (!is_main) {
    thread_ref = handle_ref(L, -1);
  }
  lua_pop(L, 1);

  int ph = tk_js_make_function_proxy((int)(intptr_t)L, fnref);
  push_handle(L, ph, i_fn);

  int vh = peek_handle(L, -1);

  if (thread_ref == LUA_NOREF) {
    tk_js_register_ref(vh, fnref);
  } else {
    tk_js_register_ref_thread(vh, fnref, thread_ref);
  }
}

static inline int lua_to_handle (lua_State *L, int i, int recurse) {

  int type = lua_type(L, i);

  if (type == LUA_TSTRING) {
    size_t slen;
    const char *s = lua_tolstring(L, i, &slen);
    int h = tk_js_lstring(s, (int)slen);
    push_handle(L, h, INT_MIN);

  } else if (type == LUA_TNUMBER) {
    int h = tk_js_number(lua_tonumber(L, i));
    push_handle(L, h, INT_MIN);

  } else if (type == LUA_TBOOLEAN) {
    int h = tk_js_bool(lua_toboolean(L, i));
    push_handle(L, h, INT_MIN);

  } else if (type == LUA_TUSERDATA || type == LUA_TLIGHTUSERDATA || type == LUA_TTHREAD) {
    lua_pushvalue(L, i);

  } else if (type == LUA_TNIL) {
    push_handle(L, TK_UNDEFINED, INT_MIN);

  } else if (type == LUA_TTABLE) {
    table_to_handle(L, i, recurse);

  } else if (type == LUA_TFUNCTION) {
    function_to_handle(L, i);

  } else {
    push_handle(L, TK_UNDEFINED, INT_MIN);
  }

  return 1;
}

static inline int lua_val_to_new_handle (lua_State *L, int i, int recurse) {
  int type = lua_type(L, i);

  if (type == LUA_TUSERDATA || type == LUA_TLIGHTUSERDATA || type == LUA_TTHREAD) {
    int h = peek_handle(L, i);
    return EM_ASM_INT({ return Module._cloneH($0); }, h);
  }

  lua_to_handle(L, i, recurse);
  int h = peek_handle(L, -1);
  int newh = EM_ASM_INT({ return Module._cloneH($0); }, h);
  lua_pop(L, 1);
  return newh;
}

static inline int mtv_gc (lua_State *L) {
  int *hp = (int *) lua_touserdata(L, -1);
  if (hp) {
    tk_js_rel(*hp);
  }
  return 0;
}

static inline int mtv_eq (lua_State *L) {
  int h0 = peek_handle(L, -1);
  int h1 = peek_handle(L, -2);
  lua_pushboolean(L, tk_js_eq(h0, h1));
  return 1;
}

static inline int mtv_lt (lua_State *L) {
  int h0 = peek_handle(L, -1);
  int h1 = peek_handle(L, -2);
  lua_pushboolean(L, tk_js_lt(h0, h1));
  return 1;
}

static inline int mtv_le (lua_State *L) {
  int h0 = peek_handle(L, -1);
  int h1 = peek_handle(L, -2);
  lua_pushboolean(L, tk_js_le(h0, h1));
  return 1;
}

static inline int mtv_add (lua_State *L) {
  int h0 = peek_handle(L, -1);
  int h1 = peek_handle(L, -2);
  int rh = tk_js_add(h0, h1);
  push_handle(L, rh, INT_MIN);
  handle_to_lua(L, -1, 0, 0);
  return 1;
}

static inline int mtv_sub (lua_State *L) {
  int h0 = peek_handle(L, -1);
  int h1 = peek_handle(L, -2);
  int rh = tk_js_sub(h0, h1);
  push_handle(L, rh, INT_MIN);
  handle_to_lua(L, -1, 0, 0);
  return 1;
}

static inline int mtv_mul (lua_State *L) {
  int h0 = peek_handle(L, -1);
  int h1 = peek_handle(L, -2);
  int rh = tk_js_mul(h0, h1);
  push_handle(L, rh, INT_MIN);
  handle_to_lua(L, -1, 0, 0);
  return 1;
}

static inline int mtv_div (lua_State *L) {
  int h0 = peek_handle(L, -1);
  int h1 = peek_handle(L, -2);
  int rh = tk_js_div(h0, h1);
  push_handle(L, rh, INT_MIN);
  handle_to_lua(L, -1, 0, 0);
  return 1;
}

static inline int mtv_mod (lua_State *L) {
  int h0 = peek_handle(L, -1);
  int h1 = peek_handle(L, -2);
  int rh = tk_js_mod(h0, h1);
  push_handle(L, rh, INT_MIN);
  handle_to_lua(L, -1, 0, 0);
  return 1;
}

static inline int mtv_pow (lua_State *L) {
  int h0 = peek_handle(L, -1);
  int h1 = peek_handle(L, -2);
  int rh = tk_js_pow(h0, h1);
  push_handle(L, rh, INT_MIN);
  handle_to_lua(L, -1, 0, 0);
  return 1;
}

static inline int mtv_unm (lua_State *L) {
  int h0 = peek_handle(L, -1);
  int rh = tk_js_unm(h0);
  push_handle(L, rh, INT_MIN);
  handle_to_lua(L, -1, 0, 0);
  return 1;
}

static inline int mtv_tostring (lua_State *L) {
  int h0 = peek_handle(L, -1);
  int sh = tk_js_tostring_val(h0);
  push_js_string(L, sh);
  tk_js_rel(sh);
  return 1;
}

EMSCRIPTEN_KEEPALIVE
int tk_j_arg (int Lp, int i) {
  lua_State *L = (lua_State *)(intptr_t) Lp;
  int h = peek_handle(L, i);
  return EM_ASM_INT({ return Module._cloneH($0); }, h);
}

EMSCRIPTEN_KEEPALIVE
int tk_j_args (int Lp, int arg0, int argc) {
  return EM_ASM_INT(({
    return Module._toH({
      [Symbol.iterator]: function () {
        var i = 0;
        return {
          next: function () {
            if (i == $2) {
              return { done: true };
            } else {
              i = i + 1;
              var arg = Module["_tk_j_arg"]($0, i + $1 - 1);
              var val = Module._tkh[arg];
              Module._rel(arg);
              return { done: false, value: val };
            }
          }
        };
      }
    })
  }), Lp, arg0, argc);
}

EMSCRIPTEN_KEEPALIVE
void tk_j_own_keys (int Lp, int it, int keysh) {

  lua_State *L = (lua_State *)(intptr_t) Lp;
  int top = lua_gettop(L);

  assert(handle_get_ref(L, it));
  int isarray = tk_web_isarray(L, -1);
  lua_pop(L, 1);

  if (isarray)
    EM_ASM(({
      var keys = Module._tkh[$0];
      keys.push("length");
    }), keysh);

  assert(handle_get_ref(L, it));
  lua_pushnil(L);
  while (lua_next(L, -2) != 0) {
    lua_to_handle(L, -2, 0);
    int kh = peek_handle(L, -1);
    EM_ASM(({
      var keys = Module._tkh[$0];
      var key = Module._tkh[$1];
      if ($2 && typeof key == "number")
        keys.push(String(key - 1));
      else
        keys.push(String(key));
    }), keysh, kh, isarray);
    lua_pop(L, 2);
  }

  lua_settop(L, top);
}

EMSCRIPTEN_KEEPALIVE
int tk_j_get (int Lp, int i, int k, int is_str) {

  lua_State *L = (lua_State *)(intptr_t) Lp;
  int top = lua_gettop(L);

  assert(handle_get_ref(L, i));

  if (is_str) {
    char *kk = (char *)(intptr_t) k;
    lua_pushstring(L, kk);
    free(kk);
  } else {
    push_handle(L, k, INT_MIN);
    handle_to_lua(L, -1, 0, 0);
    lua_remove(L, -2);
  }

  lua_gettable(L, -2);
  lua_to_handle(L, -1, 0);
  int h = peek_handle(L, -1);
  int newh = EM_ASM_INT({ return Module._cloneH($0); }, h);

  lua_settop(L, top);
  return newh;
}

EMSCRIPTEN_KEEPALIVE
void tk_j_set (int Lp, int i, int k, int v) {
  lua_State *L = (lua_State *)(intptr_t) Lp;
  push_handle(L, k, INT_MIN);
  push_handle(L, v, INT_MIN);
  handle_to_lua(L, -2, 0, 0);
  handle_to_lua(L, -2, 0, 0);
  assert(handle_get_ref(L, i));
  lua_insert(L, -3);
  lua_settable(L, -3);
  lua_pop(L, 3);
}

EMSCRIPTEN_KEEPALIVE
int tk_j_call (int Lp, int i, int argsh) {

  lua_State *L = (lua_State *)(intptr_t) Lp;
  int top = lua_gettop(L);

  assert(handle_get_ref(L, i));

  int argc = tk_js_array_length(argsh);

  for (int j = 0; j < argc; j ++) {
    int ah = tk_js_array_get(argsh, j);
    push_handle(L, ah, INT_MIN);
    handle_to_lua(L, -1, 0, 0);
    lua_remove(L, -2);
  }
  tk_js_rel(argsh);

  int t = lua_gettop(L) - argc - 1;
  int rc = lua_pcall(L, argc, LUA_MULTRET, 0);

  if (rc != 0) {

    lua_to_handle(L, -1, 0);
    int h = peek_handle(L, -1);
    int newh = EM_ASM_INT({ return Module._cloneH($0); }, h);
    EM_ASM(({
      var v = Module._tkh[$0];
      Module._rel($0);
      throw v;
    }), newh);

    lua_settop(L, top);
    return TK_UNDEFINED;

  } else if (lua_gettop(L) > t) {

    args_to_handles(L, lua_gettop(L) - t);
    int h = peek_handle(L, -1);
    int newh = EM_ASM_INT({ return Module._cloneH($0); }, h);

    lua_settop(L, top);
    return newh;

  } else {

    lua_settop(L, top);
    return TK_UNDEFINED;

  }
}

EMSCRIPTEN_KEEPALIVE
void tk_j_error (int Lp, int ep) {
  lua_State *L = (lua_State *)(intptr_t) Lp;
  push_handle(L, ep, INT_MIN);
  handle_to_lua(L, -1, 0, 0);
  lua_remove(L, -2);
  lua_error(L);
}

EMSCRIPTEN_KEEPALIVE
int tk_j_len (int Lp, int i) {
  lua_State *L = (lua_State *)(intptr_t) Lp;
  assert(handle_get_ref(L, i));
  lua_Integer len = lua_objlen(L, -1);
  lua_pop(L, 1);
  return (int) len;
}

EMSCRIPTEN_KEEPALIVE
int tk_j_tostring (int Lp, int i) {
  lua_State *L = (lua_State *)(intptr_t) Lp;
  int top = lua_gettop(L);
  lua_getglobal(L, "tostring");
  assert(handle_get_ref(L, i));
  lua_call(L, 1, 1);
  size_t slen;
  const char *str = lua_tolstring(L, -1, &slen);
  int h = tk_js_lstring(str, (int)slen);
  lua_settop(L, top);
  return h;
}

EMSCRIPTEN_KEEPALIVE
int tk_j_valueof (int Lp, int i) {
  lua_State *L = (lua_State *)(intptr_t) Lp;
  int top = lua_gettop(L);
  assert(handle_get_ref(L, i));
  lua_to_handle(L, -1, 1);
  int h = peek_handle(L, -1);
  int newh = EM_ASM_INT({ return Module._cloneH($0); }, h);
  lua_settop(L, top);
  return newh;
}

EMSCRIPTEN_KEEPALIVE
void tk_val_ref_delete (int Lp, int ref) {
  lua_State *L = (lua_State *)(intptr_t) Lp;
  lua_rawgeti(L, LUA_REGISTRYINDEX, IDX_REF_TBL);
  luaL_unref(L, -1, ref);
  lua_pop(L, 1);
  tk_web_decrement_refn(L);
}

static inline int mt_call (lua_State *L) {

  int n = lua_gettop(L);

  if (n == 3) {
    lua_remove(L, -3);
    int recurse = lua_toboolean(L, -1);
    lua_pop(L, 1);
    lua_to_handle(L, -1, recurse);
    return 1;
  } else if (n == 2) {
    lua_remove(L, -2);
    lua_to_handle(L, -1, 0);
    return 1;
  } else {
    luaL_error(L, "expected 1 or 2 arguments to val(...)");
    return 0;
  }
}

static inline int mt_global (lua_State *L) {
  const char *str = luaL_checkstring(L, -1);
  int h = tk_js_global(str);
  push_handle(L, h, INT_MIN);
  lua_remove(L, -2);
  return 1;
}

static inline int mt_bytes (lua_State *L) {
  size_t size;
  const char *str = luaL_checklstring(L, -1, &size);
  int h = tk_js_bytes(str, (int)size);
  push_handle(L, h, -1);
  handle_to_lua(L, -1, 0, 1);
  return 1;
}

static inline int mt_class (lua_State *L) {
  lua_settop(L, 2);
  lua_to_handle(L, 1, 0);
  lua_to_handle(L, 2, 0);
  int configH = peek_handle(L, 3);
  int parentH = peek_handle(L, 4);
  int ch = tk_js_class(configH, parentH);
  push_handle(L, ch, INT_MIN);
  return 1;
}

static inline int mto_index (lua_State *L) {
  lua_pushvalue(L, -1);
  lua_rawgeti(L, LUA_REGISTRYINDEX, MTO_FNS);
  lua_insert(L, -2);
  lua_gettable(L, -2);
  if (lua_type(L, -1) != LUA_TNIL)
    return 1;
  lua_pop(L, 2);
  int oh = peek_handle(L, -2);
  if (lua_type(L, -1) == LUA_TSTRING) {
    int nh = tk_js_get_prop_cstr(oh, lua_tostring(L, -1));
    push_handle(L, nh, INT_MIN);
    handle_to_lua(L, -1, 0, 0);
    return 1;
  }
  lua_to_handle(L, -1, 0);
  lua_remove(L, -2);
  int kh = peek_handle(L, -1);
  int nh = tk_js_get_prop(oh, kh);
  lua_pop(L, 2);
  push_handle(L, nh, INT_MIN);
  handle_to_lua(L, -1, 0, 0);
  return 1;
}

static inline int mto_newindex (lua_State *L) {
  return mtv_set(L);
}

static inline int mto_instanceof (lua_State *L) {
  mtv_instanceof(L);
  handle_to_lua(L, -1, 0, 0);
  return 1;
}

static inline int mto_typeof (lua_State *L) {
  mtv_typeof(L);
  handle_to_lua(L, -1, 0, 0);
  return 1;
}

static inline int mtp_index (lua_State *L) {
  const char *key = lua_tostring(L, 2);
  if (key && strcmp(key, "await") == 0) {
    lua_getglobal(L, "__tk_await");
    if (lua_type(L, -1) == LUA_TFUNCTION)
      return 1;
    lua_pop(L, 1);
  }
  lua_rawgeti(L, LUA_REGISTRYINDEX, MTP_FNS);
  lua_pushvalue(L, 2);
  lua_gettable(L, -2);
  if (lua_type(L, -1) != LUA_TNIL)
    return 1;
  lua_pop(L, 2);
  return mto_index(L);
}

static inline int mtp_await (lua_State *L) {
  args_to_handles(L, -1);
  int vh = peek_handle(L, -2);
  int fh = peek_handle(L, -1);

  int fref = handle_ref(L, -1);

  int cloned_vh = EM_ASM_INT({ return Module._cloneH($0); }, vh);
  int cloned_fh = EM_ASM_INT({ return Module._cloneH($0); }, fh);

  tk_js_promise_then((int)(intptr_t)tk_web_main_L, fref, cloned_vh, cloned_fh);

  tk_js_rel(cloned_vh);
  tk_js_rel(cloned_fh);

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
  args_to_handles(L, -1);
  int h = peek_handle(L, -1);
  int len = tk_js_uint8array_length(h);
  char *buf = tk_scratch_get(len);
  tk_js_uint8array_copy_to(h, buf);
  lua_pushlstring(L, buf, len);
  tk_scratch_free(buf);
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
  handle_to_lua(L, -1, 0, 0);
  return 1;
}

static inline int mtf_new (lua_State *L) {
  mtv_new(L);
  handle_to_lua(L, -1, 0, 0);
  return 1;
}

static inline int mto_val (lua_State *L) {
  assert(mtx_to_mtv(L, -1));
  return 1;
}

static inline int mtv_lua (lua_State *L) {
  int n = lua_gettop(L);
  if (n == 2) {
    int recurse = lua_toboolean(L, -1);
    handle_to_lua(L, -2, recurse, 0);
    return 1;
  } else if (n == 1) {
    handle_to_lua(L, -1, 0, 0);
    lua_remove(L, -2);
    return 1;
  } else {
    luaL_error(L, "expected 1 or 2 arguments to val:lua(...)");
    return 0;
  }
}

static inline int mtv_get (lua_State *L) {
  args_to_handles(L, -1);
  int kh = peek_handle(L, -1);
  int oh = peek_handle(L, -2);
  int nh = EM_ASM_INT({
    return Module._toH(Module._tkh[$0][Module._tkh[$1]]);
  }, oh, kh);
  push_handle(L, nh, INT_MIN);
  return 1;
}

static inline int mtv_set (lua_State *L) {
  args_to_handles(L, -1);
  int vh = peek_handle(L, -1);
  int kh = peek_handle(L, -2);
  int oh = peek_handle(L, -3);
  EM_ASM(({
    Module._tkh[$0][Module._tkh[$1]] = Module._tkh[$2];
  }), oh, kh, vh);
  return 0;
}

static inline int mto_len (lua_State *L) {
  args_to_handles(L, -1);
  int vh = peek_handle(L, 1);
  lua_pushinteger(L, tk_js_len(vh));
  return 1;
}

static inline int mtv_typeof (lua_State *L) {
  args_to_handles(L, -1);
  int vh = peek_handle(L, -1);
  int th = tk_js_typeof_string(vh);
  push_handle(L, th, INT_MIN);
  return 1;
}

static inline int mtv_instanceof (lua_State *L) {
  args_to_handles(L, -1);
  int vh = peek_handle(L, -2);
  int ch = peek_handle(L, -1);
  lua_pushboolean(L, tk_js_instanceof(vh, ch));
  lua_to_handle(L, -1, 0);
  return 1;
}

static inline int mtv_call (lua_State *L) {
  args_to_handles(L, -1);
  int n = lua_gettop(L);
  int fh = peek_handle(L, -n);
  int th = lua_type(L, -n + 1) == LUA_TNIL
    ? TK_UNDEFINED
    : peek_handle(L, -n + 1);
  int rh = EM_ASM_INT(({
    try {
      var fn = Module._tkh[$1];
      var ths = Module._tkh[$2];
      if (ths != undefined)
        fn = fn.bind(ths);
      var argsh = Module["_tk_j_args"]($0, $3, $4);
      var args = Module._tkh[argsh];
      Module._rel(argsh);
      var a = [];
      for (var x of args) a.push(x);
      var r = fn.apply(null, a);
      return Module._toH(r);
    } catch (e) {
      var eh = Module._toH(e);
      Module["_tk_j_error"]($0, eh);
      return 0;
    }
  }), (int)(intptr_t)L, fh, th, -n + 2, n - 2);
  push_handle(L, rh, INT_MIN);
  return 1;
}

static inline int mtv_new (lua_State *L) {
  args_to_handles(L, -1);
  int n = lua_gettop(L);
  int vh = peek_handle(L, -n);
  int rh = EM_ASM_INT(({
    var obj = Module._tkh[$1];
    var argsh = Module["_tk_j_args"]($0, $2, $3);
    var args = Module._tkh[argsh];
    Module._rel(argsh);
    var a = [];
    for (var x of args) a.push(x);
    return Module._toH(new obj(...a));
  }), (int)(intptr_t)L, vh, -n + 1, n - 1);
  push_handle(L, rh, INT_MIN);
  return 1;
}

static luaL_Reg mtp_fns[] = {
  { "await", mtp_await },
  { NULL, NULL }
};

static luaL_Reg mta_fns[] = {
  { "str", mta_str },
  { NULL, NULL }
};

static luaL_Reg mtf_fns[] = {
  { "new", mtf_new },
  { NULL, NULL }
};

static luaL_Reg mto_fns[] = {
  { "typeof", mto_typeof },
  { "instanceof", mto_instanceof },
  { "val", mto_val },
  { NULL, NULL }
};

static luaL_Reg mtv_fns[] = {
  { "lua", mtv_lua },
  { "get", mtv_get },
  { "set", mtv_set },
  { "typeof", mtv_typeof },
  { "instanceof", mtv_instanceof },
  { "call", mtv_call },
  { "new", mtv_new },
  { NULL, NULL }
};

static luaL_Reg mt_fns[] = {
  { "global", mt_global },
  { "lua", mt_lua },
  { "bytes", mt_bytes },
  { "class", mt_class },
  { NULL, NULL }
};

static void set_common_obj_mtfns (lua_State *L) {

  lua_pushcfunction(L, mto_len);
  lua_setfield(L, -2, "__len");

  lua_pushcfunction(L, mto_newindex);
  lua_setfield(L, -2, "__newindex");

  lua_pushcfunction(L, mtv_add);
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
  tk_web_main_L = L;
  tk_js_init((int)(intptr_t)L);

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

  lua_newtable(L);
  lua_newtable(L);
  lua_pushstring(L, "k");
  lua_setfield(L, -2, "__mode");
  lua_setmetatable(L, -2);
  TK_WEB_EPHEMERON_IDX = luaL_ref(L, LUA_REGISTRYINDEX);
  lua_rawgeti(L, LUA_REGISTRYINDEX, TK_WEB_EPHEMERON_IDX);
  lua_setfield(L, -2, "EPHEMERON_IDX");

  return 1;
}
