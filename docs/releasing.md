# Releasing Voiced

The Release workflow, `.github/workflows/release.yml`, builds Voiced, packages it as a disk image and attaches the image to a GitHub Release. The packaging is `make dmg` (`Tools/make-dmg.sh`), which runs the same on a Mac.

## Cut a release

1. See that `main` holds what you mean to ship, and that `MARKETING_VERSION` in `Voiced.xcodeproj/project.pbxproj` (it is there twice, once for each configuration) is the version you are about to tag. The release does not depend on it, but a build from source goes by it, and should not call itself an older version than the release cut from the same code.
2. Tag it and push the tag:

   ```sh
   git tag v0.2.0
   git push origin v0.2.0
   ```

   The tag is the version: `v0.2.0` makes Voiced 0.2.0, whatever `MARKETING_VERSION` says in the project. Only tags of the form `v1.2.3` start a release.
3. Watch the run under Actions › Release. When it ends, the release for the tag holds the DMG, the install steps, and the notes GitHub generates: a link to what changed since the release before, and a list of merged pull requests where there are any.

To try it without publishing anything, run it by hand: Actions › Release › Run workflow. The DMG is kept for 14 days as an artifact of that run, and the run's summary shows the release notes a tag would have published.

A release is seen by whoever can see the repository. While the repository is private, so are its downloads.

## Signed or unsigned

**With the five secrets below**, the DMG is `Voiced-<version>.dmg`: signed with your Developer ID and the hardened runtime, notarized by Apple and stapled. It opens like any downloaded app, and macOS knows each update as the same app, so the Microphone and Accessibility grants and the saved key carry over.

**Without them**, the DMG is `Voiced-<version>-unsigned.dmg`, signed ad hoc. It works, and this is what it costs the person installing it:

- **On first open,** macOS refuses: "Apple could not verify 'Voiced' is free of malware." They have to open System Settings › Privacy & Security, click Open Anyway beside Voiced, and confirm with their password. Right-click › Open has not got past this since macOS 15. The other way through is Terminal: `xattr -dr com.apple.quarantine /Applications/Voiced.app`. After that, setup is the same as for a signed build: allow the Microphone, switch on Accessibility, paste the key.
- **After every update,** macOS takes the new build for a different app, because an ad hoc signature names one exact build. They approve it under Open Anyway again. Accessibility still lists Voiced as on, but the grant belongs to the old build: they remove Voiced from the list and switch it on again, and until they do the hotkey does nothing. macOS may ask for the Microphone again, and asks for their login password before Voiced can read the saved key.
- **Going from an unsigned release to a signed one** costs the same once more, and then never again.

The release notes the workflow writes say this to the person downloading.

## The secrets

Add them yourself under the repository's Settings › Secrets and variables › Actions › New repository secret. Set all five or none: with only some, the run stops before it builds and names the ones missing. They need a paid Apple Developer Program membership, US$99 a year.

| Secret | Where it comes from |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Your Developer ID Application certificate with its private key. Create it in Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application. In Keychain Access › My Certificates, right-click it › Export, save a `.p12`, then `base64 -i DeveloperID.p12 \| pbcopy` and paste. |
| `DEVELOPER_ID_P12_PASSWORD` | The password you typed for that export. It must not be empty. |
| `NOTARY_KEY_P8_BASE64` | An App Store Connect API key, which is what notarization signs in with. At appstoreconnect.apple.com › Users and Access › Integrations › App Store Connect API › Team Keys, generate a key with the Developer role and download `AuthKey_<Key ID>.p8`; it can be downloaded once. Then `base64 -i AuthKey_<Key ID>.p8 \| pbcopy` and paste. |
| `NOTARY_KEY_ID` | The Key ID shown beside that key in the same list. |
| `NOTARY_ISSUER_ID` | The Issuer ID shown above the list of keys on the same page. |

The workflow never prints them. The certificate lives in a keychain made for the one job and deleted at its end, and the team ID is masked in the log. A Developer ID signature does carry the team ID, as every signed Mac app does, so it can be read from a released DMG.

Add the secrets before the first tag if you can. If a release has already gone out unsigned, ship the signed build as a new version: running the old tag's workflow again would put a second DMG beside the unsigned one and leave the release's text as it was.

A team's first notarization can take hours where later ones take minutes. The run waits 15 minutes for each of its two submissions, the app and then the image. If it gives up waiting, run it again later.

## On a Mac

```sh
make dmg
```

writes `build/dmg/Voiced-<version>-unsigned.dmg`. It builds in `build/dmg`, apart from the app `make run` uses, and never signs with the team in `local.mk`.

For the signed image, store the notarization key once, then name the certificate and the profile:

```sh
xcrun notarytool store-credentials voiced-notary --key AuthKey_<Key ID>.p8 --key-id <Key ID> --issuer <Issuer ID>
make dmg DEVELOPER_ID="Developer ID Application" NOTARY_PROFILE=voiced-notary
```

`VERSION=0.2.0` stamps a version other than the project's.

## What a run does and costs

It runs on GitHub's `macos-26` image (macOS 26, Apple silicon) with Xcode 26.2, the oldest Xcode the project supports, and builds for Apple silicon and Intel. It checks what it made before keeping it: the signature (`codesign --verify`), the hardened runtime, that the entitlements are exactly those of `Voiced/Voiced.entitlements`, both architectures, the image itself, and the app as it sits in the mounted image. A signed run also asks Gatekeeper (`spctl --assess`) and checks the notarization tickets (`stapler validate`), on the app and on the image.

On a private repository GitHub bills a minute on a macOS runner as ten, rounded up to the whole minute. An unsigned run takes about two and a half minutes, so 30 billed minutes, and a few seconds on the Linux runner that publishes. A signed run adds the wait for Apple's two answers. A public repository pays nothing.

Voiced does not update itself. A new release reaches people when they download the new DMG and replace the app.
