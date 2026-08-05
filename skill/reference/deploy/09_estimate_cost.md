# Cost Estimation (Step 9)

Agent directly executes CLI commands for template validation and cost estimation.

> **Where `$TEMPLATE_URL` comes from**: first run the step 7 template upload, i.e.
> `python3 scripts/upload_artifacts.py --template-file <generated-template.yaml> ...`,
> which uploads the template to OSS and prints a signed URL; export it as `TEMPLATE_URL`
> before running the commands below. (ROS must use `--TemplateURL`; `--TemplateBody`
> is blocked by WAF.)

---

## Template Validation

```bash
aliyun ros ValidateTemplate --RegionId "$REGION" --TemplateURL "$TEMPLATE_URL"
```

Non-zero exit → read `Code` + `Message`, fix template, retry.

---

## Cost Estimation

```bash
aliyun ros GetTemplateEstimateCost \
  --RegionId "$REGION" \
  --TemplateURL "$TEMPLATE_URL" \
  --Parameters.1.ParameterKey AppName        --Parameters.1.ParameterValue "$APP_NAME" \
  --Parameters.2.ParameterKey InstanceType   --Parameters.2.ParameterValue "$INSTANCE_TYPE" \
  --Parameters.3.ParameterKey Password       --Parameters.3.ParameterValue 'Tmp_Pwd_For_Pricing!1' \
  --Parameters.4.ParameterKey SystemDiskSize --Parameters.4.ParameterValue "40" \
  --Parameters.5.ParameterKey AppPort    --Parameters.5.ParameterValue "8080" \
  --Parameters.6.ParameterKey ZoneId         --Parameters.6.ParameterValue "$ZONE_ID" \
  --Parameters.7.ParameterKey UserDataScript --Parameters.7.ParameterValue "#!/bin/bash"
```

> With RDS: omit UserDataScript, add RDS parameters instead:
> `DbInstanceClass`, `DbInstanceStorage`, `DbName`, `DbAccount`, `DbPassword`

---

## Parse Results

Returns `Resources.<LogicalId>.Result.Order.OriginalAmount` (each resource's **hourly** amount).
Sum all to get total hourly price. Currency: always **USD**.

---

## Confirmation Display

AskUserQuestion summary should show:
- Hourly price (USD)
- Full list of billable resources to be created
- Note: does not include network traffic, snapshots, OSS storage, or other dynamic costs
