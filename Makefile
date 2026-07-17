APP_NAME := ScrollProbe
BUNDLE_ID := dev.scrollprobe.ScrollProbe
CONFIGURATION ?= release
SWIFT_BUILD_DIR := .build/$(CONFIGURATION)
DIST_DIR := dist
APP_DIR := $(DIST_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents

.PHONY: all build test app run install clean

all: test app

build:
	swift build -c $(CONFIGURATION)

test:
	swift test

app: build
	rm -rf "$(APP_DIR)"
	mkdir -p "$(CONTENTS_DIR)/MacOS"
	cp "$(SWIFT_BUILD_DIR)/$(APP_NAME)" "$(CONTENTS_DIR)/MacOS/$(APP_NAME)"
	cp "Resources/Info.plist" "$(CONTENTS_DIR)/Info.plist"
	codesign --force --sign - --identifier "$(BUNDLE_ID)" "$(APP_DIR)"

run: app
	open "$(APP_DIR)"

install: app
	mkdir -p "$(HOME)/Applications"
	ditto "$(APP_DIR)" "$(HOME)/Applications/$(APP_NAME).app"

clean:
	swift package clean
	rm -rf "$(DIST_DIR)"
