local mustache = require("santoku.mustache")
local tbl = require("santoku.table")
local lp = require("santoku.web.lpeg")
local template = mustache([[<% return readfile("res/pwa/index.html"), false %>]]) -- luacheck: ignore
local defaults = { charset = "utf-8", lang = "en" }
return function(opts)
  opts = tbl.merge({}, opts or {}, defaults)
  local out = template(opts)
  if opts.transforms then
    out = lp.transform_inline(out, opts.transforms)
    if opts.transforms.html then
      out = opts.transforms.html(out)
    end
  end
  return out
end
