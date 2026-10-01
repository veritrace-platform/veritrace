# Frontend Applications

Specifications for the three VeriTrace frontends. Each application lives in its own repository and is
built by the frontend owner. These documents define **what** each application does and the conventions
they share. Code-level choices inside the stack below are left to the repository.

| Application | Repository | Users | Specification |
| --- | --- | --- | --- |
| Enterprise dashboard | `enterprise-dashboard` | Admins, warehouse managers, inspectors (M2) | [enterprise-dashboard.md](enterprise-dashboard.md) |
| Driver and dock PWA | `driver-mobile-pwa` | Drivers; warehouse staff receiving goods | [driver-mobile-pwa.md](driver-mobile-pwa.md) |
| Public trace portal (M2) | `public-trace-portal` | Consumers (anonymous) | [public-trace-portal.md](public-trace-portal.md) |

Related decisions:

- [ADR-0020](../adr/0020-frontend-stack.md): frontend stack and repository layout.
- [ADR-0021](../adr/0021-frontend-origin-and-session.md): origin and session handling.
- [ADR-0022](../adr/0022-driver-pwa-device-capabilities.md): driver PWA device capabilities.
- The backend integration contract is in [frontend-integration.md](../guides/frontend-integration.md).

## 1. Local development

| Application | Dev server (host) | Open in the browser (through the gateway) |
| --- | --- | --- |
| Enterprise dashboard | `pnpm dev --port 3001` | `http://localhost:8001` |
| Driver PWA | `pnpm dev --port 3002` | `http://localhost:8002` (phone: `make tunnel TUNNEL_TARGET=http://gateway:8002`) |
| Public trace portal | `pnpm dev --port 3003` | `http://localhost:8003` |

- Backend: `make up-apps` in `platform-infrastructure` starts the stack and the Go services without a Go
  toolchain.
- Always open the gateway port, not the dev server port, so that `/api/v1` and `/ws` share the page's
  origin ([ADR-0021](../adr/0021-frontend-origin-and-session.md)).

## 2. API types and mocks

- `pnpm api:generate` regenerates `src/lib/api/schema.d.ts`.
  - Sources: `../core-business-service/api/openapi.yaml` and `../telemetry-stream-service/api/openapi.yaml`
    (sibling checkouts), plus the relayer document in M2.
  - CI uses the same files from the `develop` branch on GitHub.
  - Generated files are committed, so builds never depend on the network.
- The typed client (`openapi-fetch`) is the only way to call the API. It adds the bearer token, handles a
  single refresh on `401 TOKEN_EXPIRED`, and converts problem documents into typed errors.
- MSW handlers mock endpoints that are not implemented yet, using the OpenAPI examples. Remove each mock
  when its backend story is `DONE`.

## 3. Shared UX conventions

| Topic | Rule |
| --- | --- |
| Languages | Vietnamese (default) and English; the locale is in the URL prefix (`/vi/…`, `/en/…`) |
| Dates and times | The API uses UTC. The UI shows the browser's local time, with the timezone in tooltips, formatted by locale. |
| Numbers | Temperatures with 1 decimal and `°C`; distances in m or km; quantities with thousands separators |
| GS1 inputs | Digits only. Live validation of length, check digit, and (where known) the tenant prefix, using `lib/gs1`. Show the key grouped for readability, store it unformatted. |
| Errors | Map every problem `code` to a translated message. Field errors go under their inputs. Unknown codes show a generic message plus `trace_id` with a copy button. |
| Loading and empty states | Skeletons for lists; explicit empty states with the next action (for example "Create your first product") |
| Destructive actions | Recall and cancel need a confirmation dialog. Recall also requires typing the lot number. |
| Permissions | Hide navigation the role cannot use ([access-control.md](../domain/access-control.md)). Disable actions whose preconditions fail and explain why in a tooltip. The server remains the authority. |
| Accessibility | WCAG 2.2 AA; full keyboard support in the dashboard; touch targets ≥ 44 px in the PWA |

### Status colors and labels

Use the same tokens in every application:

| Value | Color token | Meaning |
| --- | --- | --- |
| `CREATED` | neutral | Awaiting pickup |
| `IN_TRANSIT` | blue | On the way |
| `DELIVERED` | green | Received |
| `CANCELLED` | muted | Cancelled |
| `RECALLED` | red | Recalled; locked |
| Breach open | red | Cold-chain breach in progress |
| Breach resolved | amber | Past excursion |

## 4. Real-time client

`lib/realtime` is shared by the dashboard and the PWA:

- It connects once per session to `/ws/v1/notifications` with the subprotocols `veritrace.v1` and
  `bearer.<token>` ([messaging.md §6](../contracts/messaging.md#6-websocket-real-time-notifications)).
- It reconnects with exponential backoff (1 s up to 30 s, with jitter). On close code `4401` it first
  refreshes the session.
- It re-subscribes to live telemetry channels after every reconnect.
- It dispatches messages to TanStack Query: it invalidates affected shipment, incident, and lot queries,
  and raises UI notifications.

## 5. Suggested CI checks

A starting point for each frontend repository's CI; the frontend owner decides the final setup.

1. `pnpm install --frozen-lockfile`
2. `biome ci`
3. `pnpm typecheck`
4. `pnpm test` (Vitest)
5. `pnpm build`

Playwright end-to-end tests run on demand and before releases, against `make up-apps`.

## 6. Environments

| Mode | Hosting | Configuration |
| --- | --- | --- |
| Local | `pnpm dev`, behind the gateway | `.env.local` from `.env.example` |
| Cloud (M2, optional) | Vercel Hobby, with rewrites for `/api/v1/*` and `/.well-known/*` | Vercel project environment variables ([ADR-0021](../adr/0021-frontend-origin-and-session.md)) |
