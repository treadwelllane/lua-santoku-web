local fs = require("santoku.fs")
local sys = require("santoku.system")

local M = {}

local function esbuild (input, ext)
  local tmp = fs.tmpname() .. ext
  fs.writefile(tmp, input)
  local parts = {}
  for chunk in sys.sh({ "esbuild", "--minify", tmp }) do
    parts[#parts + 1] = chunk
  end
  os.remove(tmp)
  return table.concat(parts, "\n")
end

M.minify_js = function (input)
  return esbuild(input, ".js")
end

M.minify_css = function (input)
  return esbuild(input, ".css")
end

return M
