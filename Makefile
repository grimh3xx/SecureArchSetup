PREFIX ?= /usr/local
LIBDIR ?= /usr/lib/secure-arch-setup

.PHONY: install uninstall test lint

install:
	install -Dm755 secure-arch-setup $(DESTDIR)$(PREFIX)/bin/secure-arch-setup
	install -Dm644 -t $(DESTDIR)$(LIBDIR) lib/*.sh

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/secure-arch-setup
	rm -rf $(DESTDIR)$(LIBDIR)

test:
	bash tests/run.sh

lint:
	shellcheck -x secure-arch-setup lib/*.sh tests/run.sh
