# Maintaining and releasing the fork

`main` mirrors `vorssaint/vorssaint-utils` upstream. `custom` contains the
fork's features, CI and release workflow. Work on feature branches based on
`custom` and merge those changes back into `custom`.

## Bring in an upstream release

From the fork checkout, with `origin` pointing to `yoyuzh/vorssaint-utils`
and `upstream` to `vorssaint/vorssaint-utils`, run:

```sh
git fetch --no-tags upstream main
git push origin upstream/main:refs/heads/main
git switch custom
git merge --no-ff upstream/main
./build.sh --test
./build.sh
./build/Vorssaint --selftest
git push origin custom
```

Resolve merge conflicts in `custom` before committing the merge. The mirror
push is a fast-forward. The fork's CI runs when `custom` is pushed or receives
a pull request. The push run uploads `vorssaint-custom-test-dmg` for local
testing. This artifact has an ad-hoc signature and stays outside the update feed.

## Set up signing once

Create or open the `fork-release-signing` environment in the fork's
**Settings → Environments**. Set the environment variable `APPLE_TEAM_ID`
to the ten-character Apple Team ID. Add these environment secrets:

| Secret | Value |
| --- | --- |
| `SIGNING_CERT_P12` | Base64-encoded Developer ID Application certificate and private key exported as a `.p12` |
| `SIGNING_CERT_PASSWORD` | Password for that `.p12` |
| `NOTARY_API_KEY_P8` | Base64-encoded App Store Connect API private key (`.p8`) |
| `NOTARY_KEY_ID` | App Store Connect API key ID |
| `NOTARY_ISSUER_ID` | App Store Connect API issuer ID |

Give the environment's deployment rules access to tags matching `custom-v*`.
The signed app uses `APPLE_TEAM_ID` to authenticate both the update DMG and the
new app. Keep the same Team ID across releases so installed copies continue to
accept updates.

## Publish a fork version

Pick a version greater than the last fork release. From the verified `custom`
commit, create and push a new fork tag as `yoyuzh`:

```sh
git tag -a custom-v3.4.4 -m "Fork release 3.4.4"
git push origin refs/tags/custom-v3.4.4
```

Use a suffix such as `-beta.1` for a prerelease. The tag sets the version of the
built App. **Fork Release** tests the tagged source, signs and notarizes the App
and DMG, and publishes the verified DMG to this fork's Releases. Stable
releases become `latest`. Prereleases are available through the beta option in
the app. Publish fixes with a new version.

Install the first signed fork DMG manually. It uses the original bundle ID and
replaces the existing app in `/Applications`. macOS may ask for permissions
again because the signing team changed. Reinstall the fan-control helper from
the fork app if you previously installed it from the upstream build.
Subsequent fork releases can be installed through the app's updater.
