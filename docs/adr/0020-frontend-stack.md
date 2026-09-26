# ADR-0020: Frontend stack

- **Status:** Accepted
- **Date:** 2026-09-26

## Context

Three web applications are built in separate repositories by the frontend owner:

- `enterprise-dashboard`: desktop-first management UI;
- `driver-mobile-pwa`: installable, touch-first app used in trucks and at docks;
- `public-trace-portal`: public, SEO-relevant pages opened from product QR codes.

They share the same API contracts, domain vocabulary, and quality bar. They must stay consistent without
a shared package to version across repositories.

## Decision

All three applications use the same baseline. Versions are pinned in each repository's `package.json`,
and Renovate or Dependabot keeps them current.

| Concern | Choice | Notes |
| --- | --- | --- |
| Runtime | Node.js 24 LTS | `.nvmrc` and the `engines` field |
| Package manager | pnpm (lockfile committed) | `packageManager` field; Corepack |
| Framework | Next.js 16, App Router, React 19, TypeScript `strict` | Server components by default; client components only for interactivity |
| Styling and components | Tailwind CSS 4 + shadcn/ui (Radix primitives) | Components are copied into `src/components/ui`; design tokens in CSS variables |
| Server state | TanStack Query 5 | Caching, retries, invalidation after mutations |
| API client | `openapi-typescript` (types) + `openapi-fetch` (client) | Types generated from the service OpenAPI documents; never hand-written |
| Forms and validation | react-hook-form + Zod 4 | Zod schemas mirror OpenAPI constraints; server errors mapped from `errors[]` |
| Internationalization | next-intl | Locales `vi` (default) and `en`; all user-facing text in message catalogs |
| Charts | Apache ECharts 6 (`echarts-for-react`) | Temperature series and cold-chain bands |
| Barcode rendering | bwip-js | GS1-128 (SSCC labels), GS1 QR (Digital Link) |
| Barcode scanning (PWA) | `BarcodeDetector` API, with the `barcode-detector` polyfill (ZXing WASM) | See ADR-0022 |
| Service worker (PWA) | Serwist (`@serwist/next`) | See ADR-0022 |
| On-chain reads (portal) | viem | Read-only `verifyLeaf` calls; no wallet |
| Lint and format | Biome | One tool for lint and format; CI runs `biome ci` |
| Unit and component tests | Vitest + Testing Library + MSW | MSW handlers built from OpenAPI examples |
| End-to-end tests | Playwright | Runs against the local stack (`make up-apps`) |
| Accessibility | WCAG 2.2 AA | Radix primitives, Biome `a11y` rules, axe checks in Playwright |

Repository layout (each frontend repository):

```
src/
  app/[locale]/…        routes (App Router)
  app/bff/…             backend-for-frontend route handlers (session only; ADR-0021)
  components/ui/        shadcn/ui components
  components/…          application components
  lib/api/              generated OpenAPI types (schema.d.ts) and the typed client
  lib/gs1/              GS1 check digit and parsing (tested with the shared test vectors)
  lib/realtime/         WebSocket client (reconnect, subscriptions)
  messages/             vi.json, en.json
tests/                  unit and component tests; e2e/ for Playwright
```

Scripts every repository provides: `dev`, `build`, `start`, `lint`, `typecheck`, `test`, `test:e2e`, and
`api:generate`. The last one regenerates `lib/api/schema.d.ts` from the pinned OpenAPI URLs.

## Consequences

- One mental model and one set of tools across the three applications, while each repository stays
  independent.
- Small shared pieces are duplicated per repository (GS1 helpers, WebSocket client). The shared test
  vectors in `docs/contracts/test-vectors/` keep them correct.
- Generated API types make breaking backend changes visible at compile time.
