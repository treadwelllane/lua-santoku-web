local json = require("cjson")
local mustache = require("santoku.mustache")
local tbl = require("santoku.table")

local template = mustache([[ <% return readfile("res/pwa/manifest.mustache"), false %> ]]) -- luacheck: ignore

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
  opts = tbl.merge({}, opts or {}, defaults)
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
  return template(opts)
end
