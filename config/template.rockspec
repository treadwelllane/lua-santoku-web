package = "<% return os.getenv('NAME') %>"
version = "<% return os.getenv('VERSION') %>"
rockspec_format = "3.0"

source = {
  url = "git+ssh://<% return os.getenv('GIT_URL') %>",
  tag = "<% return os.getenv('VERSION') %>"
}

description = {
  homepage = "<% return os.getenv('HOMEPAGE') %>",
  license = "<% return os.getenv('LICENSE') %>"
}

dependencies = {
  "lua >= 5.1"
}

-- test_dependencies = {
--   "busted >= 2.1.1",
--   "luacov >= 0.15.0",
--   "luacheck >= 1.1.0-1",
-- }

build = {
  type = "make",
  install_target = "luarocks-install",
  build_variables = {
    CFLAGS = "$(CFLAGS)",
    LIBFLAG = "$(LIBFLAG)",
  },
  install_variables  =  {
    INST_LIBDIR = "$(LIBDIR)",
  },
}

-- test = {
--   type = "command",
--   command = "sh test/run.sh"
-- }
