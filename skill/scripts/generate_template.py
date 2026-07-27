#!/usr/bin/env python3
"""
Assemble final ROS template: based on templates/ros_single[_rds].yaml skeleton,
inject templates/userdata/*.sh snippets by app_type (with placeholder substitution).

Without RDS path:
  - Template written as-is (UserData passed as Parameter)
  - UserData assembled into standalone file, passed by create_stack.sh as UserDataScript parameter

With RDS path (--with-rds):
  - Use *_rds.yaml template (ECS UserData field is Fn::Sub block with __USERDATA_BODY__ placeholder)
  - After assembling UserData body, base64-encode and inject at template __USERDATA_BODY__ position.
    At runtime, first write db.env (RDS vars substituted by Fn::Sub), then decode + source main script.
    This way Fn::Sub never touches shell variables, avoiding unreliable ${!VAR} issues.
  - --userdata-output is ignored with --with-rds (UserData is inlined in template via base64)

Usage examples:
  # Without RDS (artifact URLs read directly from upload_artifacts.py JSON output, no manual pasting)
  python upload_artifacts.py --region ap-southeast-1 --frontend-dir dist \\
    --backend-mode binary --backend-dir backend > /tmp/artifacts.json
  python generate_template.py --topology single --app-type binary-go \\
    --backend-port 8080 --backend-entry ./server \\
    --artifacts-json /tmp/artifacts.json \\
    --output /tmp/tpl.yaml --userdata-output /tmp/userdata.sh
  # Or pipe directly: upload_artifacts.py ... | generate_template.py ... --artifacts-json -

  # With RDS (password passed via DB_PASSWORD env var, not command line)
  DB_PASSWORD='Strong_P@ss1' python generate_template.py --topology single --app-type binary-go \\
    --backend-port 8080 --backend-entry ./server \\
    --frontend-artifact-url "https://..." --backend-artifact-url "https://..." \\
    --with-rds --db-name appdb --db-account appuser \\
    --output /tmp/tpl.yaml --userdata-output /tmp/userdata.sh
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import sys
from pathlib import Path


TPL_DIR = Path(__file__).resolve().parent.parent / "templates"


def load_skeleton(topology: str, with_rds: bool) -> str:
    if with_rds:
        fname = f"ros_{topology}_rds.yaml"
    else:
        fname = f"ros_{topology}.yaml"
    return (TPL_DIR / fname).read_text(encoding="utf-8")


def build_userdata(app_type: str, args) -> str:
    parts = ["#!/bin/bash", "set -euxo pipefail", "exec >> /var/log/qwencloud-bootstrap.log 2>&1"]

    nginx_mode = getattr(args, "nginx_mode", "static-proxy")

    if nginx_mode == "proxy":
        nginx = (TPL_DIR / "userdata" / "nginx_proxy.sh").read_text(encoding="utf-8")
        nginx = nginx.replace("__BACKEND_PORT__", str(args.backend_port))
        parts.append("# --- nginx: proxy (server-rendered) ---")
        parts.append(nginx)
    elif nginx_mode == "static":
        nginx = (TPL_DIR / "userdata" / "nginx_static.sh").read_text(encoding="utf-8")
        nginx = nginx.replace("__FRONTEND_ARTIFACT_URL__", args.frontend_artifact_url or "")
        parts.append("# --- nginx: static (no backend) ---")
        parts.append(nginx)
    else:
        nginx = (TPL_DIR / "userdata" / "nginx_static_proxy.sh").read_text(encoding="utf-8")
        nginx = nginx.replace("__FRONTEND_ARTIFACT_URL__", args.frontend_artifact_url or "")
        nginx = nginx.replace("__BACKEND_PORT__", str(args.backend_port))
        parts.append("# --- nginx: static-proxy (frontend + api) ---")
        parts.append(nginx)

    # Backend snippet
    if app_type == "frontend-only":
        pass
    elif app_type == "docker":
        backend = (TPL_DIR / "userdata" / "docker.sh").read_text(encoding="utf-8")
        backend = backend.replace("__BACKEND_ARTIFACT_URL__", args.backend_artifact_url or "")
        backend = backend.replace("__BACKEND_MODE__", args.backend_mode or "docker-image")
        backend = backend.replace("__BACKEND_PORT__", str(args.backend_port))
        backend = backend.replace("__BACKEND_IMAGE_NAME__", args.backend_image_name or "qwencloud-app:latest")
        parts.append("# --- backend: docker ---")
        parts.append(backend)
    elif app_type.startswith("binary-"):
        runtime = {"binary-go": "binary", "binary-java": "java", "binary-node": "node", "binary-python": "python"}[app_type]
        backend = (TPL_DIR / "userdata" / "systemd.sh").read_text(encoding="utf-8")
        backend = backend.replace("__BACKEND_ARTIFACT_URL__", args.backend_artifact_url or "")
        backend = backend.replace("__BACKEND_RUNTIME__", runtime)
        backend = backend.replace("__BACKEND_ENTRY__", args.backend_entry or "./server")
        backend = backend.replace("__BACKEND_PORT__", str(args.backend_port))
        parts.append(f"# --- backend: {app_type} ---")
        parts.append(backend)
    else:
        print(f"unknown app_type: {app_type}", file=sys.stderr)
        sys.exit(2)

    return "\n".join(parts) + "\n"


def inject_userdata_body(template_text: str, userdata_body: str) -> str:
    """Base64-encode userdata_body and inject into template's __USERDATA_BODY__ placeholder.

    Uses base64 encoding: Fn::Sub never sees shell variables. At runtime the encoded
    script is decoded and sourced, inheriting db.env environment variables.
    """
    marker = "__USERDATA_BODY__"
    if marker not in template_text:
        print(f"Cannot find {marker} placeholder in template", file=sys.stderr)
        sys.exit(2)

    encoded = base64.b64encode(userdata_body.encode("utf-8")).decode("ascii")

    loader = (
        f"echo '{encoded}' | base64 -d > /tmp/qwencloud-main.sh\n"
        f"chmod +x /tmp/qwencloud-main.sh\n"
        f". /tmp/qwencloud-main.sh"
    )

    for line in template_text.splitlines():
        if marker in line:
            indent = line[: len(line) - len(line.lstrip())]
            break

    indented_lines = []
    for ln in loader.splitlines():
        if ln.strip():
            indented_lines.append(indent + ln)
        else:
            indented_lines.append("")
    indented_body = "\n".join(indented_lines)

    full_marker_line = indent + marker
    return template_text.replace(full_marker_line, indented_body)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--topology", choices=["single"], default="single")
    ap.add_argument("--app-type", required=True,
                    choices=["frontend-only", "docker", "binary-go", "binary-java", "binary-node", "binary-python"])
    ap.add_argument("--backend-port", type=int, default=8080)
    ap.add_argument("--frontend-artifact-url", default="")
    ap.add_argument("--backend-artifact-url", default="")
    ap.add_argument("--artifacts-json", default=None,
                    help="JSON output from upload_artifacts.py (file path, or - for stdin); "
                         "automatically extracts frontend_url / backend_url, avoiding manual pasting of long signed URLs. "
                         "Explicit --frontend-artifact-url / --backend-artifact-url take priority.")
    ap.add_argument("--backend-mode", default="docker-image", choices=["docker-image", "docker-compose"])
    ap.add_argument("--backend-image-name", default="")
    ap.add_argument("--backend-entry", default="",
                    help="Full startup command (relative to /opt/qwencloud), e.g. ./server / "
                         "\"python3 app.py\" / \"java -jar app.jar\" / \"node server.js\" / "
                         "\"gunicorn -b :8080 app:app\". This is the exact command that will be exec'd.")
    ap.add_argument("--nginx-mode", default="static-proxy", choices=["static-proxy", "proxy", "static"],
                    help="static-proxy: static frontend + /api/ reverse proxy (default); proxy: full reverse proxy to backend (Flask/Django etc); static: pure static hosting")
    ap.add_argument("--output", required=True)
    ap.add_argument("--userdata-output", required=True,
                    help="Write UserData to this file when no RDS; with RDS this path only gets a placeholder comment")
    # RDS-related
    ap.add_argument("--with-rds", action="store_true",
                    help="Use *_rds.yaml template and inline UserData into template (Fn::Sub embeds RDS internal address)")
    ap.add_argument("--db-name", default="appdb")
    ap.add_argument("--db-account", default="appuser")
    ap.add_argument("--db-instance-class", default="mysql.n2.medium.1")
    ap.add_argument("--db-instance-storage", type=int, default=20)
    args = ap.parse_args()

    # RDS password existence validated via DB_PASSWORD env var (actual injection by create_stack.sh via ROS Parameter);
    # not via command line args, to avoid leaking plaintext in ps process list.
    if args.with_rds and not os.environ.get("DB_PASSWORD"):
        print("--with-rds requires DB_PASSWORD environment variable", file=sys.stderr)
        sys.exit(64)

    # Directly consume upload_artifacts.py JSON output, pipe signed URLs in (no manual pasting).
    # Explicit --frontend-artifact-url / --backend-artifact-url take priority when non-empty.
    if args.artifacts_json:
        raw = sys.stdin.read() if args.artifacts_json == "-" \
            else Path(args.artifacts_json).read_text(encoding="utf-8")
        try:
            art = json.loads(raw)
        except Exception as e:
            print(f"--artifacts-json parse failed: {e}", file=sys.stderr)
            sys.exit(64)
        if not args.frontend_artifact_url:
            args.frontend_artifact_url = art.get("frontend_url") or ""
        if not args.backend_artifact_url:
            args.backend_artifact_url = art.get("backend_url") or ""

    skeleton = load_skeleton(args.topology, args.with_rds)
    userdata = build_userdata(args.app_type, args)

    if args.with_rds:
        # UserData inlined into template; --userdata-output only writes a reference file (raw, unescaped)
        final_template = inject_userdata_body(skeleton, userdata)
        Path(args.output).write_text(final_template, encoding="utf-8")
        Path(args.userdata_output).write_text(
            "# NOTE: With --with-rds, UserData is inlined into template; not passed as ROS Parameter.\n"
            "# Below is the raw body before escaping (for diff/debug only):\n\n" + userdata,
            encoding="utf-8")
    else:
        # Original path: template written as-is, UserData goes to standalone file
        Path(args.output).write_text(skeleton, encoding="utf-8")
        Path(args.userdata_output).write_text(userdata, encoding="utf-8")

    print(json.dumps({"template": args.output, "userdata": args.userdata_output, "with_rds": args.with_rds},
                     ensure_ascii=False))


if __name__ == "__main__":
    main()
