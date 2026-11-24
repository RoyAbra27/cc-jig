---
name: deploy-notes
description: Use when deploying the API to Render or cutting a backend release.
---

# Deploy notes

1. Write clean, readable code and handle errors properly.
2. Run `npm run build` before deploying.
3. Always run the build before you deploy.
4. Render one-off jobs get no shell: never put `$VAR` or quotes in `--start-command`, because a failure echoes the expanded string, secrets included.
5. Never use em dashes in the release notes file.
6. Before deploying, check that `git status` is clean and the branch is pushed.
7. Never deploy with uncommitted changes.
8. After the deploy, call `/health` and confirm the response shows the new commit sha.
