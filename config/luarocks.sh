#!/usr/bin/env bash

set -e

SANDBOX="$PWD/.lua"
SRC="$SANDBOX/src"

[ ! -d "$SRC" ] && mkdir -p "$SRC"

pushd "$SRC"

# Install Lua
rm -fr "lua-5.4.4"
rm -fr "lua-5.4.4.tar.gz"
wget http://www.lua.org/ftp/lua-5.4.4.tar.gz;
tar -zxf "lua-5.4.4.tar.gz"
pushd lua-5.4.4
sed -i.orig 's@\(#define\s*LUA_ROOT\s*\)\(.*\)@\1"'"$SANDBOX"'"@' src/luaconf.h
emmake make INSTALL_TOP="$SANDBOX"
emmake make install INSTALL_TOP="$SANDBOX"
emmake make clean
popd

# Install luarocks
rm -fr luarocks-3.9.2
rm -fr luarocks-3.9.2.tar.gz
wget https://luarocks.org/releases/luarocks-3.9.2.tar.gz
tar -zxf luarocks-3.9.2.tar.gz
pushd  luarocks-3.9.2
./configure --with-lua="$SANDBOX" --prefix="$SANDBOX" --force-config 
emmake make && emmake make install && emmake make clean
popd

popd
