# Now

- Do we need to call stringToNewUTF8 in the proxied get() method? Can we just
  pass the string val ref into Module.get?

- Figure out how to test that EPHEMERON_IDX is empty (or as empty as it should
  be) after running garbage collection.
- Use prefixes for method names
- Basic README
- Documentation

# Next

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
