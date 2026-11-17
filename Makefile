CONFIG ?= Release
# Build output. Override to build beside a running copy: make build DERIVED_DATA=build-next
DERIVED_DATA ?= build
APP := $(DERIVED_DATA)/Build/Products/$(CONFIG)/Voiced.app
PACKAGE := Packages/VoicedKit

# Settings for this machine only; the file is git-ignored. Put your signing team in it so macOS
# keeps the Accessibility grant across rebuilds:
#   echo 'TEAM = ABCDE12345' > local.mk
-include local.mk

XCODEBUILD := xcodebuild -project Voiced.xcodeproj -scheme Voiced -configuration $(CONFIG) -derivedDataPath $(DERIVED_DATA)

# The team can also be given for one build: make run TEAM=ABCDE12345
ifdef TEAM
XCODEBUILD += DEVELOPMENT_TEAM=$(TEAM) CODE_SIGN_IDENTITY="Apple Development"
endif

# Build for a different minimum macOS than the project's, for example:
#   make run MACOS=27.0
ifdef MACOS
XCODEBUILD += MACOSX_DEPLOYMENT_TARGET=$(MACOS)
endif

.PHONY: build run quit test test-live snapshots pill-captures probe menu-bar-check microphone-check dmg clean

## Build Voiced.app
build:
	$(XCODEBUILD) build
	@# macOS caches an app's icon by path and date; a new date makes Finder and the Dock look again.
	@touch $(APP)
	@echo "Built $(APP)"

## Build, quit any running Voiced, and launch the new build
run: build
	@$(MAKE) --no-print-directory quit
	open $(APP)

## Quit a running Voiced and wait until it is gone. `open` only brings an app that is already
## running to the front, so without this a rebuild would leave the old binary running.
quit:
	@if pgrep -x Voiced >/dev/null; then \
		echo "Quitting the running Voiced"; \
		pkill -x Voiced; \
		for attempt in $$(seq 1 50); do \
			pgrep -x Voiced >/dev/null || break; \
			sleep 0.1; \
		done; \
		if pgrep -x Voiced >/dev/null; then \
			echo "Voiced did not quit; not launching the new build" >&2; \
			exit 1; \
		fi; \
	fi

## Unit and integration tests for the dictation pipeline (no network, no microphone)
test:
	swift test --package-path $(PACKAGE)

## Tests against the real xAI API. With XAI_API_KEY set this runs a full transcribe-and-clean
## round trip; without it, only the checks that need no key.
test-live:
	VOICED_LIVE_TESTS=1 swift test --package-path $(PACKAGE) --filter LiveXAI

## Save PNGs of the UI to ./snapshots (Debug build). The copy that runs keeps its settings in
## memory, so the saved settings of a Voiced on this Mac are neither read nor changed, and it
## ends itself, which make reports as Error 3, if it has not finished in 15 minutes.
snapshots:
	$(MAKE) build CONFIG=Debug
	$(DERIVED_DATA)/Build/Products/Debug/Voiced.app/Contents/MacOS/Voiced -VoicedSnapshots "$(CURDIR)/snapshots"

## Photograph the real pill into ./pill-captures (Debug build): every state in the light and the
## dark appearance with how the two differ, stills, one whole dictation picture by picture, and
## the menu bar item. The pill is driven by a script; no microphone, no hotkey, no permission.
## PLATES=<folder with a plates.json> adds the same dictation over pictures of your own, such
## as the backgrounds of the film in video/. The run fails if the two appearances differ.
pill-captures:
	$(MAKE) build CONFIG=Debug
	$(DERIVED_DATA)/Build/Products/Debug/Voiced.app/Contents/MacOS/Voiced -VoicedPillCaptures "$(CURDIR)/pill-captures" $(if $(PLATES),-VoicedPillPlates "$(abspath $(PLATES))")

## Start a second, inert copy for two seconds and print where its menu bar icon ended up.
## It has no hotkey, reads no key and opens no window, so a running Voiced is not disturbed.
probe:
	$(MAKE) build CONFIG=Debug
	$(DERIVED_DATA)/Build/Products/Debug/Voiced.app/Contents/MacOS/Voiced -VoicedProbe

## Check that a menu bar icon hidden by a menu bar manager can be brought into view. Starts a
## stand-in for the manager, then a copy of Voiced that puts its icon behind the stand-in's
## divider and moves it out again. It uses Voiced's own saved icon place and puts it back, also
## when its time limit or a signal such as Ctrl-C ends it, so quit a running Voiced first.
menu-bar-check:
	$(MAKE) build CONFIG=Debug
	@mkdir -p $(DERIVED_DATA)/tools
	xcrun swiftc -O Tools/MenuBarManagerStandIn.swift -o $(DERIVED_DATA)/tools/MenuBarManagerStandIn
	@$(DERIVED_DATA)/tools/MenuBarManagerStandIn 60 & standin=$$!; \
		sleep 2; \
		$(DERIVED_DATA)/Build/Products/Debug/Voiced.app/Contents/MacOS/Voiced -VoicedMenuBarCheck; status=$$?; \
		kill $$standin 2>/dev/null; wait $$standin 2>/dev/null; \
		exit $$status

## Measure that getting the microphone ready ahead of a hold does not start it: an inert copy
## finds the input device as Voiced does at launch and after a wake or an unlock, while it watches
## whether the device is running. The copy is started with `open`, so that macOS looks the
## Microphone grant up for Voiced and not for the app that owns this shell. The copy never
## becomes an app: it makes no menu bar icon, no window and no hotkey, and writes no settings,
## so a running Voiced is not disturbed.
##
## Succeeds only when the device never ran anywhere. Otherwise `make` fails, with its own exit
## status of 2 whatever the reason, and the last line printed, `Microphone check result: N`,
## says which: 1, the copy had the device running, or made a window; 2, nothing could be checked,
## as without the grant, when no audio is touched; 3, the device ran during the check, started by
## the copy or by another app, which cannot be told apart: run it again; 4, Voiced's saved settings changed while the check
## ran; 5, the check did not finish in 20 seconds and the copy ended itself; 6, the copy ended
## without a result, because it was ended from outside or crashed. The copy writes each line as
## it goes, so after 5 or 6 the lines printed show how far it got.
##
## To try the check itself, with stand-ins and no audio: `make microphone-check STAND_IN=stuck`
## (a lookup that never returns: result 5), `STAND_IN=stuck-main` (the same, with the main queue
## held up too) or `STAND_IN=bluetooth` (an input left alone: result 2).
MICROPHONE_CHECK := $(abspath $(DERIVED_DATA))/microphone-check
SETTINGS_DOMAIN := com.ericzakariasson.Voiced
microphone-check:
	$(MAKE) build CONFIG=Debug
	@rm -f "$(MICROPHONE_CHECK)".*
	@defaults export $(SETTINGS_DOMAIN) - > "$(MICROPHONE_CHECK).settings-before" 2>/dev/null || true
	-open -n -g -W --stdout "$(MICROPHONE_CHECK).txt" --stderr /dev/null "$(abspath $(DERIVED_DATA))/Build/Products/Debug/Voiced.app" --args -VoicedMicrophoneCheck $(if $(STAND_IN),-VoicedMicrophoneCheckStandIn $(STAND_IN))
	@defaults export $(SETTINGS_DOMAIN) - > "$(MICROPHONE_CHECK).settings-after" 2>/dev/null || true
	@cat "$(MICROPHONE_CHECK).txt" 2>/dev/null || true
	@result=$$(sed -n 's/^Microphone check exit code: //p' "$(MICROPHONE_CHECK).txt" 2>/dev/null | tail -1); \
	if [ -z "$$result" ]; then \
		if [ -s "$(MICROPHONE_CHECK).txt" ]; then \
			echo "The check copy ended without a result: it was ended from outside, or crashed. The lines above are how far it got."; \
		else \
			echo "The check copy wrote nothing: it did not start, or was ended before its first line."; \
		fi; \
		result=6; \
	fi; \
	if cmp -s "$(MICROPHONE_CHECK).settings-before" "$(MICROPHONE_CHECK).settings-after"; then \
		echo "Voiced's saved settings, the menu bar icon's place among them, are the same as before the check."; \
	else \
		echo "Voiced's saved settings changed while the check ran. If the running Voiced did not change them, the check did."; \
		result=4; \
	fi; \
	echo "Microphone check result: $$result"; \
	exit $$result

## Package the Release app as a disk image people can install from, in $(DERIVED_DATA)/dmg.
## Without a Developer ID the app is signed ad hoc and the image is named
## Voiced-<version>-unsigned.dmg. With one, and notarization credentials, the image is signed,
## notarized and stapled:
##   make dmg DEVELOPER_ID="Developer ID Application" NOTARY_PROFILE=voiced-notary
## Tools/make-dmg.sh lists every setting and docs/releasing.md explains them. It builds in a
## folder of its own and ignores TEAM, so the app `make run` uses is left as it is.
dmg:
	DMG_DIR="$(DERIVED_DATA)/dmg" Tools/make-dmg.sh

clean:
	rm -rf $(DERIVED_DATA) $(PACKAGE)/.build snapshots pill-captures
