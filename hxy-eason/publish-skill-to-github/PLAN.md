# Personal Skill Publisher: publish-skill-to-github

## Summary

开发一个 Codex skill：`publish-skill-to-github`。V1 是个人 Skill 发布工具，用本机 GitHub CLI 登录态，把本地 Codex skill 校验后发布到 `D:\skills\skills-repo`，推送到 `https://github.com/Hxy-Eason/skills.git`，创建 PR、自动合并到 `main`，并清理临时分支。V1 从一开始采用作者命名空间目录，为 V2/V3 社区投稿和 registry 做好结构准备。

长期定位不应局限于 Codex。这个项目最终应沉淀为面向 vibe coding 工程师的跨工具 skill/workflow 发布能力：Codex、Claude Code、OpenCode/OpenClaw、Cursor 或其他 agent 软件都可以复用同一套核心校验、打包、发布脚本，只是在各自工具中提供不同的入口适配层。

## Repository Layout

- V1 默认作者身份：
  - `authorId`: `hxy-eason`
  - `namespace`: `hxy-eason`
- 目标仓库结构：

```text
Hxy-Eason/skills
  hxy-eason/
    cjk-encoding-guard/
    publish-skill-to-github/
```

- 未来社区结构：

```text
Hxy-Eason/skills
  hxy-eason/
    cjk-encoding-guard/
  jack/
    pdf-workflow/
    browser-helper/
  lucy/
    data-cleanup/
```

同一上传者多次上传不同 skill 时，全部放到同一个 namespace 下，例如 `jack/<skill-name>/`，不会重复创建多个独立身份目录。

V2/V3 身份模型不能依赖用户名本身：

- 稳定身份使用 `userId`、GitHub account id 或 Vault 内部 id。
- 仓库路径使用可读 `namespace`。
- 用户改名后，平台仍通过稳定 `userId` 找到同一作者，再决定新 skill 放到当前 namespace，或触发 namespace 迁移策略。

V1 脚本先固定 `hxy-eason`，但参数和 manifest 思路按 `<namespace>/<skill-name>/` 设计。

## Key Changes

- 创建 skill 目录：`D:\skills\publish-skill-to-github`。
- 编写 `SKILL.md`：
  - 中文说明为主，面向中国社区可读。
  - 工程接口、参数名、字段名使用英文。
  - 明确默认仓库、默认 namespace、发布流程、安全检查、失败恢复。
- 添加脚本：
  - `scripts/validate_skill.ps1`
    - 输入：`-SkillPath <path> [-Json]`
    - 校验 `SKILL.md`、frontmatter、目录名、敏感文件、密钥痕迹、大文件、缓存目录、乱码风险。
  - `scripts/publish_skill.ps1`
    - 输入：`-SkillPath <path> [-RepoPath D:\skills\skills-repo] [-RemoteUrl https://github.com/Hxy-Eason/skills.git] [-Namespace hxy-eason] [-Mode auto|add|update] [-DryRun]`
    - 默认目标路径：`<RepoPath>\<Namespace>\<skill-name>`
    - 默认分支：`add-<namespace>-<skill-name>` 或 `update-<namespace>-<skill-name>`。

## Multi-Agent Compatibility

V1 的可执行核心必须尽量工具无关：

- `scripts/validate_skill.ps1` 和 `scripts/publish_skill.ps1` 不依赖 Codex runtime，只依赖 PowerShell、git、GitHub CLI。
- `SKILL.md` 是 Codex 入口，但不是唯一入口；它只是调用同一套脚本的一个适配层。
- 后续可以增加不同工具的薄适配层：
  - Codex：`SKILL.md`。
  - Claude Code：`CLAUDE.md` 片段或 `.claude/commands/publish-skill.md`。
  - Cursor：`.cursor/rules/publish-skill.mdc` 或项目规则说明。
  - OpenCode/OpenClaw 等工具：对应的 command/rule/workflow 描述文件。
- 仓库中的 canonical source 应是脚本、manifest 和通用说明；各 agent 的入口文件只描述“何时触发、如何调用、注意事项”。
- V2 投稿包也应保持 agent-agnostic：`manifest.json`、`author.json`、`checks.json` 不绑定 Codex，只记录能力类型、作者身份、校验结果、目标 namespace 和安装/使用入口。

## Safety Rules

- 阻断包含 `.env`、私钥、证书、token-like 字符串、`node_modules`、缓存目录、构建产物、超大文件的 skill。
- `.git` 目录允许存在于源 skill 中，但发布时会被忽略，绝不复制到目标仓库。
- 阻断明显 mojibake、替换字符、疑似中文乱码污染。
- 阻断缺失 `SKILL.md` 或 frontmatter 关键字段的 skill。
- 阻断目标仓库 dirty working tree，避免覆盖人工改动。
- 不 force push `main`；所有变更只通过临时分支和 PR 进入 `main`。
- 中途失败时输出中文恢复提示：当前分支、PR URL、远端分支名、建议清理命令。

## V2/V3 Preparation

- V2：skill 变成投稿包生成器：
  - 本地生成 `skill/`、`manifest.json`、`author.json`、`checks.json`、`README.md`。
  - `author.json` 记录稳定 `userId` 和当前 `namespace`。
  - 投稿包不包含 GitHub token、密钥、缓存、构建产物。
- V2：Vault 后端代上传：
  - 后端重新严格校验投稿包。
  - 根据稳定 `userId` 查作者身份和当前 namespace。
  - 写入 `<namespace>/<skill-name>/`。
  - 用 GitHub App 或维护者 token 创建 PR。
- V3：社区 Skill Registry：
  - 作者页、版本管理、安装命令生成、审核后台、安全评分、热门推荐、GitHub PR 状态同步。
  - 用户改名由平台身份映射处理，不以旧目录名作为唯一身份依据。

## Test Plan

- Dry run：
  - 用 `D:\skills\cjk-encoding-guard` 验证计划输出，确认目标为 `hxy-eason/cjk-encoding-guard/`。
- 正向测试：
  - 用 disposable test skill 跑通发布、PR、merge、删除分支、回到干净 `main`。
- 负向测试：
  - 缺少 `SKILL.md` 会阻断。
  - 包含 `.env` 或伪造密钥会阻断。
  - 包含明显乱码或替换字符会阻断。
  - `skills-repo` dirty working tree 会阻断。
- Skill 自身校验：
  - 用 `skill-creator` 的 `quick_validate.py` 校验 `D:\skills\publish-skill-to-github`。

## Assumptions

- V1 只给个人使用，依赖本机 GitHub CLI 登录态。
- V1 默认 namespace 是 `hxy-eason`。
- `https://github.com/Hxy-Eason/skills.git` 是长期社区总仓库。
- 社区投稿、用户身份映射、Vault 后端审核、作者改名迁移策略在 V2/V3 详细设计。
