# ADR-0019: Local development environment

- **Status:** Accepted
- **Date:** 2026-09-25

## Context

Backend and frontend developers need the same dependencies with the same versions, started with one
command. The frontend developer should not need a Go toolchain to get a working API.

## Decision

- `platform-infrastructure/compose.yaml` defines the environment. Every image is pinned to an exact tag
  there, and Dependabot proposes upgrades as pull requests, so this document does not repeat the tags:

  | Component | Image |
  | --- | --- |
  | PostgreSQL 18 + TimescaleDB | `timescale/timescaledb` (`-pg18` variant) |
  | Kafka (KRaft, single node) | `apache/kafka` (4.x) |
  | Mosquitto | `eclipse-mosquitto` (2.x) |
  | Redis | `redis` (alpine) |
  | Gateway | `caddy` (alpine) |

- **Compose profiles:**

  | Profile | Starts |
  | --- | --- |
  | *(default)* | PostgreSQL, Kafka with topic initialization, Mosquitto, Redis, gateway |
  | `apps` | Builds and runs the Go services from the sibling repositories (`../core-business-service`, …) and runs their migrations first. For frontend work without Go. |
  | `tools` | Kafka UI |
  | `tunnel` | Cloudflare quick tunnel: a temporary public HTTPS URL for testing on phones (camera and geolocation require HTTPS) |
  | `web3` (M2, added with SCM-EP4-US01 and SCM-EP5-US01) | Local IPFS node (Kubo) and local EVM chain (Anvil) |
  | `observability` (M2, added with SCM-EP7-US02) | Prometheus, Loki, Alloy, Grafana |

- **Gateway.** A local gateway applies the production routing table:
  - `http://localhost:8000` for API clients;
  - one origin per frontend on `:8001` (dashboard), `:8002` (PWA), and `:8003` (portal), which forward
    non-API paths to the frontend dev servers on host ports 3001–3003 (ADR-0021).

  By default the gateway forwards API paths to services running on the host (`go run`). With the `apps`
  profile it forwards them to the containers instead.
- **Bootstrap.** A first-start script creates the per-service databases, owner and runtime roles, and
  the TimescaleDB extension, reading passwords from `.env`. It creates no application tables.
- **IoT fleet simulator.** Lives in `platform-infrastructure/simulator/` (added with SCM-EP3-US01):
  - Python 3.13, `paho-mqtt` 2, managed with `uv`, linted with `ruff`, tested with `pytest`;
  - runs as a container;
  - replays YAML scenarios (normal transit, a short excursion under 30 s, a sustained breach, a sensor
    gap) for a configurable number of devices and SSCCs.
- **Workstation safety:**
  - Host ports bind to `127.0.0.1` only, so databases are never exposed to the local network.
  - Every container has a memory limit.
  - Containers restart after a crash (`on-failure`) but do **not** start automatically with Docker.
  - Ports are configurable in `.env` (`POSTGRES_HOST_PORT`, `KAFKA_HOST_PORT`, …) for machines that
    already run other stacks on the default ports.
- Every repository ships a `.env.example`. Real `.env` files are never committed.

## Consequences

- `make up` in `platform-infrastructure` is the only prerequisite for backend and frontend work.
- Version upgrades happen in one file and in one reviewed change.
