local err = require("santoku.error")
local async = require("santoku.async")
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
local json = require("cjson")

return function (opts)

  opts = tbl.merge({}, opts or {}, def.spa or {})

  local Array = js.Array
  local window = js.window
  local history = window.history
  local document = window.document
  local location = window.location

  local e_container = document.body
  local e_scroll_pane = document.documentElement
  local e_scroll_container = window

  local t_spacer = e_container:querySelector("template.tk-spacer")
  local t_ripple = e_container:querySelector("template.tk-ripple")
  local t_nav_overlay = e_container:querySelector("template.tk-nav-overlay")
  local t_modal_overlay = e_container:querySelector("template.tk-modal-overlay")

  local base_path = location.pathname
  local state = util.parse_path(str.match(location.hash, "^#(.*)"), nil, nil, opts.modal_separator)

  -- TODO: make properties of state
  local http = util.http_client()
  local root
  local size, vw, vh
  local bottom_offset_total = opts.padding
  local banner_offset_total = 0

  local M = {}

  http.on("request", function (req)
    if req.view then
      req.view.events.on("destroy", req.cancel)
    end
  end)

  http.on("response", function (_, req)
    if req.view then
      req.view.events.off("destroy", req.cancel)
    end
  end)

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

  local function same_view (view, name, m)
    m = m or "main"
    return name == tbl.get(view, m, "name")
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
        el.classList:remove("tk-clicked")
        e_ripple:remove()
      end)

      local e_wave = e_ripple:querySelector(".tk-ripple-wave")
      local rect = el:getBoundingClientRect()
      local dia = num.min(num.max(rect.height, rect.width, 100), 200)
      local x = ev.clientX - rect.left
      local y = ev.clientY - rect.top

      e_wave.style.width = dia .. "px"
      e_wave.style.height = dia .. "px"
      e_wave.style.left = (x - dia / 2) .. "px"
      e_wave.style.top = (y - dia / 2) .. "px"

      el.classList:add("tk-clicked")
      el:append(e_ripple)

    end, false)

  end

  M.setup_dropdowns = function (view, el)
    el = el or view.el
    if not el then
      return
    end
    view.e_dropdowns = el:querySelectorAll(".tk-dropdown")
    view.e_dropdowns:forEach(function (_, e_dropdown)
      local e_trigger = e_dropdown:querySelector(":scope > button")
      document:addEventListener("click", function (_, ev)
        if ev.e_dropdown ~= e_dropdown then
          e_dropdown.classList:remove("tk-open")
        end
      end)
      document:addEventListener("touchstart", function (_, ev)
        if ev.e_dropdown ~= e_dropdown then
          e_dropdown.classList:remove("tk-open")
        end
      end)
      e_scroll_container:addEventListener("scroll", function (_, ev)
        if ev.e_dropdown ~= e_dropdown then
          e_dropdown.classList:remove("tk-open")
        end
      end)
      e_dropdown:addEventListener("click", function (_, ev)
        ev.e_dropdown = e_dropdown
      end)
      e_dropdown:addEventListener("touchstart", function (_, ev)
        ev.e_dropdown = e_dropdown
      end)
      e_dropdown:addEventListener("scroll", function (_, ev)
        ev.e_dropdown = e_dropdown
      end)
      e_trigger:addEventListener("click", function ()
        e_dropdown.classList:add("tk-open")
      end)
    end)
  end

  M.setup_panes = function (view, init, el)
    el = el or view.el
    if not el or not tbl.get(view, "page", "panes") then
      return
    end
    el:querySelectorAll("[tk-pane]"):forEach(function (_, el0)
      local name = el0:getAttribute("tk-pane")
      local pane = view.page.panes[name]
      if pane then
        pane.el = el0
        M.pane(view, name, pane.pages.default, init)
      end
    end)
  end

  M.get_nav_button_page = function (el)
    local name, push
    name = el:getAttribute("tk-page") or el:getAttribute("tk-page-push")
    push = name
    name = name or el:getAttribute("tk-page-replace")
    return name, push
  end

  M.destroy_header_links = function (view)
    if not (root and root.main) then
      return
    end
    while true do
      local el = next(view.self_header_links)
      if not el then
        break
      end
      view.self_header_links[el] = nil
      root.main.header_links[el] = nil
    end
  end

  M.setup_header_links = function (view, el)
    el = el or view.el
    if not el or not (root and root.main) then
      return
    end
    view.self_header_links = {}
    root.main.header_links = root.main.header_links or {}
    el:querySelectorAll(".tk-header-link"):forEach(function (_, el)
      view.self_header_links[el] = true
      root.main.header_links[el] = true
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
        :querySelectorAll("button[tk-page], button[tk-page-replace], button[tk-page-push]")
      view.nav_order = {}
      view.e_nav_buttons:forEach(function (_, el)
        local name, push = M.get_nav_button_page(el)
        arr.push(view.nav_order, name)
        view.nav_order[name] = #view.nav_order
        el:addEventListener("mousedown", function ()
          el.classList:add("tk-transition")
          window:setTimeout(function ()
            el.classList:remove("tk-transition")
          end, tonumber(opts.transition_time) * 4)
        end)
        el:addEventListener("click", function ()
          if not el.classList:contains("tk-active") then
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

    M.modal(view, state.modal, dir, init, explicit)

    if view.e_nav then
      if size == "lg" or size == "md" then
        M.toggle_nav_state(true, false, false)
      else
        M.toggle_nav_state(false, false, false)
      end
    end

  end

  M.setup_ripples = function (el)

    el:querySelectorAll("button:not(.tk-no-ripple)"):forEach(function (_, el)
      if el._ripple then
        return
      end
      el._ripple = true
      M.setup_ripple(el)
    end)

    el:querySelectorAll(".tk-ripple"):forEach(function (_, el)
      if el._ripple or el == t_ripple then
        return
      end
      el._ripple = true
      M.setup_ripple(el)
    end)

    if el.classList:contains("tk-ripple") then
      el._ripple = true
      M.setup_ripple(el)
    end

  end

  M.get_subheader_offset = function (view)
    local offset = M.get_base_header_offset() + (view.header_offset or 0) + (opts.header_height or 0)
    if view.main and view.main.e_main_header then
      offset = offset + (opts.header_height or 0)
    end
    return offset
  end

  M.get_base_header_offset = function ()
    return banner_offset_total or 0
  end

  M.get_base_footer_offset = function ()
    return 0
  end

  M.should_show = function (view, el)

    local hides = it.collect(it.map(str.sub, str.matches(el:getAttribute("tk-hide") or "", "[^%s]+")))

    for h in it.ivals(hides) do
      if view.el.classList:contains(h) then
        return false
      end
    end

    local shows = it.collect(it.map(str.sub, str.matches(el:getAttribute("tk-show") or "", "[^%s]+")))

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
      view.e_header.classList:add("tk-animated")
      if view.header_animation then
        window:clearTimeout(view.header_animation)
        view.header_animation = nil
      end
      view.header_animation = M.after_transition(function ()
        view.e_header.classList:remove("tk-animated")
        view.header_animation = nil
      end)
    end

    view.e_header.style.transform =
      "translateY(" .. (M.get_base_header_offset() + view.header_offset) .. "px)"

    view.e_header.style.opacity = view.header_opacity
    view.e_header.style["z-index"] = view.header_index

  end

  M.style_nav = function (view, animate)

    if not view.e_nav then
      return
    end

    if animate then
      view.e_nav.classList:add("tk-animated")
      if view.nav_animation then
        window:clearTimeout(view.nav_animation)
        view.nav_animation = nil
      end
      view.nav_animation = M.after_transition(function ()
        view.e_nav.classList:remove("tk-animated")
        view.nav_animation = nil
      end)
    end

    if not view.nav_slide then
      if view.e_nav and view.el.classList:contains("tk-showing-nav") then
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
      view.e_main.classList:add("tk-animated")
      if view.main_animation then
        window:clearTimeout(view.main_animation)
        view.main_animation = nil
      end
      view.main_animation = M.after_transition(function ()
        view.e_main.classList:remove("tk-animated")
        view.main_animation = nil
      end)
    end

    local nav_push = (view.e_nav and (size == "lg" or size == "md"))
      and opts.nav_width or 0

    view.e_main.style.transform =
      "translate(" .. nav_push .. "px," .. (M.get_base_header_offset() + view.main_offset) .. "px)"

    view.e_main.style["min-width"] = "calc(100% - " .. nav_push .. "px)"
    view.e_main.style.opacity = view.main_opacity
    view.e_main.style["z-index"] = view.main_index

  end

  M.style_header_links = function (view, animate)

    if not view.header_links or not next(view.header_links) then
      return
    end

    if animate then
      for el in pairs(view.header_links) do
        el.classList:add("tk-animated")
      end
      if view.header_link_animation then
        window:clearTimeout(view.header_link_animation)
        view.header_link_animation = nil
      end
      view.header_link_animation = M.after_transition(function ()
        for el in pairs(view.header_links) do
          el.classList:remove("tk-animated")
        end
        view.header_link_animation = nil
      end)
    end

    for el in pairs(view.header_links) do
      el.style.transform = "translateY(" .. view.header_offset .. "px)"
    end

  end


  M.style_main_header_switch = function (view, animate)

    if not view.e_main_header then
      return
    end

    if animate then
      view.e_main_header.classList:add("tk-animated")
      if view.main_header_animation then
        window:clearTimeout(view.main_header_animation)
        view.main_header_animation = nil
      end
      view.main_header_animation = M.after_transition(function ()
        view.e_main_header.classList:remove("tk-animated")
        view.main_header_animation = nil
      end)
    end

    local nav_push = (view.parent and view.parent.e_nav and (size == "lg" or size == "md"))
      and opts.nav_width or 0

    view.e_main_header.style.transform =
      "translate(" .. nav_push .. "px," .. (M.get_base_header_offset() + view.main_header_offset) .. "px)"

    view.e_main_header.style["width"] = "calc(100% - " .. nav_push .. "px)"
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
      view.e_main.classList:add("tk-animated")
      if view.main_animation then
        window:clearTimeout(view.main_animation)
        view.main_animation = nil
      end
      view.main_animation = M.after_transition(function ()
        view.e_main.classList:remove("tk-animated")
        view.main_animation = nil
      end)
    end

    view.e_main.style.opacity = view.main_opacity or 1
    view.e_main.style["z-index"] = view.main_index

  end

  M.style_modal = function (view, animate)

    if animate then
      view.e_main.classList:add("tk-animated")
      if view.main_animation then
        window:clearTimeout(view.main_animation)
        view.main_animation = nil
      end
      view.main_animation = M.after_transition(function ()
        view.e_main.classList:remove("tk-animated")
        view.main_animation = nil
      end)
    end

    view.e_main.style["z-index"] = view.main_index
    view.e_main.style.opacity = view.main_opacity
    view.e_main.style.transform =
      "translate(" ..
        "calc(" .. view.main_offset_x .. "px - 50%)," ..
        "calc(" .. ((M.get_base_header_offset() / 2) + view.main_offset_y - ((bottom_offset_total - opts.padding) / 2)) .. "px - 50%))" ..
      "scale(" .. view.main_scale or 1 .. ")"

    view.e_main.style.maxHeight = "calc(100% - 2em - " .. (M.get_base_header_offset() + bottom_offset_total - opts.padding) .. "px)"

    view.e_modal_overlay.style["z-index"] = view.overlay_index
    view.e_modal_overlay.style.opacity = view.overlay_opacity

  end

  M.style_main_switch = function (view, animate)

    if not view.e_main then
      return
    end

    if animate then
      view.e_main.classList:add("tk-animated")
      if view.main_animation then
        window:clearTimeout(view.main_animation)
        view.main_animation = nil
      end
      view.main_animation = M.after_transition(function ()
        view.e_main.classList:remove("tk-animated")
        view.main_animation = nil
      end)
    end

    local nav_push = (view.parent and view.parent.e_nav and (size == "lg" or size == "md"))
      and opts.nav_width or 0

    view.e_main.style.transform =
      "translate(" .. nav_push .. "px," .. (M.get_base_header_offset() + view.main_offset) .. "px)"

    view.e_main.style["width"] = "calc(100% - " .. nav_push .. "px)"
    view.e_main.style["min-width"] = "calc(100% - " .. nav_push .. "px)"
    view.e_main.style.opacity = view.main_opacity
    view.e_main.style["z-index"] = view.main_index

  end

  M.setup_banners = function (view)
    view.banner_add = {}
    view.banner_remove = {}
    view.banner_list = {}
    view.banner_list_index = {}
  end

  M.setup_snacks = function (view)
    view.snack_add = {}
    view.snack_remove = {}
    view.snack_list = {}
    view.snack_list_index = {}
  end

  M.banner = function (view, name, page, data)
    if not (root and root.main) then
      return
    end
    local banner
    if page == nil then
      if name then
        root.banner_remove[name] = true
        tbl.set(view, "active_banners", name, nil)
      else
        for i = 1, #root.main.banner_list do
          root.main.banner_remove[root.main.banner_list[i].name] = true
          tbl.set(view, "active_banners", root.main.banner_list[i].name, nil)
        end
      end
    else
      page = maybe_wrap(page)
      banner = M.init_view(name, page, root)
      arr.push(root.banner_add, { banner = banner, data = data })
      tbl.set(view, "active_banners", name, true)
    end
    M.style_banners(root, true)
    M.on_resize()
    if banner and banner.el then
      return banner
    end
  end

  M.snack = function (view, name, page, data)
    if not (root and root.main) then
      return
    end
    local snack
    if page == nil then
      if name then
        root.main.snack_remove[name] = true
        tbl.set(view, "active_snacks", name, nil)
      else
        for i = 1, #root.main.snack_list do
          root.main.snack_remove[root.main.snack_list[i].name] = true
          tbl.set(view, "active_snacks", root.main.snack_list[i].name, nil)
        end
      end
    else
      page = maybe_wrap(page)
      snack = M.init_view(name, page, root.main)
      arr.push(root.main.snack_add, { snack = snack, data = data })
      tbl.set(view, "active_snacks", name, true)
    end
    M.style_snacks(root.main, true)
    M.on_resize()
    if snack and snack.el then
      return snack
    end
  end

  M.style_snacks = function (view, animate)

    if not (root and root.main) then
      return
    end

    for i = 1, #view.snack_add do
      M.enter_snack(view, view.snack_add[i].snack, view.snack_add[i].data)
    end

    arr.clear(view.snack_add)

    if animate then
      for i = 1, #view.snack_list do
        local snack = view.snack_list[i]
        snack.el.classList:add("tk-animated")
      end
      if view.snack_animation then
        window:clearTimeout(view.snack_animation)
        view.snack_animation = nil
      end
      view.snack_animation = M.after_transition(function ()
        for i = 1, #view.snack_list do
          local snack = view.snack_list[i]
          snack.el.classList:remove("tk-animated")
        end
        view.snack_animation = nil
      end)
    end

    bottom_offset_total = opts.padding

    local nav_push = (view.e_nav and (size == "lg" or size == "md"))
      and opts.nav_width or 0

    for i = 1, #view.snack_list do
      local snack = view.snack_list[i]
      local e_snack = snack.el
      if root.main.active_modal then
        e_snack.style["z-index"] = view.snack_index - opts.snack_index + opts.modal_index + 2
      else
        e_snack.style["z-index"] = view.snack_index
      end
      local offset = view.snack_offset - bottom_offset_total
      local height = e_snack:getBoundingClientRect().height
      if view.snack_remove[snack.name] then
        if view.snack_list_index[snack.name] then
          snack.el.style.opacity = 0
          snack.el.style["pointer-events"] = "none"
          snack.el.style.transform = "translate(" .. nav_push .. "px," .. offset .. "px)"
          M.exit_snack(view, snack)
        else
          view.snack_remove[snack.name] = nil
        end
      else
        if snack.should_update then
          snack.events.emit("update")
        end
        snack.should_update = true
        snack.el.style.opacity = view.snack_opacity
        snack.el.style["pointer-events"] = (view.snack_opacity or 0) == 0 and "none" or "all"
        snack.el.style.transform = "translate(" .. nav_push .. "px," .. offset .. "px)"
        bottom_offset_total = bottom_offset_total + height + opts.padding
      end
    end

    tbl.clear(view.snack_remove)

    local e_spacer = tbl.get(root, "main", "main", "e_spacer")
    if e_spacer then
      e_spacer.style.transform = "translateY(" .. (bottom_offset_total - opts.padding) .. "px)"
    end

  end

  M.style_banners = function (view, animate)

    if not (root and root.main) then
      return
    end

    for i = 1, #view.banner_add do
      M.enter_banner(view, view.banner_add[i].banner, view.banner_add[i].data)
    end

    arr.clear(view.banner_add)

    if animate then
      for i = 1, #view.banner_list do
        local banner = view.banner_list[i]
        banner.el.classList:add("tk-animated")
      end
      if view.banner_animation then
        window:clearTimeout(view.banner_animation)
        view.banner_animation = nil
      end
      view.banner_animation = M.after_transition(function ()
        for i = 1, #view.banner_list do
          local banner = view.banner_list[i]
          banner.el.classList:remove("tk-animated")
        end
        view.banner_animation = nil
      end)
    end

    banner_offset_total = 0

    local shown_index = opts.banner_index + #view.banner_list

    for i = 1, #view.banner_list do
      local banner = view.banner_list[i]
      if view.banner_remove[banner.name] then
        if view.banner_list_index[banner.name] then
          local transform = "translateY(" .. banner_offset_total .. "px)"
          view.after_frame(function ()
            banner.el.style["z-index"] = shown_index
            banner.el_banner.style.transform = transform
          end)
          M.exit_banner(view, banner)
        else
          view.banner_remove[banner.name] = nil
        end
      else
        if banner.should_update then
          banner.events.emit("update")
        end
        local height = banner.el:getBoundingClientRect().height
        banner.should_update = true
        banner.el.style.top = (height * -1) .. "px"
        banner_offset_total = banner_offset_total + height
        local transform = "translateY(" .. banner_offset_total .. "px)"
        view.after_frame(function ()
          banner.el.style["z-index"] = shown_index
          banner.el.style.transform = transform
        end)
      end
      shown_index = shown_index - 1
    end

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

  M.style_modal_transition = function (next_view, transition, direction, last_view, init)

    if init and direction == "forward" then

      next_view.overlay_opacity = 1
      next_view.main_scale = 1
      next_view.main_opacity = 1
      next_view.main_offset_x = 0
      next_view.main_offset_y = 0
      next_view.main_index = opts.modal_index + 1
      next_view.overlay_index = opts.modal_overlay_index + 1
      M.style_modal(next_view)

    elseif transition == "enter" and direction == "forward" then

      next_view.overlay_opacity = 0
      next_view.main_scale = opts.modal_scale
      next_view.main_opacity = 0
      if not last_view and next_view.modal_event then
        -- TODO: better calculation, use transform-origin instead of translateX
        next_view.main_offset_x = next_view.modal_event.pageX - vw / 2
        next_view.main_offset_y = next_view.modal_event.pageY - vh / 2
        local td = math.abs(next_view.main_offset_x) + math.abs(next_view.main_offset_x)
        next_view.main_offset_x = opts.transition_forward_height * next_view.main_offset_x / td
        next_view.main_offset_y = opts.transition_forward_height * next_view.main_offset_y / td
      elseif last_view then
        next_view.overlay_opacity = 1
        next_view.main_offset_x = opts.transition_forward_height
        next_view.main_offset_y = 0
      else
        next_view.main_offset_x = 0
        next_view.main_offset_y = opts.transition_forward_height
      end
      next_view.main_index = opts.modal_index + 1
      next_view.overlay_index = opts.modal_overlay_index + 1
      M.style_modal(next_view)

      util.after_frame(function ()
        next_view.overlay_opacity = 1
        next_view.main_scale = 1
        next_view.main_opacity = 1
        next_view.main_offset_x = 0
        next_view.main_offset_y = 0
        M.style_modal(next_view, true)
      end)

    elseif transition == "exit" and direction == "forward" then

      last_view.overlay_opacity = 0
      last_view.main_scale = opts.modal_scale
      last_view.main_opacity = 0
      if next_view then
        last_view.e_modal_overlay:remove()
        last_view.main_offset_x = -opts.transition_forward_height
        last_view.main_offset_y = 0
      else
        last_view.main_offset_x = 0
        last_view.main_offset_y = opts.transition_forward_height
      end
      last_view.main_index = opts.modal_index - 1
      last_view.overlay_index = opts.modal_overlay_index - 1
      M.style_modal(last_view, true)

    elseif transition == "enter" and direction == "backward" then

      -- TODO: derive initial offsets from click event (if no modal) or
      -- direction (if modal). Also, overlay opacity should remain as 1 if
      -- modal exist.
      next_view.overlay_opacity = 0
      next_view.main_scale = opts.modal_scale
      next_view.main_opacity = 0
      if last_view then
        next_view.overlay_opacity = 1
        next_view.main_offset_x = -opts.transition_forward_height
        next_view.main_offset_y = 0
      else
        next_view.main_offset_x = 0
        next_view.main_offset_y = -opts.transition_forward_height
      end
      next_view.main_index = opts.modal_index - 1
      next_view.overlay_index = opts.modal_overlay_index - 1
      M.style_modal(next_view)

      util.after_frame(function ()
        next_view.overlay_opacity = 1
        next_view.main_scale = 1
        next_view.main_opacity = 1
        next_view.main_offset_x = 0
        next_view.main_offset_y = 0
        M.style_modal(next_view, true)
      end)

    elseif transition == "exit" and direction == "backward" then

      last_view.overlay_opacity = 0
      last_view.main_scale = opts.modal_scale
      last_view.main_opacity = 0
      if next_view then
        last_view.e_modal_overlay:remove()
        last_view.main_offset_x = opts.transition_forward_height
        last_view.main_offset_y = 0
      else
        last_view.main_offset_x = 0
        last_view.main_offset_y = opts.transition_forward_height
      end
      last_view.main_index = opts.modal_index + 1
      last_view.overlay_index = opts.modal_overlay_index + 1
      M.style_modal(last_view, true)

    else
      err.error("invalid state", "modal transition")
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
    if view.main then
      view.main.main_header_offset = view.header_offset
    end
    view.nav_offset = view.header_offset
    if restyle ~= false then
      M.style_header(view, true)
      M.style_nav(view, true)
      M.style_header_links(view, true)
      if view.main then
        M.style_main_header_switch(view.main, true)
        M.style_main_switch(view.main, true)
      end
    end
  end

  M.scroll_listener = function (view)

    local scroll_distance = 0
    local last_scroll_top = e_scroll_pane.scrollTop

    return function ()

      local curr_scroll_top = e_scroll_pane.scrollTop

      if curr_scroll_top > last_scroll_top then
        scroll_distance =
          (scroll_distance < 0 and 0 or scroll_distance) +
          (curr_scroll_top - last_scroll_top)
      else
        scroll_distance =
          (scroll_distance > 0 and 0 or scroll_distance) -
          (last_scroll_top - curr_scroll_top)
      end

      last_scroll_top = curr_scroll_top

      if not (size == "lg" or size == "md") and view.el.classList:contains("tk-showing-nav") then
        M.toggle_nav_state()
      end

      if not view.header_hide and
        curr_scroll_top > tonumber(opts.header_hide_minimum) and
        scroll_distance > tonumber(opts.header_hide_threshold)
      then
        M.style_header_hide(view, true)
      elseif curr_scroll_top < tonumber(opts.header_hide_minimum) or
        -scroll_distance > tonumber(opts.header_hide_threshold)
      then
        M.style_header_hide(view, false)
      end

    end
  end

  M.after_transition = function (fn)
    return window:setTimeout(function ()
      return util.after_frame(fn)
    end, tonumber(opts.transition_time))
  end

  M.close_dropdowns = function (view)
    if view and view.e_dropdowns then
      view.e_dropdowns:forEach(function (_, e_dropdown)
        e_dropdown.classList:remove("tk-open")
      end)
    end
  end

  M.clear_snacks = function (view)
    if view and view.snack_list then
      for i = 1, #view.snack_list do
        local snack = view.snack_list[i]
        M.post_exit_snack(snack)
      end
    end
  end

  M.clear_panes = function (view)
    if view and view.page and view.page.panes then
      for _, pane in it.pairs(view.page.panes) do
        if pane.main then
          M.post_exit_pane(pane.main)
          pane.main = nil
        end
      end
    end
  end

  M.post_exit_banner = function (banner)
    banner.el:remove()
    banner.events.emit("destroy")
    M.destroy_dynamic(banner)
  end

  M.post_exit_snack = function (snack)
    snack.el:remove()
    snack.events.emit("destroy")
    M.destroy_dynamic(snack)
  end

  M.post_exit_pane = function (last_view)
    last_view.el:remove()
    last_view.events.emit("destroy")
    M.destroy_dynamic(last_view)
  end

  M.post_exit_modal = function (last_view)
    last_view.el:remove()
    last_view.events.emit("destroy")
    M.destroy_dynamic(last_view)
  end

  M.post_exit_switch = function (last_view)
    last_view.el:remove()
    last_view.events.emit("destroy")
    M.destroy_dynamic(last_view)
  end

  M.post_exit = function (last_view)
    if last_view.main then
      M.post_exit_switch(last_view.main)
    end
    last_view.el:remove()
    last_view.events.emit("destroy")
    M.clear_snacks(last_view)
    M.destroy_dynamic(last_view)
  end

  M.enter_pane = function (view_pane, next_view, last_view, init, ...)

    M.close_dropdowns(last_view)

    next_view.el, next_view.e = util.clone(next_view.page.template)
    next_view.e_main = next_view.el:querySelector("section > main")
    next_view.el.classList:add("tk-pane")
    if type(next_view.name) == "string" then
      next_view.el.classList:add("tk-pane-" .. next_view.name)
    end

    M.setup_dynamic(next_view, init)
    M.style_main_transition_pane(next_view, "enter", last_view, init)

    if next_view.page.init then
      next_view.page.init(next_view, ...)
    end

    view_pane.el.classList:add("tk-transition")
    view_pane.el:append(next_view.el)

    M.after_transition(function ()
      view_pane.el.classList:remove("tk-transition")
    end)

  end

  M.enter_modal = function (view, next_view, direction, last_view, init)

    M.close_dropdowns(last_view)

    next_view.el, next_view.e = util.clone(next_view.page.template)
    next_view.e_main = next_view.el:querySelector("section > main")
    next_view.e_modal_overlay = util.clone(t_modal_overlay, nil, next_view.el)
    next_view.el.classList:add("tk-modal")
    if type(next_view.name) == "string" then
      next_view.el.classList:add("tk-modal-" .. next_view.name)
    end

    M.setup_dynamic(next_view, init)
    M.style_modal_transition(next_view, "enter", direction, last_view, init)

    if next_view.page.init then
      next_view.page.init(next_view)
    end

    view.el.classList:add("tk-transition")
    view.el:append(next_view.el)

    M.after_transition(function ()
      view.el.classList:remove("tk-transition")
    end)

  end

  M.enter_switch = function (view, next_view, direction, last_view, init)

    M.close_dropdowns(last_view)

    next_view.el, next_view.e = util.clone(next_view.page.template)
    next_view.e_main = next_view.el:querySelector("section > main")
    next_view.e_main_header = next_view.el:querySelector("section > header")
    next_view.e_spacer = util.clone(t_spacer, nil, next_view.el)
    next_view.el.classList:add("tk-switch")
    if type(next_view.name) == "string" then
      next_view.el.classList:add("tk-switch-" .. next_view.name)
    end

    if next_view.e_main_header then
      next_view.e_main_header.classList:add("tk-header")
    end

    next_view.e_header = next_view.el:querySelector("section > header")
    next_view.e_main = next_view.el:querySelector("section > main")
    M.setup_dynamic(next_view, init)
    M.style_main_header_transition_switch(next_view, "enter", direction, last_view, init)
    M.style_main_transition_switch(next_view, "enter", direction, last_view, init)

    if next_view.page.init then
      next_view.page.init(next_view)
    end

    view.el.classList:add("tk-transition")
    view.e_main:append(next_view.el)

    M.after_transition(function ()
      view.el.classList:remove("tk-transition")
    end)

  end

  M.enter_banner = function (view, banner, data)
    if view.banner_list_index[banner.name] then
      return
    end
    banner.el, banner.e = util.clone(banner.page.template, data)
    banner.e_main = banner.el:querySelector("section > main")
    banner.el.classList:add("tk-banner")
    if type(banner.name) == "string" then
      banner.el.classList:add("tk-banner-" .. banner.name)
    end
    M.setup_dynamic(banner)
    arr.push(view.banner_list, banner)
    view.banner_list_index[banner.name] = #view.banner_list
    view.el:append(banner.el)
  end

  M.exit_banner = function (view, banner)
    local idx = view.banner_list_index[banner.name]
    view.banner_list_index[banner.name] = nil
    view.banner_remove[banner.name] = nil
    arr.remove(view.banner_list, idx, idx)
    M.after_transition(function ()
      return M.post_exit_banner(banner)
    end)
  end

  M.enter_snack = function (view, snack, data)
    if view.snack_list_index[snack.name] then
      return
    end
    snack.el, snack.e = util.clone(snack.page.template, data)
    snack.e_main = snack.el:querySelector("section > main")
    snack.el.classList:add("tk-snack")
    snack.el.style.opacity = 0
    if type(snack.name) == "string" then
      snack.el.classList:add("tk-snack-" .. snack.name)
    end
    M.setup_dynamic(snack)
    arr.push(view.snack_list, snack)
    view.snack_list_index[snack.name] = #view.snack_list
    view.el:append(snack.el)
  end

  M.exit_snack = function (view, snack)
    local idx = view.snack_list_index[snack.name]
    view.snack_list_index[snack.name] = nil
    view.snack_remove[snack.name] = nil
    arr.remove(view.snack_list, idx, idx)
    M.after_transition(function ()
      return M.post_exit_snack(snack)
    end)
  end

  M.exit_pane = function (last_view, next_view)
    if last_view.el.parentElement:getAttribute("tk-scroll-link") then
      last_view.el.style.marginLeft = -e_scroll_pane.scrollLeft .. "px"
      last_view.el.style.marginTop = -e_scroll_pane.scrollTop .. "px"
      e_scroll_pane:scrollTo({ top = 0, left = 0, behavior = "instant" })
    end
    M.style_main_transition_pane(next_view, "exit", last_view)
    M.after_transition(function ()
      return M.post_exit_pane(last_view)
    end, true)
  end

  M.exit_modal = function (last_view, direction, next_view)
    M.style_modal_transition(next_view, "exit", direction, last_view)
    M.after_transition(function ()
      return M.post_exit_modal(last_view)
    end, true)
  end

  M.exit_switch = function (view, last_view, direction, next_view)

    view.header_offset = 0
    M.style_header(view, true)

    last_view.el.style.marginLeft = -e_scroll_pane.scrollLeft .. "px"
    last_view.el.style.marginTop = -e_scroll_pane.scrollTop .. "px"
    e_scroll_pane:scrollTo({ top = 0, left = 0, behavior = "instant" })

    M.style_main_header_transition_switch(next_view, "exit", direction, last_view)
    M.style_main_transition_switch(next_view, "exit", direction, last_view)

    M.after_transition(function ()
      return M.post_exit_switch(last_view)
    end, true)

  end

  M.enter = function (next_view, direction, last_view, init, explicit)

    M.close_dropdowns(last_view)

    next_view.el, next_view.e = util.clone(next_view.page.template)
    next_view.e_header = next_view.el:querySelector("section > header")
    next_view.e_main = next_view.el:querySelector("section > main")

    next_view.el.classList:add("tk-main")
    if type(next_view.name) == "string" then
      next_view.el.classList:add("tk-main-" .. next_view.name)
    end

    if next_view.e_header then
      next_view.e_header.classList:add("tk-header")
    end

    M.setup_nav(next_view, direction, init, explicit)
    M.setup_snacks(next_view)
    M.setup_dynamic(next_view, init)
    M.style_header_transition(next_view, "enter", direction, last_view)
    M.style_nav_transition(next_view, "enter", direction, last_view)
    M.style_snacks_transition(next_view, "enter", direction, last_view)

    -- NOTE: No need to handle the main exist case, since it's handled by
    -- setup_nav above
    if not next_view.main then
      M.style_main_transition(next_view, "enter", direction, last_view)
    end

    if next_view.page.init then
      next_view.page.init(next_view)
    end

    root.el.classList:add("tk-transition")
    root.e_main:append(next_view.el)

    M.after_transition(function ()
      root.el.classList:remove("tk-transition")
      local e_menu = next_view.el:querySelector("section > header > button.tk-menu")
      if e_menu then
        e_menu:addEventListener("click", function ()
          M.toggle_nav_state()
        end)
      end
      if next_view.e_header then
        next_view.curr_scrolly = nil
        next_view.last_scrolly = nil
        next_view.scroll_listener = M.scroll_listener(next_view)
        e_scroll_container:addEventListener("scroll", next_view.scroll_listener, false)
      end
    end)

  end

  M.exit = function (last_view, direction, next_view)

    if last_view.main then
      last_view.main.e_main.style.marginLeft = -e_scroll_pane.scrollLeft .. "px"
      last_view.main.e_main.style.marginTop = -e_scroll_pane.scrollTop .. "px"
    else
      last_view.e_main.style.marginLeft = -e_scroll_pane.scrollLeft .. "px"
      last_view.e_main.style.marginTop = -e_scroll_pane.scrollTop .. "px"
    end

    e_scroll_pane:scrollTo({ top = 0, left = 0, behavior = "instant" })

    M.style_header_transition(next_view, "exit", direction, last_view)
    M.style_nav_transition(next_view, "exit", direction, last_view)
    M.style_snacks_transition(next_view, "exit", direction, last_view)

    if last_view.main then
      M.style_main_header_transition_switch(nil, "exit", direction, last_view.main)
      M.style_main_transition_switch(nil, "exit", direction, last_view.main)
    else
      M.style_main_transition(next_view, "exit", direction, last_view)
    end

    if last_view.scroll_listener then
      e_scroll_container:removeEventListener("scroll", last_view.scroll_listener)
      last_view.scroll_listener = nil
    end

    last_view.el.classList:add("tk-exit", direction)
    M.after_transition(function ()
      return M.post_exit(last_view)
    end, true)

  end

  M.destroy_dynamic = function (view)
    M.clear_panes(view)
    M.close_dropdowns(view)
    M.destroy_header_links(view)
    if root and root.main and view.active_snacks and next(view.active_snacks) then
      for n in pairs(view.active_snacks) do
        root.main.snack_remove[n] = true
      end
      M.style_snacks(root.main, true)
    end
    if root and root.main and view.active_banners and next(view.active_banners) then
      for n in pairs(view.active_banners) do
        root.main.banner_remove[n] = true
      end
      M.style_banners(root.main, true)
    end
  end

  M.setup_back = function (el)
    el:querySelectorAll(".tk-back"):forEach(function (_, el)
      el:addEventListener("click", function ()
        history:back()
      end)
    end)
  end

  M.setup_dynamic = function (view, init, el)
    el = el or view.el
    M.setup_back(el)
    M.setup_ripples(el)
    M.setup_panes(view, init, el)
    M.setup_dropdowns(view, el)
    M.setup_header_links(view, el)
  end

  M.mark = function (tag)
    tag = tag or M.route_tag(state)
    local sl = val.lua(history.state or {}, true)
    sl.id = sl.id or 0
    sl.mark = sl.mark or {}
    sl.mark[tag] = sl.id
    local sj = val(sl, true)
    history:replaceState(sj, "", location.href)
  end

  M.route_tag = function (...)
    local s = M.get_route_spec(...)
    local s0 = #s > 0 and s[1] or s
    return M.get_url(s0, false), s
  end

  M.forward_tag = function (tag, ...)
    local id = history.state and history.state.id
    local mark = history.state and history.state.mark and history.state.mark[tag]
    if id and mark and mark < id then
      local diff = id - mark
      state.popdir = "forward"
      state.popmark = M.get_route_spec(...)
      history:go(-diff)
    else
      M.replace_forward(...)
    end
  end

  M.backward_tag = function (tag, ...)
    local id = history.state and history.state.id
    local mark = history.state and history.state.mark and history.state.mark[tag]
    if id and mark and mark < id then
      local diff = id - mark
      state.popdir = "backward"
      state.popmark = M.get_route_spec(...)
      history:go(-diff)
    else
      M.replace_backward(...)
    end
  end

  M.forward_mark = function (...)
    local tag, spec = M.route_tag(...)
    return M.forward_tag(tag, spec)
  end

  M.backward_mark = function (...)
    local tag, spec = M.route_tag(...)
    return M.backward_tag(tag, spec)
  end

  M.init_view = function (name, page, parent)

    err.assert(name ~= "default", "view name can't be default")

    local view = {
      root = root,
      page = page,
      name = name,
      state = state,
      events = async.events(),
      parent = parent,
      mark = M.mark,
      data = M.data,
      replace = M.replace,
      encode_param = M.encode_param,
      decode_param = M.decode_param,
      get_param = M.get_param,
      set_param = M.set_param,
      back = M.back,
      forward = M.forward,
      backward = M.backward,
      replace_forward = M.replace_forward,
      replace_backward = M.replace_backward,
      forward_modal = M.forward_modal,
      backward_modal = M.backward_modal,
      replace_forward_modal = M.replace_forward_modal,
      replace_backward_modal = M.replace_backward_modal,
      forward_mark = M.forward_mark,
      backward_mark = M.backward_mark,
      forward_tag = M.forward_tag,
      backward_tag = M.backward_tag,
    }

    view.snack = function (...)
      return M.snack(view, ...)
    end

    view.banner = function (...)
      return M.banner(view, ...)
    end

    view.cleanup = function (fn)
      return view.events.on("destroy", fn)
    end

    view.update = function (fn)
      return view.events.on("update", fn)
    end

    view.toggle_nav = function ()
      return M.toggle_nav_state(not view.el.classList:contains("tk-showing-nav"), true, true)
    end

    view.pane = function (name, page_name, ...)
      return M.pane(view, name, page_name, false, ...)
    end

    view.after_transition = M.after_transition
    view.after_frame = util.after_frame

    view.clone_all = function (...)
      local cancel, events = util.clone_all(...)
      events.on("cloned-element", function (k, el, ...)
        M.setup_dynamic(view, nil, el)
        return k(el, ...)
      end, true)
      view.events.on("destroy", cancel)
      events.on("done", function ()
        view.events.off("destroy", cancel)
      end)
      return cancel
    end

    view.clone = function (template, data, parent, before, pre_append)
      return util.clone(template, data, parent, before, function (el)
        M.setup_dynamic(view, nil, el)
        if pre_append then
          return pre_append(el)
        end
      end)
    end

    view.http = tbl.merge({
      get = function (...)
        local req = util.request(...)
        req.view = view
        return http.get(req)
      end,
      post = function (...)
        local req = util.request(...)
        req.view = view
        return http.post(req)
      end
    }, http)

    return view

  end

  M.switch_dir = function (view, next_switch, last_switch, dir)
    if not view.e_nav then
      return dir or "forward"
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
    if name == "default" or not view.pages[name] then
      return view.pages.default
    else
      return name
    end
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

    if same_view(view_pane, page_name) then
      view_pane.main.events.emit("update")
      return
    end

    local last_view_pane = view_pane.main

    view_pane.main = M.init_view(page_name, pane_page, view)

    M.enter_pane(view_pane, view_pane.main, last_view_pane, init, ...)

    if last_view_pane then
      M.exit_pane(last_view_pane, view_pane.main)
    end

  end

  M.modal = function (view, name, dir, init, explicit)

    if not name then
      if view.active_modal then
        M.exit_modal(view.active_modal, dir)
        view.active_modal = nil
      end
      return
    end

    local page = type(name) == "table"
      and name
      or M.get_page(view.page.modals, name, "(modal)")

    if M.maybe_redirect(view, page, init, explicit) then
      return
    end

    if same_view(view, name, "active_modal") then
      view.active_modal.events.emit("update")
      return
    end

    local last_modal = view.active_modal
    view.active_modal = M.init_view(name, page, view)
    view.active_modal.modal_event = state.modal_event or (last_modal and last_modal.modal_event) or nil

    M.enter_modal(view, view.active_modal, dir, last_modal, init)

    if last_modal then
      M.exit_modal(last_modal, dir, view.active_modal)
    end

  end

  M.switch = function (view, name, dir, init, explicit)

    local page = type(name) == "table"
      and name
      or M.get_page(view.page.pages, name, "(switch)")

    if M.maybe_redirect(view, page, init, explicit) then
      return
    end

    if same_view(view, name) then
      view.main.events.emit("update")
      return
    end

    local last_view = view.main
    view.main = M.init_view(name, page, view)

    if view.e_nav then
      view.e_nav_buttons:forEach(function (_, el)
        if M.get_nav_button_page(el) == name then
          el.classList:add("tk-active")
        else
          if el.classList:contains("tk-active") then
            el.classList:add("tk-transition")
            window:setTimeout(function ()
              el.classList:remove("tk-transition")
            end, tonumber(opts.transition_time) * 4)
            el.classList:remove("tk-active")
          end
        end
      end)
    end

    dir = M.switch_dir(view, view.main, last_view, dir)

    M.enter_switch(view, view.main, dir, last_view, init)

    if last_view then
      M.exit_switch(view, last_view, dir, view.main)
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

  local function assign_persisted (v, params)
    local params0 = v and v.params
    if params0 then
      for j = 1, #params0 do
        local param = params0[j]
        params[param] = params[param] or state.params[param]
      end
    end
  end

  M.assign_persisted = function (path, modal, params)
    local v = root.page
    local m
    local i = 1
    while v do
      assign_persisted(v, params)
      v = v and path[i] and v.pages and v.pages[path[i]]
      if i == 1 then
        m = v and modal and v.modals and v.modals[modal]
      end
      i = i + 1
    end
    if m then
      assign_persisted(m, params)
    end
  end

  M.fill_defaults = function (path, modal, params)
    local v = root.page
    if #path < 1 then
      M.find_default(v, path, 1)
      M.assign_persisted(path, modal, params)
    else
      local last
      for i = 1, #path do
        path[i] = M.resolve_default(v, path[i])
        v = v.pages and v.pages[path[i]]
        if not v then
          M.find_default(v, path, i)
          M.assign_persisted(path, modal, params)
          return
        else
          last = v
        end
      end
      M.find_default(last, path, #path + 1)
      M.assign_persisted(path, modal, params)
    end
  end

  M.transition = function (dir, init, explicit)

    util.after_frame(function ()

      local page = M.get_page(root.page.pages, state.path[1], "(main)")

      if M.maybe_redirect(root, page, init, explicit) then
        return
      end

      if not root.main or page ~= root.main.page then
        local last_view = root.main
        root.main = M.init_view(state.path[1], page)
        M.enter(root.main, dir, last_view, init, explicit)
        if last_view then
          M.exit(last_view, dir, root.main)
        end
      else
        root.events.emit("update")
        if state.path[2] then
          M.switch(root.main, state.path[2], dir, init, explicit)
        end
      end

      M.modal(root.main, state.modal, dir, init, explicit)

    end)

  end

  M.toggle_nav_state = function (open, animate, restyle)
    if not (root and root.main) then
      return
    end
    if size == "lg" or size == "md" then
      open = true
    end
    if open == true then
      root.main.el.classList:add("tk-showing-nav")
    elseif open == false then
      root.main.el.classList:remove("tk-showing-nav")
    else
      root.main.el.classList:toggle("tk-showing-nav")
    end
    if root.main.el.classList:contains("tk-showing-nav") then
      root.main.nav_slide = 0
      root.main.nav_offset = root.main.header_offset
      root.main.nav_overlay_opacity = (size == "lg" or size == "md")
        and 0 or 1
      M.style_header_hide(root.main, false, restyle)
    else
      root.main.nav_slide = -opts.nav_width
      root.main.nav_overlay_opacity = 0
    end
    if restyle ~= false then
      M.style_nav(root.main, animate ~= false)
    end
  end

  M.on_resize = function ()
    if not root then
      return
    end
    vw = math.max(document.documentElement.clientWidth or 0, window.innerWidth or 0)
    vh = math.max(document.documentElement.clientHeight or 0, window.innerHeight or 0)
    local newsize =
      (vw > opts.lg_threshold and "lg") or
      (vw > opts.md_threshold and "md") or "sm"
    if size then
      root.el.classList:remove("tk-" .. size)
    end
    local oldsize = size
    size = newsize
    root.el.classList:add("tk-" .. newsize)
    if root.main then
      if newsize == "lg" or newsize == "md" then
        M.toggle_nav_state(true)
      elseif oldsize == "lg" or oldsize == "md" then
        M.toggle_nav_state(false)
      end
      M.style_banners(root, true)
      M.style_snacks(root.main, true)
      M.style_header(root.main, true)
      M.style_header_links(root.main, true)
      M.style_nav(root.main, true)
      if root.main and root.main.main then
        M.style_main_header_switch(root.main.main, true)
        M.style_main_switch(root.main.main, true)
      else
        M.style_main(root.main, true)
      end
      if root.main and root.main.active_modal then
        M.style_modal(root.main.active_modal, true)
      end
    end
  end

  M.setup_main = function ()

    root = M.init_view(nil, opts.main)
    root.el, root.e = util.clone(opts.main.template)
    root.e_main = root.el:querySelector("section > main")
    M.setup_banners(root)
    M.setup_dynamic(root)

    if root.page.init then
      root.page.init(root)
    end

    e_container:append(root.el)

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
            root.events.emit("update-worker")
            if opts.verbose then
              print("Updated service worker installed")
            end
          elseif reg.active then
            if installing then
              installing = false
              root.events.emit("update-worker")
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

  M.get_url = function (s, params)
    s = s or state
    return base_path .. "#" .. util.encode_path(s, params, opts.modal_separator)
  end

  M.get_modal_spec = function (...)
    if type(...) == "string" then
      local name, params = ...
      return {
        path = state.path,
        modal = name,
        params = params
      }
    else
      local spec = ...
      return {
        path = state.path,
        modal = spec.modal,
        params = spec.params,
        event = spec.event,
      }
    end
  end

  M.get_route_spec = function (...)
    if type(...) == "table" then
      local t = ...
      if #t > 0 then
        for i = 1, #t do
          local n = t[i]
          if n and #n > 0 then
            t[i] = M.get_route_spec(arr.spread(n))
          else
            t[i] = M.get_route_spec(n)
          end
        end
        return t
      end
      local spec = ...
      spec.path = spec.path or {}
      spec.params = spec.params or {}
      M.fill_defaults(spec.path, spec.modal, spec.params)
      return spec
    elseif type(...) == "string" then
      local spec = {}
      local args = { ... }
      if #args == 0 then
        spec.path = {}
        spec.params = {}
        M.fill_defaults(spec.path, spec.modal, spec.params)
        return spec
      else
        if type(args[#args]) == "table" then
          spec.params = args[#args]
          spec.path = args
          spec.path[#spec.path] = nil
        else
          spec.params = {}
          spec.path = args
        end
        M.fill_defaults(spec.path, spec.modal, spec.params)
        return spec
      end
    else
      err.error("Unexpected route spec", varg.map(type, ...))
    end
  end

  M.set_route = function (policy, ...)
    local spec = M.get_route_spec(...)
    if #spec > 0 then
      for i = 1, #spec do
        local spec = spec[i]
        M.set_route(policy, spec)
        policy = "push"
      end
      return
    end
    state.path = spec.path
    state.params = spec.params
    state.modal = spec.modal
    state.modal_event = spec.event
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

  M.forward_modal = function (...)
    M.set_route("push", M.get_modal_spec(...))
    M.transition("forward")
  end

  M.backward_modal = function (...)
    M.set_route("push", M.get_modal_spec(...))
    M.transition("forward")
  end

  M.replace_forward_modal = function (...)
    M.set_route("replace", M.get_modal_spec(...))
    M.transition("forward")
  end

  M.replace_backward_modal = function (...)
    M.set_route("replace", M.get_modal_spec(...))
    M.transition("backward")
  end

  M.set_default_route = function ()
    M.fill_defaults(state.path, state.modal, state.params)
    M.set_route("replace", state)
    M.mark("initial")
  end

  M.decode_param = function (v)
    return json.decode(str.from_base64_url(v))
  end

  M.encode_param = function (v)
    return str.to_base64_url(json.encode(v))
  end

  M.get_param = function (p, decode)
    local v = state.params[p]
    if decode then
      local ok, d = pcall(function ()
        return M.decode_param(v)
      end)
      return ok and d or nil
    else
      return v
    end
  end

  M.set_param = function (p, v, encode)
    if v == nil then
      state.params[p] = nil
    elseif not encode then
      state.params[p] = v
    else
      local v0 = M.encode_param(v)
      state.params[p] = v0
    end
    return v
  end

  M.data = function (...)
    local n = varg.len(...)
    if n < 1 then
      return
    elseif n == 1 then
      return M.get_param(..., true)
    else
      local k, v = ...
      if v == nil then
        return M.set_param(k, nil)
      elseif type(v) ~= "function" then
        return M.set_param(k, v, true)
      else
        return M.set_param(k, v(M.get_param(k, true)), true)
      end
    end
  end

  M.replace = function ()
    M.set_route("replace", state)
  end

  window:addEventListener("popstate", function (_, ev)
    local state0 = util.parse_path(str.match(location.hash, "^#(.*)"), nil, nil, opts.modal_separator)
    local id = ev.state and ev.state.id and tonumber(ev.state.id)
    local dir = state.popdir or (id and state.current_id and id < state.current_id) and "backward" or "forward"
    if state.popmark then
      local p = state.popmark
      state.popmark = nil
      state.popdir = nil
      M.set_route("replace", p)
    else
      M.set_route("replace", state0)
    end
    M.transition(dir)
  end)

  window:addEventListener("resize", function ()
    M.on_resize()
  end)

  history.scrollRestoration = "manual"
  M.setup_main()
  M.on_resize()
  M.set_default_route()
  M.transition("forward", true, true)

end
