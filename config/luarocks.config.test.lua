rocks_trees = {
  {
    name = "system",
    root = "<% return os.getenv('ROCKS_TREE') %>"
  }
}
variables = {
  LUA_INCDIR = "<% return os.getenv('LUA_INCDIR') %>",
  LUA_LIBDIR = "<% return os.getenv('LUA_LIBDIR') %>",
  CC = "<% return os.getenv('CC') %>",
  LD = "<% return os.getenv('LD') %>",
  AR = "<% return os.getenv('AR') %>",
  NM = "<% return os.getenv('NM') %>",
  RANLIB = "<% return os.getenv('RANLIB') %>",
  CFLAGS = "<% return os.getenv('CFLAGS') %>",
  LDFLAGS = "<% return os.getenv('LDFLAGS') %>",
  LIBFLAG = "<% return os.getenv('LIBFLAG') %>"
}
