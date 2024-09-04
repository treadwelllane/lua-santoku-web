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
  local t_nav_overlay = e_head:querySelector("template.nav-overlay")

  local base_path = location.pathname
  local state = util.parse_path(str.match(location.hash, "^#(.*)"))
  local active_view

  local M = {}

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

    end)

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

  M.setup_panes = function (view, init, el)
    el = el or view.el
    if not view.page.panes then
      return
    end
    el:querySelectorAll("[data-pane]"):forEach(function (_, el0)
      local name = el0.dataset.pane
      local pane = view.page.panes[name]
      pane.el = el0
      M.pane(view, name, pane.pages.default, init)
    end)
  end

  M.setup_alt = function (view, init, explicit)
    if not state.path[3] then
      M.find_default(view.page, state.path, 3)
    end
    if not state.path[3] then
      return
    end
    M.alt(view, state.path[3], "ignore", init, explicit)
    if view.parent then
      if active_view.el.classList:contains("is-wide") then
        M.toggle_nav_state(view.parent, true, false, false)
      else
        M.toggle_nav_state(view.parent, false, false, false)
      end
    end
  end

  M.setup_nav = function (view, dir, init, explicit)

    view.e_nav = view.el:querySelector("section > nav")

    if view.e_nav then

      view.e_nav:addEventListener("scroll", function (_, ev)
        ev:stopPropagation()
      end)

      view.e_nav_overlay = util.clone(t_nav_overlay, nil, view.el)

      view.e_nav_overlay:addEventListener("click", function ()
        M.toggle_nav_state(view, false)
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
            M.toggle_nav_state(view, true)
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

      view.e_main:addEventListener("touchstart", on_touch_start)
      view.e_main:addEventListener("touchmove", on_touch_move)
      view.e_main:addEventListener("touchend", on_touch_end)
      view.e_main:addEventListener("touchcancel", on_touch_end)

      view.e_nav_buttons = view.e_nav:querySelectorAll("button[data-page]")
      view.nav_order = {}
      view.e_nav_buttons:forEach(function (_, el)
        local n = el.dataset.page
        arr.push(view.nav_order, n)
        view.nav_order[n] = #view.nav_order
        el:addEventListener("click", function ()
          if not el.classList:contains("is-active") then
            M.forward(view.name, n)
          end
          util.after_frame(function ()
            M.toggle_nav_state(view, false)
          end)
        end)
      end)

    end

    if not state.path[2] then
      M.find_default(view.page, state.path, 2)
    end

    if state.path[2] then
      M.switch(view, state.path[2], "ignore", dir, init, explicit)
    end

    if view.e_nav then
      if active_view.el.classList:contains("is-wide") then
        M.toggle_nav_state(view, true, false, false)
      else
        M.toggle_nav_state(view, false, false, false)
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

  -- TODO: Currently this figures out how many buttons are on either side of the
  -- title, and sets the title width such that it doesn't overlap the side with
  -- the most buttons. The problem is that if one side has a button and the
  -- other doesnt, and the title is long enough to overlap, it confusingly gets
  -- cut off on the side without buttons, when ideally it should only be getting
  -- cut off by the buttons. We need some sort of adaptive centering as the user
  -- types into the title input or based on the actual displayed length.
  M.setup_header_title_width = function (view)

    if not view.e_header then
      return
    end

    local e_title = view.e_header:querySelector("h1")

    if not e_title then
      return
    end

    if active_view.el.classList:contains("is-wide") then
      e_title.style.maxWidth = nil
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
    local maxWidth = "calc(100dvw - " .. shrink .. "px)"

    e_title.style.maxWidth = maxWidth

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

    view.e_main.style["min-width"] = "calc(100dvw - " .. nav_push .. "px)"
    view.e_main.style.opacity = view.main_opacity
    view.e_main.style["z-index"] = view.main_index

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

  M.style_main_alt = function (view, animate)

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

    view.e_main.style["min-width"] = "calc(100dvw - " .. nav_push .. "px)"
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
      local snack_top = e_body.clientHeight + offset - opts.snack_height - opts.padding

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
            opts.snack_height + opts.padding
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

  M.style_main_transition_alt = function (next_view, transition, last_view, init)

    if init and transition == "enter" then

      next_view.main_opacity = 1
      next_view.main_index = opts.main_index + 1
      M.style_main_alt(next_view)

    elseif transition == "enter" then

      next_view.main_opacity = 0
      next_view.main_index = opts.main_index + 1
      M.style_main_alt(next_view)

      util.after_frame(function ()
        next_view.main_opacity = 1
        M.style_main_alt(next_view, true)
      end)

    elseif transition == "exit" then

      last_view.main_opacity = 0
      last_view.main_index = opts.main_index - 1
      M.style_main_alt(last_view, true)

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
      view.active_view.main_offset = view.header_offset
    end
    view.nav_offset = view.header_offset
    if restyle ~= false then
      M.style_header(view, true)
      M.style_nav(view, true)
      M.style_fabs(view, true)
      if view.active_view then
        M.style_main_header_switch(view.active_view, true)
        M.style_main_switch(view.active_view, true)
      end
    end
  end

  -- TODO: Should this be debounced or does the view.header_hide check
  -- accomplish that?
  M.scroll_listener = function (view)

    local ready = true

    local last_scroll_top = 0

    local n = 0

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

      if curr_diff >= 10 then
        n = (n < 0 and 0 or n) + 1
      elseif curr_diff <= -10 then
        n = (n > 0 and 0 or n) - 1
      end

      if view.header_hide and curr_scroll_top <= tonumber(opts.header_height) then
        M.style_header_hide(view, false)
      elseif not view.header_hide and n > 4 then
        M.style_header_hide(view, true)
      elseif view.header_hide and n <= -4 then
        M.style_header_hide(view, false)
      end

      if not active_view.el.classList:contains("is-wide") and view.el.classList:contains("showing-nav") then
        M.toggle_nav_state(view, false)
      end

      last_scroll_top = curr_scroll_top <= 0 and 0 or curr_scroll_top

      M.after_transition(function ()
        ready = true
      end)

    end
  end

  M.after_transition = function (fn, ...)
    return window:setTimeout(function (...)
      util.after_frame(fn, ...)
    end, tonumber(opts.transition_time), ...)
  end

  M.post_enter_pane = function (view, next_view)
    view.el.classList:remove("transition")
    M.setup_ripples(next_view.el)
  end

  M.post_enter_alt = function (view, next_view)
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
    if last_view.page.panes then
      for _, pane in it.pairs(last_view.page.panes) do
        pane.active_view = nil
      end
    end
  end

  M.post_exit_alt = function (last_view)
    last_view.el:remove()
    if last_view.page.destroy then
      last_view.page.destroy(last_view, opts)
    end
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
        M.toggle_nav_state(next_view)
      end)
    end

    if next_view.e_header then
      next_view.curr_scrolly = nil
      next_view.last_scrolly = nil
      next_view.scroll_listener = M.scroll_listener(next_view)
      window:addEventListener("scroll", next_view.scroll_listener)
    end

    M.setup_ripples(next_view.el)

  end

  M.enter_pane = function (view_pane, next_view, last_view, init, ...)

    next_view.el = util.clone(next_view.page.template)
    next_view.e_main = next_view.el:querySelector("section > main")

    M.setup_panes(next_view, init)
    M.style_main_transition_alt(next_view, "enter", last_view, init)

    if next_view.page.init then
      next_view.page.init(next_view, ...)
    end

    view_pane.el.classList:add("transition")
    view_pane.el:append(next_view.el)

    M.after_transition(function ()
      return M.post_enter_pane(view_pane, next_view)
    end)

  end

  M.enter_alt = function (view, next_view, last_view, init)

    next_view.el = util.clone(next_view.page.template)
    next_view.e_main = next_view.el:querySelector("section > main")

    M.setup_panes(next_view, init)
    M.style_main_transition_alt(next_view, "enter", last_view, init)

    if next_view.page.init then
      next_view.page.init(next_view, opts)
    end

    view.el.classList:add("transition")
    view.e_main:append(next_view.el)

    M.after_transition(function ()
      return M.post_enter_alt(view, next_view)
    end)

  end

  M.enter_switch = function (view, next_view, direction, last_view, init, explicit)

    next_view.el = util.clone(next_view.page.template)
    next_view.e_main = next_view.el:querySelector("section > main")
    next_view.e_main_header = next_view.el:querySelector("section > header")

    M.setup_alt(next_view, init, explicit)
    M.setup_panes(next_view, init)
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
    M.style_main_transition_alt(next_view, "exit", last_view)
    M.after_transition(function ()
      return M.post_exit_pane(last_view)
    end, true)
  end

  M.exit_alt = function (last_view, next_view)
    M.style_main_transition_alt(next_view, "exit", last_view)
    M.after_transition(function ()
      return M.post_exit_alt(last_view)
    end, true)
  end

  M.exit_switch = function (view, last_view, direction, next_view)

    view.header_offset = 0
    M.style_header(view, true)

    last_view.el.style.marginLeft = -window.scrollX .. "px"
    last_view.el.style.marginTop = -window.scrollY .. "px"
    last_view.no_scroll = true
    window:scrollTo({ top = 0, left = 0, behavior = "instant" })

    M.style_main_header_transition_switch(next_view, "exit", direction, last_view)
    M.style_main_transition_switch(next_view, "exit", direction, last_view)

    M.after_transition(function ()
      return M.post_exit_switch(last_view)
    end, true)

  end

  M.enter = function (next_view, direction, last_view, init, explicit)

    next_view.el = util.clone(next_view.page.template)
    next_view.e_header = next_view.el:querySelector("section > header")
    next_view.e_main = next_view.el:querySelector("section > main")

    M.setup_observer(next_view)
    M.setup_nav(next_view, direction, init, explicit)
    M.setup_fabs(next_view, last_view)
    M.setup_snacks(next_view)
    M.setup_header_title_width(next_view)
    M.setup_panes(next_view, init)
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
  end

  M.init_view = function (name, path_idx, page, parent)

    err.assert(name ~= "default", "view name can't be default")

    local view = {
      parent = parent,
      forward = M.forward,
      backward = M.backward,
      replace_forward = M.replace_forward,
      replace_backward = M.replace_backward,
      path_idx = path_idx,
      page = page,
      name = name,
      state = state
    }

    view.toggle_nav = function ()
      return M.toggle_nav_state(active_view.active_view, not view.el.classList:contains("showing-nav"), true, true)
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

  M.get_url = function ()
    local p = util.encode_path(state)
    return base_path .. "#" .. p
  end

  M.set_route = function (policy)
    if policy == "replace" then
      history:replaceState(val(state, true), nil, M.get_url())
    elseif policy == "push" then
      history:pushState(val(state, true), nil, M.get_url())
    end
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

  M.maybe_redirect = function (view, page, explicit)
    if page and page.redirect then
      return varg.tup(function (a, ...)
        if a == true then
          M.replace_forward(varg.append(..., arr.spread(state.path, 1, view.path_idx)))
          return true
        elseif a then
          M.replace_forward(a, ...)
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

  M.pane = function (view, name, page_name, init, ...)

    local view_pane = view.page.panes and view.page.panes[name]
    page_name = M.resolve_default(view_pane, page_name)
    local pane_page = view_pane.pages and view_pane.pages[page_name]
    err.assert(pane_page, "no pane found", name, page_name)

    if view_pane.active_view and pane_page == view_pane.active_view.page then
      return
    end

    local last_view_pane = view_pane.active_view
    view_pane.active_view = M.init_view(page_name, nil, pane_page, view_pane)

    M.enter_pane(view_pane, view_pane.active_view, last_view_pane, init, ...)

    if last_view_pane then
      M.exit_pane(last_view_pane, view_pane.active_view)
    end

  end

  M.alt = function (view, name, policy, init, explicit)

    local page = view.page.pages and view.page.pages[name]
    err.assert(page, "no alt found", name)

    if M.maybe_redirect(view, page, explicit) then
      return
    end

    if view.active_view and page == view.active_view.page then
      return
    end

    local last_view = view.active_view
    view.active_view = M.init_view(name, 3, page, view)

    M.enter_alt(view, view.active_view, last_view, init)

    if last_view then
      M.exit_alt(last_view, view.active_view)
    end

    M.set_route(policy)

  end

  M.switch = function (view, name, policy, dir, init, explicit)

    local page = view.page.pages and view.page.pages[name]
    err.assert(page, "no switch found", name)

    if M.maybe_redirect(view, page, explicit) then
      return
    end

    if view.active_view and page == view.active_view.page then
      if state.path[3] then
        return M.alt(view.active_view, state.path[3], policy, init, explicit)
      end
      return
    end

    local last_view = view.active_view
    view.active_view = M.init_view(name, 2, page, view)

    if view.e_nav then
      view.e_nav_buttons:forEach(function (_, el)
        if el.dataset.page == name then
          el.classList:add("is-active")
        else
          el.classList:remove("is-active")
        end
      end)
    end

    local dir = M.switch_dir(view, view.active_view, last_view, dir)

    M.enter_switch(view, view.active_view, dir, last_view, init, explicit)

    if last_view then
      M.exit_switch(view, last_view, dir, view.active_view)
    end

    M.set_route(policy)

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

  M.fill_defaults = function ()
    local v = active_view.page
    if #state.path < 1 then
      M.find_default(v, state.path, 1)
    else
      for i = 1, #state.path do
        local r = M.resolve_default(v, state.path[i])
        v = r == state.path[i] and v.pages and v.pages[r]
        if not v then
          M.find_default(v, state.path, i)
          break
        end
      end
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

  M.transition = function (policy, dir, init, explicit)

    util.after_frame(function ()

      M.fill_defaults()

      local page = active_view.page.pages[state.path[1]]
      err.assert(page, "no page found", state.path[1])

      if M.maybe_redirect(active_view, page, explicit) then
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
        M.switch(active_view.active_view, state.path[2], policy, nil, init, explicit)
      end

      M.set_route(policy)

    end)

  end

  M.toggle_nav_state = function (view, open, animate, restyle)
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
    if window.innerWidth > 961 then
      active_view.el.classList:add("is-wide")
    else
      active_view.el.classList:remove("is-wide")
    end
    if active_view.active_view then
      if active_view.el.classList:contains("is-wide") then
        M.toggle_nav_state(active_view.active_view, true)
      elseif was_wide then
        M.toggle_nav_state(active_view.active_view, false)
      end
      M.setup_header_title_width(active_view.active_view)
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
              active_view.el.classList:add("update-worker")
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

  window:addEventListener("popstate", function (_, ev)
    if ev.state then
      state = ev.state:val():lua(true)
      M.transition("ignore", "backward", nil, true)
    else
      state = util.parse_path(str.match(location.hash, "^#(.*)"))
      M.transition("replace", "forward", nil, true)
    end
  end)

  window:addEventListener("resize", function ()
    M.on_resize()
  end)

  M.setup_active_view()
  history.scrollRestoration = "manual"
  M.on_resize()

  if #state.path > 0 then
    M.transition("replace", "forward", true, true)
  else
    M.find_default(active_view.page, state.path, 1)
    M.transition("push", "forward", true, true)
  end

end
