PREFIX ?= /usr/local
BIN := $(PREFIX)/bin/peek
RELEASE := .build/release/peek

.PHONY: all build install uninstall wire unwire doctor clean

all: build

build:
	swift build -c release

$(RELEASE): build

install: $(RELEASE)
	@install -d $(PREFIX)/bin
	install -m 0755 $(RELEASE) $(BIN)
	@echo "Installed peek -> $(BIN)"
	@echo "Run 'peek install' to wire it into Claude Code / Desktop."

uninstall:
	@rm -f $(BIN) && echo "Removed $(BIN)" || true
	@command -v peek >/dev/null 2>&1 && peek install --uninstall || true

wire: $(RELEASE)
	$(RELEASE) install

unwire: $(RELEASE)
	$(RELEASE) install --uninstall

doctor: $(RELEASE)
	$(RELEASE) doctor

clean:
	swift package clean
	rm -rf .build
