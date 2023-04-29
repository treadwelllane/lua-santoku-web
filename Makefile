NAME = santoku-web
VERSION = 0.0.17-1
GIT_URL = git@github.com:broma0/lua-santoku-web.git
HOMEPAGE = https://github.com/broma0/lua-santoku-web
LICENSE = MIT

LIBFLAG = -shared

BUILD = build
CONFIG = config

ROCKSPEC = $(NAME)-$(VERSION).rockspec
ROCKSPEC_T = config/template.rockspec

build: $(BUILD)/santoku/web/window.so

install: $(BUILD)/$(ROCKSPEC)
	luarocks make $(ARGS) $(BUILD)/$(ROCKSPEC)

luarocks-install: $(INST_LIBDIR)/santoku/web/window.so

upload: $(BUILD)/$(ROCKSPEC)
	@if test -z "$(LUAROCKS_API_KEY)"; then echo "Missing LUAROCKS_API_KEY variable"; exit 1; fi
	@if ! git diff --quiet; then echo "Commit your changes first"; exit 1; fi
	git tag "$(VERSION)"
	git push --tags 
	cd "$(BUILD)" && luarocks upload --api-key "$(LUAROCKS_API_KEY)" "$(ROCKSPEC)"

clean:
	rm -rf $(BUILD)

$(INST_LIBDIR)/santoku/web/window.so: $(BUILD)/santoku/web/window.so
	@if test -z "$(INST_LIBDIR)"; then echo "Missing INST_LIBDIR variable"; exit 1; fi
	mkdir -p $(INST_LIBDIR)/santoku/web/
	cp $(BUILD)/santoku/web/window.so $(INST_LIBDIR)/santoku/web/

$(BUILD)/santoku/web/window.so: src/santoku/web/window.cpp $(BUILD)/$(ROCKSPEC)
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

.PHONY: build install luarocks-install upload shared clean
