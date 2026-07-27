---
name: qwencloud-deploy
version: "2.1"
description: >-
  One-click deploy, publish, and update a local project or Git repository to Alibaba Cloud
  International (alibabacloud.com), producing an accessible online service with a public IP.
  Supports full-stack ROS orchestration, automatic cloud-resource provisioning, pre-deployment
  price confirmation, service health checks, deployment-state recording, hot updates, and
  optional domain + HTTPS setup.
  Use when: the user asks to deploy a project to the cloud, put an app online, publish a
  website, generate an access URL, deploy a Git repo, or update an online version and has NOT
  named a specific cloud platform; or the user mentions "Alibaba Cloud", "alibabacloud.com",
  or the international site.
  Do not use when: the user explicitly targets Aliyun China (aliyun.com), AWS, GCP, Azure, or
  another specific cloud platform.
trigger: >-
  Use when the user asks to deploy a project to the cloud, put an app online, publish a website,
  generate an access URL, deploy a Git repo, or update an online version — and has NOT specified
  a particular cloud platform. Also use when the user mentions "Alibaba Cloud", "alibabacloud.com",
  or the international site.
skip: >-
  Do NOT use when the user explicitly targets Aliyun China (aliyun.com), AWS, GCP, Azure,
  or another specific cloud platform.
prerequisites:
  - aliyun CLI 3.x configured with international-site AK/SK
input: >-
  A local project directory, Git URL, or an existing deployment state file (.qwencloud-deploy).
  Optional: user preferences for instance type, region, database.
output: >-
  A running cloud service with public IP (or domain + HTTPS), deployment state file
  (.qwencloud-deploy), and success card with access URL, cost summary, and next-step guidance.
---

# Qwen Cloud Deploy

## Quick Path (Read First)

1. **Route the task** — Match the user's intent to one of 4 modes (see *Task Routing*):
   Full-Stack Deploy · Hot Update · Delete/Cleanup · HTTPS Setup.
2. **Deploy (default)** — Run the scripts under `scripts/` in order: environment check → project analysis → resource
   planning + price confirmation → create stack → health check → record state. Each step maps to one script; never
   retype logic, always call the script.
3. **Confirm cost before creating anything** — Always present hourly price in **USD** and get explicit user confirmation
   before provisioning resources.
4. **Record state** — On success write `.qwencloud-deploy`; reuse it for hot updates and deletes.

Deep detail lives in `reference/` (see *File Layout*). Read only the reference file relevant to the current step.
Everything below expands on this quick path.

## Scope & Limitations

**In scope**

- Deploying local projects or Git repos to **Alibaba Cloud International (alibabacloud.com)**.
- Full-stack ROS orchestration, hot updates, resource cleanup, and optional domain + HTTPS.
- Auto-provisioning ECS (+ optional RDS), OSS artifact upload, and public-IP service exposure.

**Out of scope / do not use**

- **Aliyun China (aliyun.com)** — use the `qianwenai-deploy` skill instead.
- **AWS, GCP, Azure**, or any other cloud platform.
- Kubernetes / serverless / container-service orchestration (this skill targets single-ECS + ROS).
- Collecting AK/SK credentials via chat — credentials must be preconfigured in the `aliyun` CLI.

**Assumptions**

- `aliyun` CLI 3.x is installed and configured with international-site AK/SK.
- Default region is `ap-southeast-1` (Singapore) unless the user specifies otherwise.

## Capability Contract

This skill accepts a deployment task and returns a running cloud service. The supervisor (agent) calls this skill with a
project context and receives back:

| Input                          | Output                                     |
|--------------------------------|--------------------------------------------|
| Local project / Git URL        | Public IP + running service                |
| Existing deployment + changes  | Updated service (hot update, same IP)      |
| "delete" / "cleanup" intent    | All resources released, state file removed |
| "bind domain" / "HTTPS" intent | Domain configured + SSL certificate active |

The skill exposes **4 task modes** — the agent routes to the correct one based on context:

---

## Task Routing

| Signal                                                    | Task Mode             |
|-----------------------------------------------------------|-----------------------|
| `.qwencloud-deploy` exists + user says "update"           | **Hot Update**        |
| `.qwencloud-deploy` exists + "delete"/"cleanup"/"release" | **Delete / Cleanup**  |
| "bind domain"/"HTTPS"/"SSL" (deployment exists)           | **HTTPS Setup**       |
| Git URL or local project (no existing deployment)         | **Full-Stack Deploy** |

> ⚠️ After entering Phase 2 (existing deployment detection) in full-stack deploy, the flow may
> jump to Hot Update based on scan results — see Phase 2 details.

On trigger, display the welcome message first (see `reference/interaction_rules.md`), then start after user confirms.

---

## Full-Stack Deploy

Three phases, each a self-contained unit with clear inputs/outputs:

### Phase 1 · Preparation (Steps 1–3)

**Goal**: Validate environment, resolve project source, analyze project structure.

| Step | Action                 | Script / Tool                       | Output                              |
|------|------------------------|-------------------------------------|-------------------------------------|
| 1    | Environment check      | `bash scripts/check_env.sh`         | CLI version, region, credentials OK |
| 2    | Git clone (if Git URL) | `git clone --depth 1 <url> /tmp/…`  | Local project directory             |
| 3    | Project analysis       | `python scripts/analyze_project.py` | APP_NAME, app_type, ports, dirs     |

**Step 1 details**: Exit 2 = CLI not installed → guide. Exit 3 = invalid credentials → guide `aliyun configure`. Region
defaults to `ap-southeast-1` (Singapore) for international AKs.

**Step 2 details** (Git URL only): Supports `url#branch` suffix. On failure: distinguish network/auth/not-found. Never
collect tokens in chat.

**Step 3 details**: Script collects raw signals only — Agent determines: `APP_NAME`, `APP_DESC`, `app_type`,
`backend_entry`, `backend_port`, `frontend_dir`, `backend_dir`, `nginx_mode`. See `reference/project_type_guide.md` for
decision rules. When uncertain, confirm with user.

> ⚠️ After analysis: check for hardcoded secrets. If found, warn user (see `reference/interaction_rules.md`).

For Git URL sources, auto-execute build after this phase (npm build / go build / etc.).

### Phase 2 · Resource Planning (Steps 4–9)

**Goal**: Detect existing deployments, choose resources, validate feasibility, confirm cost.

| Step | Action                   | Script / Tool                                                       | Output                           |
|------|--------------------------|---------------------------------------------------------------------|----------------------------------|
| 4    | Existing deployment scan | `bash scripts/check_existing.sh`                                    | Route: new / hot-update / delete |
| 5    | Database identification  | Agent decision from step 3 signals                                  | DB_INSTANCE_CLASS (or skip)      |
| 6    | Instance type selection  | AskUserQuestion (3 options)                                         | INSTANCE_TYPE                    |
| 7    | Generate template        | `python scripts/generate_template.py`                               | Template YAML + userdata script  |
| 8    | Stock check              | `bash scripts/check_stock.sh`                                       | ZONE_ID confirmed                |
| 9    | Validate + cost estimate | `upload_artifacts.py` + `validate_template.sh` + `estimate_cost.sh` | Hourly price in USD              |

**Step 4**: If existing found → AskUserQuestion: Hot update (recommended) / Delete & redeploy. **Step 5**: MySQL
signals → AskUserQuestion: Create RDS / Skip. Options: 1C2G ~$0.02/hr, 2C4G ~$0.04/hr, 4C8G ~$0.07/hr.
**Step 6**: AskUserQuestion: 2C2G ~$0.02/hr, 2C4G ~$0.04/hr, 4C8G ~$0.11/hr. **Step 7**: Artifact URLs empty at this
point (filled in step 10). **Step 8**: When stock insufficient → provide 2–3 alternatives with trade-offs. With RDS:
pass `DB_INSTANCE_CLASS`. **Step 9**: Creates temporary OSS bucket — inform user first. ROS uses `--TemplateURL` (WAF
blocks TemplateBody). Currency: always USD. Present hourly price + full resource list via AskUserQuestion for
confirmation.

### Phase 3 · Execution (Steps 10–13)

**Goal**: Upload artifacts, create stack, health-check, record state.

| Step | Action                   | Script / Tool                                                 | Output                         |
|------|--------------------------|---------------------------------------------------------------|--------------------------------|
| 10   | Upload artifacts + regen | `python scripts/upload_artifacts.py` + `generate_template.py` | Artifact URLs + final template |
| 11   | Create stack             | `bash scripts/create_stack.sh`                                | STACK_ID                       |
| 12   | Wait + health check      | `bash scripts/wait_stack.sh` + curl                           | Service live confirmation      |
| 13   | Record state             | `python scripts/record_state.py`                              | `.qwencloud-deploy` written    |

**Step 10**: Pipe artifact URLs via `--artifacts-json` — never copy-paste manually. **Step 11**: Stack name =
`qwencloud-${APP_NAME}-$(date +%Y%m%d%H%M)` — generate **once**, reuse on retry. Password: ≥12 chars, special chars
limited to `!@%^*+=_-`, never shown in chat. **Step 12**: Exit 0 = success; 2 = failed (check ListStackResources); 3 =
timeout. Health check: wait 30s → curl /healthz (retry 12x) → curl / (502/504 = backend not up). Failure → Cloud
Assistant RunCommand to check logs (see `reference/cli_troubleshooting.md`). **Step 13**: Display success card. Then
present **Post-Deployment** card:
AskUserQuestion: Go live as-is (keep IP) / Bind a domain → if binding, see `reference/https_setup.md`.

---

## Hot Update

**Trigger**: `.qwencloud-deploy` exists + user wants to update code. IP unchanged, < 3 min.

| Step | Action                   | Script / Tool                        | Output                  |
|------|--------------------------|--------------------------------------|-------------------------|
| U1   | Build + upload artifacts | `python scripts/upload_artifacts.py` | New artifact URLs       |
| U2   | Deliver update           | `bash scripts/update_app.sh`         | Code replaced on ECS    |
| U3   | Health check + state     | curl + auto-write `updated_at`       | Hot update success card |

Reuses OSS bucket from initial deployment (`artifact_bucket` in state file). Update delivery: Cloud Assistant
RunCommand → pull to staging → stop → atomic swap → restart.

---

## Delete / Cleanup

**Trigger**: User says "delete", "cleanup", "release resources", "remove everything".

> ⚠️ **Irreversible** — confirm twice, clearly state scope. With RDS: warn data destruction.

> 🚫 **Never manually delete individual resources** — ROS manages all; just run `delete_stack.sh`.

```bash
bash scripts/delete_stack.sh --project-root . --yes
```

DeleteStack → poll until 404 → clean OSS → remove state file. If DELETE_FAILED: check
`aliyun ros ListStackResources` first, fix specific error, then re-execute.

If user stops mid-deployment → confirm → `delete_stack.sh --yes` (handles CREATE_IN_PROGRESS).

---

## HTTPS Setup (Optional)

Full instructions in `reference/https_setup.md`. Summary:

| Step | Action                   | Output                                 |
|------|--------------------------|----------------------------------------|
| H1   | Domain source            | Path A (own domain) / Path B (buy new) |
| H2   | Domain purchase (Path B) | Registered domain                      |
| H3   | DNS configuration        | A record → public IP                   |
| H4   | Verify DNS               | Resolution confirmed                   |
| H5   | Certbot + HTTPS          | SSL certificate active                 |
| H6   | Verify + update state    | HTTPS success card                     |
| H7   | CORS reminder            | User warned about origin change        |

---

## Key Constraints (Quick Reference)

| Constraint          | Rule                                                          |
|---------------------|---------------------------------------------------------------|
| Currency            | Always USD — never CNY/¥                                      |
| AK/SK collection    | Never via chat                                                |
| Domain price        | Never report a number — only share official `price_url`       |
| Template upload     | Must use `--TemplateURL` (WAF blocks TemplateBody)            |
| Stack name on retry | Reuse — never regenerate (prevents orphaned stacks)           |
| Resource deletion   | Always via `delete_stack.sh` — never manual                   |
| Region default      | `ap-southeast-1` for international AKs                        |
| Commands to user    | Never show underlying commands — user speaks natural language |

---

## File Layout

```
scripts/
  check_env.sh          check_existing.sh     analyze_project.py
  generate_template.py  check_stock.sh        upload_artifacts.py
  validate_template.sh  estimate_cost.sh      create_stack.sh
  wait_stack.sh         record_state.py       delete_stack.sh
  update_app.sh         lib/build_params.sh
  setup_domain.sh
reference/
  project_type_guide.md   error_handling.md   interaction_rules.md
  deploy_state_schema.json  cli_cheatsheet.md (index)
  cli_ros_deploy.md  cli_troubleshooting.md  cli_https.md
  https_setup.md
templates/
  ros_single[_rds].yaml
  userdata/{systemd,docker,nginx_proxy,nginx_static,nginx_static_proxy}.sh
```

**State files**: `.qwencloud-deploy` = current deployment state (cleaned on deletion);
`.aliyun-config.json/deploy` = user preferences (persists across deployments).

---

For detailed constraints, error handling, and CLI reference, see:

- `reference/error_handling.md` — error classification and recovery
- `reference/interaction_rules.md` — UX rules, cards, formatting
- `reference/cli_ros_deploy.md` — ROS CLI commands
- `reference/cli_troubleshooting.md` — debugging via Cloud Assistant
- `reference/https_setup.md` — domain purchase + HTTPS certificate flow
