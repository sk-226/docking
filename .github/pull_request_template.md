# Docking 0.0.4 Pre-Release Candidate

## Scope

This PR is for the native macOS `Docking` 0.0.4 pre-release app candidate.

Apple Dock preferences remain overlay-only by default. Primary Dock mode is
opt-in, confirmation-gated, and restoreable from Control Center > Restore.

## Local Release Gate

- [ ] `./script/release_check.sh` passes on this branch.
- [ ] The generated fallback artifact is `dist/Docking-0.0.4-macos26.zip`.
- [ ] The generated tester artifact is `dist/Docking-0.0.4-macos26.dmg`.
- [ ] The generated checksums are `dist/Docking-0.0.4-macos26.zip.sha256` and
      `dist/Docking-0.0.4-macos26.dmg.sha256`.
- [ ] The zip and DMG SHA-256 values from `release_check.sh` are recorded in Notes.
- [ ] The worktree contains no unrelated local changes.

## GitHub Release Gate

- [ ] `.github/workflows/release-candidate.yml` is present and uses the same
      `./script/release_check.sh` gate.
- [ ] The workflow uploads both `Docking-0.0.4-macos26.zip` and
      `Docking-0.0.4-macos26.dmg` with their `.sha256` files.
- [ ] Tag-triggered runs create/update only draft Release assets, and leave
      already-published Release assets unchanged.
- [ ] If `Casks/docking.rb` changes, its checksum comes from the Actions-built
      release DMG; otherwise the post-publication cask update is recorded as
      follow-up.

## Manual QA

- [ ] Review [QA.md](QA.md) and either complete the remaining target-machine
      checks or leave them explicitly accepted as current pre-release limitations.
- [ ] Confirm no user-specific paths, names, screenshots, or identifiers are
      being introduced in the PR body or attached artifacts.

## Notes

<!-- Keep this section factual. Record verification dates, known limitations,
and anything intentionally not pushed or not notarized yet. -->
