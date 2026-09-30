# Frontend Integration

The backend contract for `enterprise-dashboard`, `driver-mobile-pwa`, and `public-trace-portal`. What each
application does is specified in [frontend/](../frontend/README.md). The stack and session decisions are
[ADR-0020](../adr/0020-frontend-stack.md) and [ADR-0021](../adr/0021-frontend-origin-and-session.md).

## 1. Origins and URLs

Every frontend talks to the API on **its own origin**, so no CORS is involved.

| Mode | Open the app at | REST | WebSocket |
| --- | --- | --- | --- |
| Local | Gateway port: dashboard `http://localhost:8001`, PWA `:8002`, portal `:8003` | `/api/v1/…` on the same origin | `ws://<origin>/ws/v1/notifications` |
| Phone testing | `https://….trycloudflare.com` from `make tunnel TUNNEL_TARGET=http://gateway:8002` | same origin | `wss://<origin>/ws/v1/notifications` |
| Cloud (M2, optional) | Vercel URL | Vercel rewrite to `https://api.<domain>` | `wss://api.<domain>/ws/v1/notifications` (`NEXT_PUBLIC_WS_URL`) |

The dev servers run on the host at ports 3001 (dashboard), 3002 (PWA), and 3003 (portal). The gateway
forwards to them. Always open the gateway port.

## 2. Types and mocks

- REST types are generated from each service's `api/openapi.yaml` with `openapi-typescript`. Do not
  hand-write request or response types.
- Endpoints not implemented yet are mocked with MSW from the same documents.
- WebSocket message types follow [messaging.md §6](../contracts/messaging.md#6-websocket-real-time-notifications).

## 3. Session (dashboard and PWA)

| Step | Browser | Frontend server (BFF) | Backend |
| --- | --- | --- | --- |
| Sign in | `POST /bff/session/login` | Calls `POST /api/v1/auth/login`; stores the refresh token in an encrypted `HttpOnly` cookie | Issues tokens |
| Call the API | `Authorization: Bearer <access token>` on `/api/v1/…` | — | Verifies the JWT |
| Token expired (`401 TOKEN_EXPIRED`) | `POST /bff/session/refresh` once, then retry | Calls `POST /api/v1/auth/refresh` with the cookie; rotates it | Rotates the refresh token |
| Page reload or app resume | `POST /bff/session/refresh` | as above | as above |
| Sign out | `POST /bff/session/logout` | Calls `POST /api/v1/auth/logout`; clears the cookie | Revokes the family |
| WebSocket | `new WebSocket(url, ["veritrace.v1", "bearer." + accessToken])`; on close `4401`, refresh and reconnect | — | Verifies the token |

The access token is held in memory only. Tokens never go to `localStorage`, `sessionStorage`, or
non-`HttpOnly` cookies.

Login and refresh return the same `Session` body: `access_token` with `expires_in` (seconds), the new
`refresh_token` with `refresh_token_expires_in` (the cookie's `Max-Age`), and `user`, the same object as
`GET /api/v1/me`. When the BFF calls login, refresh, and logout, it forwards the browser's address in
`X-Forwarded-For` and the browser's `User-Agent`, so rate limits and session records describe the browser
rather than the frontend server.

The public portal has no session. It renders on the server with `API_BASE_URL`.

## 4. Errors

Every error is `application/problem+json` with a stable `code`
([rest-api.md §1.1](../contracts/rest-api.md#11-errors-rfc-9457-problem-details)).

- Map `code` to translated text.
- Use `errors[].field` for form fields, and the documented extension members (for example
  `remaining_attempts`, `distance_meters`) for richer messages.
- Show `trace_id` with a copy button for unexpected errors.

## 5. Domain rules the UI mirrors

- **GS1:** client-side validation of length, check digit, and prefix. The implementation is tested with
  [`gs1-check-digit.json`](../contracts/test-vectors/gs1-check-digit.json). Scanned labels are normalized per
  [gs1-identifiers.md §3.1](../domain/gs1-identifiers.md#31-sscc-on-logistic-labels).
- **Positions:** handover actions send `{latitude, longitude, accuracy_meters}` from high-accuracy
  geolocation.
- **Recall:** a `shipment.recalled` notification blocks further actions on that shipment in every UI.
