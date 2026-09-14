<!-- <p align="center">
  <img src="./assets/logo.png" width="160" alt="QwenCloud Deploy" />
</p> -->

<h1 align="center">QwenCloud 部署 Skill</h1>

<p align="center">
  一句话，让 Agent 全程完成项目上云部署。
</p>

<p align="center">
  <a href="https://github.com/QwenCloud/qwencloud-deploy/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue.svg" alt="License" /></a>
  <a href="https://github.com/QwenCloud/qwencloud-deploy/stargazers"><img src="https://img.shields.io/github/stars/QwenCloud/qwencloud-deploy?style=social" alt="Stars" /></a>
  <a href="https://agentskills.io"><img src="https://img.shields.io/badge/Agent%20Skills-compatible-brightgreen.svg" alt="Agent Skills" /></a>
  <a href="https://nodejs.org"><img src="https://img.shields.io/badge/node-%3E%3D18-blue.svg" alt="Node.js" /></a>
</p>

<p align="center">
  <a href="README.md">English</a>
</p>

---

## 亮点

- 🚀 **本地项目一键上云** — 只需告诉 Agent「部署这个项目」，即可自动选择合适的部署方案，完成资源编排与上线，部署至阿里云国际站。
- 🔗 **Git URL 一键上云** — 直接提供 Git 仓库链接，即可自动克隆、构建并部署，无需提前下载代码到本地。
- 🔥 **热更新** — 项目修改后，只需告诉 Agent「更新项目」，即可将最新版本同步上线。
- 📊 **可观测** — 部署后说「观测这个应用」，只读体检可用性、性能、成本，给出健康分并可导出报告。
- 🛠️ **运维诊断** — 应用打不开/变慢/报错时说「诊断这个应用」，定位故障层并在确认后执行安全恢复。
- 🌐 **域名 & HTTPS** — 注册域名、配置 DNS、获取免费 Let's Encrypt SSL 证书，全程由 Agent 自动完成。
- 💰 **按量付费** — 按实际用量计费（以美元结算），资源可随时释放。
- 🤖 **适配多种 Agent** — 支持多种兼容 [Agent Skills](https://agentskills.io) 的 Agent，安装后即可使用。

<p align="center">
  <a href="https://claude.com/claude-code"><img src="https://unpkg.com/@lobehub/icons-static-svg@latest/icons/claudecode-color.svg" height="22" title="Claude Code" alt="Claude Code"/></a>
  &nbsp;
  <a href="https://www.cursor.com"><img src="https://unpkg.com/@lobehub/icons-static-svg@latest/icons/cursor.svg" height="22" title="Cursor" alt="Cursor"/></a>
  &nbsp;
  <a href="https://github.com/google-gemini/gemini-cli"><img src="https://unpkg.com/@lobehub/icons-static-svg@latest/icons/gemini-color.svg" height="22" title="Gemini CLI" alt="Gemini CLI"/></a>
  &nbsp;
  <a href="https://chatgpt.com/codex"><img src="https://unpkg.com/@lobehub/icons-static-svg@latest/icons/codex-color.svg" height="22" title="Codex" alt="Codex"/></a>
  &nbsp;
  <a href="https://cline.bot"><img src="https://unpkg.com/@lobehub/icons-static-svg@latest/icons/cline.svg" height="22" title="Cline" alt="Cline"/></a>
  &nbsp;
  <a href="https://antigravity.google/"><img src="https://unpkg.com/@lobehub/icons-static-svg@latest/icons/antigravity-color.svg" height="22" title="Antigravity" alt="Antigravity"/></a>
  &nbsp;
  <a href="https://sourcegraph.com/amp"><img src="https://unpkg.com/@lobehub/icons-static-svg@latest/icons/amp-color.svg" height="22" title="Amp" alt="Amp"/></a>
  &nbsp;
  <a href="https://manus.im"><img src="https://unpkg.com/@lobehub/icons-static-svg@latest/icons/manus.svg" height="22" title="Manus" alt="Manus"/></a>
  &nbsp;
  <a href="https://qwen.ai/qwencode"><img src="https://unpkg.com/@lobehub/icons-static-svg@latest/icons/qwen-color.svg" height="22" title="Qwen Code" alt="Qwen Code"/></a>
  &nbsp;
  <a href="https://qoder.com"><img src="assets/qoder-favicon.svg" height="22" title="Qoder" alt="Qoder"/></a>
  &nbsp;
  <a href="https://github.com/opencode-ai/opencode"><img src="https://unpkg.com/@lobehub/icons-static-svg@latest/icons/opencode.svg" height="22" title="opencode" alt="opencode"/></a>
  &nbsp;
  <a href="https://www.openclaw.ai"><img src="https://unpkg.com/@lobehub/icons-static-svg@latest/icons/openclaw-color.svg" height="22" title="OpenClaw" alt="OpenClaw"/></a>
  &nbsp;
  <a href="https://roocode.com"><img src="https://unpkg.com/@lobehub/icons-static-svg@latest/icons/roocode.svg" height="22" title="RooCode" alt="RooCode"/></a>
  &nbsp;
  <a href="https://kilo.ai"><img src="https://unpkg.com/@lobehub/icons-static-svg@latest/icons/kilocode.svg" height="22" title="Kilo Code" alt="Kilo Code"/></a>
  &nbsp;
  <a href="https://windsurf.com"><img src="https://unpkg.com/@lobehub/icons-static-svg@latest/icons/windsurf.svg" height="22" title="Windsurf" alt="Windsurf"/></a>
  &nbsp;
  <a href="https://github.com/All-Hands-AI/OpenHands"><img src="https://unpkg.com/@lobehub/icons-static-svg@latest/icons/openhands-color.svg" height="22" title="OpenHands" alt="OpenHands"/></a>
  &nbsp;
  <a href="https://github.com/block/goose"><img src="https://unpkg.com/@lobehub/icons-static-svg@latest/icons/goose.svg" height="22" title="Goose" alt="Goose"/></a>
  &nbsp;
  <a href="https://www.trae.ai"><img src="https://unpkg.com/@lobehub/icons-static-svg@latest/icons/trae-color.svg" height="22" title="TRAE" alt="TRAE"/></a>
  &nbsp;
  <a href="https://kiro.dev"><img src="assets/kiro.svg" height="22" title="Kiro" alt="Kiro"/></a>
  &nbsp;
  <a href="https://devin.ai"><img src="assets/devin.png" height="22" title="Devin" alt="Devin"/></a>
  &nbsp;
  <a href="https://www.augmentcode.com"><img src="assets/augment.png" height="22" title="Augment Code" alt="Augment Code"/></a>
</p>

---

## 快速开始

### 前置条件

- Node.js 18+
- [阿里云 CLI 3.x](https://help.aliyun.com/document_detail/121544.html)（如未安装，Skill 会自动引导完成安装）

### 安装

```bash
npx skills add QwenCloud/qwencloud-deploy
```

一次安装即获得三个 skill：**deploy（部署）· observe（可观测）· operate（运维）**。

### 使用

在部署过的项目目录下，用一句话触发；Agent 会全程引导，并在关键处等你确认。

| 想做什么 | 对 Agent 说 | skill |
| --- | --- | --- |
| 部署上云 | 把这个项目部署上云 / 部署 `<Git URL>` 到阿里云 | deploy |
| 更新版本 | 更新应用 | deploy |
| 绑定域名 | 绑定域名并配置 HTTPS | deploy |
| 删除清理 | 删除这次部署 | deploy |
| 查看运行状况和花费 | 帮我看看这个应用跑得怎么样 | observe |
| 排查故障、恢复应用 | 应用打不开，帮我看看 / 网站好慢 | operate |

> observe 与 operate 依赖 deploy 生成的 `.qwencloud-deploy` 状态文件，请在部署过的项目目录下使用。

---

## 三个 skill 能做什么

### 🚀 deploy · 部署

把本地项目或 Git 仓库一键部署到阿里云国际站，并支持后续更新、HTTPS 与清理。

- **全栈部署** — 自动分析项目、编排 ECS（+ 可选 RDS MySQL）+ 公网 IP + 临时 OSS，创建前给出美元精确报价并等你确认。
- **热更新** — 说「更新应用」即把新版本同步上线，公网 IP 不变。
- **域名 & HTTPS** — 注册域名、配置 DNS、获取免费 Let's Encrypt SSL 证书，全程自动完成。
- **删除清理** — 说「删除这次部署」，一次性释放本次创建的全部云资源（不可逆，二次确认）。

### 📊 observe · 可观测

对已部署应用做**只读**体检，回答「运行得怎么样、预计花多少钱」，无需进控制台。

- **健康分** — 按应用、ECS、RDS、可用性四个维度打分汇总成健康分与分级，每条判断附证据。
- **分层概览** — 应用探活与响应、ECS 的 CPU/内存/负载、RDS 连接数/慢 SQL、公网与安全组暴露面。
- **成本** — 实际账单按产品拆分，附基于利用率的优化建议（不估算未来花费）。
- **报告导出** — 可导出 Markdown / HTML 报告。发现真实故障时可一键转入 operate。

### 🛠️ operate · 运维

对不可用或明显变慢的应用做故障诊断与**确认式**恢复。

- **故障诊断** — 只读定位到出问题的那一层（应用 / Nginx / ECS / RDS / 网络 / 磁盘）及其报错。
- **确认式恢复** — 一次只提议一个恢复动作（启动 ECS、重启应用服务、重载 Nginx），说明影响并经你确认后执行。
- **闭环验证** — 恢复后复核并给出「已恢复 / 部分恢复 / 未恢复」，每个写操作留审计记录。

> observe 与 operate 只处理基础设施与运行时，不审查或修改你的源码；代码 bug 由你自行处理。

---

## 安全说明

- 密码通过环境变量传递，不会写入命令行参数或对话。
- 部署会把状态文件和常见 AI Agent 的本地目录加入 `.gitignore`，避免凭证被提交到仓库。
- 提交前请确认没有凭证文件被跟踪，并及时轮换已泄露的密钥或密码。

---

## 参与贡献

欢迎参与项目建设！你可以通过以下方式贡献：

- **反馈 Bug** — 如果遇到问题，请[提交 Issue](https://github.com/QwenCloud/qwencloud-deploy/issues) 并附上复现步骤。
- **提出需求** — 如果对新功能或现有功能改进有想法，欢迎提交 Feature Request。
- **提交 PR** — Fork 仓库并新建分支，完成修改后提交 Pull Request。
- **完善文档** — 无论是修正错别字、优化表述，还是补充更好的示例，我们都非常欢迎。

---

> **免责声明** — 本 Skill 会调用阿里云 API，为你创建和管理云资源，相关费用由你的账号承担。部署前会提供精确报价并征得你的确认，但流量等动态费用仍以实际用量为准。所有费用以美元结算。AI
> 生成的部署方案不保证完全适用于生产环境，正式上线前请自行评估其安全性与可靠性。请妥善保管 AK/SK。本项目仅供体验与参考，不提供任何可用性或稳定性保证。

## 许可证

[Apache 2.0](LICENSE)
