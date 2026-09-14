.PHONY: app clean
app:
	rm -rf build && mkdir -p build
	xcrun clang -Wall -Wextra -Werror -O2 -g -fobjc-arc -framework AppKit -framework CoreGraphics -framework ServiceManagement src/SmartBarHide.m -o build/SmartBarHide
	mkdir -p build/SmartBarHide.app/Contents/MacOS
	cp resources/Info.plist build/SmartBarHide.app/Contents/Info.plist
	cp build/SmartBarHide build/SmartBarHide.app/Contents/MacOS/SmartBarHide
	codesign --force --deep --sign - build/SmartBarHide.app

clean:
	rm -rf build
