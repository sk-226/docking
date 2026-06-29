# Docking 0.0.0 Pre-Release Candidate

## Scope

This PR is for the native macOS `Docking` 0.0.0 pre-release app candidate.

Apple Dock preferences remain overlay-only by default. Primary Dock mode is
opt-in, confirmation-gated, and restoreable from Control Center > Restore.

## Local Release Gate

- [ ] `./script/release_check.sh` passes on this branch.
- [ ] The generated artifact is `dist/Docking-0.0.0-macos26.zip`.
- [ ] The package SHA-256 from `release_check.sh` is recorded in Notes.
- [ ] The worktree contains no unrelated local changes.

## Manual QA

- [ ] Review [QA.md](QA.md) and either complete the remaining target-machine
      checks or leave them explicitly accepted as current 0.0.0 limitations.
- [ ] Confirm no user-specific paths, names, screenshots, or identifiers are
      being introduced in the PR body or attached artifacts.

## Notes

<!-- Keep this section factual. Record verification dates, known limitations,
and anything intentionally not pushed or not notarized yet. -->
