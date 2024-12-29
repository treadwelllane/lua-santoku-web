local template = require("santoku.template")
local manifest = (<%
  local serialize = require("santoku.serialize")
  return serialize(readfile("res/manifest.tk.json"), true)
%>) -- luacheck: ignore
local tbl = require("santoku.table")
local def = require("santoku.web.spa.defaults")
local tpl = template.compile(manifest)
return function (opts)
  local opts = tbl.merge({}, opts or {}, def.manifest or {})
  return tpl({ opts = opts }, _G)
end
