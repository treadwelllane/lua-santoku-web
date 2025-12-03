local env = {

  name = "santoku-web",
  version = "0.0.322-1",
  variable_prefix = "TK_WEB",
  license = "MIT",
  public = true,

  dependencies = {
    "lua >= 5.1",
    "santoku >= 0.0.297-1",
    "santoku-mustache >= 0.0.10-1",
    "santoku-sqlite >= 0.0.17-1",
    "lua-cjson == 2.1.0.10-1"
  },

  cxxflags = { "--std=c++17" },

  build = {
    wasm = {
      ldflags = { "--bind" },
    },
  },

  test = {
    wasm = {
      ldflags = {
        "-Og", "--bind", "-sWASM_BIGINT", "-sDEFAULT_LIBRARY_FUNCS_TO_INCLUDE='$stringToNewUTF8'",
      },
    },
  },

}

env.homepage = "https://github.com/treadwelllane/lua-" .. env.name
env.tarball = env.name .. "-" .. env.version .. ".tar.gz"
env.download = env.homepage .. "/releases/download/" .. env.version .. "/" .. env.tarball

return { env = env }
