# Error Handling & Constraints

## Error Quick Reference

| Symptom                               | Cause                                      | Resolution                                                                    |
|---------------------------------------|--------------------------------------------|-------------------------------------------------------------------------------|
| `check_env.sh` exit code 2            | CLI not installed / version too old        | `brew install aliyun-cli`                                                     |
| `check_env.sh` exit code 3            | Invalid credentials                        | Run `aliyun configure` in a separate terminal                                 |
| `check_env.sh` exit code 6            | AK identity probe failed                   | Check AK status in RAM console                                                |
| `InvalidTemplate`                     | YAML syntax error                          | Read Message and fix template                                                 |
| `InsufficientStock`                   | Out of stock                               | Provide 2-3 alternatives (larger instance type / different region)            |
| `InvalidParameter`                    | Password doesn't meet requirements         | Regenerate a strong password                                                  |
| Stack rollback `ROLLBACK_COMPLETE`    | Resource creation failed                   | Use `ListStackResources` to locate the failed resource                        |
| Health check fails but stack succeeds | UserData hasn't finished / app not started | Check `/var/log/qwencloud-bootstrap.log`                                      |
| `/healthz` passes but `/` returns 502 | Backend crashed, Nginx masking the failure | Check `/var/log/qwencloud-app.log`                                            |
| `DELETE_FAILED`                       | Resource occupied externally               | Manual cleanup via ROS console                                                |
| Password lost                         | `.local` file accidentally deleted         | Reset password via ECS/RDS console                                            |
| RunCommand timeout                    | Cloud Assistant not responding             | Check ECS status and `DescribeCloudAssistantStatus`                           |
| RunCommand permission denied          | Missing `ecs:RunCommand` permission        | Add `AliyunECSFullAccess` or grant precise permissions                        |
| App not starting after hot update     | Issue with new version artifacts           | Check remote log `/var/log/qwencloud-update.log`, fix and re-run hot update   |
| Cloud Assistant unavailable           | Not installed or not started               | `systemctl start aliyun.service`                                              |
| Security group port 80 not open       | Rule missing                               | Add inbound TCP 80 rule in ECS console                                        |
| Certbot DNS-01 TXT not found          | TXT record not yet propagated              | Wait longer (up to 5min), verify with `dig +short _acme-challenge.DOMAIN TXT` |
| Certbot "too many failed auth"        | Rate limited by Let's Encrypt              | Wait 1 hour, then retry                                                       |
| RDS `InvalidDBInstanceClass`          | Instance class unavailable                 | Check available classes in RDS console                                        |
| RDS availability zone not supported   | ECS has stock but RDS doesn't              | Re-run `check_stock.sh` with `DB_INSTANCE_CLASS`                              |
| `QuotaExceed.Instance`                | Quota full                                 | Clean up idle instances or request quota increase                             |

## Constraints

**Templates & API**:

- ROS must use `--TemplateURL` (`--TemplateBody` is blocked by WAF)
- Availability zone must be obtained from `check_stock.sh`
- `DisableRollback=false` and `from=qwencloud` tag are mandatory
- Never skip `ValidateTemplate`

**Artifacts & OSS**:

- Temporary bucket is recorded in `.qwencloud-deploy`; `delete_stack.sh` depends on it for cleanup

**Passwords**:

- Special characters limited to `!@%^*+=_-` (`& # $ | ;` will break `db.env` source)
- ECS and RDS passwords are generated separately, recorded separately, and never shown in chat

**Health Check**:

- `/healthz` only proves Nginx is alive, not the backend — health check must pass both gates
- Do not guess API route prefixes

**RDS**:

- MySQL 8.0 only — PG/Redis/MongoDB not supported
- Single AZ; password must not be reused from ECS
- `Fn::Sub` main script uses base64 encoding injection, decoded + sourced at runtime to avoid shell variable conflicts
  with Fn::Sub

## Current Limitations

- Full-stack uses pay-as-you-go only; subscription (prepaid) not supported
- HTTPS always uses DNS-01 validation (TXT record based)
- Single region
