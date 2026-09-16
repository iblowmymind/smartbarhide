.PHONY: app clean

MACOS_DEPLOYMENT_TARGET ?= 26.0
APP_VERSION := $(strip $(shell cat VERSION))

app:
	mkdir -p build
	xcrun clang -Wall -Wextra -Werror -O2 -g -fobjc-arc -mmacosx-version-min=$(MACOS_DEPLOYMENT_TARGET) -framework AppKit -framework CoreGraphics -framework ServiceManagement src/SmartBarHide.m -o build/SmartBarHide
	rm -rf build/SmartBarHide.app
	mkdir -p build/SmartBarHide.app/Contents/MacOS build/SmartBarHide.app/Contents/Resources
	xcrun actool resources/AppIcon.icon \
		--compile build/SmartBarHide.app/Contents/Resources \
		--output-format human-readable-text --notices --warnings --errors \
		--output-partial-info-plist build/AppIcon-info.plist \
		--app-icon AppIcon --include-all-app-icons \
		--enable-on-demand-resources NO --development-region en \
		--target-device mac --minimum-deployment-target $(MACOS_DEPLOYMENT_TARGET) \
		--platform macosx
	cp resources/Info.plist build/SmartBarHide.app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string $(APP_VERSION)' build/SmartBarHide.app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string $(APP_VERSION)' build/SmartBarHide.app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c 'Merge build/AppIcon-info.plist' build/SmartBarHide.app/Contents/Info.plist
	plutil -lint build/SmartBarHide.app/Contents/Info.plist
	cp build/SmartBarHide build/SmartBarHide.app/Contents/MacOS/SmartBarHide
	codesign --force --deep --sign - build/SmartBarHide.app

clean:
	rm -rf build
