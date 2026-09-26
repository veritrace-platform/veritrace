# ADR-0022: Driver PWA device capabilities

- **Status:** Accepted
- **Date:** 2026-09-26

## Context

Drivers use their own phones. They scan logistic labels, prove where they are, receive cold-chain alerts,
and sometimes work with poor connectivity. Native apps would double the frontend work, and a PWA must
therefore be explicit about what it relies on.

## Decision

- **Installable PWA:**
  - web app manifest (standalone display, portrait, icons, theme color);
  - Serwist service worker that precaches the app shell and static assets;
  - requires HTTPS, provided locally by the tunnel (ADR-0021).
- **Barcode scanning:**
  - The `BarcodeDetector` API is used where available (Chromium on Android). The `barcode-detector`
    polyfill (ZXing WASM) is used elsewhere, including iOS Safari.
  - Formats: GS1-128 (`code_128`), GS1 DataMatrix, and QR.
  - Scanned values are normalized to an SSCC by the rules in
    [gs1-identifiers.md §3.1](../domain/gs1-identifiers.md#31-sscc-on-logistic-labels).
  - Manual 18-digit entry, with live check-digit validation, is always available as a fallback.
- **Geolocation:**
  - Requested only when an action needs it (pickup, checkpoint), with `enableHighAccuracy: true`, a
    10-second timeout, and `maximumAge: 0`.
  - The reported `accuracy_meters` is sent with every position.
  - If permission is denied, the action cannot be completed. The UI explains why and how to re-enable
    it.
- **Connectivity:**
  - **State-changing actions require a connection.** They are never queued offline, because pickup codes
    expire and positions must be current.
  - The assignment list and shipment details are cached for read-only offline viewing, with a visible
    "offline, showing data from <time>" banner.
- **Alerts:**
  - Delivered over the WebSocket while the app is open, with an in-app banner, sound, and vibration
    (`navigator.vibrate`) for `cold_chain.breach_confirmed` and `shipment.recalled`.
  - Background push (Web Push) is **out of scope** for M1 and M2, and the documentation says so.
- **Supported browsers:** the current and previous major versions of Chrome for Android and Safari on
  iOS/iPadOS 17+.

## Consequences

- One codebase serves every phone. There are no app-store dependencies.
- The iOS scanning path depends on the WASM polyfill, which is heavier. It is loaded lazily only when the
  camera opens.
- Drivers do not receive alerts while the app is closed. Dispatchers see every alert on the dashboard.
