# Docker Standards

These rules apply to every Dockerfile and Compose file, regardless of the language inside the container. They are the working-development baseline. Production releases go further: before shipping an image, apply the OWASP Docker Security Cheat Sheet (https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html) in full, in particular dropping capabilities, read-only filesystems, resource limits, digest-pinned images, and image scanning.

## Commands

```bash
docker compose up -d --build              # start the stack (never bare docker run when a compose file exists)
docker compose ps                         # includes health status
docker compose logs -f <service>
docker compose down                       # stop; add -v only with confirmation, it deletes named volumes
docker compose exec <service> <command>   # run something inside a running service
docker compose exec <service> id          # verify which user a service actually runs as
```

## Rules

This list is canonical. The sections below add rationale and examples only.

**Compose**

1. If `compose.yaml` exists, every container starts through it. `docker run` is only for a throwaway command against an image outside the project, and carries `--rm`.
2. `compose.yaml` at the repo root, no `version:` key, and a top-level `name:` set to the project name.
3. Every service sets `container_name`, `<project>-<service>`, lowercase, hyphenated, spelled out. Named volumes and networks set `name:` the same way.
4. `image` pinned by tag, never `latest`.
5. Every long-running service has a `healthcheck` that proves readiness, with `interval`, `timeout`, `retries`, `start_period` set. One-shot services have none; their exit code is the check. The compose `healthcheck` is the source of truth; an image `HEALTHCHECK` mirrors it.
6. `depends_on` uses `condition: service_healthy` for long-running dependencies and `condition: service_completed_successfully` for one-shot ones (migrations, seeds).
7. Long-running services set `restart: unless-stopped`. One-shot services set no `restart:`.
8. Published ports bind to `127.0.0.1`. `0.0.0.0` only in a production compose file, on the one public service, with a comment.
9. Bind mounts use the long syntax with `bind: { create_host_path: false }`. Leave it `true` only for a directory the container populates on first run, with a comment.
10. A named network per group of services that need to talk; a service joins only the networks it needs.

**Security baseline**

11. Never mount `/var/run/docker.sock`. Never `privileged: true`.
12. Every service runs as a non-root user: `USER` in the Dockerfile and `user:` in compose with a high fixed UID (`10001`). Exception: images that manage their own privilege drop (`postgres`, `mysql`, `nginx` official images) omit `user:`; verify with `docker compose exec <service> id`.
13. `security_opt: [no-new-privileges:true]` on every service.
14. Secrets never appear in the image, the compose file, environment variables, build args, or a command line. They are compose `secrets:` backed by gitignored files, and the application reads `/run/secrets/<name>` at startup.

**Dockerfile**

15. `FROM <image>:<tag>`, never `latest`. Multi-stage: build stage, then a final stage with only the artefact and runtime dependencies.
16. `COPY` named paths only. Never `ADD`, never `COPY . .`.
17. Every Dockerfile ships with a `.dockerignore` created in the same change: copy every `.gitignore` entry into it (Docker does not read `.gitignore`), then add what git tracks but the image must not contain.
18. No `curl | bash` or equivalent. Download, verify, then run.
19. OS packages installed unpinned. Do not look up or pin individual package versions. Clean the package cache in the same `RUN` layer.
20. Python images install with `uv sync --frozen --no-dev` from `uv.lock`; Node images with `npm ci`. Never install without a lockfile.
21. The runtime image contains only what the process needs, plus `curl` for the healthcheck. `curl` is the one accepted extra binary; do not add others for convenience.

## Why these rules

**Compose over `docker run`.** A `docker run` command is state that lives in someone's shell history; a compose file is state that lives in the repo and is reviewed. When a container is missing a setting, the fix is to add it to the compose file, not to type it on the command line.

**`name:` and `container_name`.** Without a top-level `name:`, compose derives the project name from the directory, so volumes, networks, and containers change identity when the repo is cloned into a different folder. `name:` fixes the project prefix; `container_name` fixes the container. `container_name` disables `docker compose up --scale` for that service, which is an accepted trade: services here are not scaled through compose.

**Healthchecks and `depends_on`.** A container that has started is not a service that is ready. `service_healthy` makes startup order follow readiness. A one-shot service never becomes healthy, it exits, so a dependant waits on `service_completed_successfully` instead. The healthcheck proves readiness to serve (a real health endpoint, `pg_isready`, `redis-cli ping`), not merely that the process is alive.

**`restart: unless-stopped` in development.** Long-running services come back after a host reboot or a daemon restart without anyone re-running `up`. One-shot services must not restart: a migration that re-runs on every crash is a bug.

**`127.0.0.1` ports.** Docker writes its own iptables rules and bypasses host firewalls such as UFW, so a `0.0.0.0` binding is reachable from the internet regardless of `ufw deny`.

**`create_host_path: false`.** The short `./config:/config` form, and the long form's default, create an empty directory on the host when the path does not exist. A service missing its config then starts, runs with nothing, and fails somewhere far from the cause. With `create_host_path: false` the start fails immediately, naming the missing path.

**Secrets via `/run/secrets`.** Environment variables leak into `docker inspect`, crash dumps, and child processes. The application reads the file at startup; the connection URL in `environment:` carries everything except the password, and the code assembles it. Images that support the `_FILE` convention (`POSTGRES_PASSWORD_FILE`) use it; the application's own code does the same by hand.

**Non-root, with the official-image exception.** Some official images start as root deliberately, fix ownership of their data directory, then drop privileges themselves (`postgres` uses gosu). Setting `user:` on those breaks the volume initialisation. For every other image, `user:` in compose is a backstop for a Dockerfile that forgot `USER`.

**Two healthchecks.** Compose's `healthcheck` overrides the image's `HEALTHCHECK`. Both exist so the image is safe to run outside this compose file, but the compose entry is edited first and the image entry copied from it.

**`curl` as the accepted exception.** Every binary in the final stage is surface and update burden, so the runtime image is kept minimal. `curl --fail` is the exception because a healthcheck everyone can read at a glance is worth more than the small surface it adds. Nothing else gets the same pass.

## Compose example

```yaml
name: orders

services:
  orders-api:
    container_name: orders-api
    build:
      context: .
      dockerfile: Dockerfile
    user: "10001:10001"
    security_opt:
      - no-new-privileges:true
    restart: unless-stopped
    ports:
      - "127.0.0.1:8000:8000"
    environment:
      DATABASE_URL: postgresql://orders@orders-postgres:5432/orders   # password read from /run/secrets by the app
    secrets:
      - orders_database_password
    volumes:
      - type: bind
        source: ./config/orders_api.toml
        target: /application/config/orders_api.toml
        read_only: true
        bind:
          create_host_path: false   # fail if the config file is missing rather than mount an empty directory
    healthcheck:
      test: ["CMD", "curl", "--fail", "--silent", "http://localhost:8000/health"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 15s
    depends_on:
      orders-postgres:
        condition: service_healthy
      orders-migrate:
        condition: service_completed_successfully
    networks:
      - orders-internal

  orders-migrate:
    container_name: orders-migrate
    build:
      context: .
      dockerfile: Dockerfile
    user: "10001:10001"
    security_opt:
      - no-new-privileges:true
    command: ["alembic", "upgrade", "head"]
    environment:
      DATABASE_URL: postgresql://orders@orders-postgres:5432/orders
    secrets:
      - orders_database_password
    depends_on:
      orders-postgres:
        condition: service_healthy
    networks:
      - orders-internal

  orders-postgres:
    container_name: orders-postgres
    image: postgres:16.4
    # no user: the official image drops to postgres itself after initialising the data directory
    security_opt:
      - no-new-privileges:true
    restart: unless-stopped
    environment:
      POSTGRES_USER: orders
      POSTGRES_DB: orders
      POSTGRES_PASSWORD_FILE: /run/secrets/orders_database_password
    secrets:
      - orders_database_password
    volumes:
      - type: volume
        source: orders-postgres-data
        target: /var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready --username=orders --dbname=orders"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 10s
    networks:
      - orders-internal

secrets:
  orders_database_password:
    file: ./secrets/orders_database_password.txt   # gitignored

volumes:
  orders-postgres-data:
    name: orders-postgres-data

networks:
  orders-internal:
    name: orders-internal
```

Reading the secret in the application:

```python
DATABASE_PASSWORD_SECRET_PATH = Path("/run/secrets/orders_database_password")


def load_database_password() -> str:
    """Return the database password from the mounted Docker secret

    Raises:
        FileNotFoundError: If the secret is not mounted
    """
    return DATABASE_PASSWORD_SECRET_PATH.read_text().strip()
```

## Dockerfile example

```dockerfile
FROM python:3.12-slim AS build
COPY --from=ghcr.io/astral-sh/uv:0.4.18 /uv /bin/uv
WORKDIR /application
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
COPY orders_api ./orders_api
RUN uv sync --frozen --no-dev

FROM python:3.12-slim
RUN apt-get update \
    && apt-get install --yes --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 application \
    && useradd --system --uid 10001 --gid application --no-create-home application
WORKDIR /application
COPY --from=build --chown=application:application /application/.venv ./.venv
COPY --from=build --chown=application:application /application/orders_api ./orders_api
USER application
ENV PATH="/application/.venv/bin:${PATH}"
# mirrors the compose healthcheck; edit there first
HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=5 \
    CMD curl --fail --silent http://localhost:8000/health || exit 1
ENTRYPOINT ["uvicorn", "orders_api.main:application", "--host", "0.0.0.0", "--port", "8000"]
```

```gitignore
# .dockerignore: every .gitignore entry copied in, then what git tracks but the image must not contain
.git
.gitignore
.venv
__pycache__
*.pyc
.pytest_cache
.ruff_cache
node_modules
dist
.env
.env.*
secrets/
tests/
docs/
compose.yaml
Dockerfile
.dockerignore
.github/
.pre-commit-config.yaml
README.md
```
