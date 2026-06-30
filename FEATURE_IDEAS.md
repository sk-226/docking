# Feature Ideas

This file tracks useful ideas that are not implemented yet. Keep these out of
the README until they are real user-facing behavior.

## Folder Media Preview

Status: Not implemented.

When a folder stack is opened from the dock, media-like entries should be
previewable in the folder panel or an adjacent lightweight preview surface. The
first useful scope is HEIC, PDF, JPEG, and PNG files, because those are common
files people want to glance at without opening Finder or a full app.

This should use system-backed preview or thumbnail APIs where possible instead
of hand-rolling format decoders. HEIC and PDF are the important reason for that
constraint: simple image loading can make PNG/JPEG look easy while leaving the
formats that macOS already previews well either unsupported or inconsistent.

## Vertical Multi-Column Dock

Status: Not implemented.

When Docking is placed on the left or right edge, wide Calendar/Weather widget
presets intentionally make the dock wider. Compact widget presets avoid that,
but the extra width can also become a feature: let app items flow into two or
three columns in vertical dock mode.

The motivation is similar to current browser sidebars: a wider vertical surface
can show more always-available actions without becoming a long single column.
This should be opt-in so users who want a narrow side dock can keep the compact
single-column layout.
