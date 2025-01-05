return {

  spa = {
    index_js = "/index.js",
    theme_color = "#f3f4f6",
    background_color = "#f3f4f6",
    header_height = "64",
    header_bg = "#1f2937",
    header_fg = "#ffffff",
    header_border = "1px solid #f3f4f6",
    nav_bg = "#ffffff",
    nav_active_bg = "#e5e7eb",
    nav_border = "1px solid #f3f4f6",
    page_bg = "#ffffff",
    ripple_bg = "#ffffff",
    nav_ripple_bg = "#e5e7eb",
    nav_focus_bg = "#f3f4f6",
    banner_height = "32",
    banner_bg = "#374151",
    banner_fg = "#ffffff",
    fab_bg = "#374151",
    fab_fg = "#ffffff",
    fab_width_large = "56",
    fab_width_small = "40",
    fab_radius_large = "16",
    fab_radius_small = "12",
    fab_scale = "0.85",
    fab_shared_svg_transition_height = "24",
    fab_shadow = "0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1)",
    fab_shadow_transparent = "0 4px 6px -1px rgb(0 0 0 / 0), 0 2px 4px -2px rgb(0 0 0 / 0)",
    snack_height = "40",
    snack_radius = "6",
    snack_bg = "#1f2937df",
    snack_fg = "#ffffff",
    snack_shadow = "0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1)",
    nav_width = "270",
    nav_pull_gutter = "32",
    nav_pull_threshold = "32",
    banner_index = "110",
    header_index = "100",
    nav_index = "90",
    nav_overlay_index = "80",
    main_header_index = "70",
    fab_index = "60",
    snack_index = "50",
    main_index = "40",
    padding = "16",
    transition_time = "250",
    transition_time_main = "250",
    transition_time_wave = "500",
    easing = "cubic-bezier(0.4, 0, 0.2, 1)",
    header_hide_minimum = "128",
    header_hide_threshold = "128",
    transition_forward_height = "32",
    service_worker_poll_time_ms = 1000 * 60 * 5, -- 5 minutes
  },

  sw = {
    cache_fetch_retry_backoff_ms = "1000",
    cache_fetch_retry_backoff_multiply = "2",
    cache_fetch_retry_times = "3",
  },

  wrap_events = {
    event_buffer_max = "100",
  },

  manifest = {
    start_url = "/",
    scope = "/",
    display = "standalone",
    handle_links = "not-preferred",
    launch_handler = { route_to = "existing-client-retain" },
  }

}
