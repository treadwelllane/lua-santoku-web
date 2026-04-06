#include "lua.h"
#include "lauxlib.h"
#include "emscripten.h"

#include <string.h>
#include <stdint.h>

#define DOM_CMD_BUF_SIZE  (64 * 1024)
#define DOM_STR_BUF_SIZE  (128 * 1024)
#define DOM_READ_CMD_SIZE (8 * 1024)
#define DOM_READ_RES_SIZE (64 * 1024)
#define DOM_READ_STR_SIZE (64 * 1024)

#define OP_TEXT         0x01
#define OP_HTML         0x02
#define OP_ATTR_SET     0x03
#define OP_ATTR_RM      0x04
#define OP_DATA         0x05
#define OP_STYLE        0x06
#define OP_CLASS_ADD    0x07
#define OP_CLASS_RM     0x08
#define OP_INSERT_ADJ   0x09
#define OP_REMOVE       0x0A
#define OP_REMOVE_KIDS  0x0B
#define OP_FOCUS        0x0C
#define OP_BLUR         0x0D
#define OP_POPOVER_ON   0x0E
#define OP_POPOVER_OFF  0x0F
#define OP_SCROLL       0x10

#define ROP_TEXT        0x80
#define ROP_ATTR        0x81
#define ROP_DATA        0x82
#define ROP_RECT        0x83
#define ROP_SCROLL      0x84
#define ROP_CURSOR      0x85
#define ROP_SELECTION   0x86
#define ROP_HAS_CLASS   0x87
#define ROP_ELEMENT_AT  0x88

static uint8_t cmd_buf[DOM_CMD_BUF_SIZE];
static uint8_t str_buf[DOM_STR_BUF_SIZE];
static uint32_t cmd_pos = 0;
static uint32_t str_pos = 0;
static uint32_t cmd_count = 0;

static uint8_t read_cmd_buf[DOM_READ_CMD_SIZE];
static uint8_t read_res_buf[DOM_READ_RES_SIZE];
static uint8_t read_str_buf[DOM_READ_STR_SIZE];
static uint32_t read_cmd_pos = 0;
static uint32_t read_cmd_count = 0;
static uint32_t read_res_pos = 0;
static uint32_t read_str_pos = 0;

EMSCRIPTEN_KEEPALIVE uint8_t *dom_get_cmd_buf (void) { return cmd_buf; }
EMSCRIPTEN_KEEPALIVE uint8_t *dom_get_str_buf (void) { return str_buf; }
EMSCRIPTEN_KEEPALIVE uint32_t dom_get_cmd_count (void) { return cmd_count; }
EMSCRIPTEN_KEEPALIVE uint32_t dom_get_cmd_pos (void) { return cmd_pos; }
EMSCRIPTEN_KEEPALIVE uint32_t dom_get_str_pos (void) { return str_pos; }

EMSCRIPTEN_KEEPALIVE uint8_t *dom_get_read_cmd_buf (void) { return read_cmd_buf; }
EMSCRIPTEN_KEEPALIVE uint8_t *dom_get_read_res_buf (void) { return read_res_buf; }
EMSCRIPTEN_KEEPALIVE uint8_t *dom_get_read_str_buf (void) { return read_str_buf; }
EMSCRIPTEN_KEEPALIVE uint32_t dom_get_read_cmd_count (void) { return read_cmd_count; }

static void write_u8 (uint8_t v) {
  if (cmd_pos < DOM_CMD_BUF_SIZE)
    cmd_buf[cmd_pos++] = v;
}

static void write_u32 (uint32_t v) {
  if (cmd_pos + 4 <= DOM_CMD_BUF_SIZE) {
    memcpy(cmd_buf + cmd_pos, &v, 4);
    cmd_pos += 4;
  }
}

static void write_i32 (int32_t v) {
  if (cmd_pos + 4 <= DOM_CMD_BUF_SIZE) {
    memcpy(cmd_buf + cmd_pos, &v, 4);
    cmd_pos += 4;
  }
}

static uint32_t write_str (const char *s, size_t len) {
  if (str_pos + len + 1 > DOM_STR_BUF_SIZE)
    return 0;
  uint32_t off = str_pos;
  memcpy(str_buf + str_pos, s, len);
  str_pos += (uint32_t)len;
  str_buf[str_pos++] = 0;
  return off;
}

static void read_write_u8 (uint8_t v) {
  if (read_cmd_pos < DOM_READ_CMD_SIZE)
    read_cmd_buf[read_cmd_pos++] = v;
}

static void read_write_u32 (uint32_t v) {
  if (read_cmd_pos + 4 <= DOM_READ_CMD_SIZE) {
    memcpy(read_cmd_buf + read_cmd_pos, &v, 4);
    read_cmd_pos += 4;
  }
}

static void dom_reset (void) {
  cmd_pos = 0;
  str_pos = 0;
  cmd_count = 0;
}

static void dom_read_reset (void) {
  read_cmd_pos = 0;
  read_cmd_count = 0;
  read_res_pos = 0;
  read_str_pos = 0;
}

EM_JS(void, dom_js_flush, (
  uint8_t *cmd_ptr, uint32_t cmd_len,
  uint8_t *str_ptr, uint32_t str_len,
  uint32_t count
), {
  Module.__tk_dom_flush(cmd_ptr, cmd_len, str_ptr, count);
})

EM_JS(void, dom_js_read_flush, (
  uint8_t *cmd_ptr, uint32_t cmd_len,
  uint8_t *str_ptr, uint32_t str_len,
  uint32_t count,
  uint8_t *res_ptr, uint32_t res_size,
  uint8_t *res_str_ptr, uint32_t res_str_size
), {
  Module.__tk_dom_read_flush(cmd_ptr, cmd_len, str_ptr, count, res_ptr, res_size, res_str_ptr, res_str_size);
})

static int l_dom_text (lua_State *L) {
  size_t id_len, val_len;
  const char *id = luaL_checklstring(L, 1, &id_len);
  const char *val = luaL_checklstring(L, 2, &val_len);
  write_u8(OP_TEXT);
  write_u32(write_str(id, id_len));
  write_u32(write_str(val, val_len));
  write_u32((uint32_t)val_len);
  cmd_count++;
  return 0;
}

static int l_dom_html (lua_State *L) {
  size_t id_len, val_len;
  const char *id = luaL_checklstring(L, 1, &id_len);
  const char *val = luaL_checklstring(L, 2, &val_len);
  write_u8(OP_HTML);
  write_u32(write_str(id, id_len));
  write_u32(write_str(val, val_len));
  write_u32((uint32_t)val_len);
  cmd_count++;
  return 0;
}

static int l_dom_attr (lua_State *L) {
  size_t id_len, name_len;
  const char *id = luaL_checklstring(L, 1, &id_len);
  const char *name = luaL_checklstring(L, 2, &name_len);
  if (lua_isnil(L, 3)) {
    write_u8(OP_ATTR_RM);
    write_u32(write_str(id, id_len));
    write_u32(write_str(name, name_len));
  } else {
    size_t val_len;
    const char *val = luaL_checklstring(L, 3, &val_len);
    write_u8(OP_ATTR_SET);
    write_u32(write_str(id, id_len));
    write_u32(write_str(name, name_len));
    write_u32(write_str(val, val_len));
  }
  cmd_count++;
  return 0;
}

static int l_dom_data (lua_State *L) {
  size_t id_len, name_len, val_len;
  const char *id = luaL_checklstring(L, 1, &id_len);
  const char *name = luaL_checklstring(L, 2, &name_len);
  const char *val = luaL_checklstring(L, 3, &val_len);
  write_u8(OP_DATA);
  write_u32(write_str(id, id_len));
  write_u32(write_str(name, name_len));
  write_u32(write_str(val, val_len));
  cmd_count++;
  return 0;
}

static int l_dom_style (lua_State *L) {
  size_t id_len, prop_len, val_len;
  const char *id = luaL_checklstring(L, 1, &id_len);
  const char *prop = luaL_checklstring(L, 2, &prop_len);
  const char *val = luaL_checklstring(L, 3, &val_len);
  write_u8(OP_STYLE);
  write_u32(write_str(id, id_len));
  write_u32(write_str(prop, prop_len));
  write_u32(write_str(val, val_len));
  cmd_count++;
  return 0;
}

static int l_dom_class_add (lua_State *L) {
  size_t id_len, cls_len;
  const char *id = luaL_checklstring(L, 1, &id_len);
  const char *cls = luaL_checklstring(L, 2, &cls_len);
  write_u8(OP_CLASS_ADD);
  write_u32(write_str(id, id_len));
  write_u32(write_str(cls, cls_len));
  cmd_count++;
  return 0;
}

static int l_dom_class_rm (lua_State *L) {
  size_t id_len, cls_len;
  const char *id = luaL_checklstring(L, 1, &id_len);
  const char *cls = luaL_checklstring(L, 2, &cls_len);
  write_u8(OP_CLASS_RM);
  write_u32(write_str(id, id_len));
  write_u32(write_str(cls, cls_len));
  cmd_count++;
  return 0;
}

static int l_dom_insert_html (lua_State *L) {
  size_t id_len, pos_len, html_len;
  const char *id = luaL_checklstring(L, 1, &id_len);
  const char *pos = luaL_checklstring(L, 2, &pos_len);
  const char *html = luaL_checklstring(L, 3, &html_len);
  write_u8(OP_INSERT_ADJ);
  write_u32(write_str(id, id_len));
  write_u32(write_str(pos, pos_len));
  write_u32(write_str(html, html_len));
  write_u32((uint32_t)html_len);
  cmd_count++;
  return 0;
}

static int l_dom_remove (lua_State *L) {
  size_t id_len;
  const char *id = luaL_checklstring(L, 1, &id_len);
  write_u8(OP_REMOVE);
  write_u32(write_str(id, id_len));
  cmd_count++;
  return 0;
}

static int l_dom_remove_children (lua_State *L) {
  size_t id_len;
  const char *id = luaL_checklstring(L, 1, &id_len);
  write_u8(OP_REMOVE_KIDS);
  write_u32(write_str(id, id_len));
  cmd_count++;
  return 0;
}

static int l_dom_focus (lua_State *L) {
  size_t id_len;
  const char *id = luaL_checklstring(L, 1, &id_len);
  int32_t offset = lua_isnil(L, 2) ? -1 : (int32_t)luaL_checkinteger(L, 2);
  write_u8(OP_FOCUS);
  write_u32(write_str(id, id_len));
  write_i32(offset);
  cmd_count++;
  return 0;
}

static int l_dom_blur (lua_State *L) {
  size_t id_len;
  const char *id = luaL_checklstring(L, 1, &id_len);
  write_u8(OP_BLUR);
  write_u32(write_str(id, id_len));
  cmd_count++;
  return 0;
}

static int l_dom_popover_show (lua_State *L) {
  size_t id_len;
  const char *id = luaL_checklstring(L, 1, &id_len);
  write_u8(OP_POPOVER_ON);
  write_u32(write_str(id, id_len));
  cmd_count++;
  return 0;
}

static int l_dom_popover_hide (lua_State *L) {
  size_t id_len;
  const char *id = luaL_checklstring(L, 1, &id_len);
  write_u8(OP_POPOVER_OFF);
  write_u32(write_str(id, id_len));
  cmd_count++;
  return 0;
}

static int l_dom_scroll_to (lua_State *L) {
  int32_t x = (int32_t)luaL_checkinteger(L, 1);
  int32_t y = (int32_t)luaL_checkinteger(L, 2);
  write_u8(OP_SCROLL);
  write_i32(x);
  write_i32(y);
  cmd_count++;
  return 0;
}

static int l_dom_flush (lua_State *L) {
  (void)L;
  if (cmd_count == 0) return 0;
  dom_js_flush(cmd_buf, cmd_pos, str_buf, str_pos, cmd_count);
  dom_reset();
  return 0;
}

static int l_dom_read (lua_State *L) {
  dom_read_reset();
  int nargs = lua_gettop(L);
  for (int i = 1; i <= nargs; i++) {
    luaL_checktype(L, i, LUA_TTABLE);
    lua_rawgeti(L, i, 1);
    const char *op = luaL_checkstring(L, -1);
    lua_pop(L, 1);
    if (strcmp(op, "text") == 0) {
      lua_rawgeti(L, i, 2);
      size_t id_len;
      const char *id = luaL_checklstring(L, -1, &id_len);
      read_write_u8(ROP_TEXT);
      read_write_u32(write_str(id, id_len));
      lua_pop(L, 1);
    } else if (strcmp(op, "attr") == 0) {
      lua_rawgeti(L, i, 2);
      lua_rawgeti(L, i, 3);
      size_t id_len, name_len;
      const char *id = luaL_checklstring(L, -2, &id_len);
      const char *name = luaL_checklstring(L, -1, &name_len);
      read_write_u8(ROP_ATTR);
      read_write_u32(write_str(id, id_len));
      read_write_u32(write_str(name, name_len));
      lua_pop(L, 2);
    } else if (strcmp(op, "data") == 0) {
      lua_rawgeti(L, i, 2);
      lua_rawgeti(L, i, 3);
      size_t id_len, name_len;
      const char *id = luaL_checklstring(L, -2, &id_len);
      const char *name = luaL_checklstring(L, -1, &name_len);
      read_write_u8(ROP_DATA);
      read_write_u32(write_str(id, id_len));
      read_write_u32(write_str(name, name_len));
      lua_pop(L, 2);
    } else if (strcmp(op, "rect") == 0) {
      lua_rawgeti(L, i, 2);
      size_t id_len;
      const char *id = luaL_checklstring(L, -1, &id_len);
      read_write_u8(ROP_RECT);
      read_write_u32(write_str(id, id_len));
      lua_pop(L, 1);
    } else if (strcmp(op, "scroll") == 0) {
      read_write_u8(ROP_SCROLL);
    } else if (strcmp(op, "cursor") == 0) {
      lua_rawgeti(L, i, 2);
      size_t id_len;
      const char *id = luaL_checklstring(L, -1, &id_len);
      read_write_u8(ROP_CURSOR);
      read_write_u32(write_str(id, id_len));
      lua_pop(L, 1);
    } else if (strcmp(op, "has_class") == 0) {
      lua_rawgeti(L, i, 2);
      lua_rawgeti(L, i, 3);
      size_t id_len, cls_len;
      const char *id = luaL_checklstring(L, -2, &id_len);
      const char *cls = luaL_checklstring(L, -1, &cls_len);
      read_write_u8(ROP_HAS_CLASS);
      read_write_u32(write_str(id, id_len));
      read_write_u32(write_str(cls, cls_len));
      lua_pop(L, 2);
    } else if (strcmp(op, "element_at") == 0) {
      lua_rawgeti(L, i, 2);
      lua_rawgeti(L, i, 3);
      int32_t x = (int32_t)luaL_checkinteger(L, -2);
      int32_t y = (int32_t)luaL_checkinteger(L, -1);
      read_write_u8(ROP_ELEMENT_AT);
      read_write_u32((uint32_t)x);
      read_write_u32((uint32_t)y);
      lua_pop(L, 2);
    }
    read_cmd_count++;
  }

  dom_js_read_flush(
    read_cmd_buf, read_cmd_pos,
    str_buf, str_pos,
    read_cmd_count,
    read_res_buf, DOM_READ_RES_SIZE,
    read_str_buf, DOM_READ_STR_SIZE
  );

  uint32_t rpos = 0;
  uint32_t rspos = 0;
  int nresults = 0;

  for (int i = 0; i < (int)read_cmd_count; i++) {
    uint8_t tag;
    memcpy(&tag, read_res_buf + rpos, 1);
    rpos++;

    if (tag == 0) {
      lua_pushnil(L);
      nresults++;
    } else if (tag == 1) {
      uint32_t soff, slen;
      memcpy(&soff, read_res_buf + rpos, 4); rpos += 4;
      memcpy(&slen, read_res_buf + rpos, 4); rpos += 4;
      lua_pushlstring(L, (const char *)(read_str_buf + soff), slen);
      nresults++;
    } else if (tag == 2) {
      int32_t val;
      memcpy(&val, read_res_buf + rpos, 4); rpos += 4;
      lua_pushinteger(L, val);
      nresults++;
    } else if (tag == 3) {
      lua_newtable(L);
      for (int f = 0; f < 6; f++) {
        float fv;
        memcpy(&fv, read_res_buf + rpos, 4); rpos += 4;
        lua_pushnumber(L, (lua_Number)fv);
        lua_rawseti(L, -2, f + 1);
      }
      nresults++;
    } else if (tag == 4) {
      lua_newtable(L);
      for (int f = 0; f < 5; f++) {
        float fv;
        memcpy(&fv, read_res_buf + rpos, 4); rpos += 4;
        lua_pushnumber(L, (lua_Number)fv);
        lua_rawseti(L, -2, f + 1);
      }
      nresults++;
    } else if (tag == 5) {
      uint8_t bval;
      memcpy(&bval, read_res_buf + rpos, 1); rpos++;
      lua_pushboolean(L, bval);
      nresults++;
    }
  }

  dom_read_reset();
  str_pos = 0;
  return nresults;
}

int luaopen_santoku_web_dom (lua_State *L) {
  luaL_Reg fns[] = {
    { "text", l_dom_text },
    { "html", l_dom_html },
    { "attr", l_dom_attr },
    { "data", l_dom_data },
    { "style", l_dom_style },
    { "class_add", l_dom_class_add },
    { "class_rm", l_dom_class_rm },
    { "insert_html", l_dom_insert_html },
    { "remove", l_dom_remove },
    { "remove_children", l_dom_remove_children },
    { "focus", l_dom_focus },
    { "blur", l_dom_blur },
    { "popover_show", l_dom_popover_show },
    { "popover_hide", l_dom_popover_hide },
    { "scroll_to", l_dom_scroll_to },
    { "flush", l_dom_flush },
    { "read", l_dom_read },
    { NULL, NULL }
  };
  lua_newtable(L);
  luaL_register(L, NULL, fns);
  return 1;
}
