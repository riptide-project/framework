---
title: Luau Directives Policy
description: Project rules for --!strict, lint suppressions, native compilation, and optimization directives.
---

# Luau Directives Policy

Riptide source and tests are strict by default.

Every `.lua` and `.luau` file under `src/` and `test/` must start with:

```lua
--!strict
```

Allowed directives:

- `--!strict` is required for framework source and tests.
- `--!native` may be used only after profiling shows a concrete benefit in Roblox runtime.
- `--!optimize` should normally be omitted. Roblox defaults are preferred unless a benchmark proves a reason to override them.
- `--!nolint` must be scoped and justified near the suppressed code.

Disallowed directives in framework source and tests:

- `--!nonstrict`
- `--!nocheck`
- broad file-level `--!nolint` without a documented reason

The Lune test suite includes a directive policy test that scans `src/` and `test/` and fails when a Luau file does not start with `--!strict`.
