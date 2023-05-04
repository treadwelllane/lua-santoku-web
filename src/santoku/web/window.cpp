// TODO: Would it be possible to simply wrap
// val.h in lua and then build window from lua
// instead of c++? 

extern "C" {
  #include "lua.h"
  #include "lauxlib.h"
  int luaopen_santoku_web_window (lua_State *L);
}

#include "emscripten.h"
#include "emscripten/val.h"

using namespace std;
using namespace emscripten;

#define debug(...) printf("%s:%d\t", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n");

int index (lua_State *);
void wrap_val (lua_State *, val *, val, const char *);

EM_JS(EM_VAL, applyjs,  (const char *nameh, EM_VAL objh, EM_VAL args), {
  var args = Emval.toValue(args);
  var name = UTF8ToString(nameh);
  var obj = Emval.toValue(objh);
  return Emval.toHandle(obj[name](...args));
})

  /* int argc = lua_gettop(L); */
  /* vector<val> argv; */
  /* for (int i = 1; i <= argc; i ++) { */
  /*   int type = lua_type(L, -i); */
  /*   if (type == LUA_TNIL) { */
  /*     argv.push_back(val::undefined()); */
  /*   } else if (type == LUA_TBOOLEAN) { */
  /*     argv.push_back(val(lua_toboolean(L, -i))); */
  /*   } else if (type == LUA_TNUMBER) { */
  /*     argv.push_back(val(luaL_checknumber(L, -i))); */
  /*   } else if (type == LUA_TSTRING) { */
  /*     argv.push_back(val(luaL_checkstring(L, -i))); */
  /*   /1* } else if (type == LUA_TTABLE) { *1/ */
  /*   /1* } else if (type == LUA_TFUNCTION) { *1/ */
  /*   } else if (type == LUA_TUSERDATA) { */
  /*     lua_getiuservalue(L, -i, 1); */
  /*     val *v = (val *)lua_touserdata(L, -i); */
  /*     lua_pop(L, 1); */
  /*     argv.push_back(*v); */
  /*   } else { */
  /*     debug("invalid type %d", type); */
  /*   } */
  /* } */

// TODO: returns a js function that returns v
val jsconst (val v) {
  return val::undefined();
}

// TODO 
val *jsargs (lua_State *L) {
  val sym = val::global("Symbol")["iterator"];
  val obj = val::object();
  val iter = val::object();
  obj.set(sym, jsconst(iter));
  return new val(val::undefined());
}

int call (lua_State *L) {
  const char *name = luaL_checkstring(L, lua_upvalueindex(1));
  val *parent = (val *)lua_touserdata(L, lua_upvalueindex(2));
  val *args = jsargs(L);
  val *result = new val(val::take_ownership(applyjs(name, parent->as_handle(), args->as_handle())));
  wrap_val(L, result, val::undefined(), NULL);
  return 1;
}

// TODO: Check if null is handled correctly.
// TODO: How do we handle Infinity, NaN, etc?
void wrap_val (lua_State *L, val *vp, val parent, const char *name) {
  val v = *vp;
  string type = v.typeof().as<string>();
  if (type == "string") {
    lua_pushstring(L, v.as<string>().c_str());
  } else if (type == "number") {
    lua_pushnumber(L, v.as<float>());
  } else if (type == "boolean") {
    lua_pushboolean(L, v.as<bool>());
  } else if (type == "undefined") {
    lua_pushnil(L);
  } else if (type == "null") {
    lua_pushnil(L);
  } else if (type == "function") {
    lua_pushstring(L, name);
    lua_pushlightuserdata(L, new val(parent));
    lua_pushcclosure(L, call, 2);
  } else {
    lua_newuserdatauv(L, 0, 1);
    // TODO: do we need to eventually delete
    // this val? this might be a memory leak..
    lua_pushlightuserdata(L, new val(v));
    lua_setiuservalue(L, -2, 1);
    // TODO: re-use the same metatable instead
    // of createing a new one for each wrapped
    // val
    lua_newtable(L);
    lua_pushcfunction(L, index);
    lua_setfield(L, -2, "__index");
    lua_setmetatable(L, -2);
  }
}

int index (lua_State *L) {
  const char *name = luaL_checkstring(L, -1);
  lua_getiuservalue(L, -2, 1);
  val target = *((val *)lua_touserdata(L, -1));
  val next = target[name];
  lua_pop(L, 1);
  wrap_val(L, new val(next), target, name);
  return 1;
}

int luaopen_santoku_web_window (lua_State *L) {
  wrap_val(L, new val(val::global("window")), val::undefined(), NULL);
  return 1;
}
