PROJECT = Veil.xcodeproj
SCHEME = Veil
# Single-arch destination for fast local builds on Apple Silicon.
# Specifying arch keeps xcodebuild from matching multiple "My Mac" entries.
DEST = platform=macOS,arch=arm64
# Generic destination for universal binary builds (no specific machine).
DEST_UNIVERSAL = generic/platform=macOS
DERIVED = .build
APP = $(DERIVED)/Build/Products/Release/Veil.app
INSTALL_DIR = /Applications
UNIVERSAL = ONLY_ACTIVE_ARCH=NO
NO_PROFILING = CLANG_ENABLE_CODE_COVERAGE=NO CLANG_COVERAGE_MAPPING=NO

XCODEBUILD = xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)'
XCODEBUILD_UNIVERSAL = xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST_UNIVERSAL)'

.PHONY: build build-universal debug test test-verbose clean install zip release lsp

build:
	$(XCODEBUILD) -configuration Release -derivedDataPath $(DERIVED) $(NO_PROFILING) -quiet
	@echo "Built: $(APP)"

build-universal:
	$(XCODEBUILD_UNIVERSAL) -configuration Release -derivedDataPath $(DERIVED) $(UNIVERSAL) $(NO_PROFILING) -quiet
	@echo "Built (universal): $(APP)"

debug:
	$(XCODEBUILD) -configuration Debug -derivedDataPath $(DERIVED) -quiet

# Apple's xcodebuild emits per-test "Test case ... passed/failed" lines but
# no aggregate summary, so we synthesize one. The "no tests ran" branch is
# a sanity check: if xcodebuild changes its prefix again (it has before),
# the count would silently drop to 0 and look like success without it.
# Assertion details aren't in the stdout log; open the .xcresult bundle in
# Xcode or use xcrun xcresulttool to inspect them.
test:
	@swift test --package-path Packages/VeilCore --quiet
	@out=$(DERIVED)/test.log; mkdir -p $(DERIVED); \
	$(XCODEBUILD) -derivedDataPath $(DERIVED) -only-testing:VeilTests CODE_SIGNING_ALLOWED=NO test -quiet > $$out 2>&1; \
	status=$$?; \
	passed=$$(grep -cE "^Test case .* passed" $$out || true); \
	failed=$$(grep -cE "^Test case .* failed" $$out || true); \
	if [ $$failed -gt 0 ]; then \
		echo "FAIL: $$failed failed, $$passed passed"; \
		grep -E "^Test case .* failed" $$out | sed -E "s/^Test case '([^']+)' failed.*/  ✖ \1/"; \
		echo "  (full log: $$out)"; \
		exit 1; \
	elif [ $$status -ne 0 ]; then \
		echo "FAIL: build or infrastructure error"; \
		grep -E "error: " $$out | head -10; \
		echo "  (full log: $$out)"; \
		exit $$status; \
	elif [ $$passed -eq 0 ]; then \
		echo "WARN: no tests ran — xcodebuild output format may have changed"; \
		echo "  (full log: $$out)"; \
		exit 1; \
	else \
		echo "PASS: $$passed tests"; \
	fi

test-verbose:
	swift test --package-path Packages/VeilCore
	$(XCODEBUILD) -derivedDataPath $(DERIVED) -only-testing:VeilTests CODE_SIGNING_ALLOWED=NO test -quiet

clean:
	$(XCODEBUILD) clean -quiet
	/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -u $(APP) 2>/dev/null || true
	rm -rf $(DERIVED) Packages/VeilCore/.build Packages/veil/.build

install: build
	rsync -a "$(APP)/" "$(INSTALL_DIR)/Veil.app/"
	@echo "Installed to $(INSTALL_DIR)/Veil.app"

zip: build-universal
	ditto -c -k --keepParent --norsrc --noextattr --noacl "$(APP)" Veil.zip
	@echo "Packaged: Veil.zip"

lsp:
	xcode-build-server config -project $(PROJECT) -scheme $(SCHEME) --build_root $(DERIVED)

# Usage: make release V=0.2
release:
ifndef V
	$(error Usage: make release V=x.y)
endif
	sed -i '' 's/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $(V)/' $(PROJECT)/project.pbxproj
	git add $(PROJECT)/project.pbxproj
	git commit -m "Release v$(V)"
	@echo "Version set to $(V) and committed. Now tag and push."
