# Server Troubleshooting Reference

How to debug ECS issues via Cloud Assistant or SSH when health checks fail.

## Server Troubleshooting (when health check gate 2 fails / 502)

Two logs to check: `/var/log/qwencloud-bootstrap.log` (UserData bootstrap process), `/var/log/qwencloud-app.log`
(application stdout/stderr).

### Preferred: Cloud Assistant RunCommand (no SSH needed)

ECS has a built-in Cloud Assistant — run shell commands directly without opening port 22 or needing a password:

```bash
# 1. Execute (PlainText — do NOT base64-encode CommandContent)
CID=$(PAGER=cat aliyun ecs RunCommand \
  --RegionId "$REGION" --InstanceId.1 "$INSTANCE_ID" --Type RunShellScript \
  --Timeout 60 --ContentEncoding PlainText \
  --CommandContent 'systemctl status qwencloud-app --no-pager; echo ---; tail -n 100 /var/log/qwencloud-app.log' \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["InvokeId"])')

# 2. Get results (async, poll until Finished)
sleep 8
PAGER=cat aliyun ecs DescribeInvocations --RegionId "$REGION" --InvokeId "$CID" --IncludeOutput true \
  | python3 -c 'import sys,json,base64; d=json.load(sys.stdin); r=d["Invocations"]["Invocation"][0]["InvokeInstances"]["InvokeInstance"][0]; print(base64.b64decode(r["Output"]).decode())'
```

> ⚠️ **Do NOT base64-encode `--CommandContent`**. Despite some documentation examples,
> Cloud Assistant with `--ContentEncoding PlainText` (default) expects a raw shell script
> string. Base64-encoded content will be executed literally as garbled commands.

`<ECS_INSTANCE_ID>` is from `ListStackResources` where `ResourceType=ALIYUN::ECS::Instance` → `PhysicalResourceId`.
Troubleshoot → edit config → `systemctl restart qwencloud-app` → re-check health — all can be done via RunCommand.

### Alternative: SSH (single-node only, when interactive shell is needed)

> ⚠️ **Passwords cannot be piped / heredoc'd to `ssh`**: `ssh root@<ip> "..." <<< "$PWD"` (or `<<EOF`) will repeatedly
> get `Permission denied` — password auth only accepts TTY input; stdin content is treated as "input to the remote
> command" not as the password. Must use `sshpass`:

```bash
# brew install hudochenkov/sshpass/sshpass
sshpass -p "$ECS_PWD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
  root@<PUBLIC_IP> "tail -n 100 /var/log/qwencloud-app.log"
```

Read password from `.qwencloud-deploy.local` — **never echo to chat**.

> ⚠️ `aliyun` CLI **does not have a `--no-pager` argument** (passing it will cause an error). In non-interactive
> environments, use `PAGER=cat aliyun ...` to disable paging.


