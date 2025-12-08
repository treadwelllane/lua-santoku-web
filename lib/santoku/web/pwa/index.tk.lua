local mustache = require("santoku.mustache")
local tbl = require("santoku.table")
local template = mustache([[<% return readfile("res/pwa/index.html"), false %>]]) -- luacheck: ignore
local defaults = { charset = "utf-8", lang = "en" }
return function(opts)
  opts = tbl.merge({}, opts or {}, defaults)
  return template(opts)
end
