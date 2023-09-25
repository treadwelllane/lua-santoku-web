# Now

- Correctly propagate lua errors

- Basic README
- Documentation

# Next

- Better error messages
- Lua coverage

- Support Object.keys, Object.values,
  Object.entries, pairs, ipairs

- Fix x:val(false/true) and x:lua(false/true)

- Date and other object gt, lt, etc. comparisons
- Wrapped object equality checks

- Even though sanitizer reports no leaks, ensure
  that IDX_VAL_REF and IDX_TBL_VAL are correctly
  getting pruned as objects are garbage
  collected. Is there a garbage analyzer for the
  JS (non-wasm) side of things?

# Eventually

- Is it possible to implement implicit-this
  without causing confusion?

- Implement c++ coverage and linting
