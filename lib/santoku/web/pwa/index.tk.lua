<%
  str = require("santoku.string")
  squote = str.quote
  to_base64 = str.to_base64
  fs = require("santoku.fs")
  readfile = fs.readfile
%>

local cjson = require("cjson")
local mustache = require("santoku.mustache")
local str = require("santoku.string")
local tbl = require("santoku.table")

local template = str.from_base64(<% return squote(to_base64(readfile("res/pwa/index.mustache"))) %>) -- luacheck: ignore

local defaults = {
  charset = "utf-8",
  lang = "en",
  manifest = "/manifest.json",
  theme_color = "#000000",
}

return function(opts)
  opts = tbl.merge({}, defaults, opts or {})
  opts.cached_files_json = cjson.encode(opts.cached_files or {})
  return mustache(template)(opts)
end
