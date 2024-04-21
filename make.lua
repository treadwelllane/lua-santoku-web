local env = {

  name = "santoku-web",
  version = "0.0.92-1",
  variable_prefix = "TK_WEB",
  license = "MIT",
  public = true,

  dependencies = {
    "lua >= 5.1",
    "santoku >= 0.0.204-1",
    "santoku-sqlite >= 0.0.13-1",
    "santoku-fs >= 0.0.31-1",
  },

  -- NOTE: Not using build.wasm and test.wasm for emscripten flags so that the
  -- released taball contains them. In the future santoku make should allow toku
  -- make release --wasm with an optional different name (like santoku-web-wasm)
  cxxflags = { "--std=c++17" },
  ldflags = { "--bind"  },

  test = {
    cflags = { "-sDEFAULT_LIBRARY_FUNCS_TO_INCLUDE='$stringToNewUTF8'" },
    ldflags = { "--bind" },
    dependencies = {
      -- "luacov >= scm-1",
      "luacov >= 0.15.0-1",
    },

  },


}

env.homepage = "https://github.com/treadwelllane/lua-" .. env.name
env.tarball = env.name .. "-" .. env.version .. ".tar.gz"
env.download = env.homepage .. "/releases/download/" .. env.version .. "/" .. env.tarball

return {
  type = "lib",
  env = env,
}

