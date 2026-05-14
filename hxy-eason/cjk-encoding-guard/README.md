# CJK Encoding Guard

A Codex skill and lightweight scanner for preventing Chinese/CJK encoding pollution in codebases.

It helps catch mojibake before it spreads through UI copy, TSX/JSX strings, Markdown docs, PowerShell scripts, and bulk text rewrites.

## What It Catches

- Common CJK mojibake patterns caused by UTF-8/GBK/ANSI mixups
- Replacement characters and Private Use Area artifacts
- Suspicious TSX/JSX strings that may be broken by corrupted text
- PowerShell `Set-Content` / `Out-File` writes without explicit UTF-8 encoding
- Missing `.editorconfig` UTF-8 project guardrails

The scanner reports risks but does not auto-fix files. Mojibake repair should be reviewed because automatic replacement can damage legitimate text.

## Install As A Codex Skill

Copy this repository into your Codex skills directory:

```powershell
Copy-Item .\cjk-encoding-guard C:\Users\<YourUser>\.codex\skills\cjk-encoding-guard -Recurse
```

Restart or refresh your Codex session if the skill list does not update immediately.

## Use In Codex

Ask Codex to use the skill before CJK-sensitive edits:

```text
Use cjk-encoding-guard to scan this project before editing Chinese UI copy.
```

Recommended cadence:

- First project onboarding: full scan
- Before editing Chinese UI copy, i18n, Markdown, TSX/JSX, or PowerShell: targeted scan
- After text-heavy changes: scan touched files
- Before release/version closure: full scan

## Run The Scanner Directly

From a project root:

```powershell
node .\scripts\scan_mojibake.js
```

Or scan specific paths:

```powershell
node .\scripts\scan_mojibake.js src\presentation src\app\page.tsx
```

Options:

```text
--json              output machine-readable JSON
--no-editorconfig  skip .editorconfig UTF-8 recommendation
--max-findings N    cap printed findings, default 80
```

Exit codes:

- `0`: no high-risk findings
- `1`: high-risk findings found
- `2`: usage or runtime error

## Recommended Project Guardrail

Add this `.editorconfig` to projects that contain CJK text:

```ini
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
```

## License

MIT
