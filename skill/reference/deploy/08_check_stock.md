# Stock Check (Step 8)

Agent directly executes CLI commands to query ECS (and optional RDS) availability zone stock.

---

## ECS Stock Query

```bash
aliyun ecs DescribeAvailableResource \
  --RegionId "$REGION" \
  --DestinationResource InstanceType \
  --InstanceType "$INSTANCE_TYPE" \
  --InstanceChargeType PostPaid
```

Extract zones with stock from returned JSON:
`AvailableZones.AvailableZone[]` where `Status` is `Available` or `WithStock` → collect `ZoneId`.

---

## RDS Zone Verification (only when RDS is needed)

For each ECS-available zone, verify the RDS instance class is supported:

```bash
aliyun rds DescribeAvailableClasses \
  --RegionId "$REGION" --ZoneId "$ZONE_ID" \
  --Engine MySQL --EngineVersion 8.0 \
  --Category Basic --DBInstanceStorageType cloud_essd \
  --CommodityCode bards --OrderType BUY
```

If response contains `$DB_INSTANCE_CLASS` → that zone supports RDS. Take ECS ∩ RDS zone intersection.

---

## Decision Logic

| Result | Action |
|--------|--------|
| ≥1 zone available | Record `ZONE_ID` (use the first one), continue |
| 0 zones available | Offer user 2–3 alternatives (different instance type / different region) with trade-offs |

---

## Alternative Suggestions

When stock is insufficient, Agent queries stock for alternatives:
- Larger instance in same family (e.g. `ecs.e-c1m2.xlarge`)
- Same config in different family (e.g. `ecs.g7.large`)
- Different region (e.g. `ap-southeast-5`, `ap-northeast-1`)
