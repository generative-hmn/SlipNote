.PHONY: setup generate build run clean

# Setup: Install dependencies and generate project
setup:
	@echo "Checking for XcodeGen..."
	@which xcodegen > /dev/null || (echo "Installing XcodeGen..." && brew install xcodegen)
	@echo "Generating Xcode project..."
	@xcodegen generate
	@echo "Done! Open SlipNote.xcodeproj"

# Generate Xcode project from project.yml
generate:
	xcodegen generate

# Build the project
build:
	xcodebuild -project SlipNote.xcodeproj -scheme SlipNote -configuration Debug build

# Run the app
run: build
	open ./build/Debug/SlipNote.app

# Clean build artifacts
clean:
	rm -rf build
	rm -rf DerivedData
	rm -rf SlipNote.xcodeproj

# Open in Xcode
open:
	open SlipNote.xcodeproj
