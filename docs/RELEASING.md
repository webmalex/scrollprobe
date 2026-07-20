# Maintainer release workflow

Public beta binaries are built on a GitHub-hosted macOS runner, ad-hoc signed,
checksummed, and covered by a GitHub artifact attestation. They are not signed
with an Apple Developer ID and are not notarized, so macOS requires the user to
approve the first launch through **Privacy & Security > Open Anyway**.

The release asset must be the exact archive produced and attested by CI. Never
rebuild it between testing and publication.

## Build the candidate

1. Start from a clean `master` at the intended release commit.
2. Confirm that `CFBundleShortVersionString` and `CFBundleVersion` were
   incremented and that the release notes match them.
3. Run the local checks, commit, and push `master`:

   ```sh
   make test lint verify-package
   git push origin master
   ```

4. Find the successful CI run for that exact commit:

   ```sh
   gh run list --workflow CI --branch master --limit 5
   ```

5. Download its artifact. For version `0.6.0`, the artifact name is
   `ScrollProbe-0.6.0-macos-arm64`:

   ```sh
   mkdir -p dist/attested
   gh run download RUN_ID \
     --name ScrollProbe-0.6.0-macos-arm64 \
     --dir dist/attested
   ```

## Verify the candidate

Run both checks from the artifact directory:

```sh
cd dist/attested
shasum -a 256 -c ScrollProbe-0.6.0-macos-arm64.zip.sha256
gh attestation verify ScrollProbe-0.6.0-macos-arm64.zip \
  --repo webmalex/scrollprobe \
  --signer-workflow webmalex/scrollprobe/.github/workflows/ci.yml \
  --deny-self-hosted-runners
```

The attestation result must identify `webmalex/scrollprobe`, the expected commit
and `.github/workflows/ci.yml`. The denied-self-hosted option confirms that the
archive came from GitHub-hosted infrastructure.

## Smoke test the exact archive

Use the downloaded ZIP, not `dist/ScrollProbe.app`:

1. Disable `Launch at Login` and quit any pre-public ScrollProbe build.
2. Extract the archive and move the app to `/Applications`.
3. Attempt to open it, then approve it through **System Settings > Privacy &
   Security > Open Anyway**. Do not remove quarantine attributes.
4. Grant Accessibility, enable Protection, and confirm version/build and active
   status in the menu.
5. Verify scrolling, live counters, `Copy Status`, Launch at Login, and one
   quit/relaunch. Include reboot and VM pause/resume when the release changes
   lifecycle code.

## Publish the GitHub prerelease

Create the annotated tag only after the exact archive passes its smoke test:

```sh
git tag -a v0.6.0-beta.1 -m "ScrollProbe 0.6.0 beta 1"
git push origin v0.6.0-beta.1
gh release create v0.6.0-beta.1 \
  dist/attested/ScrollProbe-0.6.0-macos-arm64.zip \
  dist/attested/ScrollProbe-0.6.0-macos-arm64.zip.sha256 \
  --prerelease \
  --title "ScrollProbe 0.6.0 beta 1" \
  --notes-file docs/RELEASE_NOTES_0.6.0-beta.1.md
```

After publication, verify the release from a signed-out browser. Download the
assets again and repeat both checksum and attestation verification. Confirm the
source tag, prerelease badge, archive name, and unnotarized-beta warning.

Apple Developer ID signing and notarization are deliberately deferred. If they
become available later, add them as a separate reviewed workflow; do not imply
that GitHub attestation changes Gatekeeper's trust decision.
