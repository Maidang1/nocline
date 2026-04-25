# Release Notes

Place one Markdown file per release in this directory.

Naming convention:

- `1.0.6.md`
- `1.1.0.md`

The release script reads from:

- `docs/release-notes/<version>.md`

The release workflow publishes release note assets to:

- `docs/release-notes-signed/<AppName>-<version>.md`

Each release note should describe:

- user-visible changes
- fixes and regressions addressed
- upgrade notes when relevant

Keep the file name aligned with `MARKETING_VERSION` in the Xcode project before running `./scripts/create-release.sh <version>`.

This repository publishes the appcast and generated release note assets through GitHub Pages:

- `https://maidang1.github.io/nocline/appcast.xml`
- `https://maidang1.github.io/nocline/release-notes-signed/`
