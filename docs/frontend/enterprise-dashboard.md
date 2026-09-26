# Enterprise Dashboard

Desktop-first management application for tenant admins and warehouse managers, and for inspectors in M2.
The general conventions are in [README.md](README.md). Roles and permissions are in
[access-control.md](../domain/access-control.md).

## 1. Navigation

```
Overview · Shipments · Lots · Inventory · Catalog (Products, Locations) · Alerts · Users* · Settings
                                                                          * ADMIN only
```

A global header shows:

- the tenant name;
- the user menu (profile, language, logout);
- the real-time connection indicator;
- the alert bell with the count of open breaches.

## 2. Screens

The "Stories" column refers to [roadmap.md](../roadmap.md). Endpoints are relative to `/api/v1`, and
`telemetry/…` endpoints are served by the telemetry service.

### 2.1 Public screens

| Route | Purpose | Endpoints | Stories |
| --- | --- | --- | --- |
| `/login` | Email and password sign-in through the BFF | `POST /bff/session/login` | EP1-US06 |
| `/register` | Tenant registration, 3 steps: company (tax code, legal name, code, GCP), headquarters location (GLN, address, map pin, geo-fence radius), first admin | `POST /tenants` | EP1-US06 |

### 2.2 Operations (M1)

| Route | Purpose | Endpoints | Roles | Stories |
| --- | --- | --- | --- | --- |
| `/` | Overview: shipment counts by status, open breaches, recent recalls, live alert feed | `GET /shipments/summary`, `GET telemetry/incidents/summary`, `GET telemetry/incidents?state=open` | all | EP2-US10, EP3-US08 |
| `/shipments` | List with filters (status, party, lot, SSCC search), cursor paging | `GET /shipments` | all | EP2-US10 |
| `/shipments/new` | Create a shipment: pick a lot and origin (with available balance), quantity, destination by GLN (directory lookup preview), optional carrier by tenant code, optional driver when the carrier is the own tenant | `GET /lots`, `GET /inventory`, `GET /directory/locations/{gln}`, `GET /directory/tenants/{code}`, `GET /users?role=DRIVER`, `POST /shipments` | ADMIN, WM | EP2-US10 |
| `/shipments/{id}` | Detail: header with status and SSCC, participants, product and bounds, origin and destination, event timeline with hashes and a "Verify integrity" action, cold-chain chart with incidents (live when in transit), available actions for the caller's party | `GET /shipments/{id}`, `GET /shipments/{id}/events`, `GET /shipments/{id}/integrity`, `GET telemetry/shipments/{sscc}/readings`, `GET telemetry/shipments/{sscc}/incidents`, WebSocket `subscribe` | all participants | EP2-US10, EP3-US08 |
| ↳ action **Assign carrier** | Owner sets the carrier by tenant code | `POST /shipments/{id}/carrier` | ADMIN, WM (owner) | EP2-US10 |
| ↳ action **Assign driver** | Carrier picks one of its drivers | `POST /shipments/{id}/driver` | ADMIN, WM (carrier) | EP2-US10 |
| ↳ action **Issue pickup code** | Shows the 6-digit code in large type with a 15-minute countdown. It is shown only once and never stored in the browser. | `POST /shipments/{id}/pickup-code` | ADMIN, WM (owner) | EP2-US10 |
| ↳ action **Confirm delivery** | Consignee enters or scans the SSCC (USB scanner or webcam); the browser supplies the position | `POST /shipments/{id}/delivery` | ADMIN, WM (consignee) | EP2-US10 |
| ↳ action **Cancel** | Reason required; confirmation dialog | `POST /shipments/{id}/cancel` | ADMIN, WM (owner) | EP2-US10 |
| `/shipments/{id}/label` | Printable A6 logistic label: GS1-128 `(00)` SSCC, human-readable SSCC, product, lot, destination ([gs1-identifiers.md §3.1](../domain/gs1-identifiers.md#31-sscc-on-logistic-labels)) | `GET /shipments/{id}` | ADMIN, WM (owner) | EP2-US10 |
| `/lots` | List lots (filter by product and status) | `GET /lots` | ADMIN, WM | EP2-US10 |
| `/lots/new` | Commission a lot: product, lot number, dates, quantity, location | `GET /products`, `GET /locations`, `POST /lots` | ADMIN, WM | EP2-US10 |
| `/lots/{id}` | Lot detail: dates, status, balances by location, shipments of the lot. **Recall** action for the lot owner's admin (type the lot number, enter a reason). | `GET /lots/{id}`, `GET /inventory?lot_id=`, `GET /shipments?lot_id=`, `POST /lots/{id}/recall` | ADMIN, WM (recall: ADMIN) | EP2-US10 |
| `/inventory` | Balances by location and lot | `GET /inventory`, `GET /locations` | ADMIN, WM | EP2-US10 |
| `/catalog/products`, `/catalog/products/new`, `/catalog/products/{id}` | Product list, create, edit: GTIN (validated), name, description, temperature bounds, active flag | `GET/POST /products`, `GET/PATCH /products/{id}` | ADMIN, WM | EP2-US10 |
| `/catalog/locations`, `/catalog/locations/new`, `/catalog/locations/{id}` | Location list, create, edit with a map to pick coordinates and preview the geo-fence circle | `GET/POST /locations`, `GET/PATCH /locations/{id}` | ADMIN | EP2-US10 |
| `/alerts` | Breach incidents (open and resolved) and recall notifications, linked to shipments | `GET telemetry/incidents` | all | EP3-US08 |
| `/users`, `/users/new`, `/users/{id}` | User list, create, edit, deactivate | `GET/POST /users`, `GET/PATCH /users/{id}` | ADMIN | EP1-US06 |
| `/settings/tenant` | Tenant profile | `GET/PATCH /tenant` | ADMIN | EP1-US06 |
| `/settings/profile` | Own profile and password change | `GET /me`, `POST /me/password` | all | EP1-US06 |

### 2.3 Additions in M2

| Route or area | Purpose | Endpoints | Roles | Stories |
| --- | --- | --- | --- | --- |
| `/shipments/{id}` → Documents tab | Upload (drag and drop; PDF, PNG, or JPEG ≤ 25 MiB; document type), list with SHA-256 and CID, secure preview in a sandboxed viewer, download | `GET/POST /shipments/{id}/documents`, `GET /documents/{id}/content` | ADMIN, WM, INSPECTOR | EP4-US05 |
| `/shipments/{id}` → Participants | Add an inspector tenant | `POST /shipments/{id}/participants` | ADMIN (owner) | EP4-US05 |
| Anchoring badges | Per event and incident: `PENDING` or `ANCHORED`, with a link to the transaction | `GET /proofs/status` | all | EP6-US04 |
| `/lots/{id}` → Labels tab | Issue a label series (count) and print a QR sheet (A4 grid) with Digital Link URIs | `GET/POST /lots/{id}/label-series`, `GET /lots/{id}/label-series/{series_id}/labels` | ADMIN, WM (lot owner) | EP6-US04 |

## 3. Behavior

- **Real-time:**
  - `cold_chain.breach_confirmed` raises a toast and increments the bell.
  - `shipment.recalled` opens a **blocking modal** (red) listing the affected shipment. It stays until
    acknowledged, and the acknowledgement is remembered in memory for the session.
  - Every event invalidates the related queries.
- **Positions:** actions that need a position request browser geolocation. If the position is
  unavailable, the action is blocked with an explanation. The API decides the geo-fence result, and the UI
  shows `distance_meters` and `allowed_meters` from `OUTSIDE_GEOFENCE`.
- **Label printing:** labels are rendered client-side with bwip-js into print-specific CSS pages. Nothing
  is sent to third-party services.
- **Maps:** Leaflet with OpenStreetMap tiles (attribution shown), used only for picking and previewing
  locations.
