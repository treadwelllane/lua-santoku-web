package = "<% return os.getenv('NAME') %>"
version = "<% return os.getenv('VERSION') %>"
rockspec_format = "3.0"

source = {
  url = "<% return os.getenv('GIT_URL') %>"
  tag = "<% return os.getenv('VERSION') %>"
}

description = {
  homepage = "<% return os.getenv('HOMEPAGE') %>",
  license = "<% return os.getenv('LICENSE') %>"
}

dependencies = {
  "lua >= 5.1"
}

build = {
  type = "make",
  build_target = "shared",
  install_target = "install",
  build_variables = {
    CFLAGS = "$(CFLAGS)",
    LIBFLAG = "$(LIBFLAG)",
  },
  install_variables  =  {
    INST_LIBDIR = "$(LIBDIR)",
  },
}
