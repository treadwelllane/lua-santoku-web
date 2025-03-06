# Now

- same automatic styling of header/main within modals and panes
- no background scrolling with modals/overlays (did this break?)
- deprecate use of santoku.iter in favor of faster alternativs

- re-introduce fabs
- fancy snack overflow: max total snack height as config option, hide snacks
  that pass this threshold with a button that opens a modal-like interface where
  all snacks are visible and scrollable.

- consider: instead of margin left/top + overflow hidden, can we use overflow: clip?
- consider: use the tk-spacer div to match heights during transition?

- consider replacing map_data, and map_el with events.on("data", ..., true) or
  similar
- remove styling code related to a page without a switch (style_main(...)?)

- specify switch/dropdown via tk-switch and tk-dropdown attributes

- replace element tags with tk-section, tk-main, tk-header, etc. using custom
  elements?
    - tk-dropdown?
    - tk-switch?
    - tk-card?
    - tk-table?

- tk-inherit=".template-selector", to replace element tag and attributes with
  template
    - add tk-inherit-attrs (default) to inherit all attrs
    - add tk-inherit-class (or other attr) to inherit specific attrs
    - add tk-inherit-class+ (or orther attr, maybe not +) to append inherited
      attributes to existing

- Provide explicit funtions for val::u8string, val::string, etc. Currently,
  LUA_TSTRING is converted via val::u8string. Will this cause problems?

- Spa dynamic snack height based on content
- Spa prevent tab select of hidden buttons/etc (or make them visible when
  focused)
- Fix ugly scrollbars in desktop chrome browsers

- Dynamically add height to account for snacks
- Use a different property than tk-show/hide for banner/snack class-based
  show/hide

- Standardized mechanism for client/server API agreement (require reload)
- Smooth append helper (insert hidden, translate following elements back, unide
  inserted, translate following elements forward)

- Sort out button links: (replace with <a>? remove tk-page? use tk-page broadly?)
- Icons in buttons
- Asset generation

- Allow state preservation on back

- Generalized panes
  - Replace transition/switch/alt with "routed" panes
  - Panes can be based on path segments or query params

- Bugs
  - Redirect back to same view seems to cause error. Is init skipped here?
  - Overlay flash on small screen back from open nav
  - dvw causing vert scrollbar to trigger horiz scrollbar
  - On mobile, button tap while focused on input causes the keyboard to appear.
    It should deselect input instead. Likely due to stopPropagation or
    preventDefault

# Next

- Basic README
- Documentation

# Later

- Allow dynamic pane injection (instead of specificying pane by string, like
    - Instead of: view.pane("somepane", "somecomponent", ..args),
    - ..allow: view.pane("somepane", somecomponent, ...args)

- Standardize interpolation of arbitrary attributes and special attributes.
    - Allow dot syntax in str.interp

- Dark theme
- Typeahead single/multi select
- Footer for main and switch
- Right nav
- Navs as rails

- Smarter snack/fab/banner tk-show/hide functionality, similar to
  tk-show/hide for cloning templates

- Dynamically add snacks/fabs/banners: can be added from any view, but injected
  into active_view (for banners) and active_view.active_view for fabs/snacks.
  When the view the snack/fab/banner was added from is removed, the item is
  also removed

- Scrollable/expandable snack, fab, banner UX when too many added

- When manually changing the hash results in a redirect, we get an extra history
  entry for the previous state. This should be cleared.
- Avoid .right and .top (header buttons after h1 imply right, fabs before main
  imply top)
- Specify active page/switch via classes
- Expandable footers and headers (swipe-open, scrollable, all header levels)
  levels, overlay on short height, push on long height (maybe?))
- Nav as header tabs or footer tabs, supporting stacked header/footer
- Second nav on right side
- Pull to refresh
- Restore scroll positions
- Minimize/maximize snacks dialog
- Add extra bottom padding when snacks and fabs are shown
- Desktop site issues: zoom changes on page switch, scales tiny with small
  windows, etc
- tk-show/hide for headers, nav, etc. Use for maximize

- Better error messages
- Lua coverage

# Eventually

- Consider allowing multiple sub-views in different <main>s
    - Should they be all reflected in the URL? or just the "main" <main>?

- Consider moving strictly to classes instead of setting style attributes

- Do we need to call stringToNewUTF8 in the proxied get() method? Can we just
  pass the string val ref into Module.get?

- Figure out how to test that EPHEMERON_IDX is empty (or as empty as it should
  be) after running garbage collection.

- Consider hiding "this" argument with setfenv: a Lua function called from JS
  will have "this" in it's environment

- Why does throwing string errors, which in turn
  calls Module.error($0, Emval.toHandle(<str>))
  not cause a memory leak?

- Is it possible to implement implicit-this
  without causing confusion?

- Implement c++ coverage and linting

# Review (are these still issues?)

- Consider moving to slot-based navs: first "slot" is the forward/backward pager
  and is used for the pages passed into the top-level spa(...). Subsequent navs
  must specify tk-type as drawer, footer, or more TBD. This allows drawer

- Support Object.keys, Object.values,
  Object.entries, pairs, ipairs
- Fix x:val(false/true) and x:lua(false/true)
- Test binary and unary operators
- Use prefixes for method names
