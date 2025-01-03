local err = require("santoku.error")
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
local def = require("santoku.web.spa.defaults")

return function (opts)

  opts = tbl.merge({}, opts or {}, def.spa or {})

  local Array = js.Array
  local MutationObserver = js.MutationObserver
  local window = js.window
  local history = window.history
  local document = window.document
  local location = window.location

  local e_head = document.head
  local e_body = document.body
  local t_ripple = e_head:querySelector("template.ripple")
  local t_nav_overlay = e_head:querySelector("template.nav-overlay")

  local base_path = location.pathname
  local state = util.parse_path(str.match(location.hash, "^#(.*)"))
  local active_view

  local M = {}

  local handlers = {}

  M.add_listener = function (ev, handler)
    if not ev or not handler then
      return
    end
    handlers[ev] = handlers[ev] or {}
    handlers[ev][handler] = true
  end

  M.remove_listener = function (ev, handler)
    if not ev or not handler then
      return
    end
    local hs = handlers[ev]
    if not hs then
      return
    end
    hs[handler] = nil
    if not next(hs) then
      handlers[ev] = nil
    end
  end

  M.emit = function (ev, ...)
    if not ev then
      return
    end
    local hs = handlers[ev]
    if not hs then
      return
    end
    for h in pairs(hs) do
      h(...)
    end
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
        el.classList:remove("is-clicked")
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

      el.classList:add("is-clicked")
      el:append(e_ripple)

    end, false)

  end

  M.setup_banners = function (view)

    view.e_banners = view.el:querySelectorAll("section > aside")
    view.banner_observed_classes = {}

    for i = 0, view.e_banners.length - 1 do

      local el = view.e_banners:item(i)

      for c in it.map(str.sub, str.matches(el.dataset.hide or "", "[^%s]+")) do
        view.banner_observed_classes[c] = true
      end

      for c in it.map(str.sub, str.matches(el.dataset.show or "", "[^%s]+")) do
        view.banner_observed_classes[c] = true
      end

    end

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

        local banners = false
        local fabs = false
        local snacks = false

        view.el.classList:forEach(function (_, c)
          if not old_classes[c] then
            if view.banner_observed_classes and view.banner_observed_classes[c] then
              banners = true
            end
            if view.fab_observed_classes and view.fab_observed_classes[c] then
              fabs = true
            end
            if view.snack_observed_classes and view.snack_observed_classes[c] then
              snacks = true
            end
          end
        end)

        for c in it.keys(old_classes) do
          if not view.el.classList:contains(c) then
            if view.banner_observed_classes and view.banner_observed_classes[c] then
              banners = true
            end
            if view.fab_observed_classes and view.fab_observed_classes[c] then
              fabs = true
            end
            if view.snack_observed_classes and view.snack_observed_classes[c] then
              snacks = true
            end
          end
        end

        old_classes = it.reduce(function (a, n)
          a[n] = true
          return a
        end, {}, it.map(str.sub, str.matches(view.el.className or "", "[^%s]+")))

        if banners then
          M.style_banners(view, true)
          M.style_header(active_view.active_view, true)
          M.style_nav(active_view.active_view, true)
          M.style_fabs(active_view.active_view, true)
          if active_view.active_view.active_view then
            M.style_main_header_switch(active_view.active_view.active_view, true)
            M.style_main_switch(active_view.active_view.active_view, true)
          else
            M.style_main(active_view.active_view, true)
          end
        end

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

  M.setup_dropdowns = function (view, _, el)
    el = el or view.el
    view.e_dropdowns = el:querySelectorAll(".tk-dropdown")
    view.e_dropdowns:forEach(function (_, e_dropdown)
      local e_trigger = e_dropdown:querySelector(":scope > button")
      document:addEventListener("click", function (_, ev)
        if ev.e_dropdown ~= e_dropdown then
          e_dropdown.classList:remove("tk-open")
        end
      end)
      e_dropdown:addEventListener("click", function (_, ev)
        ev.e_dropdown = e_dropdown
      end)
      e_trigger:addEventListener("click", function ()
        e_dropdown.classList:add("tk-open")
      end)
    end)
  end

  M.setup_panes = function (view, init, el)
    el = el or view.el
    if not view.page.panes then
      return
    end
    el:querySelectorAll("[data-pane]"):forEach(function (_, el0)
      local name = el0.dataset.pane
      local pane = view.page.panes[name]
      if pane then
        pane.el = el0
        M.pane(view, name, pane.pages.default, init)
      end
    end)
  end

  M.get_nav_button_page = function (el)
    local name, push
    name = el.dataset.page or el.dataset.pagePush
    push = name
    name = name or el.dataset.pageReplace
    return name, push
  end

  -- TODO: does this cause a memory leak?
  M.setup_header_links = function (view)
    local e_header_links = active_view.active_view.e_header_links or {}
    active_view.active_view.e_header_links = e_header_links
    view.el:querySelectorAll(".tk-header-link"):forEach(function (_, el)
      arr.push(e_header_links, el)
    end)
  end

  M.setup_nav = function (view, dir, init, explicit)

    view.e_nav = view.el:querySelector("section > nav")

    if view.e_nav then

      view.e_nav:addEventListener("scroll", function (_, ev)
        ev:stopPropagation()
      end)

      view.e_nav_overlay = util.clone(t_nav_overlay, nil, view.el)

      view.e_nav_overlay:addEventListener("click", function ()
        M.toggle_nav_state(false)
      end)

      local triggered_open = false
      local n_active_touch = 0
      local active_touch_x = {}

      local function on_touch_start (_, ev)
        if n_active_touch == 0 and ev.changedTouches.length == 1 and
          ev.changedTouches[0].pageX <= tonumber(opts.nav_pull_gutter)
        then
          ev:preventDefault()
          Array:from(ev.changedTouches):forEach(function (_, t)
            n_active_touch = n_active_touch + 1
            active_touch_x[t] = t.pageX
          end)
        end
      end

      local function on_touch_move (_, ev)
        if not triggered_open and n_active_touch == 1 then
          local _, x0 = next(active_touch_x)
          local x1 = ev.changedTouches[0].pageX
          if (x1 - x0) >= tonumber(opts.nav_pull_threshold) then
            triggered_open = true
            M.toggle_nav_state(true)
          end
        end
      end

      local function on_touch_end (_, ev)
        Array:from(ev.changedTouches):forEach(function (_, t)
          n_active_touch = n_active_touch - 1
          if n_active_touch < 0 then
            n_active_touch = 0
          end
          active_touch_x[t] = nil
          if n_active_touch == 0 then
            triggered_open = false
          end
        end)
      end

      view.e_main:addEventListener("touchstart", on_touch_start, false)
      view.e_main:addEventListener("touchmove", on_touch_move)
      view.e_main:addEventListener("touchend", on_touch_end)
      view.e_main:addEventListener("touchcancel", on_touch_end)

      view.e_nav_buttons = view.e_nav
        :querySelectorAll("button[data-page], button[data-page-replace], button[data-page-push]")
      view.nav_order = {}
      view.e_nav_buttons:forEach(function (_, el)
        local name, push = M.get_nav_button_page(el)
        arr.push(view.nav_order, name)
        view.nav_order[name] = #view.nav_order
        el:addEventListener("click", function ()
          if not el.classList:contains("is-active") then
            if push then
              M.forward(view.name, name)
            else
              M.replace_forward(view.name, name)
            end
          end
          util.after_frame(function ()
            M.toggle_nav_state(false)
          end)
        end)
      end)

    end

    if not state.path[2] then
      M.find_default(view.page, state.path, 2)
    end

    if state.path[2] then
      M.switch(view, state.path[2], dir, init, explicit)
    end

    if view.e_nav then
      if active_view.el.classList:contains("is-wide") then
        M.toggle_nav_state(true, false, false)
      else
        M.toggle_nav_state(false, false, false)
      end
    end

  end

  M.setup_fabs = function (next_view, last_view)

    next_view.e_fabs = next_view.el:querySelectorAll("section > button")

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

      if not el.classList:contains("small") and not el.classList:contains("top") and
        last_view and last_view.el:querySelectorAll("section > button:not(.small):not(.top)")
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

    next_view.e_snacks = next_view.el:querySelectorAll("section > aside")
    next_view.e_snacks = Array:from(next_view.e_snacks):reverse()

    next_view.snack_observed_classes = {}

    next_view.e_snacks:forEach(function (_, el)
      for c in it.map(str.sub, str.matches(el.dataset.hide or "", "[^%s]+")) do
        next_view.snack_observed_classes[c] = true
      end
      for c in it.map(str.sub, str.matches(el.dataset.show or "", "[^%s]+")) do
        next_view.snack_observed_classes[c] = true
      end
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

  M.get_subheader_offset = function (view)
    local offset = M.get_base_header_offset() + (view.header_offset or 0) + (opts.header_height or 0)
    if view.active_view and view.active_view.e_main_header then
      offset = offset + (opts.header_height or 0)
    end
    return offset
  end

  M.get_base_header_offset = function ()
    return (active_view.banner_offset_total or 0)
  end

  M.get_base_footer_offset = function ()
    return 0
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

    view.e_header.style.transform = "translateY(" .. (M.get_base_header_offset() + view.header_offset) .. "px)"
    view.e_header.style.opacity = view.header_opacity
    view.e_header.style["z-index"] = view.header_index

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

    if not view.nav_slide then
      if view.e_nav and view.el.classList:contains("showing-nav") then
        view.nav_slide = 0
      else
        view.nav_slide = -opts.nav_width
      end
    end

    view.e_nav.style.transform =
      "translate(" .. view.nav_slide .. "px, " .. (M.get_base_header_offset() + view.nav_offset) .. "px)"

    view.e_nav.style.opacity = view.nav_opacity
    view.e_nav.style["z-index"] = view.nav_index
    view.e_nav_overlay.style.opacity = view.nav_overlay_opacity
    view.e_nav_overlay.style["z-index"] = view.nav_index - 1

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

    local nav_push = (view.e_nav and active_view.el.classList:contains("is-wide"))
      and opts.nav_width or 0

    view.e_main.style.transform =
      "translate(" .. nav_push .. "px," .. (M.get_base_header_offset() + view.main_offset) .. "px)"

    view.e_main.style["min-width"] = "calc(100% - " .. nav_push .. "px)"
    view.e_main.style.opacity = view.main_opacity
    view.e_main.style["z-index"] = view.main_index

  end

  M.style_header_links = function (view, animate)

    if not view.e_header_links or #view.e_header_links <= 0 then
      return
    end

    if animate then
      for i = 1, #view.e_header_links do
        local el = view.e_header_links[i]
        el.classList:add("animated")
      end
      if view.e_header_link_animation then
        window:clearTimeout(view.e_header_link_animation)
        view.e_header_link_animation = nil
      end
      view.e_header_link_animation = M.after_transition(function ()
        for i = 1, #view.e_header_links do
          local el = view.e_header_links[i]
          el.classList:remove("animated")
        end
        view.e_header_link_animation = nil
      end)
    end

    for i = 1, #view.e_header_links do
      local el = view.e_header_links[i]
      el.style.transform =
        "translateY(" .. (M.get_base_header_offset() + view.header_offset) .. "px)"
    end

  end


  M.style_main_header_switch = function (view, animate)

    if not view.e_main_header then
      return
    end

    if animate then
      view.e_main_header.classList:add("animated")
      if view.main_header_animation then
        window:clearTimeout(view.main_header_animation)
        view.main_header_animation = nil
      end
      view.main_header_animation = M.after_transition(function ()
        view.e_main_header.classList:remove("animated")
        view.main_header_animation = nil
      end)
    end

    local nav_push = (view.parent and view.parent.e_nav and active_view.el.classList:contains("is-wide"))
      and opts.nav_width or 0

    view.e_main_header.style.transform =
      "translate(" .. nav_push .. "px," .. (M.get_base_header_offset() + view.main_header_offset) .. "px)"

    view.e_main_header.style["min-width"] = "calc(100% - " .. nav_push .. "px)"
    view.e_main_header.style["max-width"] = "calc(100% - " .. nav_push .. "px)"
    view.e_main_header.style.opacity = view.main_header_opacity
    view.e_main_header.style["z-index"] = view.main_header_index

  end

  M.style_main_pane = function (view, animate)

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

    view.e_main.style.opacity = view.main_opacity or 1
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

    local nav_push = (view.parent and view.parent.e_nav and active_view.el.classList:contains("is-wide"))
      and opts.nav_width or 0

    view.e_main.style.transform =
      "translate(" .. nav_push .. "px," .. (M.get_base_header_offset() + view.main_offset) .. "px)"

    view.e_main.style["min-width"] = "calc(100% - " .. nav_push .. "px)"
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

    local subheader_offset = M.get_subheader_offset(view)

    local bottom_offset_total = opts.padding
    local top_offset_total = opts.padding

    arr.each(view.e_fabs_shared, function (el)

      local offset = -view.fab_shared_offset

      el.style["z-index"] = view.fab_shared_index

      if not M.should_show(view, el) then
        el.style.opacity = 0
        el.style["box-shadow"] = view.fab_shared_shadow
        el.style["pointer-events"] = "none"
        el.style.transform =
          "scale(" .. opts.fab_scale .. ") " ..
          "translateY(" .. offset .. "px)"
        return
      end

      local e_svg = el:querySelector("svg")

      el.style["z-index"] = view.fab_shared_index
      el.style.opacity = view.fab_shared_opacity
      el.style["pointer-events"] = "all"
      el.style["box-shadow"] = view.fab_shared_shadow

      el.style.transform =
        "scale(" .. view.fab_shared_scale .. ") " ..
        "translateY(" .. offset .. "px)"

      e_svg.style.transform =
        "translateY(" .. view.fab_shared_svg_offset .. "px)"

      bottom_offset_total = bottom_offset_total +
        (el.classList:contains("small") and
          opts.fab_width_small or
          opts.fab_width_large) + opts.padding

    end)

    local bottom_cutoff = subheader_offset + opts.padding
    local last_bottom_top = 0

    arr.each(view.e_fabs_bottom, function (el)

      local offset = view.fabs_bottom_offset - bottom_offset_total

      local height = el.classList:contains("small") and
        opts.fab_width_small or
        opts.fab_width_large

      el.style["z-index"] = view.fabs_bottom_index

      last_bottom_top = (e_body.clientHeight + offset - height - opts.padding)

      if last_bottom_top <= bottom_cutoff or not M.should_show(view, el)
      then
        el.style.opacity = 0
        el.style["pointer-events"] = "none"
        el.style.transform =
          "scale(" .. opts.fab_scale .. ") " ..
          "translateY(" .. offset .. "px)"
        return
      end

      el.style["pointer-events"] = "all"
      el.style.opacity = view.fabs_bottom_opacity
      el.style.transform =
        "scale(" .. view.fabs_bottom_scale .. ") " ..
        "translateY(" .. offset .. "px)"

      bottom_offset_total = bottom_offset_total + height + opts.padding

    end)

    arr.each(view.e_fabs_top, function (el)

      local offset = subheader_offset + view.fabs_top_offset + top_offset_total

      local height = el.classList:contains("small") and
        opts.fab_width_small or
        opts.fab_width_large

      el.style["z-index"] = view.fabs_top_index

      if (offset + height) >= last_bottom_top or not M.should_show(view, el)
      then
        el.style.opacity = 0
        el.style["pointer-events"] = "none"
        el.style.transform =
          "scale(" .. opts.fab_scale .. ") " ..
          "translateY(" .. offset .. "px)"
        return
      end

      el.style["pointer-events"] = "all"
      el.style.opacity = view.fabs_top_opacity or 0
      el.style.transform =
        "scale(" .. (view.fabs_top_scale or 1) .. ") " ..
        "translateY(" .. offset .. "px)"

      top_offset_total = top_offset_total + height + opts.padding

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

    local bottom_cutoff = M.get_subheader_offset(view) + opts.padding
    local bottom_offset_total = opts.padding

    local nav_push = (view.e_nav and active_view.el.classList:contains("is-wide"))
      and opts.nav_width or 0

    view.e_snacks:forEach(function (_, e_snack)

      e_snack.style["z-index"] = view.snack_index

      local offset = view.snack_offset - bottom_offset_total
      local height = e_snack:getBoundingClientRect().height
      local snack_top = e_body.clientHeight + offset - height - opts.padding

      if snack_top <= bottom_cutoff or not M.should_show(view, e_snack)
      then
        e_snack.style.opacity = 0
        e_snack.style["pointer-events"] = "none"
        e_snack.style.transform =
          "translate(" .. nav_push .. "px," .. offset .. "px)"
      else
        e_snack.style.opacity = view.snack_opacity
        e_snack.style["pointer-events"] = (view.snack_opacity or 0) == 0 and "none" or "all"
        e_snack.style.transform =
          "translate(" .. nav_push .. "px," .. offset .. "px)"
        bottom_offset_total = bottom_offset_total +
            height + opts.padding
      end

    end)

  end

  M.style_banners = function (view, animate)
    if view.e_banners.length <= 0 then
      return
    end
    if animate then
      view.e_banners:forEach(function (_, e_banner)
        e_banner.classList:add("animated")
      end)
      if view.banner_animation then
        window:clearTimeout(view.banner_animation)
        view.banner_animation = nil
      end
      view.banner_animation = M.after_transition(function ()
        view.e_banners:forEach(function (_, e_banner)
          e_banner.classList:remove("animated")
        end)
        view.banner_animation = nil
      end)
    end
    view.banner_offset_total = 0
    local shown_index = opts.banner_index + view.e_banners.length
    view.e_banners:forEach(function (_, e_banner)
      if not M.should_show(view, e_banner) then
        e_banner.style["z-index"] = shown_index
        e_banner.style.transform = "translateY(" .. view.banner_offset_total .. "px)"
      else
        view.banner_offset_total = view.banner_offset_total + opts.banner_height
        e_banner.style["z-index"] = shown_index
        e_banner.style.transform = "translateY(" .. view.banner_offset_total .. "px)"
      end
      shown_index = shown_index - 1
    end)
  end

  M.style_nav_transition = function (next_view, transition, direction, last_view)

    if not last_view and transition == "enter" then

      next_view.nav_offset = 0
      next_view.nav_opacity = 1
      next_view.nav_index = opts.nav_index + 1
      M.style_nav(next_view)

    elseif transition == "enter" and direction == "forward" then

      next_view.nav_offset = opts.transition_forward_height
      next_view.nav_opacity = 0
      next_view.nav_index = opts.nav_index + 1
      M.style_nav(next_view)

      util.after_frame(function ()
        next_view.nav_offset = next_view.nav_offset - opts.transition_forward_height
        next_view.nav_opacity = 1
        M.style_nav(next_view, true)
      end)

    elseif transition == "exit" and direction == "forward" then

      last_view.nav_offset = last_view.nav_offset - opts.transition_forward_height
      last_view.nav_opacity = 0
      last_view.nav_overlay_opacity = 0
      last_view.nav_index = opts.nav_index - 1
      M.style_nav(last_view, true)

    elseif transition == "enter" and direction == "backward" then

      next_view.nav_offset = -opts.transition_forward_height
      next_view.nav_opacity = 0
      next_view.nav_index = opts.nav_index - 1
      M.style_nav(next_view)

      util.after_frame(function ()
        next_view.nav_offset = 0
        next_view.nav_opacity = 1
        M.style_nav(next_view, true)
      end)

    elseif transition == "exit" and direction == "backward" then

      last_view.nav_offset = opts.transition_forward_height
      last_view.nav_opacity = 0
      last_view.nav_overlay_opacity = 0
      last_view.nav_index = opts.nav_index + 1
      M.style_nav(last_view, true)

    else
      err.error("invalid state", "main transition")
    end

  end

  M.style_header_transition = function (next_view, transition, direction, last_view)

    next_view.header_min = -opts.header_height
    next_view.header_max = 0

    if not last_view and transition == "enter" then

      next_view.header_offset = 0
      next_view.header_opacity = 1
      next_view.header_index = opts.header_index + 1
      M.style_header(next_view)

    elseif transition == "enter" and direction == "forward" then

      next_view.header_offset = last_view.header_offset
      next_view.header_index = opts.header_index + 1

      if next_view.header_offset < 0 then
        next_view.header_opacity = 1
      else
        next_view.header_opacity = 0
      end

      M.style_header(next_view)

      util.after_frame(function ()
        next_view.header_offset = 0
        next_view.header_opacity = 1
        M.style_header(next_view, true)
      end)

    elseif transition == "exit" and direction == "forward" then

      last_view.header_index = opts.header_index - 1
      M.style_header(last_view, true)

    elseif transition == "enter" and direction == "backward" then

      next_view.header_offset = last_view.e_header and last_view.header_offset or 0
      next_view.header_opacity = 1
      next_view.header_index = opts.header_index - 1
      M.style_header(next_view)

      util.after_frame(function ()
        next_view.header_offset = 0
        next_view.header_opacity = 1
        M.style_header(next_view, true)
      end)

    elseif transition == "exit" and direction == "backward" then

      last_view.header_opacity = 0
      last_view.header_index = opts.header_index + 1
      M.style_header(last_view, true)

    else
      err.error("invalid state", "header transition")
    end

  end

  M.style_main_transition = function (next_view, transition, direction, last_view)

    if not last_view and transition == "enter" then

      next_view.main_offset = 0
      next_view.main_opacity = 1
      next_view.main_index = opts.main_index - 1
      M.style_main(next_view)

    elseif transition == "enter" and direction == "forward" then

      next_view.main_offset = opts.transition_forward_height
      next_view.main_opacity = 0
      next_view.main_index = opts.main_index + 1
      M.style_main(next_view)

      util.after_frame(function ()
        next_view.main_offset = next_view.main_offset - opts.transition_forward_height
        next_view.main_opacity = 1
        M.style_main(next_view, true)
      end)

    elseif transition == "exit" and direction == "forward" then

      last_view.main_offset = -opts.transition_forward_height
      last_view.main_opacity = 0
      last_view.main_index = opts.main_index - 1
      M.style_main(last_view, true)

    elseif transition == "enter" and direction == "backward" then

      next_view.main_offset = -opts.transition_forward_height
      next_view.main_opacity = 0
      next_view.main_index = opts.main_index + 1
      M.style_main(next_view)

      util.after_frame(function ()
        next_view.main_offset = 0
        next_view.main_opacity = 1
        M.style_main(next_view, true)
      end)

    elseif transition == "exit" and direction == "backward" then

      last_view.main_offset = opts.transition_forward_height
      last_view.main_opacity = 0
      last_view.main_index = opts.main_index + 1
      M.style_main(last_view, true)

    else
      err.error("invalid state", "main transition")
    end

  end

  M.style_main_header_transition_switch = function (next_view, transition, direction, last_view, init)

    if init and direction == "forward" then

      next_view.main_header_offset = 0
      next_view.main_header_opacity = 1
      next_view.main_header_index = opts.main_header_index + 1
      M.style_main_header_switch(next_view)

    elseif transition == "enter" and direction == "forward" then

      next_view.main_header_offset = opts.transition_forward_height
      next_view.main_header_opacity = 0
      next_view.main_header_index = opts.main_header_index + 1
      M.style_main_header_switch(next_view)

      util.after_frame(function ()
        next_view.main_header_offset = 0
        next_view.main_header_opacity = 1
        M.style_main_header_switch(next_view, true)
      end)

    elseif transition == "exit" and direction == "forward" then

      last_view.main_header_offset =
        (not next_view) and ((last_view.main_header_offset or 0) - opts.transition_forward_height)
        or -opts.transition_forward_height
      last_view.main_header_opacity = 0
      last_view.main_header_index = opts.main_header_index - 1
      M.style_main_header_switch(last_view, true)

    elseif transition == "enter" and direction == "backward" then

      next_view.main_header_offset = -opts.transition_forward_height
      next_view.main_header_opacity = 0
      next_view.main_header_index = opts.main_header_index - 1
      M.style_main_header_switch(next_view)

      util.after_frame(function ()
        next_view.main_header_offset = 0
        next_view.main_header_opacity = 1
        M.style_main_header_switch(next_view, true)
      end)

    elseif transition == "exit" and direction == "backward" then

      last_view.main_header_offset = opts.transition_forward_height
      last_view.main_header_opacity = 0
      last_view.main_header_index = opts.main_header_index + 1
      M.style_main_header_switch(last_view, true)

    else
      err.error("invalid state", "main header transition")
    end

  end

  M.style_main_transition_pane = function (next_view, transition, last_view, init)

    if init and transition == "enter" then

      next_view.main_opacity = 1
      next_view.main_index = opts.main_index + 1
      M.style_main_pane(next_view)

    elseif transition == "enter" then

      next_view.main_opacity = 0
      next_view.main_index = opts.main_index + 1
      M.style_main_pane(next_view)

      util.after_frame(function ()
        next_view.main_opacity = 1
        M.style_main_pane(next_view, true)
      end)

    elseif transition == "exit" then

      last_view.main_opacity = 0
      last_view.main_index = opts.main_index - 1
      M.style_main_pane(last_view, true)

    else
      err.error("invalid state", "main transition")
    end

  end

  M.style_main_transition_switch = function (next_view, transition, direction, last_view, init)

    if init and direction == "forward" then

      next_view.main_offset = 0
      next_view.main_opacity = 1
      next_view.main_index = opts.main_index + 1
      M.style_main_switch(next_view)

    elseif transition == "enter" and direction == "forward" then

      next_view.main_offset = opts.transition_forward_height
      next_view.main_opacity = 0
      next_view.main_index = opts.main_index + 1
      M.style_main_switch(next_view)

      util.after_frame(function ()
        next_view.main_offset = 0
        next_view.main_opacity = 1
        M.style_main_switch(next_view, true)
      end)

    elseif transition == "exit" and direction == "forward" then

      last_view.main_offset = (last_view.main_offset or 0) - opts.transition_forward_height
      last_view.main_opacity = 0
      last_view.main_index = opts.main_index - 1
      M.style_main_switch(last_view, true)

    elseif transition == "enter" and direction == "backward" then

      next_view.main_offset = -opts.transition_forward_height
      next_view.main_opacity = 0
      next_view.main_index = opts.main_index - 1
      M.style_main_switch(next_view)

      util.after_frame(function ()
        next_view.main_offset = 0
        next_view.main_opacity = 1
        M.style_main_switch(next_view, true)
      end)

    elseif transition == "exit" and direction == "backward" then

      last_view.main_offset = opts.transition_forward_height
      last_view.main_opacity = 0
      last_view.main_index = opts.main_index + 1
      M.style_main_switch(last_view, true)

    else
      err.error("invalid state", "main transition")
    end

  end

  M.style_fabs_transition = function (next_view, transition, direction, last_view)

    local is_shared =
      (next_view and next_view.e_fabs and next_view.e_fabs.length > 0) and
      (last_view and last_view.e_fabs and last_view.e_fabs.length > 0)

    if not last_view and transition == "enter" then

      next_view.fab_shared_index = opts.fab_index + 1
      next_view.fab_shared_scale = 1
      next_view.fab_shared_opacity = 1
      next_view.fab_shared_shadow = opts.fab_shadow
      next_view.fab_shared_offset = opts.padding
      next_view.fab_shared_svg_offset = 0

      next_view.fabs_bottom_index = opts.fab_index - 1
      next_view.fabs_bottom_scale = 1
      next_view.fabs_bottom_opacity = 1
      next_view.fabs_bottom_offset = 0

      next_view.fabs_top_index = opts.fab_index - 1
      next_view.fabs_top_scale = 1
      next_view.fabs_top_opacity = 1
      next_view.fabs_top_offset = 0

      M.style_fabs(next_view)

    elseif is_shared and transition == "enter" and direction == "forward" then

      next_view.fab_shared_index = opts.fab_index + 1
      next_view.fab_shared_scale = 1
      next_view.fab_shared_opacity = 0
      next_view.fab_shared_shadow = opts.fab_shadow
      next_view.fab_shared_offset = opts.padding
      next_view.fab_shared_svg_offset = opts.fab_shared_svg_transition_height

      next_view.fabs_bottom_index = opts.fab_index - 1
      next_view.fabs_bottom_scale = opts.fab_scale
      next_view.fabs_bottom_opacity = 0
      next_view.fabs_bottom_offset = opts.transition_forward_height

      next_view.fabs_top_index = opts.fab_index - 1
      next_view.fabs_top_scale = 1
      next_view.fabs_top_opacity = 0
      next_view.fabs_top_offset = opts.transition_forward_height

      M.style_fabs(next_view)

      util.after_frame(function ()
        next_view.fab_shared_svg_offset = 0
        next_view.fab_shared_opacity = 1
        next_view.fabs_bottom_scale = 1
        next_view.fabs_bottom_opacity = 1
        next_view.fabs_bottom_offset = 0
        next_view.fabs_top_scale = 1
        next_view.fabs_top_opacity = 1
        next_view.fabs_top_offset = 0
        M.style_fabs(next_view, true)
      end)

    elseif is_shared and transition == "exit" and direction == "forward" then

      last_view.fab_shared_index = opts.fab_index + 1
      last_view.fab_shared_scale = 1
      last_view.fab_shared_opacity = 1
      last_view.fab_shared_shadow = opts.fab_shadow_transparent
      last_view.fab_shared_offset = opts.padding
      last_view.fab_shared_svg_offset = - opts.fab_shared_svg_transition_height

      last_view.fabs_bottom_index = opts.fab_index - 2
      last_view.fabs_bottom_scale = 1
      last_view.fabs_bottom_opacity = 0
      last_view.fabs_bottom_offset = 0

      last_view.fabs_top_index = opts.fab_index - 2
      last_view.fabs_top_scale = 1
      last_view.fabs_top_opacity = 0
      last_view.fabs_top_offset = 0

      M.style_fabs(last_view, true)

    elseif is_shared and transition == "enter" and direction == "backward" then

      next_view.fab_shared_index = opts.fab_index + 1
      next_view.fab_shared_scale = 1
      next_view.fab_shared_opacity = 0
      next_view.fab_shared_shadow = opts.fab_shadow
      next_view.fab_shared_offset = opts.padding
      next_view.fab_shared_svg_offset = - opts.fab_shared_svg_transition_height

      next_view.fabs_bottom_index = opts.fab_index - 2
      next_view.fabs_bottom_scale = opts.fab_scale
      next_view.fabs_bottom_opacity = 0
      next_view.fabs_bottom_offset = 0

      next_view.fabs_top_index = opts.fab_index - 2
      next_view.fabs_top_scale = 1
      next_view.fabs_top_opacity = 0
      next_view.fabs_top_offset = 0

      M.style_fabs(next_view)

      util.after_frame(function ()
        next_view.fab_shared_svg_offset = 0
        next_view.fab_shared_opacity = 1
        next_view.fabs_bottom_scale = 1
        next_view.fabs_bottom_opacity = 1
        next_view.fabs_top_scale = 1
        next_view.fabs_top_opacity = 1
        M.style_fabs(next_view, true)
      end)

    elseif is_shared and transition == "exit" and direction == "backward" then

      last_view.fab_shared_index = opts.fab_index + 1
      last_view.fab_shared_scale = 1
      last_view.fab_shared_opacity = 1
      last_view.fab_shared_shadow = opts.fab_shadow_transparent
      last_view.fab_shared_offset = opts.padding
      last_view.fab_shared_svg_offset = opts.fab_shared_svg_transition_height

      last_view.fabs_bottom_index = opts.fab_index - 1
      last_view.fabs_bottom_scale = opts.fab_scale
      last_view.fabs_bottom_opacity = 0
      last_view.fabs_bottom_offset = opts.transition_forward_height

      last_view.fabs_top_index = opts.fab_index + 2
      last_view.fabs_top_scale = 1
      last_view.fabs_top_opacity = 0
      last_view.fabs_top_offset = opts.transition_forward_height

      M.style_fabs(last_view, true)

    elseif transition == "enter" and direction == "forward" then

      next_view.fab_shared_index = opts.fab_index - 1
      next_view.fab_shared_scale = opts.fab_scale
      next_view.fab_shared_opacity = 0
      next_view.fab_shared_shadow = opts.fab_shadow
      next_view.fab_shared_offset = opts.padding + opts.transition_forward_height
      next_view.fab_shared_svg_offset = 0

      next_view.fabs_bottom_index = opts.fab_index - 1
      next_view.fabs_bottom_scale = opts.fab_scale
      next_view.fabs_bottom_opacity = 0
      next_view.fabs_bottom_offset = opts.transition_forward_height

      next_view.fabs_top_index = opts.fab_index - 1
      next_view.fabs_top_scale = 1
      next_view.fabs_top_opacity = 0
      next_view.fabs_top_offset = opts.transition_forward_height

      M.style_fabs(next_view)

      util.after_frame(function ()
        next_view.fab_shared_scale = 1
        next_view.fab_shared_opacity = 1
        next_view.fab_shared_offset = opts.padding
        next_view.fabs_bottom_scale = 1
        next_view.fabs_bottom_opacity = 1
        next_view.fabs_bottom_offset = 0
        next_view.fabs_top_scale = 1
        next_view.fabs_top_opacity = 1
        next_view.fabs_top_offset = 0
        M.style_fabs(next_view, true)
      end)

    elseif transition == "enter" and direction == "backward" then

      next_view.fab_shared_index = opts.fab_index - 2
      next_view.fab_shared_scale = 1
      next_view.fab_shared_opacity = 0
      next_view.fab_shared_shadow = opts.fab_shadow
      next_view.fab_shared_offset = opts.padding
      next_view.fab_shared_svg_offset = 0

      next_view.fabs_bottom_index = opts.fab_index - 2
      next_view.fabs_bottom_scale = 1
      next_view.fabs_bottom_opacity = 0
      next_view.fabs_bottom_offset = 0

      next_view.fabs_top_index = opts.fab_index - 2
      next_view.fabs_top_scale = 1
      next_view.fabs_top_opacity = 0
      next_view.fabs_top_offset = 0

      M.style_fabs(next_view)

      util.after_frame(function ()
        next_view.fab_shared_scale = 1
        next_view.fab_shared_opacity = 1
        next_view.fabs_bottom_scale = 1
        next_view.fabs_bottom_opacity = 1
        next_view.fabs_top_scale = 1
        next_view.fabs_top_opacity = 1
        M.style_fabs(next_view, true)
      end)

    elseif transition == "exit" and direction == "forward" then

      last_view.fab_shared_index = opts.fab_index - 2
      last_view.fab_shared_scale = 1
      last_view.fab_shared_opacity = 0
      last_view.fab_shared_shadow = opts.fab_shadow
      last_view.fab_shared_offset = opts.padding
      last_view.fab_shared_svg_offset = 0

      last_view.fabs_bottom_index = opts.fab_index - 2
      last_view.fabs_bottom_scale = 1
      last_view.fabs_bottom_opacity = 0
      last_view.fabs_bottom_offset = 0

      last_view.fabs_top_index = opts.fab_index - 2
      last_view.fabs_top_scale = 1
      last_view.fabs_top_opacity = 0
      last_view.fabs_top_offset = 0

      M.style_fabs(last_view, true)

    elseif transition == "exit" and direction == "backward" then

      last_view.fab_shared_index = opts.fab_index - 1
      last_view.fab_shared_scale = opts.fab_scale
      last_view.fab_shared_opacity = 0
      last_view.fab_shared_shadow = opts.fab_shadow
      last_view.fab_shared_offset = opts.padding + opts.transition_forward_height
      last_view.fab_shared_svg_offset = 0

      last_view.fabs_bottom_index = opts.fab_index - 1
      last_view.fabs_bottom_scale = opts.fab_scale
      last_view.fabs_bottom_opacity = 0
      last_view.fabs_bottom_offset = opts.transition_forward_height

      last_view.fabs_top_index = opts.fab_index - 1
      last_view.fabs_top_scale = opts.fab_scale
      last_view.fabs_top_opacity = 0
      last_view.fabs_top_offset = opts.transition_forward_height

      M.style_fabs(last_view, true)

    else
      err.error("invalid state", "fabs transition")
    end

  end

  M.style_snacks_transition = function (next_view, transition, direction, last_view)

    if not last_view and transition == "enter" then

      next_view.snack_offset = M.get_base_footer_offset()
      next_view.snack_opacity = 1
      next_view.snack_index = opts.snack_index - 1
      M.style_snacks(next_view)

    elseif transition == "enter" and direction == "forward" then

      next_view.snack_offset = M.get_base_footer_offset() + opts.transition_forward_height
      next_view.snack_opacity = 0
      next_view.snack_index = opts.snack_index + 1
      M.style_snacks(next_view)

      util.after_frame(function ()
        next_view.snack_offset = next_view.snack_offset - opts.transition_forward_height
        next_view.snack_opacity = 1
        M.style_snacks(next_view, true)
      end)

    elseif transition == "exit" and direction == "forward" then

      last_view.snack_offset = M.get_base_footer_offset()
      last_view.snack_opacity = 0
      last_view.snack_index = opts.snack_index - 1
      M.style_snacks(last_view, true)

    elseif transition == "enter" and direction == "backward" then

      next_view.snack_offset = M.get_base_footer_offset()
      next_view.snack_opacity = 0
      next_view.snack_index = opts.snack_index - 1
      M.style_snacks(next_view)

      util.after_frame(function ()
        next_view.snack_offset = M.get_base_footer_offset()
        next_view.snack_opacity = 1
        M.style_snacks(next_view, true)
      end)

    elseif transition == "exit" and direction == "backward" then

      last_view.snack_offset = M.get_base_footer_offset() + opts.transition_forward_height
      last_view.snack_opacity = 0
      last_view.snack_index = opts.snack_index + 1
      M.style_snacks(last_view, true)

    else
      err.error("invalid state", "main transition")
    end

  end

  M.style_header_hide = function (view, hide, restyle)
    if hide then
      view.header_hide = true
      view.header_offset = -opts.header_height
    else
      view.header_hide = false
      view.header_offset = 0
    end
    if view.active_view then
      view.active_view.main_header_offset = view.header_offset
      -- view.active_view.main_offset = view.header_offset
    end
    view.nav_offset = view.header_offset
    if restyle ~= false then
      M.style_header(view, true)
      M.style_nav(view, true)
      M.style_fabs(view, true)
      M.style_header_links(view, true)
      if view.active_view then
        M.style_main_header_switch(view.active_view, true)
        M.style_main_switch(view.active_view, true)
      end
    end
  end

  M.scroll_listener = function (view)

    local n = 0
    local ready = true
    local last_scroll_top = 0

    return function ()

      if not ready then
        return
      end

      if view.no_scroll then
        view.no_scroll = false
        return
      end

      local curr_scroll_top = window.pageYOffset or document.documentElement.scrollTop
      local curr_diff = curr_scroll_top - last_scroll_top

      if curr_diff >= 16 then
        n = (n < 0 and 0 or n) + 1
      elseif curr_diff <= -16 then
        n = (n > 0 and 0 or n) - 1
      end

      if not active_view.el.classList:contains("is-wide") and view.el.classList:contains("showing-nav") then
        M.toggle_nav_state()
      end

      last_scroll_top = curr_scroll_top <= 0 and 0 or curr_scroll_top

      if view.header_hide and curr_scroll_top <= tonumber(opts.header_height) then
        ready = false
        M.after_transition(function ()
          ready = true
        end)
        M.style_header_hide(view, false)
      elseif not view.header_hide and n >= 1 then
        ready = false
        M.after_transition(function ()
          ready = true
        end)
        M.style_header_hide(view, true)
      elseif view.header_hide and n <= -1 then
        ready = false
        M.after_transition(function ()
          ready = true
        end)
        M.style_header_hide(view, false)
      end

    end
  end

  M.after_transition = function (fn, ...)
    return window:setTimeout(function (...)
      util.after_frame(fn, ...)
    end, tonumber(opts.transition_time), ...)
  end

  M.close_dropdowns = function (view)
    if view and view.e_dropdowns then
      view.e_dropdowns:forEach(function (_, e_dropdown)
        e_dropdown.classList:remove("tk-open")
      end)
    end
  end

  M.clear_panes = function (view)
    if view and view.page and view.page.panes then
      for _, pane in it.pairs(view.page.panes) do
        if pane.active_view then
          M.post_exit_pane(pane.active_view)
          pane.active_view = nil
        end
      end
    end
  end

  M.post_enter_pane = function (view, next_view)
    view.el.classList:remove("transition")
    M.setup_ripples(next_view.el)
  end

  M.post_enter_switch = function (view, next_view)
    view.el.classList:remove("transition")
    M.setup_ripples(next_view.el)
  end

  M.post_exit_pane = function (last_view)
    last_view.el:remove()
    if last_view.page.destroy then
      last_view.page.destroy(last_view, opts)
    end
    M.clear_panes(last_view)
  end

  M.post_exit_switch = function (last_view)
    last_view.el:remove()
    if last_view.page.destroy then
      last_view.page.destroy(last_view, opts)
    end
    M.clear_panes(last_view)
  end

  M.post_exit = function (last_view)
    if last_view.active_view then
      M.post_exit_switch(last_view.active_view)
    end
    last_view.el:remove()
    if last_view.page.destroy then
      last_view.page.destroy(last_view, opts)
    end
    M.clear_panes(last_view)
  end

  M.post_enter = function (next_view)

    active_view.el.classList:remove("transition")

    if next_view.page.post_append then
      next_view.page.post_append(next_view, opts)
    end

    local e_back = next_view.el:querySelector("section > header > button.back")

    if e_back then
      e_back:addEventListener("click", function ()
        history:back()
      end)
    end

    local e_menu = next_view.el:querySelector("section > header > button.menu")

    if e_menu then
      e_menu:addEventListener("click", function ()
        M.toggle_nav_state()
      end)
    end

    if next_view.e_header then
      next_view.curr_scrolly = nil
      next_view.last_scrolly = nil
      next_view.scroll_listener = M.scroll_listener(next_view)
      window:addEventListener("scroll", next_view.scroll_listener, false)
    end

    M.setup_ripples(next_view.el)

  end

  M.enter_pane = function (view_pane, next_view, last_view, init, ...)

    M.close_dropdowns(last_view)

    next_view.el = util.clone(next_view.page.template)
    next_view.e_main = next_view.el:querySelector("section > main")

    M.setup_panes(next_view, init)
    M.setup_dropdowns(next_view, init)
    M.setup_header_links(next_view)
    M.style_main_transition_pane(next_view, "enter", last_view, init)

    if next_view.page.init then
      next_view.page.init(next_view, ...)
    end

    view_pane.el.classList:add("transition")
    view_pane.el:append(next_view.el)

    M.after_transition(function ()
      return M.post_enter_pane(view_pane, next_view)
    end)

  end

  M.enter_switch = function (view, next_view, direction, last_view, init)

    M.close_dropdowns(last_view)

    next_view.el = util.clone(next_view.page.template)
    next_view.e_main = next_view.el:querySelector("section > main")
    next_view.e_main_header = next_view.el:querySelector("section > header")

    M.setup_panes(next_view, init)
    M.setup_dropdowns(next_view, init)
    M.setup_header_links(next_view)
    M.style_main_header_transition_switch(next_view, "enter", direction, last_view, init)
    M.style_main_transition_switch(next_view, "enter", direction, last_view, init)

    if next_view.page.init then
      next_view.page.init(next_view, opts)
    end

    view.el.classList:add("transition")
    view.e_main:append(next_view.el)

    M.after_transition(function ()
      return M.post_enter_switch(view, next_view)
    end)

  end

  M.exit_pane = function (last_view, next_view)
    M.style_main_transition_pane(next_view, "exit", last_view)
    M.after_transition(function ()
      return M.post_exit_pane(last_view)
    end, true)
  end

  M.exit_switch = function (view, last_view, direction, next_view)

    view.header_offset = 0
    M.style_header(view, true)

    last_view.el.style.marginLeft = -window.scrollX .. "px"
    last_view.el.style.marginTop = -window.scrollY .. "px"
    active_view.active_view.no_scroll = true
    window:scrollTo({ top = 0, left = 0, behavior = "instant" })

    M.style_main_header_transition_switch(next_view, "exit", direction, last_view)
    M.style_main_transition_switch(next_view, "exit", direction, last_view)

    M.after_transition(function ()
      return M.post_exit_switch(last_view)
    end, true)

  end

  M.enter = function (next_view, direction, last_view, init, explicit)

    M.close_dropdowns(last_view)

    next_view.el = util.clone(next_view.page.template)
    next_view.e_header = next_view.el:querySelector("section > header")
    next_view.e_main = next_view.el:querySelector("section > main")

    if next_view.e_main.firstElementChild and next_view.e_main.firstElementChild.tagName == "SECTION" then
      next_view.el.classList:add("direct-switch")
    end

    M.setup_observer(next_view)
    M.setup_nav(next_view, direction, init, explicit)
    M.setup_fabs(next_view, last_view)
    M.setup_snacks(next_view)
    M.setup_panes(next_view, init)
    M.setup_dropdowns(next_view, init)
    M.setup_header_links(next_view)
    M.style_header_transition(next_view, "enter", direction, last_view)
    M.style_nav_transition(next_view, "enter", direction, last_view)
    M.style_fabs_transition(next_view, "enter", direction, last_view)
    M.style_snacks_transition(next_view, "enter", direction, last_view)

    -- NOTE: No need to handle the active_view exist case, since it's handled by
    -- setup_nav above
    if not next_view.active_view then
      M.style_main_transition(next_view, "enter", direction, last_view)
    end

    if next_view.page.init then
      next_view.page.init(next_view, opts)
    end

    active_view.el.classList:add("transition")
    active_view.e_main:append(next_view.el)

    M.after_transition(function ()
      return M.post_enter(next_view)
    end)

  end

  M.exit = function (last_view, direction, next_view)

    if last_view.active_view then
      last_view.active_view.e_main.style.marginLeft = -window.scrollX .. "px"
      last_view.active_view.e_main.style.marginTop = -window.scrollY .. "px"
    else
      last_view.e_main.style.marginLeft = -window.scrollX .. "px"
      last_view.e_main.style.marginTop = -window.scrollY .. "px"
    end

    last_view.no_scroll = true
    window:scrollTo({ top = 0, left = 0, behavior = "instant" })

    M.setup_fabs(last_view, next_view)
    M.style_header_transition(next_view, "exit", direction, last_view)
    M.style_nav_transition(next_view, "exit", direction, last_view)
    M.style_fabs_transition(next_view, "exit", direction, last_view)
    M.style_snacks_transition(next_view, "exit", direction, last_view)

    if last_view.active_view then
      M.style_main_header_transition_switch(nil, "exit", direction, last_view.active_view)
      M.style_main_transition_switch(nil, "exit", direction, last_view.active_view)
    else
      M.style_main_transition(next_view, "exit", direction, last_view)
    end

    if last_view.scroll_listener then
      window:removeEventListener("scroll", last_view.scroll_listener)
      last_view.scroll_listener = nil
    end

    last_view.el.classList:add("exit", direction)
    M.after_transition(function ()
      return M.post_exit(last_view, opts)
    end, true)

  end

  M.setup_dynamic = function (view, el)
    M.setup_ripples(el)
    M.setup_panes(view, nil, el)
    M.setup_dropdowns(view, nil, el)
    M.setup_header_links(view)
  end

  M.at_bottom = function ()
    return (window.innerHeight + window.pageYOffset) >= e_body.offsetHeight
  end

  M.scroll_bottom = function ()
    active_view.active_view.no_scroll = true
    window:scrollTo({ top = e_body.scrollHeight, left = 0, behavior = "instant" })
  end

  M.mark = function ()
    local tag = M.route_tag(arr.spread(state.path))
    local sl = val.lua(history.state or {}, true)
    sl.id = sl.id or 0
    sl.mark = sl.mark or {}
    sl.mark[tag] = sl.id
    local sj = val(sl, true)
    history:replaceState(sj, "", location.href)
  end

  M.route_tag = function (...)
    local r = {}
    for i = 1, varg.len(...) do
      local x = varg.get(i, ...)
      if type(x) ~= "string" then
        break
      end
      r[i] = x
    end
    return arr.concat(r, ".")
  end

  M.forward_mark = function (...)
    local tag = M.route_tag(...)
    local id = history.state and history.state.id
    local mark = history.state and history.state.mark and history.state.mark[tag]
    if id and mark and mark < id then
      local diff = id - mark
      state.popmark = { ... }
      history:go(-diff)
    else
      M.replace_forward(...)
    end
  end

  M.backward_mark = function (...)
    local tag = M.route_tag(...)
    local id = history.state and history.state.id
    local mark = history.state and history.state.mark and history.state.mark[tag]
    if id and mark and mark < id then
      local diff = id - mark
      state.popmark = { ... }
      history:go(-diff)
    else
      M.replace_backward(...)
    end
  end

  M.init_view = function (name, path_idx, page, parent)

    err.assert(name ~= "default", "view name can't be default")

    local view = {
      parent = parent,
      back = M.back,
      forward = M.forward,
      backward = M.backward,
      replace_forward = M.replace_forward,
      replace_backward = M.replace_backward,
      mark = M.mark,
      forward_mark = M.forward_mark,
      backward_mark = M.backward_mark,
      at_bottom = M.at_bottom,
      path_idx = path_idx,
      add_listener = M.add_listener,
      remove_listener = M.remove_listener,
      emit = M.emit,
      page = page,
      name = name,
      state = state
    }

    view.scroll_bottom = function ()
      return M.scroll_bottom()
    end

    view.toggle_nav = function ()
      return M.toggle_nav_state(not view.el.classList:contains("showing-nav"), true, true)
    end

    view.pane = function (name, page_name, ...)
      return M.pane(view, name, page_name, false, ...)
    end

    view.after_transition = M.after_transition
    view.after_frame = util.after_frame

    local clone_all_wrap_opts
    clone_all_wrap_opts = function (view, opts)
      return setmetatable({
        map_el = function (el, data, clone_all)
          M.setup_dynamic(view, el)
          if opts.map_el then
            return opts.map_el(el, data, function (opts0)
              return clone_all(clone_all_wrap_opts(view, opts0))
            end)
          end
        end
      }, { __index = opts })
    end

    view.clone_all = function (opts)
      return util.clone_all(clone_all_wrap_opts(view, opts))
    end

    view.clone = function (template, data, parent, before, pre_append)
      return util.clone(template, data, parent, before, function (el)
        M.setup_dynamic(view, el)
        if pre_append then
          return pre_append(el)
        end
      end)
    end

    return view

  end

  M.switch_dir = function (view, next_switch, last_switch, dir)
    if not view.e_nav then
      return "forward"
    elseif view.header_offset and view.header_offset < 0 then
      return "backward"
    end
    local idx_next, idx_last
    idx_next = varg.sel(2, arr.find(view.nav_order, fun.bind(op.eq, next_switch.name)))
    if last_switch then
      idx_last = varg.sel(2, arr.find(view.nav_order, fun.bind(op.eq, last_switch.name)))
      return idx_next < idx_last and "backward" or "forward"
    else
      return dir or "forward"
    end
  end

  M.maybe_redirect = function (view, page, init, explicit)
    if page and page.redirect then
      return varg.tup(function (...)
        if ... then
          M.set_route("replace", ...)
          M.transition("forward", init, explicit)
          return true
        end
      end, page.redirect(view, page, explicit))
    end
  end

  M.resolve_default = function (view, name)
    if name == "default" then
      return view.pages.default
    else
      return name
    end
  end

  local function wrap (el)
    local t = document:createElement("template")
    local s = document:createElement("section")
    local m = document:createElement("main")
    if el then
      m:append(el)
    end
    s:append(m)
    t.content:append(s)
    return t
  end

  local function maybe_wrap (page)

    local template

    if page.tagName == "TEMPLATE" then
      template = page
      page = {
        init = function (view, data)
          if data then
            util.populate(view.el, data)
          end
        end
      }
    else
      template = page.template
    end

    local sect = template and template.content and template.content.firstElementChild
    if (not sect) or sect.tagName ~= "SECTION" then
      page.template = wrap(sect and util.clone(template) or nil)
      return page
    end

    page.template = template
    return page

  end

  M.get_page = function (pages, name, parent_name)
    if pages then
      local page = pages[name]
      if page then
        return maybe_wrap(page)
      end
    end
    err.error("no page found", parent_name or "(none)", name or "(none)")
  end

  M.pane = function (view, name, page_name, init, ...)

    local view_pane = view.page.panes and view.page.panes[name]
    page_name = M.resolve_default(view_pane, page_name)
    local pane_page = M.get_page(view_pane.pages, page_name, name)

    if view_pane.active_view and pane_page == view_pane.active_view.page then
      return
    end

    local last_view_pane = view_pane.active_view

    view_pane.active_view = M.init_view(page_name, nil, pane_page, view)

    M.enter_pane(view_pane, view_pane.active_view, last_view_pane, init, ...)

    if last_view_pane then
      M.exit_pane(last_view_pane, view_pane.active_view)
    end

  end

  M.switch = function (view, name, dir, init, explicit)

    local page = type(name) == "table"
      and name
      or M.get_page(view.page.pages, name, "(switch)")

    if M.maybe_redirect(view, page, init, explicit) then
      return
    end

    if view.active_view and page == view.active_view.page then
      return
    end

    local last_view = view.active_view
    view.active_view = M.init_view(name, 2, page, view)

    if view.e_nav then
      view.e_nav_buttons:forEach(function (_, el)
        if M.get_nav_button_page(el) == name then
          el.classList:add("is-active")
        else
          el.classList:remove("is-active")
        end
      end)
    end

    local dir = M.switch_dir(view, view.active_view, last_view, dir)

    M.enter_switch(view, view.active_view, dir, last_view, init)

    if last_view then
      M.exit_switch(view, last_view, dir, view.active_view)
    end

  end

  M.find_default = function (page, path, i)
    i = i or 1
    path = path or {}
    if not page then
      return path
    end
    local def = page and page.pages and page.pages.default
    if not def then
      return path
    else
      path[i] = def
    end
    local pages = page and page.pages
    if not pages or not pages[def] then
      return path
    else
      return M.find_default(pages[def], path, i + 1)
    end
  end

  M.assign_persisted = function (path, params)
    local v = active_view.page
    local i = 1
    while v do
      local params0 = v and v.params
      if params0 then
        for j = 1, #params0 do
          local param = params0[j]
          params[param] = params[param] or state.params[param]
        end
      end
      v = v and path[i] and v.pages and v.pages[path[i]]
      i = i + 1
    end
  end

  M.fill_defaults = function (path, params)
    local v = active_view.page
    if #path < 1 then
      M.find_default(v, path, 1)
    else
      local last
      for i = 1, #path do
        local r = M.resolve_default(v, path[i])
        v = r == path[i] and v.pages and v.pages[r]
        if not v then
          M.find_default(v, path, i)
          return
        else
          last = v
        end
      end
      M.find_default(last, path, #path + 1)
    end
    M.assign_persisted(path, params)
  end

  M.transition = function (dir, init, explicit)

    util.after_frame(function ()

      local page = M.get_page(active_view.page.pages, state.path[1], "(main)")

      if M.maybe_redirect(active_view, page, init, explicit) then
        return
      end

      if not active_view.active_view or page ~= active_view.active_view.page then
        local last_view = active_view.active_view
        active_view.active_view = M.init_view(state.path[1], 1, page)
        M.enter(active_view.active_view, dir, last_view, init, explicit)
        if last_view then
          M.exit(last_view, dir, active_view.active_view)
        end
      elseif state.path[2] then
        M.switch(active_view.active_view, state.path[2], nil, init, explicit)
      end

    end)

  end

  M.toggle_nav_state = function (open, animate, restyle)
    local view = active_view.active_view
    if active_view.el.classList:contains("is-wide") then
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
      view.nav_offset = view.header_offset
      view.nav_overlay_opacity = active_view.el.classList:contains("is-wide")
        and 0 or 0.5
      M.style_header_hide(view, false, restyle)
    else
      view.nav_slide = -opts.nav_width
      view.nav_overlay_opacity = 0
    end
    if restyle ~= false then
      M.style_nav(view, animate ~= false)
    end
  end

  M.on_resize = function ()
    local was_wide = active_view.el.classList:contains("is-wide")
    if window.innerWidth > (opts.wide_threshold or 961) then
      active_view.el.classList:add("is-wide")
    else
      active_view.el.classList:remove("is-wide")
    end
    if active_view.active_view then
      if active_view.el.classList:contains("is-wide") then
        M.toggle_nav_state(true)
      elseif was_wide then
        M.toggle_nav_state(false)
      end
      M.style_nav(active_view.active_view, true)
      M.style_snacks(active_view.active_view, true)
      M.style_fabs(active_view.active_view, true)
      if active_view.active_view.active_view then
        M.style_main_header_switch(active_view.active_view.active_view, true)
        M.style_main_switch(active_view.active_view.active_view, true)
      else
        M.style_main(active_view.active_view, true)
      end
    end
  end

  M.setup_active_view = function ()

    active_view = M.init_view(nil, 0, opts.main)

    active_view.el = util.clone(opts.main.template)
    active_view.e_main = active_view.el:querySelector("section > main")
    M.setup_observer(active_view)
    M.setup_banners(active_view)

    if active_view.page.init then
      active_view.page.init(active_view, opts)
    end

    e_body:append(active_view.el)
    M.setup_ripples(active_view.el)

  end

  if opts.service_worker then

    local navigator = window.navigator
    local serviceWorker = navigator.serviceWorker
    local poll_worker_interval

    M.poll_worker_update = function (reg)

      if poll_worker_interval then
        window:clearInterval(poll_worker_interval)
        poll_worker_interval = nil
      end

      local polling = false
      local installing = false

      poll_worker_interval = window:setInterval(function ()

        if polling then
          return
        end

        polling = true

        reg:update():await(function (_, ok, reg)

          polling = false

          if not ok then
            if opts.verbose then
              print("Service worker update error", reg and reg.message or reg)
            end
          elseif reg.installing then
            installing = true
            if opts.verbose then
              print("Updated service worker installing")
            end
          elseif reg.waiting then
            if opts.verbose then
              print("Updated service worker installed")
            end
          elseif reg.active then
            if installing then
              installing = false
              active_view.el.classList:add("update-worker")
            end
            if opts.verbose then
              print("Updated service worker active")
            end
          end

        end)

      end, opts.service_worker_poll_time_ms)

    end

    if serviceWorker then

      serviceWorker:register("/sw.js", { scope = "/" }):await(function (_, ...)

        local reg = err.checkok(...)

        if reg.installing then
          if opts.verbose then
            print("Initial service worker installing")
          end
        elseif reg.waiting then
          if opts.verbose then
            print("Initial service worker installed")
          end
        elseif reg.active then
          if opts.verbose then
            print("Initial service worker active")
          end
        end

        M.poll_worker_update(reg)

      end)

    end

  end

  M.get_route = function (s)
    s = s or state
    local path = {}
    local params = {}
    if s and s.path then
      arr.copy(path, s.path)
    end
    if s and s.params then
      tbl.assign(params, s.params)
    end
    arr.push(path, params)
    return arr.spread(path)
  end

  M.get_url = function (s)
    s = s or state
    return base_path .. "#" .. util.encode_path(s)
  end

  M.set_route = function (policy, ...)
    local n = varg.len(...)
    local path, params
    if n == 0 then
      path = {}
      params = {}
    else
      params = varg.sel(n, ...)
      if type(params) == "table" then
        n = n - 1
        path = { varg.take(n, ...) }
      else
        params = {}
        path = { varg.take(n, ...) }
      end
    end
    M.fill_defaults(path, params)
    state.path = path
    state.params = params
    local url = M.get_url(state)
    if policy == "push" then
      local hstate = { id = (history.state and history.state.id or 0) + 1 }
      hstate.mark = history.state and history.state.mark or {}
      history:pushState(val(hstate, true), "", url)
      state.current_id = hstate.id
    elseif policy == "replace" then
      local hstate = { id = (history.state and history.state.id or 0) }
      hstate.mark = history.state and history.state.mark or {}
      history:replaceState(val(hstate, true), "", url)
      state.current_id = hstate.id
    else
      err.error("Invalid history setting", policy)
    end
  end

  M.back = function ()
    history:back()
  end

  M.forward = function (...)
    M.set_route("push", ...)
    M.transition("forward")
  end

  M.backward = function (...)
    M.set_route("push", ...)
    M.transition("backward")
  end

  M.replace_forward = function (...)
    M.set_route("replace", ...)
    M.transition("forward")
  end

  M.replace_backward = function (...)
    M.set_route("replace", ...)
    M.transition("backward")
  end

  window:addEventListener("popstate", function (_, ev)
    local state0 = util.parse_path(str.match(location.hash, "^#(.*)"))
    local id = ev.state and ev.state.id and tonumber(ev.state.id)
    local dir = (id and state.current_id and id < state.current_id) and "backward" or "forward"
    if state.popmark then
      local p = state.popmark
      state.popmark = nil
      M.set_route("replace", arr.spread(p))
    else
      M.set_route("replace", M.get_route(state0))
    end
    M.transition(dir)
  end)

  window:addEventListener("resize", function ()
    M.on_resize()
  end)

  history.scrollRestoration = "manual"
  M.setup_active_view()
  M.on_resize()
  M.set_route("replace", M.get_route())
  M.transition("forward", true, true)

end
