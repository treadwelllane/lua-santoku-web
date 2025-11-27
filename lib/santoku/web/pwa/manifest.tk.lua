<%
  str = require("santoku.string")
  squote = str.quote
  to_base64 = str.to_base64
  fs = require("santoku.fs")
  readfile = fs.readfile
%>

local mustache = require("santoku.mustache")
local str = require("santoku.string")
local tbl = require("santoku.table")

local template = str.from_base64(<% return squote(to_base64(readfile("res/pwa/manifest.mustache"))) %>) -- luacheck: ignore

local defaults = {
  start_url = "/",
  display = "standalone",
  theme_color = "#000000",
  background_color = "#ffffff",
}

-- Simple JSON encoder for icons array (avoids cjson dependency at build time)
local function encode_icons(icons)
  local parts = {}
  for i, icon in ipairs(icons) do
    local fields = {}
    for k, v in pairs(icon) do
      table.insert(fields, string.format('"%s": "%s"', k, v))
    end
    parts[i] = "{ " .. table.concat(fields, ", ") .. " }"
  end
  return "[\n    " .. table.concat(parts, ",\n    ") .. "\n  ]"
end

return function(opts)
  opts = tbl.merge({}, defaults, opts or {})
  -- Handle icons array as JSON
  if opts.icons and #opts.icons > 0 then
    opts.icons_json = ",\n  \"icons\": " .. encode_icons(opts.icons)
  else
    opts.icons_json = ""
  end
  return mustache(template, opts)
end
