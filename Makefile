NAME ?= santoku-web
VERSION ?= 0.0.19-1
GIT_URL ?= git@github.com:broma0/lua-santoku-web.git
HOMEPAGE ?= https://github.com/broma0/lua-santoku-web
LICENSE ?= MIT

BUILD_DIR ?= build/work
TEST_DIR ?= build/test
CONFIG_DIR ?= config

LOCAL_CFLAGS ?= --std=c++17 --bind
LOCAL_LDFLAGS ?=

LIBFLAG ?= -shared

ROCKSPEC ?= $(BUILD_DIR)/$(NAME)-$(VERSION).rockspec
ROCKSPEC_T ?= $(CONFIG_DIR)/template.rockspec

LUAROCKS ?= luarocks

TEST_SPEC_DIST_DIR ?= $(TEST_DIR)/spec
TEST_SPEC_SRC_DIR ?= test/spec

TEST_SPEC_SRCS ?= $(shell find $(TEST_SPEC_SRC_DIR) -type f -name '*.lua')
TEST_SPEC_DISTS ?= $(patsubst $(TEST_SPEC_SRC_DIR)/%.lua, $(TEST_SPEC_DIST_DIR)/%, $(TEST_SPEC_SRCS))

TEST_EM_VARS ?= CC="emcc" LD="emcc" AR="emar rcu" NM="emnm" RANLIB="emranlib"
TEST_CFLAGS ?= -I $(TEST_LUA_INC_DIR) --bind
TEST_LDFLAGS ?= -L $(TEST_LUA_LIB_DIR) $(LOCAL_LDFLAGS) $(LIBFLAG)
TEST_VARS ?= $(TEST_EM_VARS) LUAROCKS='$(TEST_LUAROCKS)' BUILD_DIR="$(TEST_DIR)/build" CFLAGS="$(TEST_CFLAGS)" LDFLAGS="$(TEST_LDFLAGS)" LIBFLAG="$(TEST_LIBFLAG)"
TEST_LUAROCKS_VARS ?= $(TEST_EM_VARS)	CFLAGS="$(TEST_LUAROCKS_CFLAGS)" LDFLAGS="$(TEST_LUAROCKS_LDFLAGS)" LIBFLAG="$(TEST_LUAROCKS_LIBFLAG)"
TEST_LUAROCKS_CFLAGS ?= -I $(TEST_LUA_INC_DIR) $(CFLAGS)
TEST_LUAROCKS_LDFLAGS ?= -L $(TEST_LUA_LIB_DIR) $(LDFLAGS)
TEST_LUAROCKS_LIBFLAG ?= $(LIBFLAG)
TEST_LUA_CFLAGS ?= $(CFLAGS)
TEST_LUA_LDFLAGS ?= $(LDFLAGS) -lnodefs.js -lnoderawfs.js
TEST_LUA_VARS ?= $(TEST_EM_VARS) CFLAGS="$(TEST_LUA_CFLAGS)" LDFLAGS="$(TEST_LUA_LDFLAGS)"
TEST_LUA_PATH ?= $(TEST_LUAROCKS_TREE)/share/lua/$(TEST_LUA_MINMAJ)/?.lua;$(TEST_LUAROCKS_TREE)/share/lua/$(TEST_LUA_MINMAJ)/?/init.lua
TEST_LUA_CPATH ?= $(TEST_LUAROCKS_TREE)/lib/lua/$(TEST_LUA_MINMAJ)/?.so

TEST_LUAROCKS_CFG ?= $(TEST_DIR)/luarocks.config.test.lua
TEST_LUAROCKS_CFG_T ?= $(CONFIG_DIR)/luarocks.config.test.lua
TEST_LUAROCKS_TREE ?= $(TEST_DIR)/luarocks
TEST_LUAROCKS ?= LUAROCKS_CONFIG="$(TEST_LUAROCKS_CFG)" luarocks --tree "$(TEST_LUAROCKS_TREE)"

TEST_LUA_VERSION ?= 5.4.4
TEST_LUA_MAKE ?= make $(TEST_LUA_VARS)
TEST_LUA_MAKE_LOCAL ?= make $(TEST_LUA_VARS) local
TEST_LUA_MINMAJ ?= $(shell echo $(TEST_LUA_VERSION) | grep -o ".\..")
TEST_LUA_ARCHIVE ?= lua-$(TEST_LUA_VERSION).tar.gz
TEST_LUA_DL ?= $(TEST_DIR)/$(TEST_LUA_ARCHIVE)
TEST_LUA_DIR ?= $(TEST_DIR)/lua-$(TEST_LUA_VERSION)
TEST_LUA_URL ?= https://www.lua.org/ftp/$(TEST_LUA_ARCHIVE)
TEST_LUA_DIST_DIR ?= $(TEST_LUA_DIR)/install
TEST_LUA_INC_DIR ?= $(TEST_LUA_DIST_DIR)/include
TEST_LUA_LIB_DIR ?= $(TEST_LUA_DIST_DIR)/lib
TEST_LUA_LIB ?= $(TEST_LUA_DIST_DIR)/lib/liblua.a
TEST_LUA_INTERP ?= $(TEST_LUA_DIST_DIR)/bin/lua

# ifeq ($(ENV),test)
#
# TEST_LUA = node $(PWD)/../lua-emscripten/build/dist/5.4.4/node/bin/lua
# TEST_LUA_PATH = $(PWD)/build/test/share/lua/5.4/?.lua;$(LUA_PATH)
# TEST_LUA_CPATH = $(PWD)/build/test/lib/lua/5.4/?.so;$(LUA_CPATH)
# LUA_INCDIR = $(PWD)/../lua-emscripten/build/dist/5.4.4/default/include
# LUA_LIBDIR = $(PWD)/../lua-emscripten/build/dist/5.4.4/default/lib
# CFLAGS += -I$(LUA_INCDIR) -L$(LUA_LIBDIR) -O0 -sSIDE_MODULE
# LDFLAGS += -I$(LUA_INCDIR) -L$(LUA_LIBDIR) -O0 -sSIDE_MODULE -lnodefs.js -lnoderawfs.js
# LIBFLAG = -shared -sSIDE_MODULE
#
# $(MAKECMDGOALS)::
# 	emmake make $(MAKECMDGOALS) \
# 		ENV= \
# 		BUILD="build/test" \
# 		TEST_LUA="$(TEST_LUA)" \
# 		TEST_LUA_PATH="$(TEST_LUA_PATH)" \
# 		TEST_LUA_CPATH="$(TEST_LUA_CPATH)" \
# 		LUA_INCDIR="$(LUA_INCDIR)" \
# 		LUA_LIBDIR="$(LUA_LIBDIR)" \
# 		CFLAGS="$(CFLAGS)" \
# 		LDFLAGS="$(LDFLAGS)" \
# 		LIBFLAG="$(LIBFLAG)"
#
# else

build: $(BUILD_DIR)/santoku/web/val.so $(ROCKSPEC)

install: $(ROCKSPEC)
	$(LUAROCKS) make $(ROCKSPEC)

luarocks-build: $(BUILD_DIR)/santoku/web/val.so

luarocks-install: $(INST_LUADIR)/santoku/web/js.lua $(INST_LIBDIR)/santoku/web/val.so

upload: $(ROCKSPEC)
	@if test -z "$(LUAROCKS_API_KEY)"; then echo "Missing LUAROCKS_API_KEY variable"; exit 1; fi
	@if ! git diff --quiet; then echo "Commit your changes first"; exit 1; fi
	git tag "$(VERSION)"
	git push --tags
	$(LUAROCKS) upload --api-key "$(LUAROCKS_API_KEY)" "$(ROCKSPEC)"

clean:
	rm -rf build

test: $(TEST_LUAROCKS_CFG) $(ROCKSPEC) $(TEST_LUA_DIST_DIR)
	$(TEST_VARS) $(TEST_LUAROCKS) test $(ROCKSPEC)

luarocks-test: install $(TEST_LUAROCKS_CFG) $(ROCKSPEC) $(TEST_SPEC_DISTS)
	LUA_PATH="$(TEST_LUA_PATH)" LUA_CPATH="$(TEST_LUA_CPATH)" \
		toku test -i node $(TEST_SPEC_DISTS)
	@if [ "$(TEST_ITERATE)" = "1" ]; then \
		inotifywait -qqr -e close_write -e create -e delete -e delete \
			$(SRC_DIR) $(CONFIG_DIR) $(TEST_SPEC_SRC_DIR); \
		exec make luarocks-test; \
	fi

include $(shell find $(TEST_DIR) -type f -name '*.d')

.PHONY: build install luarocks-build luarocks-install upload clean test #iterate run-test

# iterate:
# 	make ENV=test run-test ARGS+=iterate
#
# run-test: install $(LUAROCKS_CFG) $(ROCKSPEC)
# 	TEST_LUA="$(TEST_LUA)" \
# 	TEST_LUA_PATH="$(TEST_LUA_PATH)" \
# 	TEST_LUA_CPATH="$(TEST_LUA_CPATH)" \
# 		$(LUAROCKS) test $(ROCKSPEC) $(ARGS)

$(INST_LUADIR)/santoku/web/js.lua: src/santoku/web/js.lua
	@if test -z "$(INST_LUADIR)"; then echo "Missing INST_LUADIR variable"; exit 1; fi
	mkdir -p "$(dir $@)"
	cp "$^" "$@"

$(INST_LIBDIR)/santoku/web/val.so: $(BUILD_DIR)/santoku/web/val.so
	@if test -z "$(INST_LIBDIR)"; then echo "Missing INST_LIBDIR variable"; exit 1; fi
	mkdir -p $(INST_LIBDIR)/santoku/web/
	cp $(BUILD_DIR)/santoku/web/val.so $(INST_LIBDIR)/santoku/web/

$(BUILD_DIR)/santoku/web/val.so: src/santoku/web/val.cpp $(ROCKSPEC)
	mkdir -p "$(dir $@)"
	$(CC) $(CFLAGS) $(LOCAL_CFLAGS) $(LDFLAGS) $(LOCAL_LDFLAGS) $(LIBFLAG) "$<" -o "$@"

$(ROCKSPEC): $(ROCKSPEC_T)
	mkdir -p "$(dir $@)"
	NAME="$(NAME)" \
	VERSION="$(VERSION)" \
	GIT_URL="$(GIT_URL)" \
	HOMEPAGE="$(HOMEPAGE)" \
	LICENSE="$(LICENSE)" \
		toku template \
			-f "$(ROCKSPEC_T)" \
			-o "$(ROCKSPEC)"

$(TEST_LUAROCKS_CFG): $(TEST_LUAROCKS_CFG_T)
	mkdir -p "$(dir $@)"
	ROCKS_TREE="$(PWD)/$(TEST_LUAROCKS_TREE)" \
	LUA_INCDIR="$(PWD)/$(TEST_LUA_INC_DIR)" \
	LUA_LIBDIR="$(PWD)/$(TEST_LUA_LIB_DIR)" \
	$(TEST_LUAROCKS_VARS) \
		toku template \
			-f "$(TEST_LUAROCKS_CFG_T)" \
			-o "$(TEST_LUAROCKS_CFG)"

$(TEST_SPEC_DIST_DIR)/%: $(TEST_SPEC_SRC_DIR)/%.lua
	mkdir -p "$(dir $@)"
	$(TEST_VARS) toku bundle -M -f "$<" -o "$(dir $@)" \
		-e LUA_PATH "$(TEST_LUA_PATH)" \
		-e LUA_CPATH "$(TEST_LUA_CPATH)"

$(TEST_LUA_DIST_DIR): $(TEST_LUA_DL)
	rm -rf "$(TEST_LUA_DIR)"
	mkdir -p "$(dir $(TEST_LUA_DIR))"
	tar xf "$(TEST_LUA_DL)" -C "$(dir $(TEST_LUA_DIR))"
	cd "$(TEST_LUA_DIR)" && $(TEST_LUA_MAKE)
	cd "$(TEST_LUA_DIR)" && $(TEST_LUA_MAKE_LOCAL)
	cp "$(TEST_LUA_DIR)/src/"*.wasm "$(TEST_LUA_DIST_DIR)/bin/"

$(TEST_LUA_DL):
	curl -o "$(TEST_LUA_DL)" "$(TEST_LUA_URL)"

# endif
