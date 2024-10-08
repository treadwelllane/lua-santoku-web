# Now

- Components can "claim" query parameters such that they're removed on component
  destroy

- Modals
- Dropdowns
- Sort out button links: (replace with <a>? remove data-page? use data-page broadly?)
- Icons in buttons
- Asset generation

- Allow state preservation on back

- Generalized panes
  - Replace transition/switch/alt with "routed" panes
  - Panes can be based on path segments or query params

- Bugs
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

- When manually changing the hash results in a redirect, we get an extra history
  entry for the previous state. This should be cleared.
- Avoid .right and .top (header buttons after h1 imply right, fabs before main
  imply top)
- Dynamically add snacks/fabs/modals/banners
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
- Data-show/hide for headers, nav, etc. Use for maximize

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
  must specify data-type as drawer, footer, or more TBD. This allows drawer

- Support Object.keys, Object.values,
  Object.entries, pairs, ipairs
- Fix x:val(false/true) and x:lua(false/true)
- Test binary and unary operators
- Use prefixes for method names
