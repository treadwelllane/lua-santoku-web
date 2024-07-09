# Now

- Link buttons, dropdown, typeahead single/multi select
- Modals (with workflow)
- Restore scroll positions
- Malformed URL handling
- Asset generation

# Next

- Basic README
- Documentation

- Generalized banner
- Snacks
- Footer with tray extend
- Header with tray extend
- Pull to refresh

# Later

- Consider using properties instead of classes when not needed in CSS

- Refactor to slot-based navs: first "slot" is the forward/backward pager and
  is used for the pages passed into the top-level spa(...). Subsequent navs must
  specify data-type as drawer, footer, or more TBD.

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

- Support Object.keys, Object.values,
  Object.entries, pairs, ipairs
- Fix x:val(false/true) and x:lua(false/true)
- Test binary and unary operators
- Use prefixes for method names
