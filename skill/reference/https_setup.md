# HTTPS & Domain Setup (Optional, Post-Deployment)

**Trigger**: After full-stack deployment succeeds (step 13 complete), present the **Post-Deployment: Go Live As-Is or
Bind a Domain** card (two-step; see
`reference/interaction_rules.md`).

Also triggered when the user says "configure HTTPS", "bind domain", "set up SSL" at any time after deployment exists.

> ⚠️ HTTPS requires a domain name. Pure IP addresses cannot obtain SSL certificates.
> Steps H3–H5 use DNS-01 validation (works even if port 80 is unreachable, and
> supports wildcard certs). HTTPS is configured directly via Cloud Assistant commands
> on the ECS — no wrapper script needed.

## Step H1 · Domain Source

AskUserQuestion: **I have a domain** / **Buy a new domain**

### Path A: User has a domain

User provides the domain (e.g. `app.example.com`). Proceed to step H3.

### Path B: Buy a new domain

**H2a. Recommend a default domain (lowers user effort)**: Instead of making the user invent a name, propose a default in
the format **`my-<project>.<tld>`** and probe registrable suffixes automatically. This Skill uses an
**international-site** access key.
`.com` is preferred as the default (most trusted, verified registrable here), with the probe order
`com net org online site top tech me co`
(`.cn`/`.com.cn` are excluded because they require China real-name verification):

```bash
MODE=suggest PROJECT="coolproject" bash scripts/setup_domain.sh
```

- **Exit 0** → prints JSON with `suggested` (e.g. `my-coolproject.online`), the chosen
  `tld`, and a `price_url` (official Alibaba Cloud live-price page for that exact name). Present this as the **default
  recommendation** and let the user accept it with one tap, or type their own name.
- **Exit 41** → none of the candidate suffixes was registrable; ask the user for a different base name.

If the user provides their own name instead, validate it with:

```bash
MODE=check DOMAIN="mydomain.online" bash scripts/setup_domain.sh
```

**H2a-price. Only ever share the official price link (never a number):**

```bash
MODE=price DOMAIN="my-coolproject.online" bash scripts/setup_domain.sh
```

`MODE=price` never calls a price API; it only returns a `price_url` and exits **40**.

> 🚫 **HARD RULE — never report a domain price number.** Do NOT read a price from
> `check-domain`/`CheckDomain` or any other API and tell the user. Do NOT estimate, guess,
> or hardcode a price. The ONLY approved way to communicate price is to hand the user the
> official `price_url` and let them read the number themselves on Alibaba Cloud's page.

Alibaba Cloud exposes **no scriptable, authoritative domain price API** (verified: Domain OpenAPI, BSS billing, and the
web endpoint all lack a callable accurate-price interface), which is exactly why the number must always come from the
user reading the official page.

**H2b. Registrant profile**: Check if user already has a registrant profile:

```bash
MODE=profiles bash scripts/setup_domain.sh
```

If no profile exists (first time), collect registrant info from user:

> 💬 First-time domain purchase requires registrant information (will be saved for future use):
>
> **Required:**
> • Name (English, e.g. John Smith)
> • Email (e.g. john@example.com)
> • Phone (with country code, e.g. +1-5551234567)
> • Country (e.g. US, SG, JP)
> • Province/State (e.g. California)
> • City (e.g. San Francisco)
> • Street address (e.g. 123 Main St)
> • Postal code (e.g. 94102)
>
> **Defaults:** Type=Individual · WHOIS privacy=enabled
>
> 🔒 WHOIS privacy protection is enabled — your info won't be publicly visible.
>
> Accept free-form input; infer country from phone code if provided.
> If any required field is missing, ask only for the missing fields.


Then create the profile:

```bash
MODE=create-profile EMAIL="user@example.com" REGISTRANT_NAME="John Doe" \
  COUNTRY="US" PROVINCE="California" CITY="San Francisco" \
  ADDRESS="123 Main St" POSTAL_CODE="94102" \
  TEL_AREA="1" TELEPHONE="5551234567" bash scripts/setup_domain.sh
```

**H2c. Email verification**: After creating the profile, send verification email:

```bash
MODE=send-email-verification EMAIL="user@example.com" bash scripts/setup_domain.sh
```

Then inform the user:

> 💬 📧 A verification email has been sent to **user@example.com**.
> Please check your inbox (and spam folder) and click the verification link.
> Let me know once you've completed the verification.

Wait for user confirmation, then verify programmatically:

```bash
MODE=check-email-verification EMAIL="user@example.com" bash scripts/setup_domain.sh
```

If verification status is not "SUCCESS", remind the user to check their email again.

**H2d. Register domain**:

```bash
MODE=buy DOMAIN="my-coolproject.online" REGISTRANT_PROFILE_ID="$PROFILE_ID" bash scripts/setup_domain.sh
```

> ⚠️ Domain registration is a **paid operation**. Confirm with the user using the **real price obtained in step H2a**
> (never an estimate) before executing. If H2a could not confirm an accurate price, do NOT purchase.
> ⚠️ Domain purchase will only proceed **after email verification is confirmed**.

## Step H3 · DNS Configuration

Add A record pointing the domain to the deployment's public IP:

```bash
MODE=dns DOMAIN="my-coolproject.online" IP="$PUBLIC_IP" bash scripts/setup_domain.sh
```

For user-owned domains not hosted on Alibaba Cloud DNS, instruct the user to manually add the A record at their DNS
provider, then wait for propagation.

> **Newly-registered domain?** A brand-new domain is only usable after the TLD root
> delegates its nameservers to Alibaba Cloud DNS; until then public resolvers return
> NXDOMAIN for every record (the classic "first HTTPS attempt fails" trap). Instead of a
> fixed sleep, poll until delegation is live (returns as soon as it is ready):
>
> ```bash
> MODE=wait-delegation DOMAIN="my-coolproject.online" bash scripts/setup_domain.sh
> ```
>
> Records are created with **TTL=600s** (AliDNS free-plan minimum; lower values are rejected).

## Step H4 · Verify DNS

```bash
MODE=verify DOMAIN="my-coolproject.online" IP="$PUBLIC_IP" bash scripts/setup_domain.sh
```

Polls every 10s for up to 2 minutes. If DNS doesn't resolve, guide user to check their DNS settings.

> **Domain-only (HTTP) path:** Only if the user explicitly opted out of the certificate,
> STOP here — skip H5. Show the **Domain-only (HTTP) Success Card** (see
> `reference/interaction_rules.md`).

## Step H5 · Obtain Certificate & Configure HTTPS

certbot runs on the ECS via Cloud Assistant (DNS-01). The agent executes commands directly — no wrapper script. See
`reference/cli_https.md` for full command templates.

> ⚠️ **Critical gotchas** (learned from production):
> - **CommandContent = PlainText** — do NOT base64-encode; Cloud Assistant runs it directly as shell
> - **Package manager**: Alibaba Cloud Linux uses yum, not apt; `epel-release` may conflict with
    `epel-aliyuncs-release` — use `pip3 install certbot` as fallback
> - **Install `bind-utils`** (provides `dig`) — not present by default on Alibaba Cloud Linux
> - **Kill stale certbot** before re-running — previous timeouts leave lock files
> - **Token freshness**: each `certbot certonly` generates a NEW token; script deletes old token file before starting;
    agent must poll for fresh token and update TXT accordingly
> - **`--agree-tos` is mandatory** — certbot in `--non-interactive` mode will fail if the ToS is not explicitly
    accepted; always include `--agree-tos`
> - **Timeout 600s** for the certbot RunCommand (DNS propagation needs time)

**Flow** (5 steps, ~90s total):

1. **Install certbot + bind-utils** (RunCommand, 120s) — `yum install -y certbot bind-utils || pip3 install certbot`
2. **Launch certbot** (RunCommand, 600s) — auth-hook writes token to `/etc/qwencloud/certbot/token.txt`, polls NS
3. **Create TXT locally** (parallel with step 2) — submit ONE self-polling RunCommand to wait for token (not repeated
   RunCommands), then `MODE=dns-txt bash scripts/setup_domain.sh`
4. **Configure Nginx** (RunCommand, 60s) — write ssl.conf (443→proxy, 80→301), `nginx -t && systemctl reload nginx`
5. **Cleanup TXT** — `MODE=dns-txt-clean bash scripts/setup_domain.sh`

Idempotent (skips if cert valid >7 days). Renewal: re-run steps 2–5 around day 80.

## Step H6 · Verify & Update State

1. `curl -sI https://$DOMAIN/ | head -1` → expect `HTTP/2 200` or `HTTP/1.1 200`
2. Update `.qwencloud-deploy` state file with domain and certificate info
3. Display HTTPS success card (see `reference/interaction_rules.md`)

## Step H7 · CORS Reminder

Access URL changed from `http://<IP>` to `https://<domain>`. Warn user about potential CORS issues, scan project for
CORS config (`Access-Control-Allow-Origin`, `cors()`,
`@CrossOrigin`, `ALLOWED_ORIGINS`), and offer to add the new domain + redeploy if a clear config is found.
