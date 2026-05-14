---
name: cjk-encoding-guard
description: Prevent and diagnose Chinese/CJK encoding pollution in codebases. Use before or after tasks involving Chinese UI copy, i18n text, TSX/JSX strings, Markdown docs, PowerShell scripts, bulk text rewrites, or any project that previously showed mojibake.
license: MIT
metadata:
  short-description: Guard CJK text from encoding pollution
---

# CJK Encoding Guard

Use this skill to prevent CJK text corruption, distinguish terminal display issues from real file pollution, and catch risky text-writing patterns before they derail development.

## When To Use

Run this skill as a lightweight quality gate, not as a ritual on every task.

Use a **full scan** when:
- A project is first onboarded.
- A release/version is being closed.
- The repo already shows mojibake or broken Chinese strings.
- A task includes broad text rewrites or encoding cleanup.

Use a **targeted scan** when:
- Editing Chinese/CJK UI copy, i18n files, Markdown docs, TSX/JSX text, or PowerShell scripts.
- Touching files that previously contained mojibake.
- Finishing a task that modified text-bearing files.

Skip the scan when the task is clearly unrelated to text encoding, such as a pure CSS spacing change, database query tweak, or English-only API field.

## Core Rules

1. **Separate display mojibake from real file mojibake.**
   - Display issue: the terminal renders normal UTF-8 bytes incorrectly.
   - Real pollution: source files contain suspicious mojibake sequences or replacement characters that the bundled scanner flags.
   - Do not edit files merely because PowerShell output looks garbled. Inspect bytes or use the scanner first.

2. **Scan before high-risk edits.**
   - Before changing CJK text in TSX/JSX/Markdown/PowerShell, run the scanner on the relevant files or the whole repo.
   - If high-risk findings already exist, report them and isolate cleanup from feature work.

3. **Avoid unsafe text writes on Windows.**
   - Prefer `apply_patch` for source edits.
   - Avoid `Set-Content`, `Out-File`, shell redirection, or ad hoc rewrite scripts for source files containing CJK text.
   - If PowerShell text output is unavoidable, explicitly use UTF-8, for example `Set-Content -Encoding utf8`.

4. **Do not mix cleanup with feature development.**
   - First establish the current encoding baseline.
   - Then clean real mojibake in a separate, reviewable change.
   - Only after lint/build pass should feature work continue.

5. **Centralize CJK UI copy when practical.**
   - For React/Next apps, prefer `src/presentation/i18n/zh-cn.ts` or an equivalent copy module over scattering large Chinese strings through TSX.
   - This reduces future scan scope and makes encoding cleanup safer.

## Scanner Usage

The bundled scanner is dependency-free Node.js:

```powershell
node C:\Users\Lenovo\.codex\skills\cjk-encoding-guard\scripts\scan_mojibake.js
```

Run from a project root for a full scan, or pass paths for a targeted scan:

```powershell
node C:\Users\Lenovo\.codex\skills\cjk-encoding-guard\scripts\scan_mojibake.js src\app src\presentation\components\shell.tsx
```

Useful flags:

```text
--json              output machine-readable JSON
--no-editorconfig  skip .editorconfig UTF-8 recommendation
--max-findings N    cap printed findings, default 80
```

Exit codes:
- `0`: no high-risk findings.
- `1`: high-risk mojibake, replacement characters, broken JSX/TSX-like strings, or unsafe PowerShell writes were found.
- `2`: scanner usage or runtime error.

## Interpreting Results

Treat findings this way:
- **high**: likely real file pollution or syntax-breaking text. Stop feature work and fix or report first.
- **medium**: risky practice, such as PowerShell writes without UTF-8. Fix before it spreads.
- **low**: project hygiene recommendation, such as missing `.editorconfig` UTF-8 setting.

The scanner intentionally does **not** auto-fix. Automatic mojibake repair is risky and can corrupt legitimate text. Fix only after confirming the intended wording from context, screenshots, previous commits, docs, or the user.

## Completion Checklist

Before finishing a CJK-sensitive task:
- Scanner has run on either the whole repo or all touched text-bearing files.
- No new high-risk findings were introduced.
- Existing unrelated mojibake is reported, not silently rewritten.
- `lint`/`build` or the repo's equivalent validation has passed when available.
