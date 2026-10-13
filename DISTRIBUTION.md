# Distribution

Usage Rings uses the same download flow as `cc:`. Download a GitHub Release DMG,
then drag the app into Applications. The app is **not notarized by Apple**. Paid
Apple Developer membership is not part of this distribution plan.

## Install a release

Requires macOS 26+ and **Apple silicon (arm64)**. The current app does not support
Intel Macs. Xcode is needed only when building from source, not for the downloads.

1. Download [usage-rings-macos.dmg](https://github.com/hayashiii-ghub/usage-rings/releases/latest/download/usage-rings-macos.dmg)
   from [GitHub Releases](https://github.com/hayashiii-ghub/usage-rings/releases).
2. Open the DMG. Quit any running Usage Rings and drag `Usage Rings.app` into
   Applications. When updating, replace the existing app in its current location
   so there is only one installed copy. If it is already in `~/Applications`,
   use that location rather than creating a second copy in `/Applications`.
3. Open the installed app. This is an ad-hoc signed, unnotarized app; macOS may
   block its first launch. If you trust the source, follow Apple's
   [per-app approval instructions](https://support.apple.com/102445) in
   **System Settings → Privacy & Security → Open Anyway**. Managed-device policy
   may prevent approval. Stop if macOS reports malware or an integrity failure.
4. Read the connection explanation in Usage Rings and choose **Enable AI usage**
   to connect. Until then the app does not read provider credentials or contact
   usage providers. Upgrades from versions that connected automatically also
   require this action. Codex needs the official Codex CLI 0.160.1+ installed
   separately and already signed in with ChatGPT; Usage Rings does not install
   it or start a login flow. The CLI manages its own existing sign-in and local
   state. See [the accounts guide](README.md#accounts).
5. Right-click the desktop, choose **Edit Widgets**, and add **Usage Rings → AI
   Usage**. Keep the host app running to refresh usage. Login Items are optional.

A ZIP is also available in the release. Extract it and follow steps 2–5. No
installer removes quarantine attributes or disables Gatekeeper. Claude Code
integration is optional; see below before changing an existing custom status line.

For verification, download `usage-rings-macos.zip`, `usage-rings-macos.dmg`,
`appcast.xml`, `usage-rings-macos.json`, and `usage-rings-macos.sha256` from the same release,
then run `shasum -a 256 -c usage-rings-macos.sha256` in that directory. The JSON
records version, build, source commit, architecture, signing state and hashes.
Neither archive includes account credentials, settings, or usage caches.

The development Mac has confirmed the updated app and small widget. Fresh
installation, first-launch approval, and widget registration on a separate Mac
remain untested; publishing an unnotarized build does not imply those were tested.

## In-app updates

Sparkle provides the standard **Check for Updates…** window, download, and
relaunch-to-install flow. The feed is
`https://github.com/hayashiii-ghub/usage-rings/releases/latest/download/appcast.xml`.
The first release with Sparkle must be installed manually by users of older
versions. Keep the app bundle identifier and increase the build number for
subsequent releases.

Update archives are verified with an EdDSA public key embedded in the app. The
corresponding private key belongs in the macOS login Keychain under the dedicated
account `work.hayashigoto.UsageRings`. Create it only with the release operator's
approval, using Sparkle's `generate_keys --account work.hayashigoto.UsageRings`.
Save the printed public key as `public_ed_key` in `script/sparkle-config.json`;
that file also records the feed URL and Keychain account. The account name does
not contain the private key. Keep the private key out of source, command arguments, logs, and release assets;
only the public key belongs in the repository. Losing the private key can prevent
installed clients from accepting future updates.

Packaging uses Sparkle’s `generate_appcast` with the dedicated Keychain account
to sign the final ZIP and record its signature in `appcast.xml`. A release is
ready for in-app updating only after that appcast and matching ZIP are published
together. Uploading files or publishing a GitHub
release still requires explicit approval. Until that feed is published, a real
update check can fail even when the local framework integration is correct.
Existing users' preferences, provider connections, and widget data are retained.

The updater does not change Apple's signing or notarization status. Follow the
same unnotarized distribution requirements below; do not bypass Gatekeeper.

## Build and package an unnotarized release

From a clean committed checkout with macOS 26+ and Xcode:

```sh
make check
APP_VERSION=0.1.5 APP_BUILD=7 make build
make package-unnotarized
```

This explicitly selects unnotarized distribution and creates a versioned folder
under `dist/packages/` with five assets:

- `usage-rings-macos.dmg`: compressed disk image with the app, Applications shortcut,
  and installation notes.
- `usage-rings-macos.zip`: the same app bundle.
- `appcast.xml`: Sparkle update information and the ZIP’s EdDSA signature, using
  an immutable `releases/download/v<version>/` URL.
- `usage-rings-macos.json`: build and signing metadata plus archive and appcast hashes.
- `usage-rings-macos.sha256`: checksums for the DMG, ZIP, appcast, and JSON.

Stable asset names support GitHub's `releases/latest/download` links; the local
versioned directory preserves earlier builds. Packaging rejects dirty-source or
debug builds, mismatched host/widget metadata, broken signatures, and invalid
entitlements. It checks the embedded Sparkle components, extracts the ZIP and mounts the DMG
read-only to recheck their contents, then detaches it. Missing update configuration
or archive signatures prevent release packaging. It does not install or launch the app.

The mode never calls notarization or changes system security settings. Ad-hoc
signing checks bundle integrity but does not verify a developer's identity.
`make package-draft` remains available for a review-only ZIP. Release draft status
is independent of code signing: public publishing is an explicit release step.

`APP_VERSION` is three numeric components; `APP_BUILD` is an increasing integer
from 1 to 9999. Ordinary local builds retain their original defaults (0.1.0,
build 1). `SOURCE_REVISION` defaults to the full checked-out HEAD and cannot refer
to a different commit. The host and widget record the same version and build.

## Build from source instead

Clone the repository and run `make check`, then `make install`. This requires
Xcode but no paid Apple Developer membership. The source installer installs to
`~/Applications` and connects Claude Code's status line if no custom command
exists; custom commands are preserved. Use `make build` to inspect the bundle
without installing it or connecting the helper.

Before the first signing-key setup, `CONFIGURATION=debug make build` can build a
local app with updates disabled. Release builds require the public key. To test
a configured build without changing its saved automatic-check preference, launch
it with `-SUEnableAutomaticChecks NO`. A Debug build does not rewrite that
preference.

## Optional notarized build

This is not part of the current release plan. With an already installed Developer
ID Application certificate and configured notarization access, build using its
identity hash, submit to Apple, and staple an accepted ticket:

```sh
APP_VERSION=0.1.1 APP_BUILD=4 CODE_SIGN_IDENTITY='<installed-identity-SHA1>' make build
ditto -c -k --sequesterRsrc --keepParent 'dist/Usage Rings.app' dist/notary-upload.zip
xcrun notarytool submit dist/notary-upload.zip --keychain-profile '<existing-profile>' --wait
# Continue only after Apple reports Accepted:
xcrun stapler staple 'dist/Usage Rings.app'
make package
```

`make package` retains the stricter notarized mode: matching Developer ID teams,
hardened runtime, secure timestamps, a stapled ticket, and successful Gatekeeper
assessment. It does not silently fall back to the unnotarized mode. See Apple's
[Developer ID overview](https://developer.apple.com/developer-id/) and
[notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## Optional Claude Code integration

Moving the app does not connect Claude Code's status line automatically. To opt
in, merge the following property into `~/.claude/settings.json` (or the configured
Claude config directory). Preserve all other settings. If a custom `statusLine`
already exists, compose its command with the helper instead of replacing it:

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"/Applications/Usage Rings.app/Contents/Helpers/UsageRingsStatusline\""
  }
}
```

The quoted command handles the space in the app's name. If the app is installed
under `~/Applications`, replace `/Applications` with `$HOME/Applications` in that
command. Use Claude Code once;
the usage reading appears after an API response. See [README](README.md#accounts)
for provider availability, cache freshness, and privacy details.

To disconnect this manual setup, remove only the `statusLine` property added
above. If it was composed with a custom command, remove only the Usage Rings
helper invocation and keep the custom command. The source installer’s
`--uninstall` recognizes only the command that installer wrote; it does not
remove every manually written form.
