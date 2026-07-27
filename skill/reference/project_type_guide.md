# Project Type Decision Guide

After the Agent reads the signal output from `analyze_project.py`, use this document for final determination.

## app_type Mapping

| Signal                                           | app_type        | backend_entry Example     |
|--------------------------------------------------|-----------------|---------------------------|
| Dockerfile / docker-compose.yml                  | `docker`        | —                         |
| go.mod                                           | `binary-go`     | `./server`                |
| Cargo.toml (Rust)                                | `binary-go`     | `./target/release/<name>` |
| pom.xml / build.gradle                           | `binary-java`   | `java -jar app.jar`       |
| package.json + express/fastify/koa/nest          | `binary-node`   | `node server.js`          |
| requirements.txt / pyproject.toml + Python entry | `binary-python` | See table below           |
| Pure frontend (React/Vue/Vite, no backend)       | `frontend-only` | —                         |

When a Dockerfile exists, prefer `docker` unless the user explicitly doesn't want to use it. Rust compiles to a static
binary, reusing `binary-go`'s `binary` runtime.

## Python Framework Startup Commands

| Framework | backend_entry                                                    | Default Port |
|-----------|------------------------------------------------------------------|--------------|
| FastAPI   | `uvicorn main:app --host 0.0.0.0 --port 8080`                    | 8080         |
| Flask     | `gunicorn -b 0.0.0.0:8080 app:app`                               | 8080         |
| Django    | `gunicorn -b 0.0.0.0:8080 <project>.wsgi:application`            | 8080         |
| Streamlit | `streamlit run app.py --server.port 8080 --server.headless true` | 8080         |
| Gradio    | `python3 app.py`                                                 | 7860         |
| Generic   | `python3 main.py`                                                | Check code   |

## nginx_mode Decision

| Condition                                               | nginx_mode               |
|---------------------------------------------------------|--------------------------|
| Has frontend artifacts + has backend                    | `static-proxy` (default) |
| No frontend, pure backend (Flask/Django/Streamlit etc.) | `proxy`                  |
| Pure frontend, no backend                               | `static`                 |

> In `proxy` mode, all requests are reverse-proxied to the backend. Flask/Django/Streamlit/Gradio **must** use `proxy` —
> using `static-proxy` by mistake will cause `try_files` to intercept routes.

## Agent Decision Flow

1. Read `file_tree` to understand overall structure
2. Read `config_files` for dependency manifests and build configuration
3. Read `source_samples` to confirm framework and port
4. Read `readme_excerpt` for build/run instructions
5. If confident → decide directly; if uncertain → use AskUserQuestion to ask

## `--backend-entry` Explanation

`--backend-entry` is the **full startup command** (relative to `/opt/qwencloud`), not a file path. The script only
parses the first token as an absolute path; it does not automatically prepend an interpreter prefix.

- Go binary: `./server`
- Python: `python3 app.py` or `gunicorn -b :8080 app:app`
- Java: `java -jar app.jar`
- Node: `node server.js`

## Build Commands for Git URL Sources

| Type    | Build Command                                       |
|---------|-----------------------------------------------------|
| Node.js | `npm install && npm run build`                      |
| Go      | `go build -o <binary> .`                            |
| Python  | `pip install -r requirements.txt`                   |
| Java    | `mvn package -DskipTests` or `gradle build -x test` |
| Rust    | `cargo build --release`                             |
| Docker  | `docker build -t <name>:latest .`                   |
