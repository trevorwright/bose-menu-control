.PHONY: build app run dev test clean

# Swift Testing ships with the command-line tools but is not on the default search paths.
CLT_DEV := /Library/Developer/CommandLineTools/Library/Developer
TEST_FLAGS := -Xswiftc -F -Xswiftc $(CLT_DEV)/Frameworks \
	-Xlinker -F -Xlinker $(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib

build:
	swift build

app:
	Scripts/build-app.sh release

run: app
	open .build/BoseMenuControl.app

dev:
	swift run BoseMenuControl

test:
	swift test $(TEST_FLAGS)

clean:
	swift package clean
	rm -rf .build/BoseMenuControl.app
