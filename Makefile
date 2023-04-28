NAME = santoku-web
VERSION = 0.0.15-1
GIT_URL = git@github.com:broma0/lua-santoku-web.git
HOMEPAGE = https://github.com/broma0/lua-santoku-web
LICENSE = MIT

LIBFLAG = -shared

BUILD = build
CONFIG = config

ROCKSPEC = $(NAME)-$(VERSION).rockspec
ROCKSPEC_T = config/template.rockspec

shared: $(BUILD)/santoku/web/window.so

install:
	luarocks make $(BUILD)/$(ROCKSPEC)

luarocks-build: shared

luarocks-install: shared
	test -n "$(INST_LIBDIR)"
	mkdir -p $(INST_LIBDIR)/santoku/web/
	cp $(BUILD)/santoku/web/window.so $(INST_LIBDIR)/santoku/web/

upload: $(BUILD)/$(ROCKSPEC)
	@if test -z "$(LUAROCKS_API_KEY)"; then echo "Missing LUAROCKS_API_KEY variable"; exit 1; fi
	@if ! git diff --quiet; then echo "Commit your changes first"; exit 1; fi
	git tag "$(VERSION)"
	git push --tags 
	cd "$(BUILD)" && luarocks upload --api-key "$(LUAROCKS_API_KEY)" "$(ROCKSPEC)"

clean:
	rm -rf $(BUILD)

$(BUILD)/santoku/web/window.so: src/santoku/web/window.cpp $(ROCKSPEC_OUT) $(BUILD)/$(ROCKSPEC)
	mkdir -p "$(dir $@)"
	luarocks make --deps-only $(BUILD)/$(ROCKSPEC)
	$(CC) $(CFLAGS) $(LDFLAGS) src/santoku/web/window.cpp $(LIBFLAG) -o "$@"

$(BUILD)/$(ROCKSPEC): $(ROCKSPEC_T)
	NAME="$(NAME)" VERSION="$(VERSION)" \
	HOMEPAGE="$(HOMEPAGE)" LICENSE="$(LICENSE)" \
	GIT_URL="$(GIT_URL)" \
		toku template \
			-f "$(ROCKSPEC_T)" \
			-o "$(BUILD)/$(ROCKSPEC)"

.PHONY: clean install upload shared
