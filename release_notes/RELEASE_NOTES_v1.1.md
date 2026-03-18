# Release Notes - v1.1.0

**Release Date:** March 18, 2026

## Highlights

- Added `felix update` so installed users can update Felix directly from the CLI
- Added cross-platform update support for Windows, Linux, and macOS release artifacts
- Added updater test coverage for mocked GitHub release responses, staged payload application, and Unix helper execution in CI

---

## New Features

### CLI Self-Update Command

Felix now supports:

- `felix update`
- `felix update --check`
- `felix update --yes`

The command checks GitHub Releases, compares the installed version to the latest published version, downloads the correct platform artifact, verifies checksums, prompts before install unless `--yes` is supplied, and stages the update for replacement after the current process exits.

### Cross-Platform Artifact Selection

Updater asset selection now supports these release targets:

- `win-x64`
- `linux-x64`
- `osx-x64`
- `osx-arm64`

This allows the same CLI update flow to work across supported Felix platforms.

When no installed Felix binary is present in the target install directory, the updater can bootstrap that location with the latest published release.

---

## Improvements

- Reused shared install directory/version resolution in the CLI installer and updater paths
- Added generated helper scripts for Windows and Unix update-apply flows
- Extended CLI help and docs to describe the new update workflow

---

## Test Coverage

Added and expanded coverage for updater behavior:

- semantic version normalization and comparison
- GitHub release asset selection
- checksum parsing and verification
- mocked HTTP coverage for latest release responses
- temp-directory integration coverage for the Windows helper apply flow
- Unix helper execution coverage through dedicated Linux and macOS CI jobs

---

## Notes

- `felix install` remains the bootstrap path for first-time installation.
- `felix update` is intended for updating an existing installed CLI, but can also bootstrap the install directory when no prior installed copy is found.
- Release packaging continues to publish platform-specific zip artifacts and Windows installer assets.
