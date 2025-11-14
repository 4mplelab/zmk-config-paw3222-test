YQ := $(shell command -v yq 2> /dev/null)
WEST := $(shell command -v west 2> /dev/null)

ifeq ($(YQ),)
  $(error "yq is not installed.")
endif
ifeq ($(WEST),)
  $(error "west is not installed.")
endif

ROOT_DIR := $(abspath $(CURDIR))
WEST_WS := $(ROOT_DIR)/_west

.PHONY: build clean

build:
	@bash scripts/build.sh

clean:
	@echo "🧹 Cleaning firmware_builds/"
	@rm -rf "$(ROOT_DIR)/firmware_builds"
	@echo "🧹🧹🧹 Cleaned!! 🧹🧹🧹"
	@echo "To reset workspace (optional): rm -rf $(WEST_WS) && make setup-west"
