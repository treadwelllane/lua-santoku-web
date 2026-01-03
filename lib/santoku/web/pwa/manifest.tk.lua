local json = require("cjson")
local mustache = require("santoku.mustache")
local tbl = require("santoku.table")

local template = mustache([[ <% return readfile("res/pwa/manifest.json"), false %> ]]) -- luacheck: ignore

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
    for i, icon in ipairs(opts.icons) do
      icon.comma = i < #opts.icons and "," or ""
    end
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
