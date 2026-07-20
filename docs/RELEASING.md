# Maintainer release workflow

Public ScrollProbe binaries are distributed outside the Mac App Store. They
must be signed with Developer ID, use Hardened Runtime and a secure timestamp,
and be notarized and stapled before upload.

## One-time Apple setup

1. Join the Apple Developer Program and add the account in Xcode.
2. In **Xcode > Settings > Accounts**, select the team, choose **Manage
   Certificates**, press `+`, and create a **Developer ID Application**
   certificate.
3. Confirm that the certificate and its private key are available:

   ```sh
   security find-identity -v -p codesigning
   ```

4. Generate an app-specific password for the Apple ID used for notarization.
5. Store it in the login Keychain through an interactive secure prompt. Do not
   put the password on the command line:

   ```sh
   xcrun notarytool store-credentials scrollprobe-notary \
     --apple-id "APPLE_ID_EMAIL" \
     --team-id "TEAM_ID"
   ```

6. Verify the stored profile without exposing credentials:

   ```sh
   xcrun notarytool history --keychain-profile scrollprobe-notary
   ```

Apple references:

- [Create Developer ID certificates](https://developer.apple.com/developer-id/)
- [Notarize macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Customize the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

## Build and notarize

1. Start from a clean `master` at the intended release commit.
2. Confirm that `CFBundleShortVersionString` and `CFBundleVersion` were
   incremented.
3. Run:

   ```sh
   make test lint
   make release-package \
     SIGN_IDENTITY="Developer ID Application: NAME (TEAM_ID)" \
     NOTARY_PROFILE="scrollprobe-notary"
   ```

4. Preserve the printed SHA-256 value and run the verification target:

   ```sh
   make verify-release
   ```

The final artifact for version `0.6.0` is:

```text
dist/ScrollProbe-0.6.0-macos-arm64.zip
```

The temporary ZIP submitted to Apple is removed after the ticket has been
stapled to the app and the final archive has been created.

## Smoke test the distributed archive

Test the exact final ZIP rather than the build directory:

1. Copy it to a second macOS installation or the UTM guest.
2. Extract and move the app to `/Applications`.
3. Confirm that Gatekeeper presents an identified-developer first-launch prompt,
   not an unidentified-developer or malware warning.
4. Grant Accessibility and enable Protection.
5. Verify scrolling, `Copy Status`, Launch at Login, and one quit/relaunch.

## Publish the GitHub prerelease

Create and push an annotated release tag only after the distributed-archive
smoke test:

```sh
git tag -a v0.6.0-beta.1 -m "ScrollProbe 0.6.0 beta 1"
git push origin v0.6.0-beta.1
gh release create v0.6.0-beta.1 \
  dist/ScrollProbe-0.6.0-macos-arm64.zip \
  --prerelease \
  --title "ScrollProbe 0.6.0 beta 1" \
  --notes-file docs/RELEASE_NOTES_0.6.0-beta.1.md
```

Maintainers with an established GPG or SSH signing identity may use a signed tag
instead. Developer ID signing and notarization authenticate the distributed app
independently of Git tag signing.

After publication, verify the release page from a signed-out browser and check
that the archive name, checksum, source tag, and prerelease badge are correct.
