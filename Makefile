APP_NAME := ScrollProbe
BUNDLE_ID := io.github.webmalex.ScrollProbe
CONFIGURATION ?= release
PRE_COMMIT ?= pre-commit
SIGN_IDENTITY ?=
NOTARY_PROFILE ?= scrollprobe-notary
SWIFT_BUILD_DIR := .build/$(CONFIGURATION)
DIST_DIR := dist
APP_DIR := $(DIST_DIR)/$(APP_NAME).app
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
ARCHIVE_PATH := $(DIST_DIR)/$(APP_NAME)-$(VERSION)-macos-arm64.zip
NOTARY_UPLOAD_PATH := $(DIST_DIR)/.$(APP_NAME)-notary-upload.zip
CONTENTS_DIR := $(APP_DIR)/Contents

.PHONY: all build test assemble-app app package release-app release-package \
	verify-release run install hooks lint clean

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
	rm -f "$(ARCHIVE_PATH)"
	ditto -c -k --sequesterRsrc --keepParent "$(APP_DIR)" "$(ARCHIVE_PATH)"

release-app: assemble-app
	@test -n "$(SIGN_IDENTITY)" || (echo "SIGN_IDENTITY is required" >&2; exit 1)
	codesign --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)" \
		--identifier "$(BUNDLE_ID)" "$(APP_DIR)"
	codesign --verify --deep --strict --verbose=2 "$(APP_DIR)"

release-package: release-app
	@test -n "$(NOTARY_PROFILE)" || (echo "NOTARY_PROFILE is required" >&2; exit 1)
	rm -f "$(NOTARY_UPLOAD_PATH)" "$(ARCHIVE_PATH)"
	ditto -c -k --sequesterRsrc --keepParent "$(APP_DIR)" "$(NOTARY_UPLOAD_PATH)"
	xcrun notarytool submit "$(NOTARY_UPLOAD_PATH)" \
		--keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(APP_DIR)"
	xcrun stapler validate "$(APP_DIR)"
	spctl --assess --type execute --verbose=2 "$(APP_DIR)"
	ditto -c -k --sequesterRsrc --keepParent "$(APP_DIR)" "$(ARCHIVE_PATH)"
	rm -f "$(NOTARY_UPLOAD_PATH)"
	shasum -a 256 "$(ARCHIVE_PATH)"

verify-release:
	codesign --verify --deep --strict --verbose=2 "$(APP_DIR)"
	xcrun stapler validate "$(APP_DIR)"
	spctl --assess --type execute --verbose=2 "$(APP_DIR)"
	shasum -a 256 "$(ARCHIVE_PATH)"

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
