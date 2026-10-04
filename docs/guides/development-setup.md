# Development Setup

## 1. Prerequisites

| Tool | Version | Needed for |
| --- | --- | --- |
| Docker Engine (`docker-ce`) with the Buildx and Compose plugins | Docker 29+, Compose 2.27+ | Everything |
| GNU Make | 4+ | Task shortcuts |
| Go | 1.27 (`GOTOOLCHAIN=auto` downloads it on demand) | Go services |
| Node.js | 22 LTS | Frontends |
| `uv` (installs and manages Python 3.13) | latest | IoT simulator (optional; it also runs in Docker) |
| Foundry (`forge`, `cast`, `anvil`) | latest stable | Smart contracts and local chain (M2) |
| GitHub CLI (`gh`) | latest | Optional: pull requests from the terminal |
| `shellcheck`, `jq` | latest | Script linting and JSON inspection |

All repositories live side by side in one parent directory. The `apps` compose profile and the workspace
tooling rely on this layout. Clone the project home first, then let it fetch the rest:

```bash
mkdir veritrace-platform && cd veritrace-platform
git clone https://github.com/veritrace-platform/veritrace.git
make -C veritrace workspace           # clones every missing repository next to it, on develop
make -C veritrace status              # branch and pending changes of every repository
```

```
veritrace-platform/
├── veritrace/                    project home: docs, roadmap, workspace tooling
├── platform-infrastructure/      local stack, bootstrap, gateway, simulator
├── core-business-service/
├── telemetry-stream-service/
├── blockchain-relayer-service/
├── smart-contracts/
├── enterprise-dashboard/
├── driver-mobile-pwa/
└── public-trace-portal/
```

## 2. Start the environment

```bash
cd platform-infrastructure
make up                     # creates .env on the first run; PostgreSQL, Kafka (+ topics), Mosquitto, Redis, gateway
make ps                     # everything should be healthy
```

`make help` lists all targets. `make reset` deletes all volumes, so local data is lost. When
`.env.example` gains variables, `make up` adds them to `.env` and keeps the values you changed.

## 3. Ports

Host ports are defaults. If a port is taken, override it in `platform-infrastructure/.env` (for example
`POSTGRES_HOST_PORT=15432`) and use the same port in the services' `.env` files.

| Port | Service |
| --- | --- |
| 8000 | Gateway: single entry point for REST and WebSocket |
| 5432 | PostgreSQL (`veritrace_core`, `veritrace_telemetry`, `veritrace_relayer`) |
| 9092 | Kafka (host listener) |
| 1883 | Mosquitto |
| 6379 | Redis |
| 8080 / 8081 | core-business-service (API / admin) when run on the host |
| 8090 / 8091 | telemetry-stream-service (API / admin) |
| 8100 / 8101 | blockchain-relayer-service (API / admin, M2) |
| 8085 | Kafka UI (`tools` profile) |
| 8001 / 8002 / 8003 | Gateway origins for the dashboard, PWA, and portal (open these in the browser) |
| 3001 / 3002 / 3003 | Frontend dev servers on the host (behind the gateway) |

## 4. Backend workflow (Go on the host)

```bash
cd core-business-service
cp .env.example .env        # development-only secrets and the local Kafka broker
make migrate-up             # applies migrations as the owner role
make run                    # serves on :8080, admin on :8081
make test                   # unit tests
make test-integration       # integration tests (needs Docker)
make lint
make check                  # everything CI checks: lint, generated code, OpenAPI, all tests
```

`make -C veritrace check-all` runs `make check` in every backend repository (platform-infrastructure lints its
configuration and tests the simulator and the demonstration kit), then checks the documentation links and the
shared Go platform code across repositories. It prints the repositories that failed.

The gateway on `:8000` forwards to services on the host by default. When `.env.example` gains variables,
copy them into your `.env`; `serve` reports every missing setting at startup.

`telemetry-stream-service` works the same way. Its `.env.example` connects to the local Kafka and
Mosquitto, and `make run` starts the ingest and processor components next to the API
([ADR-0012](../adr/0012-cold-chain-detection-engine.md)). To watch readings flow, create a shipment through
the core API and replay a scenario of the IoT fleet simulator for its SSCC:

```bash
cd platform-infrastructure
make simulate-list                                         # normal, short-excursion, sustained-breach, sensor-gap
make simulate SCENARIO=sustained-breach SSCC=<shipment SSCC>
make psql-telemetry                                        # then: SELECT * FROM telemetry.sensor_readings;
```

The simulator runs in a container (`simulator` profile) and needs no Python on the host. Its README in
`platform-infrastructure/simulator/` describes the scenarios and options.

## 5. Demonstration kit

`platform-infrastructure/demo/` seeds a small supply chain through the APIs and runs the M1 acceptance
scenario: four companies (owner, carrier, consignee, and an unrelated tenant), an account for every role, and
the catalog, locations, and lots that a shipment needs.

```bash
cd platform-infrastructure
make up-apps
make seed            # idempotent; make demo-accounts lists the accounts
make demo            # the acceptance run: handover, breach, delivery, recall (about 2 minutes)
make demo-watch ACCOUNT=admin@d7mart.example   # an account's notifications in the terminal
```

Every demo account signs in with `DEMO_PASSWORD` from `platform-infrastructure/.env`. The runbook in
`platform-infrastructure/demo/README.md` lists the companies and accounts, explains each step of the acceptance
run, and suggests how to present it.

## 6. Stopping and cleaning up the stack

| Command | Effect |
| --- | --- |
| `make down` | Stop all VeriTrace containers and keep data. Containers never start automatically with Docker. |
| `make reset` | Stop containers and delete VeriTrace data volumes |
| `make clean` | `reset` plus removal of locally built VeriTrace images |
| `make disk` | Show Docker disk usage |

## 7. Frontend workflow (no Go toolchain)

```bash
cd platform-infrastructure
make up-apps                # also builds and runs the Go services from sibling repositories
```

Point the frontend at `http://localhost:8000`. See [frontend-integration.md](frontend-integration.md).
`make seed` provides companies, accounts for every role, and catalog data to sign in with (§5). For live
telemetry, create a shipment and run `make simulate SSCC=<shipment SSCC>` as in §4.
