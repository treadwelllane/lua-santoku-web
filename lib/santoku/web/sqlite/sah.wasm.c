#include <lua.h>
#include <lauxlib.h>
#include <sqlite3.h>
#include <string.h>
#include <emscripten.h>
#include <emscripten/html5.h>

#define SAH_HEADER_SZ 4096
#define SAH_PATH_MAX 512
#define SAH_VFS_NAME "opfs-sahpool"

EM_JS(void, tk_sah_setup, (), {
  if (Module._sahPool) return;
  Module._sahPool = {
    files: [],
    pathMap: {},
    capacity: 0,
    dirHandle: null,
    opaqueHandle: null,
  };
  globalThis.__tk_sah_pool_init = async function (dir, capacity) {
    var pool = Module._sahPool;
    var root = await navigator.storage.getDirectory();
    pool.dirHandle = await root.getDirectoryHandle(dir, { create: true });
    pool.opaqueHandle = await pool.dirHandle.getDirectoryHandle(".opaque", { create: true });
    var existing = [];
    for await (var entry of pool.opaqueHandle.values()) {
      if (entry.kind === "file") existing.push(entry.name);
    }
    existing.sort();
    for (var i = 0; i < existing.length; i++) {
      var fh = await pool.opaqueHandle.getFileHandle(existing[i]);
      var sah = await fh.createSyncAccessHandle();
      var hdr = new Uint8Array(4096);
      sah.read(hdr, { at: 0 });
      var path = "";
      for (var j = 0; j < 512; j++) {
        if (hdr[j] === 0) break;
        path += String.fromCharCode(hdr[j]);
      }
      var flags = hdr[512] | (hdr[513] << 8) |
                  (hdr[514] << 16) | (hdr[515] << 24);
      var slot = { sah: sah, path: path, flags: flags, fid: i };
      pool.files.push(slot);
      if (path.length > 0)
        pool.pathMap[path] = i;
    }
    for (var k = pool.files.length; k < capacity; k++) {
      var name = String(k).padStart(8, "0");
      var fh = await pool.opaqueHandle.getFileHandle(name, { create: true });
      var sah = await fh.createSyncAccessHandle();
      var slot = { sah: sah, path: "", flags: 0, fid: k };
      pool.files.push(slot);
    }
    pool.capacity = pool.files.length;
  };
});

EM_JS(int, tk_sah_xopen, (const char *cpath, int flags), {
  var pool = Module._sahPool;
  var path = UTF8ToString(cpath);
  if (path in pool.pathMap)
    return pool.pathMap[path];
  for (var i = 0; i < pool.files.length; i++) {
    if (pool.files[i].path.length === 0) {
      var slot = pool.files[i];
      slot.path = path;
      slot.flags = flags;
      pool.pathMap[path] = i;
      var hdr = new Uint8Array(4096);
      for (var j = 0; j < path.length && j < 512; j++)
        hdr[j] = path.charCodeAt(j);
      hdr[512] = flags & 0xff;
      hdr[513] = (flags >> 8) & 0xff;
      hdr[514] = (flags >> 16) & 0xff;
      hdr[515] = (flags >> 24) & 0xff;
      slot.sah.write(hdr, { at: 0 });
      slot.sah.flush();
      return i;
    }
  }
  return -1;
});

EM_JS(void, tk_sah_xclose, (int fid), {
});

EM_JS(int, tk_sah_xread, (int fid, unsigned char *buf, int n, double off), {
  var pool = Module._sahPool;
  var sah = pool.files[fid].sah;
  var tmp = new Uint8Array(n);
  var nread = sah.read(tmp, { at: 4096 + off });
  HEAPU8.set(tmp.subarray(0, nread), buf);
  if (nread < n) {
    HEAPU8.fill(0, buf + nread, buf + n);
    return 522;
  }
  return 0;
});

EM_JS(int, tk_sah_xwrite, (const unsigned char *buf, int n, double off, int fid), {
  var pool = Module._sahPool;
  var sah = pool.files[fid].sah;
  var data = HEAPU8.slice(buf, buf + n);
  sah.write(data, { at: 4096 + off });
  return 0;
});

EM_JS(double, tk_sah_xfilesize, (int fid), {
  var pool = Module._sahPool;
  var sah = pool.files[fid].sah;
  var sz = sah.getSize();
  return sz > 4096 ? sz - 4096 : 0;
});

EM_JS(int, tk_sah_xtruncate, (int fid, double sz), {
  var pool = Module._sahPool;
  var sah = pool.files[fid].sah;
  sah.truncate(4096 + sz);
  return 0;
});

EM_JS(void, tk_sah_xsync, (int fid), {
  var pool = Module._sahPool;
  pool.files[fid].sah.flush();
});

EM_JS(int, tk_sah_xaccess, (const char *cpath), {
  var pool = Module._sahPool;
  var path = UTF8ToString(cpath);
  return (path in pool.pathMap) ? 1 : 0;
});

EM_JS(void, tk_sah_xdelete, (const char *cpath), {
  var pool = Module._sahPool;
  var path = UTF8ToString(cpath);
  if (!(path in pool.pathMap)) return;
  var fid = pool.pathMap[path];
  var slot = pool.files[fid];
  var hdr = new Uint8Array(4096);
  slot.sah.write(hdr, { at: 0 });
  slot.sah.truncate(4096);
  slot.sah.flush();
  slot.path = "";
  slot.flags = 0;
  delete pool.pathMap[path];
});

typedef struct {
  sqlite3_file base;
  int fid;
} tk_sah_file;

static int sah_io_close (sqlite3_file *pFile) {
  tk_sah_file *f = (tk_sah_file *) pFile;
  tk_sah_xclose(f->fid);
  return SQLITE_OK;
}

static int sah_io_read (sqlite3_file *pFile, void *buf, int iAmt, sqlite3_int64 iOfst) {
  tk_sah_file *f = (tk_sah_file *) pFile;
  return tk_sah_xread(f->fid, (unsigned char *) buf, iAmt, (double) iOfst);
}

static int sah_io_write (sqlite3_file *pFile, const void *buf, int iAmt, sqlite3_int64 iOfst) {
  tk_sah_file *f = (tk_sah_file *) pFile;
  return tk_sah_xwrite((const unsigned char *) buf, iAmt, (double) iOfst, f->fid);
}

static int sah_io_truncate (sqlite3_file *pFile, sqlite3_int64 sz) {
  tk_sah_file *f = (tk_sah_file *) pFile;
  return tk_sah_xtruncate(f->fid, (double) sz);
}

static int sah_io_sync (sqlite3_file *pFile, int flags) {
  (void) flags;
  tk_sah_file *f = (tk_sah_file *) pFile;
  tk_sah_xsync(f->fid);
  return SQLITE_OK;
}

static int sah_io_filesize (sqlite3_file *pFile, sqlite3_int64 *pSize) {
  tk_sah_file *f = (tk_sah_file *) pFile;
  *pSize = (sqlite3_int64) tk_sah_xfilesize(f->fid);
  return SQLITE_OK;
}

static int sah_io_lock (sqlite3_file *p, int l) { (void) p; (void) l; return SQLITE_OK; }
static int sah_io_unlock (sqlite3_file *p, int l) { (void) p; (void) l; return SQLITE_OK; }
static int sah_io_check_reserved (sqlite3_file *p, int *r) { (void) p; *r = 0; return SQLITE_OK; }
static int sah_io_file_control (sqlite3_file *p, int o, void *a) { (void) p; (void) o; (void) a; return SQLITE_NOTFOUND; }
static int sah_io_sector_size (sqlite3_file *p) { (void) p; return 4096; }
static int sah_io_device_char (sqlite3_file *p) { (void) p; return SQLITE_IOCAP_UNDELETABLE_WHEN_OPEN; }

static const sqlite3_io_methods sah_io = {
  1,
  sah_io_close,
  sah_io_read,
  sah_io_write,
  sah_io_truncate,
  sah_io_sync,
  sah_io_filesize,
  sah_io_lock,
  sah_io_unlock,
  sah_io_check_reserved,
  sah_io_file_control,
  sah_io_sector_size,
  sah_io_device_char,
  NULL, NULL, NULL, NULL, NULL, NULL
};

static int sah_vfs_open (sqlite3_vfs *pVfs, const char *zName, sqlite3_file *pFile, int flags, int *pOutFlags) {
  (void) pVfs;
  tk_sah_file *f = (tk_sah_file *) pFile;
  memset(f, 0, sizeof(*f));
  f->base.pMethods = &sah_io;
  const char *path = zName ? zName : ":memory:";
  f->fid = tk_sah_xopen(path, flags);
  if (f->fid < 0) {
    f->base.pMethods = NULL;
    return SQLITE_CANTOPEN;
  }
  if (pOutFlags)
    *pOutFlags = flags;
  return SQLITE_OK;
}

static int sah_vfs_delete (sqlite3_vfs *pVfs, const char *zName, int syncDir) {
  (void) pVfs; (void) syncDir;
  tk_sah_xdelete(zName);
  return SQLITE_OK;
}

static int sah_vfs_access (sqlite3_vfs *pVfs, const char *zName, int flags, int *pResOut) {
  (void) pVfs; (void) flags;
  *pResOut = tk_sah_xaccess(zName);
  return SQLITE_OK;
}

static int sah_vfs_fullpathname (sqlite3_vfs *pVfs, const char *zName, int nOut, char *zOut) {
  (void) pVfs;
  strncpy(zOut, zName, (size_t) nOut);
  zOut[nOut - 1] = '\0';
  return SQLITE_OK;
}

static int sah_vfs_randomness (sqlite3_vfs *pVfs, int nBuf, char *zBuf) {
  (void) pVfs;
  for (int i = 0; i < nBuf; i++)
    zBuf[i] = (char) (emscripten_random() * 256);
  return nBuf;
}

static int sah_vfs_sleep (sqlite3_vfs *pVfs, int microseconds) {
  (void) pVfs;
  (void) microseconds;
  return 0;
}

static int sah_vfs_current_time (sqlite3_vfs *pVfs, double *pTime) {
  (void) pVfs;
  *pTime = emscripten_date_now() / 86400000.0 + 2440587.5;
  return SQLITE_OK;
}

static sqlite3_vfs sah_vfs = {
  1,
  sizeof(tk_sah_file),
  SAH_PATH_MAX,
  NULL,
  SAH_VFS_NAME,
  NULL,
  sah_vfs_open,
  sah_vfs_delete,
  sah_vfs_access,
  sah_vfs_fullpathname,
  NULL, NULL, NULL, NULL,
  sah_vfs_randomness,
  sah_vfs_sleep,
  sah_vfs_current_time,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL
};

static int tk_sah_register_vfs (lua_State *L) {
  (void) L;
  sqlite3_vfs_register(&sah_vfs, 0);
  return 0;
}

int luaopen_santoku_web_sqlite_sah (lua_State *L) {
  tk_sah_setup();
  lua_newtable(L);
  lua_pushcfunction(L, tk_sah_register_vfs);
  lua_setfield(L, -2, "register_vfs");
  return 1;
}
