# Now

- Remove support for < 5.4
- Remove unneeded fns like undefined, null,
  object, array, etc.

- Ensure that all MTVs return MTVs, and all MTO,
  MTF, MTP return wrapped

- Fix memory leaks

- Correctly propagate lua errors

- Date and other object gt, lt, etc. comparisons
- Wrapped object equality checks

- Fix x:val(false/true) and x:lua(false/true)

- Basic README
- Documentation

# Next

- Better error messages
- Run tests with sanitizers
- Ensure no memory leaks
- Coverage
- Linting

- Support Object.keys, Object.values,
  Object.entries, pairs, ipairs

# Eventually

- Is it possible to implement implicit-this
  without causing confusion?

- Implement c++ coverage and linting

- Figure out trace onerror and fetch events,
  currently they don't work because they're
  registered asynchronously instead of on
  initial script evaluation.

- Implement optional support for Asyncify which
- Figure out how to implement :await() without a
  callback. Asyncify will work, but is there a
  way to do without it?
    - Require :await() calls to be inside a
      wrapping coroutine
    - Get a reference to the main coroutine
    - Register a .then callback that resumes the
      main coroutine
    - yield to a dummy coroutine that calls exit(0)
    - C++20 coroutines?
