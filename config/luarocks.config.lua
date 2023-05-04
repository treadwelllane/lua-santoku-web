rocks_trees = {}
variables = {
  LUA_INCDIR = "<% return os.getenv('LUA_INCDIR') %>",
  LUA_LIBDIR = "<% return os.getenv('LUA_LIBDIR') %>",
  CFLAGS = "<% return os.getenv('CFLAGS') %>",
  LDFLAGS = "<% return os.getenv('LDFLAGS') %>"
}
