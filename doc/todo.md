# Now

- Use either static or prefixes to hide methods
- Basic README
- Documentation

# Next

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
