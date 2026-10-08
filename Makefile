PROJECT  := Tuck.xcodeproj
SCHEME   := Tuck
DERIVED  := build/DerivedData
DEST     := 'platform=macOS'
XCB      := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination $(DEST) -derivedDataPath $(DERIVED)

.PHONY: gen build test run install clean

gen:
	xcodegen generate

build: gen
	$(XCB) -configuration Debug build

test: gen
	$(XCB) test

run: build
	-pkill -x Tuck
	open $(DERIVED)/Build/Products/Debug/Tuck.app

install: gen
	$(XCB) -configuration Release build
	-pkill -x Tuck
	rm -rf /Applications/Tuck.app
	cp -R $(DERIVED)/Build/Products/Release/Tuck.app /Applications/Tuck.app
	open /Applications/Tuck.app

clean:
	rm -rf build $(PROJECT)
