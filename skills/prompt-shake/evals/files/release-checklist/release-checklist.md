---
name: release-checklist
description: Use when cutting a release of the Android app.
---

# Release checklist

- Bump versionCode in app/build.gradle.kts; Play rejects an upload that reuses a code.
- Be careful and thorough.
- Tag the release commit `vX.Y.Z` only after the Play upload succeeds, never before.
- Always increase versionCode before building a release, or Play Console rejects the upload.
