# Now

- Dark theme
- Footer for main and switch
- Link buttons
- Dropdown
- Typeahead single/multi select
- Typeahead date picker
- Typeahead time picker
- Banners (using show/hide similar to snacks/fabs, user-provided update-worker)
- Modals (as above)
- Malformed URL handling
- Asset generation

# Next

- Basic README
- Documentation

# Later

- Consider using properties instead of classes when not needed in CSS

- Generalized banners (like snacks, modals, fabs, etc.)
- Dynamically add snacks/fabs/modals, banners
- Expandable footers and headers
- Nav as header tabs or footer tabs, supporting stacked header/footer
- Pull to refresh
- Restore scroll positions

- Better error messages
- Lua coverage

# Eventually

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
