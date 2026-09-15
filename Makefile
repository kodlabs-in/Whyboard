.PHONY: build check format lint test

PROJECT := Whyboard.xcodeproj
SCHEME := Whyboard
DERIVED_DATA_PATH ?= $(CURDIR)/.build/DerivedData
DEVICE_ID ?=

check: lint build

format:
	swift format --in-place --recursive --configuration .swift-format Whyboard WhyboardTests WhyboardUITests

lint:
	swift format lint --recursive --strict --configuration .swift-format Whyboard WhyboardTests WhyboardUITests
	swiftlint lint --no-cache --strict --config .swiftlint.yml

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination "generic/platform=iOS" -derivedDataPath "$(DERIVED_DATA_PATH)" \
		CODE_SIGNING_ALLOWED=NO build

test:
	@test -n "$(DEVICE_ID)" || (echo "DEVICE_ID is required; run 'xcrun devicectl list devices'"; exit 1)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination "platform=iOS,id=$(DEVICE_ID)" -derivedDataPath "$(DERIVED_DATA_PATH)" test
