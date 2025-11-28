<%
  str = require("santoku.string")
  squote = str.quote
  to_base64 = str.to_base64
  fs = require("santoku.fs")
  readfile = fs.readfile
%>

local json = require("cjson")
local mustache = require("santoku.mustache")
local str = require("santoku.string")
local tbl = require("santoku.table")

local template = str.from_base64(<% return squote(to_base64(readfile("res/pwa/manifest.mustache"))) %>) -- luacheck: ignore

local defaults = {
  start_url = "/",
  scope = "/",
  display = "standalone",
  theme_color = "#000000",
  background_color = "#ffffff",
  handle_links = "preferred",
  launch_handler = { client_mode = "navigate-existing" },
}

return function(opts)
  opts = tbl.merge({}, defaults, opts or {})
  if opts.icons and #opts.icons > 0 then
    opts.icons_json = json.encode(opts.icons)
  else
    opts.icons_json = "[]"
  end
  if opts.categories and #opts.categories > 0 then
    opts.categories_json = json.encode(opts.categories)
  end
  if opts.launch_handler then
    opts.launch_handler_json = json.encode(opts.launch_handler)
  end
  if opts.screenshots and #opts.screenshots > 0 then
    opts.screenshots_json = json.encode(opts.screenshots)
  end
  return mustache(template, opts)
end
