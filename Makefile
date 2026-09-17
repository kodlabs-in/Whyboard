.PHONY: build check format lint test

PROJECT := Whyboard.xcodeproj
SCHEME := Whyboard
DERIVED_DATA_PATH ?= $(CURDIR)/.build/DerivedData
DEVICE_ID ?=
SIMULATOR_ID ?= $(shell xcrun simctl list devices available | sed -nE '/iPad/ { s/.*\(([0-9A-F-]+)\).*/\1/p; q; }')

ifeq ($(strip $(DEVICE_ID)),)
TEST_PLATFORM := iOS Simulator
TEST_DEVICE_ID = $(SIMULATOR_ID)
TEST_SIGNING_ARGUMENT := CODE_SIGNING_ALLOWED=NO
else
TEST_PLATFORM := iOS
TEST_DEVICE_ID := $(DEVICE_ID)
TEST_SIGNING_ARGUMENT :=
endif

check: lint build test

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
	@test -n "$(TEST_DEVICE_ID)" || (echo "No available iPad simulator found"; exit 1)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination "platform=$(TEST_PLATFORM),id=$(TEST_DEVICE_ID)" \
		-derivedDataPath "$(DERIVED_DATA_PATH)" $(TEST_SIGNING_ARGUMENT) test
