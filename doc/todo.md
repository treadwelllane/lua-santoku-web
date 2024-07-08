# Now

- Do we need to call stringToNewUTF8 in the proxied get() method? Can we just
  pass the string val ref into Module.get?

- Figure out how to test that EPHEMERON_IDX is empty (or as empty as it should
  be) after running garbage collection.
- Use prefixes for method names
- Basic README
- Documentation

# Next

- Link buttons, dropdown, typeahead single/multi select
- Generalized banner
- Modals (with workflow)
- Snacks (minimize, maximize)
- Footer with tray extend
- Header with tray extend
- Pull to refresh

- Header-fixed elements
- Restore scroll positions
- Malformed URL handling
- Asset generation

- Consider using properties instead of classes when not needed in CSS
- Refactor to slot-based navs: first "slot" is the forward/backward pager and
  is used for the pages passed into the top-level spa(...). Subsequent navs must
  specify data-type as drawer, footer, or more TBD.

- Snacks/fabs incorrectly positioned when browser toolbar hides on scroll
- Consider not automatically setting up .fab.minmax and not automatically
  rotating it based on the state (should be users responsibility)

- Consider hiding "this" argument with setfenv: a Lua function called from JS
  will have "this" in it's environment

- Better error messages
- Lua coverage

- Support Object.keys, Object.values,
  Object.entries, pairs, ipairs

- Fix x:val(false/true) and x:lua(false/true)

- Test binary and unary operators

# Eventually

- Why does throwing string errors, which in turn
  calls Module.error($0, Emval.toHandle(<str>))
  not cause a memory leak?

- Is it possible to implement implicit-this
  without causing confusion?

- Implement c++ coverage and linting
