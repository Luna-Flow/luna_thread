# Agent Guide

## Scope

This repository stores the MoonBit parallel FFI specification and its supporting review material.

## Commit Rules

- Use English Conventional Commits.
- Prefer `docs:` for documentation-only changes.
- Keep each commit focused on one logical unit.
- Do not mention file names or paths in the commit summary.
- Split the specification history by part:
  - English source first.
  - Chinese source after the matching English part.
  - Mark Chinese commits as translation updates.

## Document Workflow

- Treat `docs/moonbit-parallel-spec-en.typ` as the authoritative source.
- Keep `docs/moonbit-parallel-spec-zh.typ` as a strict mirror of the English text.
- Keep application/proposal drafts out of version control.
