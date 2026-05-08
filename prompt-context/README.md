# `prompt-context/` — local-only context drop

Drop images, screenshots, PDFs, or anything else here that you want to feed
into a chat prompt as context. **Nothing in this folder is committed** —
only this README is tracked.

## How it's wired

The `.gitignore` rule at the repo root is:

```
prompt-context/*
!prompt-context/README.md
```

Every file inside is ignored except this README. So on a fresh clone the
folder exists with this note, and once you start dropping images they stay
on your machine only.

## Suggested workflow

1. Take a screenshot or save an image into `prompt-context/`.
2. Reference it in your prompt by absolute path:
   ```
   D:\Downloads\hermes-agent-setup\prompt-context\my-screenshot.png
   ```
   Or relative if the agent is rooted at the repo:
   ```
   prompt-context/my-screenshot.png
   ```
3. The agent reads it via the `Read` tool (Claude Code, Cursor) or as an
   inline attachment. Its contents stay local — nothing leaves your machine
   unless you upload it somewhere else.

## Safety check

```bash
git status --short prompt-context/    # should be empty even with files inside
git check-ignore -v prompt-context/foo.png   # confirms the rule matched
```

If `git status` ever shows a file in here, the gitignore rule got broken —
double-check the rule above is intact in the repo root `.gitignore`.
