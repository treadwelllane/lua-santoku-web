local compat = require("santoku.compat")

local env = {

  name = "santoku-web",
  version = "0.0.85-1",
  variable_prefix = "TK_WEB",
  license = "MIT",
  public = true,

  dependencies = {
    "lua >= 5.1",
    "santoku >= 0.0.158-1",
    "lsqlite3 >= 0.9.5-1"
  },

  -- NOTE: Not using build.wasm and test.wasm for emscripten flags so that the
  -- released taball contains them. In the future santoku make should allow toku
  -- make release --wasm with an optional different name (like santoku-web-wasm)
  cxxflags = "--std=c++17",
  ldflags = "--bind",

  test = {
    ldflags = "--bind",
    dependencies = {
      "santoku-test >= 0.0.4-1",
      "luassert >= 1.9.0-1",
      "luacov >= scm-1",
    }
  },

}

env.homepage = "https://github.com/treadwelllane/lua-" .. env.name
env.tarball = env.name .. "-" .. env.version .. ".tar.gz"
env.download = env.homepage .. "/releases/download/" .. env.version .. "/" .. env.tarball

return {
  type = "lib",
  env = env,
}

