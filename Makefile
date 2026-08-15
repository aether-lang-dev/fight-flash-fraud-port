AE ?= ae

BUILD_DIR = build
SRC_DIR = src

TARGETS = $(BUILD_DIR)/f3
APP_TARGET = $(BUILD_DIR)/fight_flash_fraud

PREFIX = /usr/local
INSTALL = install

all: $(TARGETS)
app: all $(APP_TARGET)
test: test-unit test-ui

# The spec framework is `std.spec`, which ships inside the toolchain, so
# the only module dir the unit test needs is this repo's own src.
test-unit: | $(BUILD_DIR)
	AETHER_F3_CFLAGS="" AETHER_F3_LINK_FLAGS="" AETHER_LIB_DIR=$(CURDIR)/src $(AE) build tests/unit/spec_f3app.ae -o $(BUILD_DIR)/spec_f3app
	$(BUILD_DIR)/spec_f3app

test-ui: app
	scripts/test-ui.sh

install: all
	$(INSTALL) -d $(DESTDIR)$(PREFIX)/bin
	$(INSTALL) -m755 $(TARGETS) $(DESTDIR)$(PREFIX)/bin

uninstall:
	cd $(DESTDIR)$(PREFIX)/bin ; rm $(notdir $(TARGETS))

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/f3: $(SRC_DIR)/f3.ae $(SRC_DIR)/f3core/module.ae aether.toml | $(BUILD_DIR)
	AETHER_F3_CFLAGS="" AETHER_F3_LINK_FLAGS="" $(AE) build --lib $(SRC_DIR) $(SRC_DIR)/f3.ae -o $@

$(APP_TARGET): app/fight_flash_fraud.ae $(SRC_DIR)/f3app/module.ae $(SRC_DIR)/f3core/module.ae scripts/build-ui.sh | $(BUILD_DIR)
	scripts/build-ui.sh app/fight_flash_fraud.ae $@

.PHONY: app test test-unit test-ui clean uninstall

clean:
	rm -rf $(BUILD_DIR)
