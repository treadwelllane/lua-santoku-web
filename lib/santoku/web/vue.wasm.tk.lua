<% build = require("santoku.web.build") %>
local val = require("santoku.web.val")

local g = val.global("globalThis"):lua()

g:eval([==[<% return build.minify_js(readfile("res/web/vue.js")), false %>]==])

local vue_mount = g.__tkVueMount
local vue_reactive = g.__tkVueReactive
local vue_next_tick = g.__tkVueNextTick

local M = {}

function M.reactive (obj)
  return vue_reactive(nil, val(obj, true))
end

function M.nextTick (fn)
  vue_next_tick(nil, val(fn))
end

function M.createApp (init_scope)
  local app = {}
  local directives = {}

  function app.directive (_, name, fn)
    directives[name] = fn
    return app
  end

  function app.mount (_, sel)
    local scope_obj = init_scope and val(init_scope, true) or false
    local dir_handler = false
    if next(directives) then
      dir_handler = val(function (_, dir_name, el, dir_arg, expr, scope, effect_fn, get_fn)
        local fn = directives[dir_name]
        if not fn then return end
        fn({
          el = el,
          arg = dir_arg ~= false and dir_arg or nil,
          exp = expr,
          get = function () return get_fn(nil) end,
          effect = function (efn) effect_fn(nil, val(efn)) end,
          scope = scope
        })
      end)
    end
    vue_mount(nil, sel or false, scope_obj, dir_handler)
    return app
  end

  return app
end

return M
