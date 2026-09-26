# Driver and Dock PWA

Touch-first progressive web app for the people who handle goods physically. The general conventions are
in [README.md](README.md), device behavior is in
[ADR-0022](../adr/0022-driver-pwa-device-capabilities.md), and the handover rules are in
[shipment-lifecycle.md §6](../domain/shipment-lifecycle.md#6-custody-handover-protocol).

| Persona | Role | Uses the PWA to |
| --- | --- | --- |
| Driver | `DRIVER` (carrier tenant) | See assignments, pick up with SSCC scan and pickup code, record checkpoints, follow temperature, receive alerts |
| Dock receiver | `WAREHOUSE_MANAGER` or `ADMIN` (consignee tenant) | Scan an arriving pallet and confirm delivery at the destination |

The app shows the screens that match the signed-in role. Other roles are directed to the dashboard.

## 1. Screens

Endpoints are relative to `/api/v1`; `telemetry/…` is served by the telemetry service.

| Route | Purpose | Endpoints | Persona | Stories |
| --- | --- | --- | --- | --- |
| `/login` | Sign-in through the BFF; offers "Add to home screen" after the first sign-in | `POST /bff/session/login` | all | EP2-US11 |
| `/` (driver) | Assignments: shipments assigned to me in `CREATED` or `IN_TRANSIT`, sorted by status then time, with pull-to-refresh | `GET /shipments?assigned_to_me=true` | Driver | EP2-US11 |
| `/shipments/{id}` | Shipment card: SSCC, product, lot, bounds, origin and destination (name and "open in maps" link), status, live temperature with the current excursion state, primary action button | `GET /shipments/{id}`, `GET telemetry/shipments/{sscc}/readings?resolution=raw`, WebSocket `subscribe` | Driver | EP2-US11, EP3-US08 |
| `/shipments/{id}/pickup` | Pickup wizard (§2.1) | `POST /shipments/{id}/pickup` | Driver | EP2-US11 |
| `/shipments/{id}/checkpoint` | Checkpoint wizard (§2.2) | `GET /directory/locations/{gln}`, `POST /shipments/{id}/checkpoints` | Driver | EP2-US11 |
| `/receive` | Dock receiving (§2.3) | `GET /shipments?sscc=`, `POST /shipments/{id}/delivery` | Dock receiver | EP2-US11 |
| `/alerts` | Breach and recall notifications for my shipments | `GET telemetry/incidents` | all | EP3-US08 |
| `/settings` | Language, app version, logout, and camera and location permission status with how to enable them | `POST /bff/session/logout` | all | EP2-US11 |

## 2. Flows

### 2.1 Pickup (driver, shipment `CREATED`)

1. **Scan the SSCC.** The camera opens full screen with a torch toggle, and "Enter manually" is available.
   The scanned value is normalized
   ([gs1-identifiers.md §3.1](../domain/gs1-identifiers.md#31-sscc-on-logistic-labels)). If it differs
   from the shipment, show "This is not the pallet assigned to you" and stay on this step.
2. **Enter the pickup code.** Six digit boxes with the numeric keypad and paste support. The warehouse
   staff reads the code from the dashboard.
3. **Confirm location.** Acquire a high-accuracy position and show its accuracy. Submit when the accuracy
   is ≤ 100 m, or after the 10 s timeout with a warning.
4. **Submit.** On success, show a confirmation screen; the status becomes `IN_TRANSIT` and live temperature
   starts. On error, map the problem code:

   | Code | UI |
   | --- | --- |
   | `SSCC_MISMATCH` | Back to step 1 |
   | `PICKUP_CODE_INVALID` | Clear the boxes; show `remaining_attempts` |
   | `PICKUP_CODE_EXPIRED`, `PICKUP_CODE_LOCKED` | "Ask the warehouse for a new code" |
   | `OUTSIDE_GEOFENCE` | Show `distance_meters` versus `allowed_meters`; retry location |
   | `SHIPMENT_RECALLED_LOCKED` | Red recall screen; the flow ends |

### 2.2 Checkpoint (driver, shipment `IN_TRANSIT`)

1. Scan the SSCC (same checks as §2.1).
2. Identify the facility: scan its GLN barcode or enter the GLN. The directory lookup shows the facility
   name for confirmation.
3. Confirm location, then submit.

### 2.3 Receiving (dock receiver, shipment `IN_TRANSIT`)

1. Scan the SSCC. The app looks it up (`GET /shipments?sscc=`), and it must be visible to the tenant as
   `CONSIGNEE`.
2. Show a summary (product, lot, quantity, origin, carrier) and any cold-chain incidents, so the receiver
   can inspect the goods before accepting.
3. Confirm location, then submit `POST /shipments/{id}/delivery`. The success screen shows `DELIVERED`.

## 3. Behavior

- **Alerts:** `cold_chain.breach_confirmed` for my shipments and `shipment.recalled` trigger a
  full-width banner, sound, and vibration. A recall replaces the shipment screen with a red "Do not
  deliver; contact dispatch" state.
- **Offline:** a banner appears when offline. Assignments and shipment cards come from the cache with a
  timestamp. Every action button is disabled until the connection returns.
- **Session:** the access token is kept in memory and refreshed through the BFF on app resume.
- **Performance:** first load under 3 s on mid-range Android over 4G. The scanner polyfill and charts
  load lazily.
