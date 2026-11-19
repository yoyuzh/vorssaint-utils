# Maintaining and releasing the fork

`main` mirrors `vorssaint/vorssaint-utils` upstream. The fork's default branch,
`custom`, contains its features, CI and release workflow. Base feature branches
on `custom` and merge those changes back into `custom`.

## Follow upstream releases

Every six hours, **Fork Release** checks the latest verified upstream stable
release and fast-forwards `main` to upstream `main`. It opens a PR into `custom`
from the upstream release commit, without pulling in unrelated unreleased
commits. If GitHub can merge the PR, the workflow merges it and runs the release
tests, signing and notarization. The tag `custom-vX.Y.Z` is created only after
packaging succeeds. Upstream prereleases do not trigger an automatic release.

To check immediately, use **Actions → Fork Release → Run workflow** on `custom`.
Leave `dry_run` enabled to inspect the state without making changes. Disable it
to run synchronization and, after a successful build, publish. The fork Actions
settings must allow GitHub Actions to create pull requests.

### Resolve a sync PR conflict

For a PR from `sync/upstream-vX.Y.Z`, bring `custom` into that PR branch:

```sh
git fetch origin
git switch --track origin/sync/upstream-vX.Y.Z
git merge origin/custom
```

Resolve the conflicts, stage the resolved files and finish the merge. Then run:

```sh
./build.sh --test
git push origin HEAD
```

Merge the PR with a merge commit so the upstream release commit remains in
`custom`'s history. The next sync run resumes CD. A conflict, failed test or
failed signing step leaves already published versions untouched.

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

Give the environment's deployment rules access to the `custom` branch and tags
matching `custom-v*`.
The signed app uses `APPLE_TEAM_ID` to authenticate both the update DMG and the
new app. Keep the same Team ID across releases so installed copies continue to
accept updates.

## Publish a fork version manually

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
