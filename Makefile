APP_NAME := ScrollProbe
BUNDLE_ID := io.github.webmalex.ScrollProbe
CONFIGURATION ?= release
PRE_COMMIT ?= pre-commit
SWIFT_BUILD_DIR := .build/$(CONFIGURATION)
DIST_DIR := dist
APP_DIR := $(DIST_DIR)/$(APP_NAME).app
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
ARCHIVE_PATH := $(DIST_DIR)/$(APP_NAME)-$(VERSION)-macos-arm64.zip
CHECKSUM_PATH := $(ARCHIVE_PATH).sha256
CONTENTS_DIR := $(APP_DIR)/Contents

.PHONY: all build test assemble-app app package verify-package \
	print-archive-path run install hooks lint clean

all: test app

build:
	xcrun swift build -c $(CONFIGURATION)

test:
	xcrun swift test

assemble-app: build
	rm -rf "$(APP_DIR)"
	mkdir -p "$(CONTENTS_DIR)/MacOS"
	cp "$(SWIFT_BUILD_DIR)/$(APP_NAME)" "$(CONTENTS_DIR)/MacOS/$(APP_NAME)"
	cp "Resources/Info.plist" "$(CONTENTS_DIR)/Info.plist"

app: assemble-app
	codesign --force --sign - --identifier "$(BUNDLE_ID)" \
		--requirements '=designated => identifier "$(BUNDLE_ID)"' "$(APP_DIR)"

package: app
	rm -f "$(ARCHIVE_PATH)" "$(CHECKSUM_PATH)"
	ditto -c -k --sequesterRsrc --keepParent "$(APP_DIR)" "$(ARCHIVE_PATH)"
	cd "$(DIST_DIR)" && shasum -a 256 "$(notdir $(ARCHIVE_PATH))" > \
		"$(notdir $(CHECKSUM_PATH))"

verify-package: package
	codesign --verify --deep --strict --verbose=2 "$(APP_DIR)"
	@test "$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
		'$(APP_DIR)/Contents/Info.plist')" = "$(BUNDLE_ID)"
	cd "$(DIST_DIR)" && shasum -a 256 -c "$(notdir $(CHECKSUM_PATH))"

print-archive-path:
	@echo "$(ARCHIVE_PATH)"

run: app
	open "$(APP_DIR)"

install: app
	mkdir -p "$(HOME)/Applications"
	ditto "$(APP_DIR)" "$(HOME)/Applications/$(APP_NAME).app"

hooks:
	$(PRE_COMMIT) install --install-hooks

lint:
	$(PRE_COMMIT) run --all-files

clean:
	xcrun swift package clean
	rm -rf "$(DIST_DIR)"
