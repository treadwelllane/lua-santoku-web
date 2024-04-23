local template = require("santoku.template")
local defaults = require("santoku.web.spa.defaults")
local manifest = <%
  local serialize = require("santoku.serialize")
  return serialize(readfile("res/manifest.json"))
%> -- luacheck: ignore

return template.compile(manifest)
