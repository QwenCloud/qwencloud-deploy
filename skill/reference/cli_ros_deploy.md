# aliyun CLI · Deployment API Reference

ROS, ECS, OSS, and STS/RAM commands used during full-stack deployment. For full documentation:
`aliyun <product> <Api> --help`.

## STS / RAM · Identity & Permission Verification (for pre-checks)

### GetCallerIdentity (Step 1 identity probe)

```bash
aliyun sts GetCallerIdentity
# {"AccountId":"1234567890","UserId":"...","Arn":"acs:ram::1234567890:user/deployer","RequestId":"..."}
```

Any valid AK can call this; if it fails → AK is expired or policy-denied.

### SimulatePrincipalPolicy (RAM permission simulation)

```bash
aliyun ram SimulatePrincipalPolicy \
  --PolicySourceArn 'acs:ram::1234567890:user/deployer' \
  --ActionNames 'ros:CreateStack,ecs:RunInstances,vpc:CreateVpc,oss:PutObject'
```

Returns `EvaluationResults.EvaluationResult[].EvalDecision`: `Allowed` / `ImplicitDeny` / `ExplicitDeny`. **The caller
itself needs `ram:SimulatePrincipalPolicy`** (simplest: attach `AliyunRAMReadOnlyAccess`); without this permission,
`check_env.sh` automatically falls back to the read-only probe combination below.

### Read-only Probes (RAM simulation fallback)

```bash
aliyun ros ListStacks --PageSize 1 --RegionId ap-southeast-1   # ROS reachable
aliyun ecs DescribeRegions                                  # ECS reachable
aliyun vpc DescribeRegions --AcceptLanguage en-US           # VPC reachable
aliyun oss ls -s                                            # OSS reachable
aliyun rds DescribeRegions                                  # RDS reachable (only with --with-rds)
```

If any returns 401/403/Forbidden → that product is unreachable for the current AK, write permissions cannot exist, fail
immediately.

## ROS · Templates & Stacks

### ValidateTemplate

```bash
aliyun ros ValidateTemplate \
  --RegionId ap-southeast-1 \
  --TemplateBody "$(cat template.yaml)"
```

Returns `Parameters`, `Resources`, `Outputs` structures. On error, exit code is non-zero with `Code` + `Message` in
stderr.

### GetTemplateEstimateCost

```bash
aliyun ros GetTemplateEstimateCost \
  --RegionId ap-southeast-1 \
  --TemplateBody "$(cat template.yaml)" \
  --Parameters.1.ParameterKey InstanceType \
  --Parameters.1.ParameterValue "$INSTANCE_TYPE" \   # User-selected instance type, e.g. ecs.e-c1m1.large / ecs.e-c1m2.large / ecs.e-c1m2.xlarge
  --Parameters.2.ParameterKey Password \
  --Parameters.2.ParameterValue 'Tmp_Pwd_For_Pricing_Only!1' \
  --Parameters.3.ParameterKey AppName \
  --Parameters.3.ParameterValue myapp
```

> Cost estimation requires all template Parameters **without default values** (including NoEcho Password — use a
> temporary password placeholder).
> Return structure: `Resources.<LogicalId>.Result.Order.OriginalAmount` (each resource's **hourly** amount in USD).
> Parsing example (get total hourly price):
> ```bash
> bash scripts/estimate_cost.sh "$REGION" "$TPL_URL" \
>   | python3 -c 'import json,sys; d=json.load(sys.stdin); print(sum(r["Result"]["Order"]["OriginalAmount"] for r in d["Resources"].values()))'
> ```
> Monthly estimate = total hourly price × 730; **does not include** public network traffic, snapshots, OSS storage,
> logs, or other dynamic costs.

### CreateStack

```bash
aliyun ros CreateStack \
  --RegionId ap-southeast-1 \
  --StackName qwencloud-myapp-202606081230 \
  --TemplateBody "$(cat template.yaml)" \
  --DisableRollback false \
  --TimeoutInMinutes 30 \
  --Tags.1.Key from \
  --Tags.1.Value qwencloud \
  --Tags.2.Key qwencloud-appName \
  --Tags.2.Value myapp \
  --Tags.3.Key qwencloud-appDesc \
  --Tags.3.Value 'My app description' \
  --Parameters.1.ParameterKey AppName --Parameters.1.ParameterValue myapp \
  --Parameters.2.ParameterKey InstanceType --Parameters.2.ParameterValue "$INSTANCE_TYPE" \
  --Parameters.3.ParameterKey Password --Parameters.3.ParameterValue 'My_Strong_Pwd_123!' \
  --Parameters.4.ParameterKey UserDataScript --Parameters.4.ParameterValue "$(cat /tmp/userdata.sh)"
```

Returns `{"StackId":"..."}`. **Tags must include `from=qwencloud`**. **DisableRollback must be false** (auto-rollback on
failure).

### GetStack (poll status)

```bash
aliyun ros GetStack --RegionId ap-southeast-1 --StackId <id>
```

Key fields: `Status` (CREATE_IN_PROGRESS / CREATE_COMPLETE / CREATE_FAILED / ROLLBACK_IN_PROGRESS / ROLLBACK_COMPLETE /
ROLLBACK_FAILED), `StatusReason`, `Outputs`.

### ListStackResources

```bash
aliyun ros ListStackResources --RegionId ap-southeast-1 --StackId <id>
```

Used for troubleshooting: which resource failed, ResourceType, PhysicalResourceId.

### DeleteStack

```bash
aliyun ros DeleteStack \
  --RegionId ap-southeast-1 \
  --StackId <id>
```

Default behavior: deletes the stack and all its resources (no retention). **This skill never passes
`--RetainAllResources` or `--RetainResources`**. Poll GetStack until it returns `StackNotFound` (HTTP 404) to confirm
deletion is complete.

## ECS · Stock & Images

### DescribeAvailableResource (stock query)

```bash
aliyun ecs DescribeAvailableResource \
  --RegionId ap-southeast-1 \
  --DestinationResource InstanceType \
  --InstanceType "$INSTANCE_TYPE" \
  --InstanceChargeType PostPaid   # pay-as-you-go, always PostPaid
```

Returns `AvailableZones[].Status`: `Available` / `SoldOut` / `WithStock`.

### DescribeImages (verify image ID exists)

```bash
aliyun ecs DescribeImages \
  --RegionId ap-southeast-1 \
  --ImageId aliyun_3_x64_20G_alibase_20240528.vhd
```

## OSS · Build Artifact Temporary Bucket

### Create temporary bucket (with 7-day expiration lifecycle)

```bash
aliyun oss mb oss://qwencloud-deploy-tmp-<random>/ --region ap-southeast-1
# lifecycle set via ossutil or PutBucketLifecycle
```

### Upload artifacts

```bash
aliyun oss cp /tmp/frontend.tar.gz oss://qwencloud-deploy-tmp-xxx/frontend.tar.gz
```

### Generate signed URL (used in UserData)

```bash
aliyun oss sign oss://qwencloud-deploy-tmp-xxx/frontend.tar.gz --timeout 86400
# Outputs an https URL that can be directly curled (valid for 24 hours)
```

### Clean up bucket (in sync with stack deletion)

```bash
aliyun oss rm oss://qwencloud-deploy-tmp-xxx/ -r -f
aliyun oss rb oss://qwencloud-deploy-tmp-xxx/ -f
```

