---
name: publish-skill-to-github
description: 校验并发布本地 Codex skill 到 GitHub skill 仓库。Use when the user wants to submit, upload, publish, update, or release a local Codex skill folder to Hxy-Eason/skills or a compatible GitHub repository through GitHub CLI, with safety checks for SKILL.md, secrets, mojibake, large files, cache/build artifacts, namespace layout, PR creation, merge, and branch cleanup.
---

# Publish Skill To GitHub

把本地 Codex skill 发布到 GitHub skill 仓库。V1 默认服务个人发布：校验本地 skill 后，把它复制到 `Hxy-Eason/skills` 的作者命名空间目录，创建 PR，合并到 `main`，并清理临时分支。

默认仓库结构：

```text
Hxy-Eason/skills
  hxy-eason/
    cjk-encoding-guard/
    publish-skill-to-github/
```

未来社区结构沿用同一规则：

```text
Hxy-Eason/skills
  <namespace>/
    <skill-name>/
```

`namespace` 是可读路径，不是稳定身份。多人社区场景下，稳定身份应由 Vault 的 `userId`、GitHub account id 或平台账号 id 判断；用户改名时，平台仍应通过稳定 ID 找到同一作者，再决定当前 namespace 和迁移策略。

## Quick Start

先做 dry run：

```powershell
D:\skills\publish-skill-to-github\scripts\publish_skill.ps1 -SkillPath D:\skills\cjk-encoding-guard -DryRun
```

正式发布：

```powershell
D:\skills\publish-skill-to-github\scripts\publish_skill.ps1 -SkillPath D:\skills\cjk-encoding-guard
```

只运行校验：

```powershell
D:\skills\publish-skill-to-github\scripts\validate_skill.ps1 -SkillPath D:\skills\cjk-encoding-guard
```

机器可读校验结果：

```powershell
D:\skills\publish-skill-to-github\scripts\validate_skill.ps1 -SkillPath D:\skills\cjk-encoding-guard -Json
```

## Defaults

- `RepoPath`: `D:\skills\skills-repo`
- `RemoteUrl`: `https://github.com/Hxy-Eason/skills.git`
- `Namespace`: `hxy-eason`
- `Mode`: `auto`
- Target path: `<RepoPath>\<Namespace>\<skill-name>`
- Branch:
  - new skill: `add-<namespace>-<skill-name>`
  - existing skill: `update-<namespace>-<skill-name>`

## Workflow

1. Resolve and validate the source skill directory.
2. Check `SKILL.md` exists and has frontmatter with `name` and `description`.
3. Block risky files, secrets, cache/build artifacts, oversized files, and suspicious CJK mojibake; ignore `.git` during publish.
4. Verify `git` and `gh` are available, and GitHub CLI is authenticated.
5. Verify the target repository remote matches `RemoteUrl`.
6. Stop if the target repository has uncommitted changes.
7. Checkout `main`, fetch, and pull `origin/main` with fast-forward only.
8. Create a temporary branch.
9. Copy the skill to `<namespace>/<skill-name>/`.
10. Stage only that target skill directory.
11. Commit, push, create PR, merge PR, delete remote branch, delete local branch.
12. Return the local repository to a clean updated `main`.

## Safety Rules

Stop publishing when any of these are found:

- Missing `SKILL.md`.
- Missing `name` or `description` in frontmatter.
- Skill folder name does not match frontmatter `name`.
- `.env`, private keys, certificates, `node_modules`, caches, build artifacts, or package install output.
- `.git` directories are ignored and never copied into the target repository.
- Token-like strings such as GitHub tokens, OpenAI keys, private key blocks, or common secret assignment patterns.
- Large files above the default threshold.
- Replacement characters or common mojibake sequences in text files.
- Dirty target repository working tree.

Never force-push `main`. All repository changes enter through a temporary branch and PR.

## Failure Recovery

If publishing fails after branch creation, report:

- current branch
- temporary branch name
- PR URL if one was created
- target path
- suggested cleanup commands

Do not hide partial state. The user should be able to inspect and clean up manually.

## V2 Preparation

Keep validation reusable. V2 should use the same checks when generating a community submission package:

```text
submission/
  skill/
  manifest.json
  author.json
  checks.json
  README.md
```

`author.json` should include a stable user identity and the current namespace. The Vault backend must re-run validation before creating a PR.
