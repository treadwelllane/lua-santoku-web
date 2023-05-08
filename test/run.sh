#!/bin/sh

cd "$(dirname "$0")"

run()
{
  TOKU_LUA="../build/test/lib/luarocks/rocks-5.4/santoku-cli/0.0.22-1/bin/toku"
  # COV_LUA="../build/test/lib/luarocks/rocks-5.4/luacov/0.15.0-1/bin/luacov"
  # CHECK_LUA="../build/test/lib/luarocks/rocks-5.4/luacheck/1.1.0-1/bin/luacheck"

  test -z "$TEST_LUA" && echo "Missing TEST_LUA variable" && exit 1
  export LUA_PATH="$TEST_LUA_PATH"
  export LUA_CPATH="$TEST_LUA_CPATH"
  # if $TEST_LUA \
  #   -e "package.path='$LUA_PATH';package.cpath='$LUA_CPATH';" \
  #     -lluacov $TOKU_LUA test spec
  if $TEST_LUA \
    -e "package.path='$LUA_PATH';package.cpath='$LUA_CPATH';" \
      $TOKU_LUA test spec
  then
    echo
    # ../build/test/bin/luacov -c luacov.lua
    ../build/test/bin/luacheck --config luacheck.lua ../src
    # cat luacov.report.out | \
    #   awk '/^Summary/ { P = NR } P && NR > P + 1' | \
    #   awk "{ print }"
  fi
}

iterate()
{
  while true; do
    run "$@"
    inotifywait -qqr ../src spec *.lua run.sh \
      -e modify \
      -e close_write
  done
}

[ -z "$1" ] && set run

"$@"
