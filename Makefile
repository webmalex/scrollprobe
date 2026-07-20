APP_NAME := ScrollProbe
BUNDLE_ID := dev.scrollprobe.ScrollProbe
CONFIGURATION ?= release
SWIFT_BUILD_DIR := .build/$(CONFIGURATION)
DIST_DIR := dist
APP_DIR := $(DIST_DIR)/$(APP_NAME).app
ARCHIVE_PATH := $(DIST_DIR)/$(APP_NAME)-macos-arm64.zip
CONTENTS_DIR := $(APP_DIR)/Contents

.PHONY: all build test app package run install hooks clean

all: test app

build:
	xcrun swift build -c $(CONFIGURATION)

test:
	xcrun swift test

app: build
	rm -rf "$(APP_DIR)"
	mkdir -p "$(CONTENTS_DIR)/MacOS"
	cp "$(SWIFT_BUILD_DIR)/$(APP_NAME)" "$(CONTENTS_DIR)/MacOS/$(APP_NAME)"
	cp "Resources/Info.plist" "$(CONTENTS_DIR)/Info.plist"
	codesign --force --sign - --identifier "$(BUNDLE_ID)" \
		--requirements '=designated => identifier "$(BUNDLE_ID)"' "$(APP_DIR)"

package: app
	rm -f "$(ARCHIVE_PATH)"
	ditto -c -k --sequesterRsrc --keepParent "$(APP_DIR)" "$(ARCHIVE_PATH)"

run: app
	open "$(APP_DIR)"

install: app
	mkdir -p "$(HOME)/Applications"
	ditto "$(APP_DIR)" "$(HOME)/Applications/$(APP_NAME).app"

hooks:
	/opt/homebrew/bin/pre-commit install --install-hooks

clean:
	swift package clean
	rm -rf "$(DIST_DIR)"
