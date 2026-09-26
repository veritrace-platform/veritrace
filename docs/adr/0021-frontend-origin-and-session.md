# ADR-0021: Frontend origin and session handling

- **Status:** Accepted
- **Date:** 2026-09-26

## Context

Browsers must reach three backend services, plus a WebSocket, from three frontends. This must work
locally, on phones through a temporary HTTPS tunnel, and in the optional cloud mode (ADR-0018). Tokens
must not be exposed to scripts more than necessary, and cross-origin requests (CORS) add configuration and
failure modes.

## Decision

1. **Single origin per frontend.** The browser always talks to its own origin:
   - page routes and `/bff/*` go to the frontend;
   - `/api/v1/*`, `/.well-known/*`, and `/ws/*` go to the backend through the gateway routing table.

   | Mode | How the single origin is achieved |
   | --- | --- |
   | Local | The Caddy gateway serves each frontend on its own port: dashboard `:8001`, PWA `:8002`, portal `:8003`. It forwards API paths to the services and everything else to the frontend dev server on the host (ports 3001, 3002, 3003). |
   | Phone testing | The tunnel targets the frontend's gateway port (for example `TUNNEL_TARGET=http://gateway:8002`), so the phone gets one HTTPS origin for pages, API, and WebSocket. |
   | Cloud mode | Vercel rewrites `/api/v1/*` and `/.well-known/*` to `https://api.<domain>`. WebSocket connects directly to `wss://api.<domain>/ws/v1/notifications`, the only cross-origin connection, and the server checks `Origin` against an allowlist. |

   The services therefore need **no CORS** configuration. The WebSocket endpoint validates `Origin`
   (`WS_ALLOWED_ORIGINS`).
2. **Session through a backend-for-frontend (dashboard and PWA).**
   - `POST /bff/session/login` calls `POST /api/v1/auth/login`. It stores the refresh token in an
     encrypted, `HttpOnly`, `Secure`, `SameSite=Lax` cookie (iron-session) and returns only the access
     token, its expiry, and the user.
   - `POST /bff/session/refresh` rotates the refresh token from the cookie and returns a new access token.
   - `POST /bff/session/logout` revokes the session and clears the cookie.
   - The access token lives **in memory only**. It is attached as `Authorization: Bearer` to `/api/v1/*`
     calls and passed as the WebSocket subprotocol `bearer.<token>`.
   - On a page reload, the app calls `/bff/session/refresh` to obtain a new access token.
   - On `401 TOKEN_EXPIRED`, the client refreshes once and retries. Concurrent refreshes are coalesced
     into a single request.
3. **The public portal has no session.** It renders server-side and calls public endpoints with
   `API_BASE_URL` (server-only environment variable). The browser calls only `/api/v1/public/*` on its own
   origin.
4. **Environment variables** (identical names in every frontend):

   | Variable | Scope | Example (local) |
   | --- | --- | --- |
   | `API_BASE_URL` | server only | `http://localhost:8000` |
   | `SESSION_SECRET` | server only (dashboard, PWA) | 32+ random bytes |
   | `NEXT_PUBLIC_WS_URL` | browser, optional | unset: derived from `location` (`wss://<origin>/ws/v1/notifications`) |
   | `NEXT_PUBLIC_CHAIN_ID`, `NEXT_PUBLIC_RPC_URL`, `NEXT_PUBLIC_CONTRACT_ADDRESS`, `NEXT_PUBLIC_EXPLORER_URL` | browser (portal, M2) | Amoy or Anvil values |

## Consequences

- No CORS, no tokens in `localStorage`, and a refresh token that scripts cannot read.
- The same frontend build works locally, over a tunnel, and in cloud mode; only the environment
  variables differ.
- The gateway gains three frontend listeners. They are defined in `platform-infrastructure`, like the
  API routes.
