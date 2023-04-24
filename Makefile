install: shared
	mkdir -p $(INST_LIBDIR)/santoku/web/
	cp build/santoku/web/window.so $(INST_LIBDIR)/santoku/web/

shared: build/santoku/web/window.so

build/santoku/web/window.so: src/santoku/web/window.cpp
	mkdir -p "$(dir $@)"
	$(CC) $(CFLAGS) $(LDFLAGS) "$^" $(LIBFLAG) -o "$@"

clean:
	rm -rf build

.PHONY: clean install shared
