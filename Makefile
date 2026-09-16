.PHONY: app icon clean

MACOS_DEPLOYMENT_TARGET ?= 26.0
APP_VERSION := $(strip $(shell cat VERSION))

# Compiled icon is committed: CI runners lack the Xcode that authored AppIcon.icon.
# Run `make icon` after editing the icon and commit the result.
ICON_OUT := resources/AppIcon-compiled

app:
	mkdir -p build
	xcrun clang -Wall -Wextra -Werror -O2 -g -fobjc-arc -mmacosx-version-min=$(MACOS_DEPLOYMENT_TARGET) -framework AppKit -framework CoreGraphics -framework ServiceManagement src/SmartBarHide.m -o build/SmartBarHide
	rm -rf build/SmartBarHide.app
	mkdir -p build/SmartBarHide.app/Contents/MacOS build/SmartBarHide.app/Contents/Resources
	cp $(ICON_OUT)/Assets.car $(ICON_OUT)/AppIcon.icns build/SmartBarHide.app/Contents/Resources/
	cp resources/Info.plist build/SmartBarHide.app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string $(APP_VERSION)' build/SmartBarHide.app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string $(APP_VERSION)' build/SmartBarHide.app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c 'Merge $(ICON_OUT)/AppIcon-info.plist' build/SmartBarHide.app/Contents/Info.plist
	plutil -lint build/SmartBarHide.app/Contents/Info.plist
	cp build/SmartBarHide build/SmartBarHide.app/Contents/MacOS/SmartBarHide
	codesign --force --deep --sign - build/SmartBarHide.app

icon:
	rm -rf $(ICON_OUT)
	mkdir -p $(ICON_OUT)
	xcrun actool resources/AppIcon.icon \
		--compile $(ICON_OUT) \
		--output-format human-readable-text --notices --warnings --errors \
		--output-partial-info-plist $(ICON_OUT)/AppIcon-info.plist \
		--app-icon AppIcon --include-all-app-icons \
		--enable-on-demand-resources NO --development-region en \
		--target-device mac --minimum-deployment-target $(MACOS_DEPLOYMENT_TARGET) \
		--platform macosx

clean:
	rm -rf build
