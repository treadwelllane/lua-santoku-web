#include "lua.h"
#include "lauxlib.h"
#include "emscripten.h"

#include <stdio.h>
#include <stdint.h>

int luaopen_santoku_web_rpc (lua_State *);

extern int tk_val_peek (int Lp, int idx);
extern void tk_val_push (int Lp, int h);
extern void tk_val_push_r (int Lp, int h);
extern int tk_val_from_lua (int Lp, int idx, int recurse);

EM_JS(int, tk_rpc_send, (int Lp, int port_h, const char *method_ptr, int method_len, int first_arg_idx, int nargs), {
  var port = Module._tkh[port_h];
  var method = UTF8ToString(method_ptr, method_len);
  var ch = new MessageChannel();
  var args = [method, ch.port2];
  var transferables = [ch.port2];
  for (var i = 0; i < nargs; i++) {
    var h = Module._tk_val_from_lua(Lp, first_arg_idx + i, 1);
    var v = Module._tkh[h];
    Module._rel(h);
    args.push(v);
    if (v instanceof MessagePort || v instanceof ArrayBuffer ||
        v instanceof ReadableStream || v instanceof WritableStream ||
        v instanceof TransformStream)
      transferables.push(v);
  }
  var promise = new Promise(function (resolve, reject) {
    ch.port1.onmessage = function (ev) {
      ch.port1.close();
      var data = ev.data;
      if (data[0] === true) {
        resolve(data.slice(1));
      } else {
        reject(data[1]);
      }
    };
  });
  port.postMessage(args, transferables);
  return Module._toH(promise);
})

EM_JS(int, tk_rpc_extract, (int Lp, int ev_h, int port_slot_ref), {
  var ev = Module._tkh[ev_h];
  var data = ev.data;
  var method = data[0];
  var response_port = data[1];
  var port_h = Module._toH(response_port);
  Module._tkh[port_slot_ref] = port_h;
  var method_h = Module._toH(method);
  Module._tk_val_push(Lp, method_h);
  var nargs = data.length - 2;
  for (var i = 0; i < nargs; i++) {
    var arg_h = Module._toH(data[i + 2]);
    Module._tk_val_push_r(Lp, arg_h);
  }
  return nargs;
})

EM_JS(void, tk_rpc_respond, (int Lp, int port_h, int first_result, int nresults), {
  var port = Module._tkh[port_h];
  var response = [true];
  for (var i = 0; i < nresults; i++) {
    var h = Module._tk_val_from_lua(Lp, first_result + i, 1);
    var v = Module._tkh[h];
    Module._rel(h);
    response.push(v);
  }
  port.postMessage(response);
  port.close();
  Module._rel(port_h);
})

EM_JS(void, tk_rpc_respond_error, (int port_h, const char *msg_ptr, int msg_len), {
  var port = Module._tkh[port_h];
  var msg = UTF8ToString(msg_ptr, msg_len);
  port.postMessage([false, msg]);
  port.close();
  Module._rel(port_h);
})

EM_JS(void, tk_rpc_register_port, (int worker_h, int port_h), {
  var worker = Module._tkh[worker_h];
  var port = Module._tkh[port_h];
  var msg = { REGISTER_PORT: port };
  worker.postMessage(msg, [port]);
})

EM_JS(int, tk_rpc_create_port_async, (int worker_h), {
  var worker = Module._tkh[worker_h];
  var ch = new MessageChannel();
  var msg = { REGISTER_PORT: ch.port2 };
  worker.postMessage(msg, [ch.port2]);
  var promise = new Promise(function (resolve) {
    ch.port1.addEventListener("message", function handler(ev) {
      if (ev.data && ev.data.type === "port_ready") {
        ch.port1.removeEventListener("message", handler);
        resolve(ch.port1);
      }
    });
    ch.port1.start();
  });
  return Module._toH(promise);
})

static int rpc_call (lua_State *L) {
  int nargs = lua_gettop(L);
  int Lp = (int)(intptr_t)L;
  int port_h = tk_val_peek(Lp, 1);
  size_t method_len;
  const char *method = luaL_checklstring(L, 2, &method_len);
  int first_arg = 3;
  int argc = nargs - 2;
  int ph = tk_rpc_send(Lp, port_h, method, (int)method_len, first_arg, argc);
  tk_val_push(Lp, ph);
  return 1;
}

static int rpc_server_handler (lua_State *L) {
  int Lp = (int)(intptr_t)L;
  int ev_h = tk_val_peek(Lp, 1);
  int port_slot = EM_ASM_INT({ return Module._toH(null); });
  int nargs = tk_rpc_extract(Lp, ev_h, port_slot);
  int port_h = EM_ASM_INT({ return Module._tkh[$0]; }, port_slot);
  EM_ASM({ Module._rel($0); }, port_slot);
  int method_idx = 2;
  int first_arg_idx = 3;
  lua_pushvalue(L, lua_upvalueindex(1));
  lua_pushvalue(L, method_idx);
  lua_gettable(L, -2);
  if (lua_type(L, -1) == LUA_TNIL) {
    lua_pop(L, 2);
    size_t elen = 0;
    const char *method_str = lua_tolstring(L, method_idx, &elen);
    char buf[512];
    int len = snprintf(buf, sizeof(buf), "Property '%.*s' not found",
                       (int)elen, method_str ? method_str : "(nil)");
    tk_rpc_respond_error(port_h, buf, len);
    return 0;
  }
  lua_remove(L, -2);
  lua_insert(L, first_arg_idx);
  int rc = lua_pcall(L, nargs, LUA_MULTRET, 0);
  if (rc != 0) {
    size_t elen;
    const char *estr = lua_tolstring(L, -1, &elen);
    tk_rpc_respond_error(port_h, estr, (int)elen);
    lua_pop(L, 1);
    return 0;
  }
  int nresults = lua_gettop(L) - (first_arg_idx - 1);
  tk_rpc_respond(Lp, port_h, first_arg_idx, nresults);
  return 0;
}

static int rpc_server (lua_State *L) {
  luaL_checktype(L, 1, LUA_TTABLE);
  lua_pushvalue(L, 1);
  lua_pushcclosure(L, rpc_server_handler, 1);
  return 1;
}

static int rpc_register_port_fn (lua_State *L) {
  int Lp = (int)(intptr_t)L;
  int worker_h = tk_val_peek(Lp, 1);
  int port_h = tk_val_peek(Lp, 2);
  tk_rpc_register_port(worker_h, port_h);
  return 0;
}

static int rpc_create_port (lua_State *L) {
  int Lp = (int)(intptr_t)L;
  int worker_h = tk_val_peek(Lp, 1);
  int ph = tk_rpc_create_port_async(worker_h);
  tk_val_push(Lp, ph);
  return 1;
}

static luaL_Reg rpc_fns[] = {
  { "call", rpc_call },
  { "server", rpc_server },
  { "register_port", rpc_register_port_fn },
  { "create_port", rpc_create_port },
  { NULL, NULL }
};

int luaopen_santoku_web_rpc (lua_State *L) {
  lua_newtable(L);
  luaL_register(L, NULL, rpc_fns);
  return 1;
}
