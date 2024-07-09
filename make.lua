local env = {

  name = "santoku-web",
  version = "0.0.126-1",
  variable_prefix = "TK_WEB",
  license = "MIT",
  public = true,

  dependencies = {
    "lua >= 5.1",
    "santoku >= 0.0.204-1",
    "santoku-sqlite >= 0.0.14-1",
    "santoku-fs >= 0.0.32-1",
  },

  -- NOTE: Not using build.wasm and test.wasm for emscripten flags so that the
  -- released taball contains them. In the future santoku make should allow toku
  -- make release --wasm with an optional different name (like santoku-web-wasm)
  cxxflags = { "--std=c++17" },
  ldflags = { "--bind"  },

  test = {
    ldflags = {
      -- "-flto", "-Oz", "--closure", "1",
      "--bind", "-sDEFAULT_LIBRARY_FUNCS_TO_INCLUDE='$stringToNewUTF8'",
    },
    dependencies = {
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
