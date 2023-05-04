# TODO

# # NOTE: this requires lua-emscripten be cloned
# # as a sibling directory
# LUA_EMSCRIPTEN = ../lua-emscripten
# LUA_VERSION = 5.4.4
# LUA_TAG = default

# ROCKSPEC := $(or $(ROCKSPEC), $(error Missing ROCKSPEC variable))
# BUILD := $(or $(BUILD), build/test)

# LUAROCKS_VARS = make --silent -C "$(LUA_EMSCRIPTEN)" VERSION="$(LUA_VERSION)" TAG="$(LUA_TAG)" all luarocks-vars 
# LUAROCKS_CFG = $(BUILD)/luarocks.config.lua
# LUAROCKS_CFG_T = config/luarocks.config.lua
# LUAROCKS = LUAROCKS_CONFIG="$(LUAROCKS_CFG)" luarocks --tree "$(BUILD)"

# test:	$(LUAROCKS_CFG)
# 	LUA_PATH="build/share/lua/5.4/?.lua" \
# 	LUA_CPATH="build/lib/lua/5.4/?.so" \
# 	$(shell $(LUAROCKS_VARS)) $(LUAROCKS) test "$(ROCKSPEC)" $(ARGS)
# 	# $(shell $(LUAROCKS_VARS)) $(LUAROCKS) test "$(ROCKSPEC)" $(ARGS)

# iterate: $(LUAROCKS_CFG)
# 	$(shell $(LUAROCKS_VARS)) $(LUAROCKS) test "$(ROCKSPEC)" iterate $(ARGS)

# $(LUAROCKS_CFG): $(LUAROCKS_CFG_T)
# 	$(shell $(LUAROCKS_VARS)) \
# 		toku template -f "$^" -o "$@"

# .PHONY: test iterate
