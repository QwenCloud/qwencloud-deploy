# Instance Type Selection (Step 6)

Topology is fixed: single ECS + EIP + VPC + SG. Ask user to choose ECS instance type via AskUserQuestion.

---

## ECS Instance Options (AskUserQuestion)

| Option | Instance Type | Config | Est. Price |
|--------|--------------|--------|------------|
| Starter | `ecs.e-c1m1.large` | 2C2G | ~$0.02/hr |
| General | `ecs.e-c1m2.large` | 2C4G | ~$0.04/hr |
| Performance | `ecs.e-c1m2.xlarge` | 4C8G | ~$0.11/hr |

---

## Selection Guidance

| Project Type | Recommended |
|--------------|-------------|
| Static site / lightweight API | Starter 2C2G |
| Full-stack app (static + app + small DB) | General 2C4G |
| Java app / compute-heavy app | Performance 4C8G |

---

## Output

- `INSTANCE_TYPE`: User-selected ECS instance type ID

---

## Notes

- Prices shown are estimates; actual price confirmed in step 9 (cost estimation)
- Instance type affects step 8 (stock check) availability zone matching
