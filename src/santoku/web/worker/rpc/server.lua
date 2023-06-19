local js = require("santoku.web.js")
local val = require("santoku.web.val")
local tup = require("santoku.tuple")
local compat = require("santoku.compat")

local global = js.self

local M = {}

M.init = function (obj)
  global:addEventListener("message", function (_, ev)
    local ch = ev.ports[0]
    local fn = ev.data[0]
    local args = ev.data:slice(1)
    local out = val.array()
    local ret = tup(obj[fn](compat.unpack(args)))
    -- TODO: santoku web should expose helper
    -- function to convert to js, or at least
    -- allow structured clones of proxy objects
    for i = 1, tup.len(ret()) do
      out:set(i - 1, tup.get(i, ret()))
    end
    -- TODO: Need to serialize results from obj
    -- call for postMessage
    ch:postMessage(out)
  end)
end

return M
