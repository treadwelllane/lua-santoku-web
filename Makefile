install: shared

shared: build/santoku/web/window.so

build/santoku/web/window.so: src/santoku/web/window.cpp
	mkdir -p "$(dir $@)"
	$(CC) $(CFLAGS) $(LDFLAGS) "$^" -o "$@"

clean:
	rm -rf build

.PHONY: clean install shared
