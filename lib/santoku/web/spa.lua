local err = require("santoku.error")
local error = err.error

local js = require("santoku.web.js")
local val = require("santoku.web.val")
local str = require("santoku.string")
local fun = require("santoku.functional")
local op = require("santoku.op")
local tbl = require("santoku.table")
local varg = require("santoku.varg")
local it = require("santoku.iter")
local arr = require("santoku.array")
local num = require("santoku.num")
local util = require("santoku.web.util")
local defaults = require("santoku.web.spa.defaults")

return function (opts)

  opts = tbl.merge({}, opts, defaults)

  local Array = js.Array
  local MutationObserver = js.MutationObserver
  local window = js.window
  local document = window.document
  local history = window.history
  local location = window.location

  local e_head = document.head
  local e_body = document.body
  local t_ripple = e_head:querySelector("template.ripple")

  local state = util.parse_path(str.match(location.hash, "^#+(.*)"))
  local active_view
  local update_worker = false

  local M = {}

  M.find_default = function (pages, path, i)
    path = path or {}
    i = i or 1
    for k, v in it.pairs(pages) do
      if v.default then
        path[i] = k
        if v.pages then
          return M.find_default(v.pages, path, i + 1)
        else
          return path
        end
      end
    end
    return path
  end

  M.setup_ripple = function (el)

    el:addEventListener("mousedown", function (_, ev)

      if el.disabled then
        return
      end

      ev:stopPropagation()
      ev:preventDefault()

      local e_ripple = util.clone(t_ripple)

      e_ripple:addEventListener("animationend", function ()
        e_ripple:remove()
      end)

      local e_wave = e_ripple:querySelector(".ripple-wave")
      local dia = num.min(el.offsetHeight, el.offsetWidth, 100)

      local x = ev.offsetX
      local y = ev.offsetY
      local el0 = ev.target
      while el0 and el0 ~= el do
        local rchild = el0:getBoundingClientRect()
        local rparent = el0.parentElement:getBoundingClientRect()
        x = x + rchild.left - rparent.left
        y = y + rchild.top - rparent.top
        el0 = el0.parentNode
      end

      e_wave.style.width = dia .. "px"
      e_wave.style.height = dia .. "px"
      e_wave.style.left = (x - dia / 2) .. "px"
      e_wave.style.top = (y - dia / 2) .. "px"

      el:append(e_ripple)

    end)

  end

  -- TODO: there must be a better way to do this
  M.setup_observer = function (view)

    local old_classes = it.reduce(function (a, n)
      a[n] = true
      return a
    end, {}, it.map(str.sub, str.matches(view.el.className, "[^%s]+")))

    view.observer = MutationObserver:new(function (_, mutations)

      return mutations:forEach(function (_, mu)

        local recs = view.observer:takeRecords()

        recs:push(mu)

        if not recs:find(function (_, mu)
          return mu["type"] == "attributes" and mu.attributeName == "class"
        end) then
          return
        end

        local fabs = false
        local snacks = false

        view.el.classList:forEach(function (_, c)
          if not old_classes[c] then
            if view.fab_observed_classes[c] then
              fabs = true
            end
            if view.snack_observed_classes[c] then
              snacks = true
            end
          end
        end)

        for c in it.keys(old_classes) do
          if not view.el.classList:contains(c) then
            if view.fab_observed_classes[c] then
              fabs = true
            end
            if view.snack_observed_classes[c] then
              snacks = true
            end
          end
        end

        old_classes = it.reduce(function (a, n)
          a[n] = true
          return a
        end, {}, it.map(str.sub, str.matches(view.el.className or "", "[^%s]+")))

        if fabs then
          M.style_fabs(view, true)
        end

        if snacks then
          M.style_snacks(view, true)
        end

      end)

    end)

    view.observer:observe(view.el, {
      attributes = true,
      attributeFilter = { "class" }
    })

  end

  M.setup_nav = function (next_view, sub_view_name)

    next_view.e_nav = next_view.el:querySelector(".page > nav")

    if not next_view.e_nav then
      return
    end

    next_view.e_nav:addEventListener("click", function (_, ev)
      local rect = next_view.e_nav:getBoundingClientRect()
      if ev.clientX > rect.right then
        M.toggle_nav_state(next_view, false)
      end
    end)

    next_view.e_nav_buttons = next_view.e_nav:querySelectorAll("button[data-page]")
    next_view.nav_order = {}
    next_view.e_nav_buttons:forEach(function (_, el)
      local n = el.dataset.page
      arr.push(next_view.nav_order, n)
      next_view.nav_order[n] = #next_view.nav_order
      el:addEventListener("click", function ()
        if el.classList:contains("is-active") then
          return
        end
        M.forward(next_view.name, n)
        M.toggle_nav_state(next_view, false)
      end)
    end)

    if not sub_view_name then
      M.find_default(next_view.page.pages, state.path, 2)
      sub_view_name = state.path[2]
    end

    M.switch(next_view, sub_view_name, "ignore")

    if e_body.classList:contains("is-wide") then
      M.toggle_nav_state(next_view, true, false, false)
    else
      M.toggle_nav_state(next_view, false, false, false)
    end

  end

  M.setup_fabs = function (next_view, last_view)

    next_view.e_fabs = next_view.el:querySelectorAll(".page > .fab")

    next_view.e_fabs_shared = {}
    next_view.e_fabs_top = {}
    next_view.e_fabs_bottom = {}
    next_view.fab_observed_classes = {}

    for i = 0, next_view.e_fabs.length - 1 do

      local el = next_view.e_fabs:item(i)

      for c in it.map(str.sub, str.matches(el.dataset.hide or "", "[^%s]+")) do
        next_view.fab_observed_classes[c] = true
      end

      for c in it.map(str.sub, str.matches(el.dataset.show or "", "[^%s]+")) do
        next_view.fab_observed_classes[c] = true
      end

      if el.classList:contains("minmax") then
        next_view.e_minmax = el
      end

      if not el.classList:contains("small") and
        last_view and last_view.el:querySelectorAll(".page > .fab:not(.small)")
      then
        arr.push(next_view.e_fabs_shared, el)
      elseif el.classList:contains("top") then
        arr.push(next_view.e_fabs_top, el)
      else
        arr.push(next_view.e_fabs_bottom, el)
      end

    end

    arr.reverse(next_view.e_fabs_bottom)

  end

  M.setup_snacks = function (next_view)

    next_view.e_snacks = next_view.el:querySelectorAll(".page > .snack")
    next_view.snack_observed_classes = {}

    for i = 0, next_view.e_snacks.length - 1 do

      local el = next_view.e_snacks:item(i)

      for c in it.map(str.sub, str.matches(el.dataset.hide or "", "[^%s]+")) do
        next_view.snack_observed_classes[c] = true
      end

      for c in it.map(str.sub, str.matches(el.dataset.show or "", "[^%s]+")) do
        next_view.snack_observed_classes[c] = true
      end

    end

  end

  -- TODO: Currently this figures out how many
  -- buttons are on either side of the title,
  -- and sets the title width such that it
  -- doesn't overlap the side with the most
  -- buttons. The problem is that if one side
  -- has a button and the other doesnt, and the
  -- title is long enough to overlap, it
  -- confusingly gets cut off on the side
  -- without buttons, when ideally it should
  -- only be getting cut off by the buttons. We
  -- need some sort of adaptive centering as the
  -- user types into the title input or based on
  -- the actual displayed length.
  M.setup_header_title_width = function (view)

    if not view.e_header then
      return
    end

    local e_title = view.e_header:querySelector("header > h1")

    if not e_title then
      return
    end

    if e_body.classList:contains("is-wide") then
      e_title.style.width = nil
      return
    end

    local offset_left = 0
    local offset_right = 0

    local lefting = true

    Array:from(view.e_header.children):forEach(function (_, el)

      if el.tagName == "H1" then
        return
      end

      if lefting and el.classList:contains("right") then
        lefting = false
      end

      if lefting then
        offset_left = offset_left + opts.header_height
      else
        offset_right = offset_right + opts.header_height
      end

    end)

    local shrink = num.max(offset_left, offset_right) * 2
    local width = "calc(100vw - " .. shrink .. "px)"

    e_title.style.width = width

  end

  M.style_maximized = function (view, animate)

    if view.maximized == nil then
      view.maximized = false
    end

    view.maximized = not view.maximized

    if view.maximized then
      view.el.classList:add("maximized")
      view.header_offset = view.header_offset - opts.header_height
      view.nav_offset = view.nav_offset - opts.header_height
      view.main_offset = view.main_offset - opts.header_height
      view.fabs_top_offset = (view.fabs_top_offset or 0) - opts.header_height
      view.snack_offset = view.snack_offset + opts.header_height
      view.snack_opacity = 0
    else
      view.el.classList:remove("maximized")
      view.header_offset = view.header_offset + opts.header_height
      view.nav_offset = view.nav_offset + opts.header_height
      view.main_offset = view.main_offset + opts.header_height
      view.fabs_top_offset = (view.fabs_top_offset or 0) + opts.header_height
      view.snack_offset = view.snack_offset - opts.header_height
      view.snack_opacity = 1
      if view.e_nav and e_body.classList:contains("is-wide") then
        M.toggle_nav_state(view, true, false, false)
      end
    end

    M.style_header(view, animate)
    M.style_nav(view, animate)
    M.style_main(view, animate)
    M.style_fabs(view, animate)
    M.style_snacks(view, animate)

  end

  M.setup_maximize = function (next_view)

    if not next_view.e_minmax then
      return
    end

    if next_view.e_header then
      next_view.e_header.classList:add("no-hide")
    end

    next_view.e_minmax:addEventListener("click", function ()
      M.style_maximized(next_view, true)
    end)

  end

  M.setup_ripples = function (el)

    el:querySelectorAll("button:not(.no-ripple)"):forEach(function (_, el)
      if el._ripple then
        return
      end
      M.setup_ripple(el)
      el._ripple = true
    end)

    el:querySelectorAll(".ripple"):forEach(function (_, el)
      if el._ripple or el == t_ripple then
        return
      end
      el._ripple = true
      M.setup_ripple(el)
    end)

  end

  M.get_base_nav_offset = function (view)
    return (update_worker and opts.banner_height or 0) +
           (view.maximized and (- opts.header_height) or 0)
  end

  M.get_base_main_offset = function (view)
    return (update_worker and opts.banner_height or 0) +
           (view.maximized and (- opts.header_height) or 0)
  end

  M.get_base_header_offset = function (view)
    return (update_worker and opts.banner_height or 0) +
           (view.maximized and (- opts.header_height) or 0)
  end

  M.get_base_fabs_top_offset = function (view)
    return (update_worker and opts.banner_height or 0) +
           (view.maximized and (- opts.header_height) or 0)
  end

  M.get_base_snack_offset = function (view)
    return (view.maximized and opts.header_height or 0)
  end

  M.should_show = function (view, el)

    local hides = it.collect(it.map(str.sub, str.matches(el.dataset.hide or "", "[^%s]+")))

    for h in it.ivals(hides) do
      if view.el.classList:contains(h) then
        return false
      end
    end

    local shows = it.collect(it.map(str.sub, str.matches(el.dataset.show or "", "[^%s]+")))

    if #shows == 0 then
      return true
    end

    for s in it.ivals(shows) do
      if view.el.classList:contains(s) then
        return true
      end
    end

    return false

  end

  M.style_header = function (view, animate)

    if not view.e_header then
      return
    end

    if animate then
      view.e_header.classList:add("animated")
      if view.header_animation then
        window:clearTimeout(view.header_animation)
        view.header_animation = nil
      end
      view.header_animation = M.after_transition(function ()
        view.e_header.classList:remove("animated")
        view.header_animation = nil
      end)
    end

    view.e_header.style.transform = "translateY(" .. view.header_offset .. "px)"
    view.e_header.style.opacity = view.header_opacity
    view.e_header.style["z-index"] = view.header_index
    view.e_header.style["box-shadow"] = view.header_shadow

  end

  M.style_nav = function (view, animate)

    if not view.e_nav then
      return
    end

    if animate then
      view.e_nav.classList:add("animated")
      if view.nav_animation then
        window:clearTimeout(view.nav_animation)
        view.nav_animation = nil
      end
      view.nav_animation = M.after_transition(function ()
        view.e_nav.classList:remove("animated")
        view.nav_animation = nil
      end)
    end

    if view.maximized then
      view.nav_slide = -270
    elseif not view.nav_slide then
      if view.e_nav and view.el.classList:contains("showing-nav") then
        view.nav_slide = 0
      else
        view.nav_slide = -270
      end
    end

    view.e_nav.style.transform = "translate(" .. view.nav_slide .. "px, " .. view.nav_offset .. "px)"
    view.e_nav.style.opacity = view.nav_opacity
    view.e_nav.style["z-index"] = view.nav_index

  end

  M.style_main = function (view, animate)

    if not view.e_main then
      return
    end

    if animate then
      view.e_main.classList:add("animated")
      if view.main_animation then
        window:clearTimeout(view.main_animation)
        view.main_animation = nil
      end
      view.main_animation = M.after_transition(function ()
        view.e_main.classList:remove("animated")
        view.main_animation = nil
      end)
    end

    local nav_push = view.maximized and 0 or ((view.e_nav and e_body.classList:contains("is-wide")) and 270 or 0)
    view.e_main.style.transform = "translate(" .. nav_push .. "px," .. view.main_offset .. "px)"
    view.e_main.style["min-width"] = "calc(100vw - " .. nav_push .. "px)"
    view.e_main.style.opacity = view.main_opacity
    view.e_main.style["z-index"] = view.main_index

  end

  M.style_main_switch = function (view, animate)

    if not view.e_main then
      return
    end

    if animate then
      view.e_main.classList:add("animated")
      if view.main_animation then
        window:clearTimeout(view.main_animation)
        view.main_animation = nil
      end
      view.main_animation = M.after_transition(function ()
        view.e_main.classList:remove("animated")
        view.main_animation = nil
      end)
    end

    view.e_main.style.transform = "translateY(" .. -view.main_offset .. "px)"
    view.e_main.style.opacity = view.main_opacity
    view.e_main.style["z-index"] = view.main_index

  end

  M.style_fabs = function (view, animate)

    if not view.e_fabs or view.e_fabs.length <= 0 then
      return
    end

    if animate then
      view.e_fabs:forEach(function (_, e_fab)
        e_fab.classList:add("animated")
      end)
      if view.fabs_animation then
        window:clearTimeout(view.fabs_animation)
        view.fabs_animation = nil
      end
      view.fabs_animation = M.after_transition(function ()
        view.e_fabs:forEach(function (_, e_fab)
          e_fab.classList:remove("animated")
        end)
        view.fabs_animation = nil
      end)
    end

    local bottom_offset_total = 0
    local top_offset_total = 0

    arr.each(view.e_fabs_shared, function (el)

      el.style["z-index"] = view.fab_shared_index

      if not M.should_show(view, el) then
        el.style.opacity = 0
        el.style["box-shadow"] = view.fab_shared_shadow
        el.style["pointer-events"] = "none"
        el.style.transform =
          "scale(0.75) " ..
          "translateY(" .. view.fab_shared_offset .. "px)"
        return
      end

      local e_svg = el:querySelector("svg")

      el.style["z-index"] = view.fab_shared_index
      el.style.opacity = view.fab_shared_opacity
      el.style["pointer-events"] = "all"
      el.style["box-shadow"] = view.fab_shared_shadow

      el.style.transform =
        "scale(" .. view.fab_shared_scale .. ") " ..
          "translateY(" .. view.fab_shared_offset .. "px)"

      e_svg.style.transform =
        "translateY(" .. view.fab_shared_svg_offset .. "px)"

      if el.classList:contains("top") then
        top_offset_total = top_offset_total +
          (el.classList:contains("small") and
            opts.fab_width_small or
            opts.fab_width_large)
      else
        bottom_offset_total = bottom_offset_total +
          (el.classList:contains("small") and
            opts.fab_width_small or
            opts.fab_width_large)
      end

    end)

    arr.each(view.e_fabs_bottom, function (el)

      el.style["z-index"] = view.fabs_bottom_index

      if not M.should_show(view, el) then
        el.style.opacity = 0
        el.style["pointer-events"] = "none"
        el.style.transform =
          "scale(0.75) " ..
          "translateY(" .. (view.fabs_bottom_offset - bottom_offset_total) .. "px)"
        return
      end

      el.style["pointer-events"] = "all"
      el.style.opacity = view.fabs_bottom_opacity
      el.style.transform =
        "scale(" .. view.fabs_bottom_scale .. ") " ..
        "translateY(" .. (view.fabs_bottom_offset - bottom_offset_total) .. "px)"

      bottom_offset_total = bottom_offset_total +
        (el.classList:contains("small") and
          opts.fab_width_small or
          opts.fab_width_large) + 16

    end)

    arr.each(view.e_fabs_top, function (el)

      el.style["z-index"] = view.fabs_top_index

      if not M.should_show(view, el) then
        el.style.opacity = 0
        el.style["pointer-events"] = "none"
        el.style.transform =
          "scale(0.75) " ..
          "translateY(" .. (view.fabs_top_offset - top_offset_total) .. "px)"
        return
      end

      el.style["pointer-events"] = "all"
      el.style.opacity = view.fabs_top_opacity
      el.style.transform =
        "scale(" .. (view.fabs_top_scale or 1) .. ") " ..
        "translateY(" .. (view.fabs_top_offset + top_offset_total) .. "px)"

      top_offset_total = top_offset_total +
        (el.classList:contains("small") and
          opts.fab_width_small or
          opts.fab_width_large) + 16

    end)

  end

  M.style_snacks = function (view, animate)

    if view.e_snacks.length <= 0 then
      return
    end

    if animate then
      view.e_snacks:forEach(function (_, e_snack)
        e_snack.classList:add("animated")
      end)
      if view.snack_animation then
        window:clearTimeout(view.snack_animation)
        view.snack_animation = nil
      end
      view.snack_animation = M.after_transition(function ()
        view.e_snacks:forEach(function (_, e_snack)
          e_snack.classList:remove("animated")
        end)
        view.snack_animation = nil
      end)
    end

    local bottom_offset_total = 0

    view.e_snacks:forEach(function (_, e_snack)
      local nav_push = view.maximized and 0 or ((view.e_nav and e_body.classList:contains("is-wide")) and 270 or 0)
      e_snack.style["z-index"] = view.snack_index
      if not M.should_show(view, e_snack) then
        e_snack.style.opacity = 0
        e_snack.style["pointer-events"] = "none"
        e_snack.style.transform =
          "translate(" .. nav_push .. "px," .. (view.snack_offset - bottom_offset_total) .. "px)"
      else
        e_snack.style.opacity = view.snack_opacity
        e_snack.style["pointer-events"] = (view.snack_opacity or 0) == 0 and "none" or "all"
        e_snack.style.transform =
          "translate(" .. nav_push .. "px," .. (view.snack_offset - bottom_offset_total) .. "px)"
        bottom_offset_total = bottom_offset_total +
            opts.snack_height + 16
      end
    end)

  end

  M.style_nav_transition = function (next_view, transition, direction, last_view)

    if not last_view and transition == "enter" then

      next_view.nav_offset = M.get_base_nav_offset(next_view)
      next_view.nav_opacity = 1
      next_view.nav_index = 97
      M.style_nav(next_view)

    elseif not last_view and transition == "exit" then

      error("invalid state: nav exit transition with no last view")

    elseif transition == "enter" and direction == "forward" then

      next_view.nav_offset = M.get_base_nav_offset(next_view) + opts.transition_forward_height
      next_view.nav_opacity = 0
      next_view.nav_index = 99
      M.style_nav(next_view)

      M.after_frame(function ()
        next_view.nav_offset = next_view.nav_offset - opts.transition_forward_height
        next_view.nav_opacity = 1
        M.style_nav(next_view, true)
      end)

    elseif transition == "exit" and direction == "forward" then

      last_view.nav_offset = M.get_base_nav_offset(last_view) - opts.transition_forward_height / 2
      last_view.nav_opacity = 1
      last_view.nav_index = 97
      M.style_nav(last_view, true)

    elseif transition == "enter" and direction == "backward" then

      next_view.nav_offset = M.get_base_nav_offset(next_view) - opts.transition_forward_height / 2
      next_view.nav_opacity = 1
      next_view.nav_index = 97
      M.style_nav(next_view)

      M.after_frame(function ()
        next_view.nav_offset = M.get_base_nav_offset(next_view)
        M.style_nav(next_view, true)
      end)

    elseif transition == "exit" and direction == "backward" then

      last_view.nav_offset = opts.transition_forward_height + M.get_base_nav_offset(last_view)
      last_view.nav_opacity = 0
      last_view.nav_index = 99
      M.style_nav(last_view, true)

    else

      error("invalid state: main transition")

    end

  end

  M.style_header_transition = function (next_view, transition, direction, last_view)

    next_view.header_min = - opts.header_height + M.get_base_header_offset(next_view)
    next_view.header_max = M.get_base_header_offset(next_view)

    if not last_view and transition == "enter" then

      next_view.header_offset = M.get_base_header_offset(next_view)
      next_view.header_opacity = 1
      next_view.header_index = 100
      next_view.header_shadow = opts.header_shadow
      M.style_header(next_view)

    elseif not last_view and transition == "exit" then

      error("invalid state: header exit transition with no last view")

    elseif transition == "enter" and direction == "forward" then

      next_view.header_offset = last_view and last_view.header_offset or
        M.get_base_header_offset(next_view)

      next_view.header_opacity = 0
      next_view.header_index = 100
      next_view.header_shadow = opts.header_shadow
      M.style_header(next_view)

      M.after_frame(function ()
        next_view.header_offset = M.get_base_header_offset(next_view)
        next_view.header_opacity = 1
        M.style_header(next_view, true)
      end)

    elseif transition == "exit" and direction == "forward" then

      last_view.header_offset = M.get_base_header_offset(last_view)
      last_view.header_opacity = 1
      last_view.header_index = 98
      last_view.header_shadow = opts.header_shadow
      M.style_header(last_view, true)

    elseif transition == "enter" and direction == "backward" then

      next_view.header_offset = last_view.e_header and last_view.header_offset or
        M.get_base_header_offset(next_view)
      next_view.header_opacity = 1
      next_view.header_index = 98
      next_view.header_shadow = opts.header_shadow
      M.style_header(next_view)

      M.after_frame(function ()
        next_view.header_offset = M.get_base_header_offset(next_view)
        next_view.header_opacity = 1
        M.style_header(next_view, true)
      end)

    elseif transition == "exit" and direction == "backward" then

      last_view.header_offset = last_view.e_header and last_view.header_offset or
        M.get_base_header_offset(next_view)
      last_view.header_opacity = 0
      last_view.header_index = 100
      last_view.header_shadow = opts.header_shadow
      M.style_header(last_view, true)

    else

      error("invalid state: header transition")

    end

  end

  M.style_main_transition = function (next_view, transition, direction, last_view)

    if not last_view and transition == "enter" then

      next_view.main_offset = M.get_base_main_offset(next_view)
      next_view.main_opacity = 1
      next_view.main_index = 96
      M.style_main(next_view)

    elseif not last_view and transition == "exit" then

      error("invalid state: main exit transition with no last view")

    elseif transition == "enter" and direction == "forward" then

      next_view.main_offset = M.get_base_main_offset(next_view) + opts.transition_forward_height
      next_view.main_opacity = 0
      next_view.main_index = 98
      M.style_main(next_view)

      M.after_frame(function ()
        next_view.main_offset = next_view.main_offset - opts.transition_forward_height
        next_view.main_opacity = 1
        M.style_main(next_view, true)
      end)

    elseif transition == "exit" and direction == "forward" then

      last_view.main_offset = M.get_base_main_offset(last_view) - opts.transition_forward_height / 2
      last_view.main_opacity = 1
      last_view.main_index = 96
      M.style_main(last_view, true)

    elseif transition == "enter" and direction == "backward" then

      next_view.main_offset = M.get_base_main_offset(next_view) - opts.transition_forward_height / 2
      next_view.main_opacity = 1
      next_view.main_index = 96
      M.style_main(next_view)

      M.after_frame(function ()
        next_view.main_offset = M.get_base_main_offset(next_view)
        M.style_main(next_view, true)
      end)

    elseif transition == "exit" and direction == "backward" then

      last_view.main_offset = opts.transition_forward_height + M.get_base_main_offset(last_view)
      last_view.main_opacity = 0
      last_view.main_index = 98
      M.style_main(last_view, true)

    else

      error("invalid state: main transition")

    end

  end

  M.style_main_transition_switch = function (next_view, transition, direction, last_view)

    if not last_view and transition == "enter" then

      next_view.main_offset = 0
      next_view.main_opacity = 1
      next_view.main_index = 96
      M.style_main_switch(next_view)

    elseif not last_view and transition == "exit" then

      error("invalid state: main exit transition with no last view")

    elseif transition == "enter" and direction == "forward" then

      next_view.main_offset = 32
      next_view.main_opacity = 0
      next_view.main_index = 96
      M.style_main_switch(next_view)

      M.after_frame(function ()
        next_view.main_offset = 0
        next_view.main_opacity = 1
        M.style_main_switch(next_view, true)
      end)

    elseif transition == "exit" and direction == "forward" then

      last_view.main_offset = -32
      last_view.main_opacity = 0
      last_view.main_index = 98
      M.style_main_switch(last_view, true)

    elseif transition == "enter" and direction == "backward" then

      next_view.main_offset = -32
      next_view.main_opacity = 0
      next_view.main_index = 96
      M.style_main_switch(next_view)

      M.after_frame(function ()
        next_view.main_offset = 0
        next_view.main_opacity = 1
        M.style_main_switch(next_view, true)
      end)

    elseif transition == "exit" and direction == "backward" then

      last_view.main_offset = 32
      last_view.main_opacity = 0
      last_view.main_index = 98
      M.style_main_switch(last_view, true)

    else

      error("invalid state: main transition")

    end

  end

  M.style_fabs_transition = function (next_view, transition, direction, last_view)

    local is_shared =
      (next_view and next_view.e_fabs and next_view.e_fabs.length > 0) and
      (last_view and last_view.e_fabs and last_view.e_fabs.length > 0)

    if not last_view and transition == "enter" then

      next_view.fab_shared_index = 99
      next_view.fab_shared_scale = 1
      next_view.fab_shared_opacity = 1
      next_view.fab_shared_shadow = opts.fab_shadow
      next_view.fab_shared_offset = 0
      next_view.fab_shared_svg_offset = 0

      next_view.fabs_bottom_index = 98
      next_view.fabs_bottom_scale = 1
      next_view.fabs_bottom_opacity = 1
      next_view.fabs_bottom_offset = 0

      next_view.fabs_top_index = 98
      next_view.fabs_top_scale = 1
      next_view.fabs_top_opacity = 1
      next_view.fabs_top_offset = M.get_base_fabs_top_offset(next_view)

      M.style_fabs(next_view)

    elseif not last_view and transition == "exit" then

      error("invalid state: fabs exit transition with no last view")

    elseif is_shared and transition == "enter" and direction == "forward" then

      next_view.fab_shared_index = 99
      next_view.fab_shared_scale = 1
      next_view.fab_shared_opacity = 0
      next_view.fab_shared_shadow = opts.fab_shadow
      next_view.fab_shared_offset = 0
      next_view.fab_shared_svg_offset = opts.fab_shared_svg_transition_height

      next_view.fabs_bottom_index = 98
      next_view.fabs_bottom_scale = 0.75
      next_view.fabs_bottom_opacity = 0
      next_view.fabs_bottom_offset = opts.transition_forward_height

      next_view.fabs_top_index = 98
      next_view.fabs_top_scale = 0.75
      next_view.fabs_top_opacity = 0
      next_view.fabs_top_offset = opts.transition_forward_height + M.get_base_fabs_top_offset(next_view)

      M.style_fabs(next_view)

      M.after_frame(function ()
        next_view.fab_shared_svg_offset = 0
        next_view.fab_shared_opacity = 1
        next_view.fabs_bottom_scale = 1
        next_view.fabs_bottom_opacity = 1
        next_view.fabs_bottom_offset = 0
        next_view.fabs_top_scale = 1
        next_view.fabs_top_opacity = 1
        next_view.fabs_top_offset = M.get_base_fabs_top_offset(next_view)
        M.style_fabs(next_view, true)
      end)

    elseif is_shared and transition == "exit" and direction == "forward" then

      last_view.fab_shared_index = 99
      last_view.fab_shared_scale = 1
      last_view.fab_shared_opacity = 1
      last_view.fab_shared_shadow = opts.fab_shadow_transparent
      last_view.fab_shared_offset = 0
      last_view.fab_shared_svg_offset = - opts.fab_shared_svg_transition_height

      last_view.fabs_bottom_index = 96
      last_view.fabs_bottom_scale = 1
      last_view.fabs_bottom_opacity = 0
      last_view.fabs_bottom_offset = 0

      last_view.fabs_top_index = 96
      last_view.fabs_top_scale = 1
      last_view.fabs_top_opacity = 0
      last_view.fabs_top_offset = M.get_base_fabs_top_offset(last_view)

      M.style_fabs(last_view, true)

    elseif is_shared and transition == "enter" and direction == "backward" then

      next_view.fab_shared_index = 99
      next_view.fab_shared_scale = 1
      next_view.fab_shared_opacity = 0
      next_view.fab_shared_shadow = opts.fab_shadow
      next_view.fab_shared_offset = 0
      next_view.fab_shared_svg_offset = - opts.fab_shared_svg_transition_height

      next_view.fabs_bottom_index = 96
      next_view.fabs_bottom_scale = 0.75
      next_view.fabs_bottom_opacity = 0
      next_view.fabs_bottom_offset = 0

      next_view.fabs_top_index = 96
      next_view.fabs_top_scale = 0.75
      next_view.fabs_top_opacity = 0
      next_view.fabs_top_offset = M.get_base_fabs_top_offset(next_view)

      M.style_fabs(next_view)

      M.after_frame(function ()
        next_view.fab_shared_svg_offset = 0
        next_view.fab_shared_opacity = 1
        next_view.fabs_bottom_scale = 1
        next_view.fabs_bottom_opacity = 1
        next_view.fabs_top_scale = 1
        next_view.fabs_top_opacity = 1
        M.style_fabs(next_view, true)
      end)

    elseif is_shared and transition == "exit" and direction == "backward" then

      last_view.fab_shared_index = 99
      last_view.fab_shared_scale = 1
      last_view.fab_shared_opacity = 1
      last_view.fab_shared_shadow = opts.fab_shadow_transparent
      last_view.fab_shared_offset = 0
      last_view.fab_shared_svg_offset = opts.fab_shared_svg_transition_height

      last_view.fabs_bottom_index = 98
      last_view.fabs_bottom_scale = 0.75
      last_view.fabs_bottom_opacity = 0
      last_view.fabs_bottom_offset = opts.transition_forward_height

      last_view.fabs_top_index = 100
      last_view.fabs_top_scale = 0.75
      last_view.fabs_top_opacity = 0
      last_view.fabs_top_offset = opts.transition_forward_height + M.get_base_fabs_top_offset(last_view)

      M.style_fabs(last_view, true)

    elseif transition == "enter" and direction == "forward" then

      next_view.fab_shared_index = 98
      next_view.fab_shared_scale = 0.75
      next_view.fab_shared_opacity = 0
      next_view.fab_shared_shadow = opts.fab_shadow
      next_view.fab_shared_offset = opts.transition_forward_height
      next_view.fab_shared_svg_offset = 0

      next_view.fabs_bottom_index = 98
      next_view.fabs_bottom_scale = 0.75
      next_view.fabs_bottom_opacity = 0
      next_view.fabs_bottom_offset = opts.transition_forward_height

      next_view.fabs_top_index = 98
      next_view.fabs_bottom_scale = 0.75
      next_view.fabs_bottom_opacity = 0
      next_view.fabs_top_offset = opts.transition_forward_height + M.get_base_fabs_top_offset(next_view)

      M.style_fabs(next_view)

      M.after_frame(function ()
        next_view.fab_shared_scale = 1
        next_view.fab_shared_opacity = 1
        next_view.fab_shared_offset = 0
        next_view.fabs_bottom_scale = 1
        next_view.fabs_bottom_opacity = 1
        next_view.fabs_bottom_offset = 0
        next_view.fabs_top_scale = 1
        next_view.fabs_top_opacity = 1
        next_view.fabs_top_offset = M.get_base_fabs_top_offset(next_view)
        M.style_fabs(next_view, true)
      end)

    elseif transition == "enter" and direction == "backward" then

      next_view.fab_shared_index = 96
      next_view.fab_shared_scale = 0.75
      next_view.fab_shared_opacity = 0
      next_view.fab_shared_shadow = opts.fab_shadow
      next_view.fab_shared_offset = 0
      next_view.fab_shared_svg_offset = 0

      next_view.fabs_bottom_index = 96
      next_view.fabs_bottom_scale = 0.75
      next_view.fabs_bottom_opacity = 0
      next_view.fabs_bottom_offset = 0

      next_view.fabs_top_index = 96
      next_view.fabs_bottom_scale = 0.75
      next_view.fabs_bottom_opacity = 0
      next_view.fabs_top_offset = M.get_base_fabs_top_offset(next_view)

      M.style_fabs(next_view)

      M.after_frame(function ()
        next_view.fab_shared_scale = 1
        next_view.fab_shared_opacity = 1
        next_view.fabs_bottom_scale = 1
        next_view.fabs_bottom_opacity = 1
        next_view.fabs_top_scale = 1
        next_view.fabs_top_opacity = 1
        M.style_fabs(next_view, true)
      end)

    elseif transition == "exit" and direction == "forward" then

      last_view.fab_shared_index = 96
      last_view.fab_shared_scale = 1
      last_view.fab_shared_opacity = 0
      last_view.fab_shared_shadow = opts.fab_shadow
      last_view.fab_shared_offset = 0
      last_view.fab_shared_svg_offset = 0

      last_view.fabs_bottom_index = 96
      last_view.fabs_bottom_scale = 1
      last_view.fabs_bottom_opacity = 0
      last_view.fabs_bottom_offset = 0

      last_view.fabs_top_index = 96
      last_view.fabs_top_scale = 1
      last_view.fabs_top_opacity = 0
      last_view.fabs_top_offset = M.get_base_fabs_top_offset(last_view)

      M.style_fabs(last_view, true)

    elseif transition == "exit" and direction == "backward" then

      last_view.fab_shared_index = 98
      last_view.fab_shared_scale = 0.75
      last_view.fab_shared_opacity = 0
      last_view.fab_shared_shadow = opts.fab_shadow
      last_view.fab_shared_offset = opts.transition_forward_height
      last_view.fab_shared_svg_offset = 0

      last_view.fabs_bottom_index = 98
      last_view.fabs_bottom_scale = 0.75
      last_view.fabs_bottom_opacity = 0
      last_view.fabs_bottom_offset = opts.transition_forward_height

      last_view.fabs_top_index = 98
      last_view.fabs_top_scale = 0.75
      last_view.fabs_top_opacity = 0
      last_view.fabs_top_offset = opts.transition_forward_height + M.get_base_fabs_top_offset(last_view)

      M.style_fabs(last_view, true)

    else

      error("invalid state: fabs transition")

    end

  end

  M.style_snacks_transition = function (next_view, transition, direction, last_view)

    if not last_view and transition == "enter" then

      next_view.snack_offset = M.get_base_snack_offset(next_view)
      next_view.snack_opacity = next_view.maximized and 0 or 1
      next_view.snack_index = 96
      M.style_snacks(next_view)

    elseif not last_view and transition == "exit" then

      error("invalid state: snack exit transition with no last view")

    elseif transition == "enter" and direction == "forward" then

      next_view.snack_offset = M.get_base_snack_offset(next_view) + opts.transition_forward_height
      next_view.snack_opacity = 0
      next_view.snack_index = 98
      M.style_snacks(next_view)

      M.after_frame(function ()
        next_view.snack_offset = next_view.snack_offset - opts.transition_forward_height
        next_view.snack_opacity = next_view.maximized and 0 or 1
        M.style_snacks(next_view, true)
      end)

    elseif transition == "exit" and direction == "forward" then

      last_view.snack_offset = M.get_base_snack_offset(last_view) - opts.transition_forward_height / 2
      last_view.snack_opacity = next_view.maximized and 0 or 1
      last_view.snack_index = 96
      M.style_snacks(last_view, true)

    elseif transition == "enter" and direction == "backward" then

      next_view.snack_offset = M.get_base_snack_offset(next_view)  - opts.transition_forward_height / 2
      next_view.snack_opacity = next_view.maximized and 0 or 1
      next_view.snack_index = 96
      M.style_snacks(next_view)

      M.after_frame(function ()
        next_view.snack_offset = M.get_base_snack_offset(next_view)
        M.style_snacks(next_view, true)
      end)

    elseif transition == "exit" and direction == "backward" then

      last_view.snack_offset = opts.transition_forward_height + M.get_base_snack_offset(last_view)
      last_view.snack_opacity = 0
      last_view.snack_index = 98
      M.style_snacks(last_view, true)

    else

      error("invalid state: main transition")

    end

  end

  M.style_header_hide = function (view, hide)
    if hide then
      view.header_offset = M.get_base_header_offset(view) - opts.header_height
    else
      view.header_offset = M.get_base_header_offset(view)
    end
    view.nav_offset = view.header_offset
    M.style_header(view, true)
    M.style_nav(view, true)
  end

  M.scroll_listener = function (view)
    local ready = true
    local last_scroll, curr_scroll
    return function ()
      if ready then
        ready = false
        M.after_frame(function ()
          curr_scroll = window.scrollY
          if (curr_scroll <= tonumber(opts.header_height)) or (last_scroll and last_scroll - curr_scroll > 10) then
            M.style_header_hide(view, false)
          elseif (last_scroll and curr_scroll - last_scroll > 10) then
            M.style_header_hide(view, true)
          end
          last_scroll = curr_scroll
          ready = true
        end)
      end
    end
  end

  M.after_transition = function (fn)
    return window:setTimeout(function ()
      window:requestAnimationFrame(fn)
    end, tonumber(opts.transition_time))
  end

  M.after_frame = function (fn)
    return window:requestAnimationFrame(function ()
      window:requestAnimationFrame(fn)
    end)
  end

  M.post_enter_switch = function (view, next_view)
    view.el.classList:remove("transition")
    M.setup_ripples(next_view.el)
  end

  M.post_exit_switch = function (last_view)
    last_view.el:remove()
    if last_view.page.destroy then
      last_view.page.destroy(last_view, opts)
    end
  end

  M.post_exit = function (last_view)
    last_view.el:remove()
    if last_view.page.destroy then
      last_view.page.destroy(last_view, opts)
    end
  end

  M.post_enter = function (next_view)

    e_body.classList:remove("transition")

    if next_view.page.post_append then
      next_view.page.post_append(next_view, opts)
    end

    local e_back = next_view.el:querySelector(".page > header > .back")

    if e_back then
      e_back:addEventListener("click", function ()
        history:back()
      end)
    end

    local e_menu = next_view.el:querySelector(".page > header > .menu")

    if e_menu then
      e_menu:addEventListener("click", function ()
        M.toggle_nav_state(next_view)
      end)
    end

    if next_view.e_header and not next_view.e_header.classList:contains("no-hide") then
      next_view.curr_scrolly = nil
      next_view.last_scrolly = nil
      next_view.scroll_listener = M.scroll_listener(next_view)
      window:addEventListener("scroll", next_view.scroll_listener)
    end

    M.setup_ripples(next_view.el)

  end

  M.enter_switch = function (view, next_view, direction, last_view)

    next_view.el = util.clone(next_view.page.template)
    next_view.e_main = next_view.el:querySelector(".page > main")

    M.style_main_transition_switch(next_view, "enter", direction, last_view)

    if next_view.page.init then
      next_view.page.init(next_view, opts)
    end

    view.el.classList:add("transition")
    view.e_main:append(next_view.el)

    M.after_transition(function ()
      return M.post_enter_switch(view, next_view)
    end)

  end

  M.exit_switch = function (view, last_view, direction, next_view)

    view.header_offset = M.get_base_header_offset(view)
    M.style_header(view, true)

    last_view.el.style.marginTop = "-" .. window.scrollY .. "px"
    window:scrollTo({ top = 0, left = 0, behavior = "instant" })

    M.style_main_transition_switch(next_view, "exit", direction, last_view)

    M.after_transition(function ()
      return M.post_exit_switch(last_view)
    end)

    last_view.el.classList:add("exit", direction)

  end

  M.enter = function (next_view, direction, last_view, sub_view_name)

    next_view.el = util.clone(next_view.page.template)
    next_view.e_header = next_view.el:querySelector(".page > header")
    next_view.e_main = next_view.el:querySelector(".page > main")
    next_view.e_snacks = next_view.el:querySelector(".page > .snacks")

    M.setup_observer(next_view)
    M.setup_nav(next_view, sub_view_name)
    M.setup_fabs(next_view, last_view)
    M.setup_snacks(next_view)
    M.setup_header_title_width(next_view)
    M.setup_maximize(next_view)
    M.style_header_transition(next_view, "enter", direction, last_view)
    M.style_main_transition(next_view, "enter", direction, last_view)
    M.style_nav_transition(next_view, "enter", direction, last_view)
    M.style_fabs_transition(next_view, "enter", direction, last_view)
    M.style_snacks_transition(next_view, "enter", direction, last_view)

    if next_view.page.init then
      next_view.page.init(next_view, opts)
    end

    e_body.classList:add("transition")
    e_body:append(next_view.el)

    M.after_transition(function ()
      return M.post_enter(next_view)
    end)

  end

  M.exit = function (last_view, direction, next_view)

    last_view.e_main.style.marginTop = (opts.header_height - window.scrollY) .. "px"
    window:scrollTo({ top = 0, left = 0, behavior = "instant" })
    M.after_transition(function ()
      last_view.e_main.style.marginTop = opts.header_height .. "px"
    end)

    M.style_header_transition(next_view, "exit", direction, last_view)
    M.style_main_transition(next_view, "exit", direction, last_view)
    M.style_nav_transition(next_view, "exit", direction, last_view)
    M.style_fabs_transition(next_view, "exit", direction, last_view)
    M.style_snacks_transition(next_view, "exit", direction, last_view)

    if last_view.scroll_listener then
      window:removeEventListener("scroll", last_view.scroll_listener)
      last_view.scroll_listener = nil
    end

    last_view.el.classList:add("exit", direction)
    M.after_transition(function ()
      return M.post_exit(last_view, opts)
    end)

  end

  M.init_view = function (name, page)

    local view = {
      forward = M.forward,
      backward = M.backward,
      replace_forward = M.replace_forward,
      replace_backward = M.replace_backward,
      page = page,
      name = name,
      state = state
    }

    view.toggle_nav = function ()
      return M.toggle_nav_state(active_view, not view.el.classList:contains("showing-nav"), true, true)
    end

    view.toggle_maximize = function ()
      return M.style_maximized(active_view, true)
    end

    return view

  end

  M.get_url = function ()
    local p = util.encode_path(state)
    return "/#" .. p
  end

  M.set_route = function (policy)
    if policy == "replace" then
      history:replaceState(val(state, true), nil, M.get_url())
    elseif policy == "push" then
      history:pushState(val(state, true), nil, M.get_url())
    end
  end

  M.switch_dir = function (view, next_switch, last_switch)
    local idx_next, idx_last
    idx_next = varg.sel(2, arr.find(view.nav_order, fun.bind(op.eq, next_switch.name)))
    if last_switch then
      idx_last = varg.sel(2, arr.find(view.nav_order, fun.bind(op.eq, last_switch.name)))
      return idx_next < idx_last and "backward" or "forward"
    else
      return "forward"
    end
  end

  M.maybe_redirect = function (page)
    if page and page.redirect then
      return varg.tup(function (redir, ...)
        if redir then
          M.replace_forward(...)
          return true
        end
      end, page.redirect(active_view, page))
    end
  end

  M.switch = function (view, name, policy)

    local page = view.page.pages and view.page.pages[name]

    if not page then
      err.error("no switch found", name)
    end

    if M.maybe_redirect(page, policy) then
      return
    end

    local last_view = view.active_view
    view.active_view = M.init_view(name, page)

    view.e_nav_buttons:forEach(function (_, el)
      if el.dataset.page == name then
        el.classList:add("is-active")
      else
        el.classList:remove("is-active")
      end
    end)

    local dir = M.switch_dir(view, view.active_view, last_view)

    M.enter_switch(view, view.active_view, dir, last_view)

    if last_view then
      M.exit_switch(view, last_view, dir, view.active_view)
    end

    M.set_route(policy)

  end

  M.fill_defaults = function ()
    if #state.path < 1 then
      return
    end
    local v = opts.pages[state.path[1]]
    if not v then
      err.error("Invalid page", state.path[1])
    end
    if v.pages and not state.path[2] then
      M.find_default(v.pages, state.path, 2)
    end
  end

  M.forward = function (...)
    arr.overlay(state.path, 1, ...)
    M.transition("push", "forward")
  end

  M.backward = function (...)
    arr.overlay(state.path, 1, ...)
    M.transition("push", "backward")
  end

  M.replace_forward = function (...)
    arr.overlay(state.path, 1, ...)
    M.transition("replace", "forward")
  end

  M.replace_backward = function (...)
    arr.overlay(state.path, 1, ...)
    M.transition("replace", "backward")
  end

  M.transition = function (policy, dir)
    dir = dir or "forward"
    M.after_frame(function ()

      M.fill_defaults()

      local page = opts.pages[state.path[1]]

      if not page then
        err.error("no page found", state.path[1])
      end

      if M.maybe_redirect(page, policy) then
        return
      end

      if not active_view or page ~= active_view.page then
        local last_view = active_view
        active_view = M.init_view(state.path[1], page)
        M.enter(active_view, dir, last_view, state.path[2])
        if last_view then
          M.exit(last_view, dir, active_view)
        end
        M.set_route(policy)
      elseif state.path[2] then
        M.switch(active_view, state.path[2], policy)
      else
        M.set_route(policy)
      end

    end)
  end

  window:addEventListener("popstate", function (_, ev)
    if ev.state then
      state = ev.state:val():lua(true)
      M.transition("ignore", "backward")
    end
  end)

  M.setup_ripples(e_body)

  M.toggle_nav_state = function (view, open, animate, restyle)
    if e_body.classList:contains("is-wide") then
      open = true
    end
    if open == true then
      view.el.classList:add("showing-nav")
    elseif open == false then
      view.el.classList:remove("showing-nav")
    else
      view.el.classList:toggle("showing-nav")
    end
    if view.el.classList:contains("showing-nav") then
      view.nav_slide = 0
    else
      view.nav_slide = -270
    end
    if restyle ~= false then
      M.style_nav(view, animate ~= false)
    end
  end

  M.on_resize = function ()
    local was_wide = e_body.classList:contains("is-wide")
    if window.innerWidth > 961 then
      e_body.classList:add("is-wide")
    else
      e_body.classList:remove("is-wide")
    end
    if active_view then
      if e_body.classList:contains("is-wide") then
        M.toggle_nav_state(active_view, true, false, false)
      elseif was_wide then
        M.toggle_nav_state(active_view, false, false, false)
      end
      M.style_nav(active_view, true)
      M.style_main(active_view, true)
      M.style_snacks(active_view, true)
    end
  end

  if opts.service_worker then

    local navigator = window.navigator
    local serviceWorker = navigator.serviceWorker

    local e_reload = document:querySelector("body > .warn-update-worker")
    if e_reload then
      e_reload:addEventListener("click", function ()
        window.location:reload()
      end)
    end

    M.style_update_worker = function ()

      if not update_worker then

        update_worker = true

        active_view.header_offset = active_view.header_offset + opts.banner_height
        active_view.nav_offset = active_view.nav_offset + opts.banner_height
        active_view.main_offset = active_view.main_offset + opts.banner_height
        active_view.fabs_top_offset = active_view.fabs_top_offset + opts.banner_height
        active_view.header_min = - opts.header_height + M.get_base_header_offset(active_view)
        active_view.header_max = M.get_base_header_offset(active_view)

        M.style_header(active_view, true)
        M.style_nav(active_view, true)
        M.style_main(active_view, true)
        M.style_fabs(active_view, true)

      end

      e_body.classList:add("update-worker")

    end

    M.poll_worker_update = function (reg)

      local polling = false
      local installing = false

      window:setInterval(function ()

        if polling then
          return
        end

        polling = true

        reg:update():await(function (_, ok, reg)

          polling = false

          if not ok then
            print("Service worker update error", reg and reg.message or reg)
          elseif reg.installing then
            installing = true
            print("Updated service worker installing")
          elseif reg.waiting then
            print("Updated service worker installed")
          elseif reg.active then
            if installing then
              installing = false
              M.style_update_worker()
            end
            print("Updated service worker active")
          end

        end)

      end, opts.service_worker_poll_time_ms)

    end

    if serviceWorker then

      serviceWorker:register("/sw.js", { scope = "/" }):await(function (_, ...)

        local reg = err.checkok(...)

        if reg.installing then
          print("Initial service worker installing")
        elseif reg.waiting then
          print("Initial service worker installed")
        elseif reg.active then
          print("Initial service worker active")
        end

        M.poll_worker_update(reg)

      end)

    end

  end

  window:addEventListener("resize", function ()
    M.on_resize()
  end)

  M.on_resize()

  if #state.path > 0 then
    M.transition("replace", "forward")
  else
    M.find_default(opts.pages, state.path, 1)
    M.transition("push", "forward")
  end

end
