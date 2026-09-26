# Public Trace Portal (M2)

Anonymous, mobile-first pages opened by scanning a product's QR code. The rules are in
[public-verification.md](../domain/public-verification.md), and the general conventions are in
[README.md](README.md).

## 1. Routes

| Route | Purpose | Data |
| --- | --- | --- |
| `/` | Landing page: what VeriTrace verification means, plus a form to enter GTIN, lot, and serial (or open the camera to scan a label) | — |
| `/01/{gtin}/10/{lot}/21/{serial}?k=&s=` | **Label page**: verdict plus the lot timeline | Server: `GET /api/v1/public/lots/{gtin}/{lot}`. Client: `POST /api/v1/public/scans` |
| `/01/{gtin}/10/{lot}` | Lot timeline without a unit verdict ("This code identifies a batch, not an individual product") | Server: `GET /api/v1/public/lots/{gtin}/{lot}` |
| Anything else | GS1 Digital Link parse error page with a link to `/` | — |

GTIN and lot are validated before any request. An invalid check digit renders the error page directly.

## 2. Label page

**Server-side rendering.**

- The timeline is fetched without caching (`no-store`), so a recall is visible on the next scan.
- Telemetry summaries may be cached for 60 s.
- The page sets `noindex`, because label URLs identify individual units. The landing page is indexable.

**Verification, on the client after the page loads.**

1. Show a short consent prompt: "Share your approximate location to help detect counterfeit labels?" with
   Allow and Skip.
2. `POST /api/v1/public/scans` with the label fields, plus the position rounded to 2 decimals if
   allowed. Scans are recorded only from the browser, never during server rendering, so previews and bots
   do not count as scans.
3. Render the verdict at the top of the page:

   | Verdict | Presentation |
   | --- | --- |
   | `RECALLED` | Full-width red danger banner with the advisory ("Do not consume. Return to the point of sale."); overrides every other state |
   | `FORGED` | Red: "This label cannot be verified" |
   | `SUSPICIOUS_DUPLICATE` | Amber: "This code may have been copied", with an explanation |
   | `GENUINE` | Green: "Verified product" |
   | `UNKNOWN` | Grey: "Product not found" |

**Timeline sections,** following the exposure rules in
[public-verification.md §5](../domain/public-verification.md#5-public-timeline-content):

1. Product: name, GTIN, lot, production and expiration dates.
2. Journey: one card per shipment, in order. Each card shows the facilities (name and city), the events
   with times, and the cold-chain result (in bounds, or incidents with their duration).
3. Temperature: ECharts line per shipment (15-minute series) with the safe band shaded and incidents
   marked (`GET /api/v1/public/telemetry/shipments/{sscc}/summary`).
4. Certificates: document type and SHA-256 (no content).
5. Integrity: each event and incident shows its hash and an anchoring badge
   (`GET /api/v1/public/proofs/{leaf_hash}`).
   - **"Verify on-chain"** runs `verifyLeaf(batchId, leafHash, proof)` in the browser with viem, against
     `NEXT_PUBLIC_RPC_URL` and `NEXT_PUBLIC_CONTRACT_ADDRESS`, and shows the result.
   - A link opens the transaction in `NEXT_PUBLIC_EXPLORER_URL` (Polygonscan Amoy).
   - With a local Anvil chain the explorer link is hidden and only the in-browser verification is shown.

## 3. Non-functional requirements

- **Privacy:**
  - no cookies, no analytics, no third-party scripts;
  - location is used only with consent and is rounded before it is sent.
- **Performance:**
  - Largest Contentful Paint under 2.5 s on a mid-range phone over 4G;
  - initial JavaScript under 200 KB gzipped, with ECharts and viem loaded only when their sections
    scroll into view.
- **Accessibility:** verdict colors always come with an icon and text.
- **Languages:** Vietnamese by default, English available. The locale is chosen from the
  `Accept-Language` header, and the locale prefix is optional on label routes so printed URLs stay short.
