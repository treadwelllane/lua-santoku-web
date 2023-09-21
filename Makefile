NAME ?= santoku-web
VERSION ?= 0.0.56-1
GIT_URL ?= git@github.com:treadwelllane/lua-santoku-web.git
HOMEPAGE ?= https://github.com/treadwelllane/lua-santoku-web
LICENSE ?= MIT

BUILD_DIR ?= build/work
TEST_DIR ?= build/test
CONFIG_DIR ?= config
SRC_DIR ?= src

SRC_LUA ?= $(shell find $(SRC_DIR) -name '*.lua')
SRC_CPP ?= $(shell find $(SRC_DIR) -name '*.cpp')
BUILD_LUA ?= $(patsubst $(SRC_DIR)/%.lua, $(BUILD_DIR)/%.lua, $(SRC_LUA))
BUILD_CPP ?= $(patsubst $(SRC_DIR)/%.cpp, $(BUILD_DIR)/%.so, $(SRC_CPP))
INST_LUA ?= $(patsubst $(SRC_DIR)/%.lua, $(INST_LUADIR)/%.lua, $(SRC_LUA))
INST_CPP ?= $(patsubst $(SRC_DIR)/%.cpp, $(INST_LIBDIR)/%.so, $(SRC_CPP))

ASYNCIFY_FLAGS ?= -sASYNCIFY=1 -sASSERTIONS -O3 -sEXPORTED_RUNTIME_METHODS=ccall -sEXPORTED_FUNCTIONS=_main,_j_args,_j_arg,_j_call

LOCAL_CFLAGS ?= $(if $(LUA_INCDIR), -I$(LUA_INCDIR)) --std=c++17 --bind $(ASYNCIFY_FLAGS)
LOCAL_LDFLAGS ?= $(if $(LUA_LIBDIR), -L$(LUA_LIBDIR)) $(ASYNCIFY_FLAGS)

LIBFLAG ?= -shared

ROCKSPEC ?= $(BUILD_DIR)/$(NAME)-$(VERSION).rockspec
ROCKSPEC_T ?= $(CONFIG_DIR)/template.rockspec

LUAROCKS ?= luarocks

TEST_SPEC_DIST_DIR ?= $(TEST_DIR)/spec
TEST_SPEC_SRC_DIR ?= test/spec

TEST_SPEC_SRCS ?= $(shell find $(TEST_SPEC_SRC_DIR) -type f -name '*.lua')
TEST_SPEC_DISTS ?= $(patsubst $(TEST_SPEC_SRC_DIR)/%.lua, $(TEST_SPEC_DIST_DIR)/%.test, $(TEST_SPEC_SRCS))

TEST_CC ?= emcc
TEST_EM_VARS ?= CC="$(TEST_CC)" LD="$(TEST_CC)" AR="emar rcu" NM="emnm" RANLIB="emranlib"
TEST_CFLAGS ?= -I $(TEST_LUA_INC_DIR) --bind $(ASYNCIFY_FLAGS)
TEST_LDFLAGS ?= -L $(TEST_LUA_LIB_DIR) $(LOCAL_LDFLAGS) $(LIBFLAG) $(ASYNCIFY_FLAGS) -lnodefs.js -lnoderawfs.js
TEST_VARS ?= $(TEST_EM_VARS) LUAROCKS='$(TEST_LUAROCKS)' BUILD_DIR="$(TEST_DIR)/build" CFLAGS="$(TEST_CFLAGS)" LDFLAGS="$(TEST_LDFLAGS)" LIBFLAG="$(TEST_LIBFLAG)"
TEST_LUAROCKS_VARS ?= $(TEST_EM_VARS)	CFLAGS="$(TEST_LUAROCKS_CFLAGS)" LDFLAGS="$(TEST_LUAROCKS_LDFLAGS)" LIBFLAG="$(TEST_LUAROCKS_LIBFLAG)"
TEST_LUAROCKS_CFLAGS ?= -I $(TEST_LUA_INC_DIR) $(CFLAGS) $(ASYNCIFY_FLAGS)
TEST_LUAROCKS_LDFLAGS ?= -L $(TEST_LUA_LIB_DIR) $(LDFLAGS) $(ASYNCIFY_FLAGS)
TEST_LUAROCKS_LIBFLAG ?= $(LIBFLAG)
TEST_LUA_CFLAGS ?= $(CFLAGS) $(ASYNCIFY_FLAGS)
TEST_LUA_LDFLAGS ?= $(LDFLAGS) $(ASYNCIFY_FLAGS) -lnodefs.js -lnoderawfs.js
TEST_LUA_VARS ?= $(TEST_EM_VARS) CFLAGS="$(TEST_LUA_CFLAGS)" LDFLAGS="$(TEST_LUA_LDFLAGS)"
TEST_LUA_PATH ?= $(TEST_LUAROCKS_TREE)/share/lua/$(TEST_LUA_MINMAJ)/?.lua;$(TEST_LUAROCKS_TREE)/share/lua/$(TEST_LUA_MINMAJ)/?/init.lua
TEST_LUA_CPATH ?= $(TEST_LUAROCKS_TREE)/lib/lua/$(TEST_LUA_MINMAJ)/?.so

TEST_LUAROCKS_CFG ?= $(TEST_DIR)/luarocks.config.test.lua
TEST_LUAROCKS_CFG_T ?= $(CONFIG_DIR)/luarocks.config.test.lua
TEST_LUAROCKS_TREE ?= $(TEST_DIR)/luarocks
TEST_LUAROCKS ?= LUAROCKS_CONFIG="$(TEST_LUAROCKS_CFG)" luarocks --tree "$(TEST_LUAROCKS_TREE)"

TEST_LUA_VERSION ?= 5.4.4
TEST_LUA_MAKE ?= $(MAKE) $(TEST_LUA_VARS)
TEST_LUA_MAKE_LOCAL ?= $(MAKE) $(TEST_LUA_VARS) local
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

TEST_LUACHECK_CFG ?= test/luacheck.lua
TEST_LUACHECK_SRCS ?= src

TEST_LUACOV_CFG ?= $(TEST_DIR)/luacov.lua
TEST_LUACOV_CFG_T ?= test/luacov.lua
TEST_LUACOV_STATS_FILE ?= $(TEST_DIR)/luacov.stats.out
TEST_LUACOV_REPORT_FILE ?= $(TEST_DIR)/luacov.report.out
TEST_LUACOV_INCLUDE ?= src

build: $(BUILD_CPP) $(ROCKSPEC)

install: $(ROCKSPEC)
	$(LUAROCKS) make $(ROCKSPEC)

luarocks-build: $(BUILD_CPP)

luarocks-install: $(INST_LUA) $(INST_CPP)

upload: $(ROCKSPEC)
	@if test -z "$(LUAROCKS_API_KEY)"; then echo "Missing LUAROCKS_API_KEY variable"; exit 1; fi
	@if ! git diff --quiet; then echo "Commit your changes first"; exit 1; fi
	git tag "$(VERSION)"
	git push --tags
	git push
	$(LUAROCKS) upload --skip-pack --api-key "$(LUAROCKS_API_KEY)" "$(ROCKSPEC)"

clean:
	rm -rf build

test: $(TEST_LUAROCKS_CFG) $(ROCKSPEC) $(TEST_LUA_DIST_DIR)
	$(TEST_VARS) $(TEST_LUAROCKS) test $(ROCKSPEC)

iterate: $(TEST_LUAROCKS_CFG) $(ROCKSPEC) $(TEST_LUA_DIST_DIR)
	@while true; do \
		$(TEST_VARS) $(TEST_LUAROCKS) test $(ROCKSPEC); \
		inotifywait -qqr -e close_write -e create -e delete -e delete \
			Makefile $(SRC_DIR) $(CONFIG_DIR) $(TEST_SPEC_SRC_DIR); \
	done

# TODO: This should be luarocks-install, but how to we set INST_LIB/BINDIR?
luarocks-test: install $(TEST_LUAROCKS_CFG) $(ROCKSPEC) $(TEST_SPEC_DISTS) $(TEST_LUACOV_CFG)
	@if LUA_PATH="$(TEST_LUA_PATH)" LUA_CPATH="$(TEST_LUA_CPATH)" \
		toku test -s -i node $(TEST_SPEC_DISTS); \
	then \
		luacov -c "$(PWD)/$(TEST_LUACOV_CFG)"; \
		cat "$(TEST_LUACOV_REPORT_FILE)" | \
			awk '/^Summary/ { P = NR } P && NR > P + 1'; \
		echo; \
		luacheck --config "$(TEST_LUACHECK_CFG)" $(TEST_LUACHECK_SRCS) || true; \
		echo; \
	fi

luarocks-test-run:
	$(TEST_LUAROCKS) $(ARGS)

$(INST_LUADIR)/%.lua: $(SRC_DIR)/%.lua
	@if test -z "$(INST_LUADIR)"; then echo "Missing INST_LUADIR variable"; exit 1; fi
	mkdir -p "$(dir $@)"
	cp "$^" "$@"

$(INST_LIBDIR)/%.so: $(BUILD_DIR)/%.so
	@if test -z "$(INST_LIBDIR)"; then echo "Missing INST_LIBDIR variable"; exit 1; fi
	mkdir -p "$(dir $@)"
	cp "$^" "$@"

$(BUILD_DIR)/%.so: $(SRC_DIR)/%.cpp
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

$(TEST_SPEC_DIST_DIR)/%.test: $(TEST_SPEC_SRC_DIR)/%.lua
	mkdir -p "$(dir $@)"
	$(TEST_VARS) toku bundle -C -M -f "$<" -o "$(dir $@)" -O "$(notdir $@)" \
		-e LUA_PATH "$(TEST_LUA_PATH)" \
		-e LUA_CPATH "$(TEST_LUA_CPATH)" \
		-E LUACOV_CONFIG "$(PWD)/$(TEST_LUACOV_CFG)" \
		-l luacov -l luacov.hook \
		-i debug

$(TEST_LUACOV_CFG): $(TEST_LUACOV_CFG_T)
	mkdir -p "$(dir $@)"
	STATS_FILE="$(PWD)/$(TEST_LUACOV_STATS_FILE)" \
	REPORT_FILE="$(PWD)/$(TEST_LUACOV_REPORT_FILE)" \
	INCLUDE="$(TEST_LUACOV_INCLUDE)" \
	$(TEST_LUAROCKS_VARS) \
		toku template \
			-f "$(TEST_LUACOV_CFG_T)" \
			-o "$(TEST_LUACOV_CFG)"

$(TEST_LUA_DIST_DIR): $(TEST_LUA_DL)
	rm -rf "$(TEST_LUA_DIR)"
	mkdir -p "$(dir $(TEST_LUA_DIR))"
	tar xf "$(TEST_LUA_DL)" -C "$(dir $(TEST_LUA_DIR))"
	cd "$(TEST_LUA_DIR)" && $(TEST_LUA_MAKE)
	cd "$(TEST_LUA_DIR)" && $(TEST_LUA_MAKE_LOCAL)
	cp "$(TEST_LUA_DIR)/src/"*.wasm "$(TEST_LUA_DIST_DIR)/bin/"

$(TEST_LUA_DL):
	curl -o "$(TEST_LUA_DL)" "$(TEST_LUA_URL)"

echo:
	find $(TEST_DIR) -type f -name '*.d'

include $(shell find $(TEST_DIR) -type f -name '*.d')

.PHONY: echo build install luarocks-build luarocks-install upload clean test iterate luarocks-test luarocks-test-run
