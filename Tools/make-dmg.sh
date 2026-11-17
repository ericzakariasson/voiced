#!/bin/bash
#
# Builds the Release app and packages it as a disk image people can install from. Run it as
# `make dmg`; the release workflow runs the same command. docs/releasing.md is the guide.
#
# With nothing set it writes build/dmg/Voiced-<version>-unsigned.dmg. That app is signed ad hoc:
# macOS will not open it until the person approves it in System Settings, and every update is a
# new app to macOS, so the Accessibility grant has to be given again.
#
# With a Developer ID and notarization credentials it writes build/dmg/Voiced-<version>.dmg:
# signed with the hardened runtime, notarized, stapled and checked.
#
#   DEVELOPER_ID     the signing identity: "Developer ID Application", or the SHA-1 of the
#                    certificate when the keychain holds more than one
#   NOTARY_PROFILE   a notarytool keychain profile, made once with
#                    `xcrun notarytool store-credentials`
#   NOTARY_KEY, NOTARY_KEY_ID, NOTARY_ISSUER_ID
#                    instead of a profile: the path of an App Store Connect API key (.p8), its
#                    key ID and its issuer ID
#   VERSION          the version to stamp, in place of the project's MARKETING_VERSION
#   BUILD_NUMBER     the build number to stamp, in place of the project's CURRENT_PROJECT_VERSION
#   DMG_DIR          where everything is written; build/dmg when not given
#
# It builds in a folder of its own and never signs with the team in local.mk, so the app that
# `make run` uses, and the grants that app holds, are left as they are.

set -euo pipefail

cd "$(dirname "$0")/.."

DEVELOPER_ID="${DEVELOPER_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
NOTARY_KEY="${NOTARY_KEY:-}"
NOTARY_KEY_ID="${NOTARY_KEY_ID:-}"
NOTARY_ISSUER_ID="${NOTARY_ISSUER_ID:-}"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
DMG_DIR="${DMG_DIR:-build/dmg}"

ENTITLEMENTS="Voiced/Voiced.entitlements"
# How long to wait for Apple's answer to one submission. It usually comes within five minutes.
NOTARY_TIMEOUT="15m"

step() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nmake-dmg: %s\n' "$*" >&2; exit 1; }

# Nothing printed here may hold a signing team ID. Apple writes it in brackets after the name on
# a certificate, so whatever the signing tools say passes through this first.
redact() {
    sed -E 's/\([A-Z0-9]{10}\)/(team)/g; s/TeamIdentifier=[A-Z0-9]{10}/TeamIdentifier=(team)/g'
}

notary() {
    if [ -n "$NOTARY_PROFILE" ]; then
        xcrun notarytool "$@" --keychain-profile "$NOTARY_PROFILE"
    else
        xcrun notarytool "$@" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID"
    fi
}

# Sends one file to Apple and waits. notarytool can end successfully with an answer other than
# Accepted, so the answer is read, and Apple's list of what it found is printed when it is not.
notarize() {
    local file="$1" result="$DMG_DIR/notary-result.json" id status
    step "Notarizing $(basename "$file"); waiting up to $NOTARY_TIMEOUT for Apple"
    if ! notary submit "$file" --wait --timeout "$NOTARY_TIMEOUT" --output-format json > "$result"; then
        redact < "$result" >&2 || true
        fail "notarytool could not submit $(basename "$file"). Check the notarization credentials."
    fi
    id="$(plutil -extract id raw -o - "$result" 2>/dev/null || true)"
    status="$(plutil -extract status raw -o - "$result" 2>/dev/null || true)"
    echo "Apple's answer: ${status:-none}"
    if [ "$status" != "Accepted" ]; then
        if [ -n "$id" ]; then
            notary log "$id" 2>&1 | redact >&2 || true
        fi
        fail "Apple did not accept $(basename "$file"). If the answer is still In Progress, run this again later: a team's first submission can take hours."
    fi
    rm -f "$result"
}

entitlement_keys() { { grep -o '<key>[^<]*</key>' || true; } | sort; }

# The checks that hold for either kind of signature.
check_app() {
    local app="$1" details signed_keys source_keys archs
    codesign --verify --deep --strict --verbose=2 "$app" 2>&1 | redact

    details="$(codesign --display --verbose=4 "$app" 2>&1)"
    grep -Eq 'flags=0x[0-9a-f]+\(.*runtime' <<< "$details" \
        || fail "$app is not signed with the hardened runtime."

    # Xcode adds get-task-allow, which lets a debugger attach, to what `xcodebuild build` signs.
    # Apple refuses to notarize it. Signing again with the entitlements file leaves it out.
    signed_keys="$(codesign --display --entitlements - --xml "$app" 2>/dev/null | entitlement_keys)"
    source_keys="$(entitlement_keys < "$ENTITLEMENTS")"
    [ "$signed_keys" = "$source_keys" ] \
        || fail "$app carries entitlements other than those in $ENTITLEMENTS."

    # macOS 26 still runs on Intel Macs, so a release holds both halves.
    archs="$(lipo -archs "$app/Contents/MacOS/Voiced")"
    case " $archs " in *" arm64 "*) ;; *) fail "$app has no arm64 half: $archs" ;; esac
    case " $archs " in *" x86_64 "*) ;; *) fail "$app has no x86_64 half: $archs" ;; esac
    echo "Hardened runtime, the entitlements of $ENTITLEMENTS and nothing else, $archs."
}

[ "$(uname)" = "Darwin" ] || fail "this needs macOS and Xcode."

if [ -n "$DEVELOPER_ID" ]; then
    if [ -z "$NOTARY_PROFILE" ] && { [ -z "$NOTARY_KEY" ] || [ -z "$NOTARY_KEY_ID" ] || [ -z "$NOTARY_ISSUER_ID" ]; }; then
        fail "DEVELOPER_ID is set without notarization credentials. Set NOTARY_PROFILE, or NOTARY_KEY with NOTARY_KEY_ID and NOTARY_ISSUER_ID; or set none of them for an unsigned image."
    fi
    signed=1
    suffix=""
    volume="Voiced"
else
    if [ -n "$NOTARY_PROFILE$NOTARY_KEY$NOTARY_KEY_ID$NOTARY_ISSUER_ID" ]; then
        fail "notarization credentials are set without DEVELOPER_ID. Set it, or set none of them for an unsigned image."
    fi
    signed=0
    suffix="-unsigned"
    volume="Voiced (unsigned)"
fi

mkdir -p "$DMG_DIR"
DMG_DIR="$(cd "$DMG_DIR" && pwd)"
derived="$DMG_DIR/derived"
stage="$DMG_DIR/staging"
mount="$DMG_DIR/mount"

# An image from an earlier run must not be taken for this one's.
rm -rf "$stage" "$DMG_DIR"/Voiced-*.dmg "$DMG_DIR"/Voiced-*.zip
if [ -d "$mount" ]; then
    hdiutil detach "$mount" -force -quiet 2>/dev/null || true
    rmdir "$mount"
fi

step "Building the Release app for Apple silicon and Intel with $(xcodebuild -version | tr '\n' ' ')"
# The project's own signing: ad hoc, with no team. The generic destination builds both halves.
set -- ONLY_ACTIVE_ARCH=NO
if [ -n "$VERSION" ]; then set -- "$@" "MARKETING_VERSION=$VERSION"; fi
if [ -n "$BUILD_NUMBER" ]; then set -- "$@" "CURRENT_PROJECT_VERSION=$BUILD_NUMBER"; fi
xcodebuild -project Voiced.xcodeproj -scheme Voiced -configuration Release \
    -derivedDataPath "$derived" -destination 'generic/platform=macOS' -quiet "$@" build

built="$derived/Build/Products/Release/Voiced.app"
[ -d "$built" ] || fail "the build left no app at $built."
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$built/Contents/Info.plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$built/Contents/Info.plist")"

mkdir -p "$stage"
app="$stage/Voiced.app"
ditto "$built" "$app"
ln -s /Applications "$stage/Applications"

# Voiced holds no code besides its own executable. If it gains a framework or a helper, that
# has to be signed first, before the app around it.
if [ "$signed" = 1 ]; then
    step "Signing Voiced $version ($build_number) with the Developer ID"
    codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" \
        --sign "$DEVELOPER_ID" "$app" 2>&1 | redact
else
    step "Signing Voiced $version ($build_number) ad hoc"
    codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign - "$app" 2>&1 | redact
fi
check_app "$app"

if [ "$signed" = 1 ]; then
    # The app is notarized and stapled by itself first, so that the copy a person drags to
    # Applications opens on a Mac that is offline. The image is notarized again around it.
    archive="$DMG_DIR/Voiced-$version-for-notarization.zip"
    ditto -c -k --keepParent "$app" "$archive"
    notarize "$archive"
    rm -f "$archive"
    xcrun stapler staple "$app"
fi

dmg="$DMG_DIR/Voiced-$version$suffix.dmg"
step "Packaging $(basename "$dmg")"
# On a hosted runner hdiutil now and then answers "Resource busy" while the system is still
# scanning the new app. A second try a few seconds later gets through.
attempt=1
until hdiutil create -volname "$volume" -srcfolder "$stage" -fs HFS+ -format UDZO -ov -quiet "$dmg"; do
    [ "$attempt" -lt 3 ] || fail "hdiutil could not make the disk image."
    attempt=$((attempt + 1))
    sleep 5
done

if [ "$signed" = 1 ]; then
    codesign --force --timestamp --sign "$DEVELOPER_ID" "$dmg" 2>&1 | redact
    notarize "$dmg"
    xcrun stapler staple "$dmg"
fi

step "Checking the disk image"
hdiutil verify -quiet "$dmg"
mkdir -p "$mount"
trap 'hdiutil detach "$mount" -force -quiet 2>/dev/null || true' EXIT
hdiutil attach "$dmg" -readonly -nobrowse -mountpoint "$mount" -quiet
[ -d "$mount/Voiced.app" ] || fail "the image holds no Voiced.app."
[ "$(readlink "$mount/Applications")" = "/Applications" ] || fail "the image holds no link to Applications."
check_app "$mount/Voiced.app"

if [ "$signed" = 1 ]; then
    xcrun stapler validate "$mount/Voiced.app"
    spctl --assess --type execute --verbose=4 "$mount/Voiced.app" 2>&1 | redact
    codesign --verify --strict --verbose=2 "$dmg" 2>&1 | redact
    xcrun stapler validate "$dmg"
    spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg" 2>&1 | redact
else
    # Said for the record, and to show that Gatekeeper's answer on this Mac means something:
    # a Mac that accepted this build would accept anything.
    if verdict="$(spctl --assess --type execute --verbose=4 "$mount/Voiced.app" 2>&1)"; then
        echo "Warning: Gatekeeper accepted a build with no Developer ID on this Mac, so its answer here proves nothing."
    else
        echo "Gatekeeper refuses this build, as it does any build with no Developer ID:"
    fi
    printf '%s\n' "$verdict" | redact | sed 's/^/    /'
fi

hdiutil detach "$mount" -quiet || hdiutil detach "$mount" -force -quiet
trap - EXIT
rmdir "$mount"

step "Built $dmg"
bytes="$(wc -c < "$dmg" | tr -d ' ')"
echo "Voiced $version ($build_number), $bytes bytes ($(awk -v b="$bytes" 'BEGIN { printf "%.1f", b / 1048576 }') MB)"
echo "SHA-256 $(shasum -a 256 "$dmg" | cut -d ' ' -f 1)"
if [ "$signed" = 1 ]; then
    echo "Signed with a Developer ID, notarized and stapled: it opens like any downloaded app."
else
    echo "NOT signed with a Developer ID and NOT notarized. macOS will not open it until the person"
    echo "clicks Open Anyway under System Settings > Privacy & Security, and each update has to be"
    echo "approved again and given Accessibility again. See docs/releasing.md."
fi
