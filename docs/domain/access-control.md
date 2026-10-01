# Access Control

Authorization has two layers:

1. **Visibility.** PostgreSQL row-level security decides which rows a tenant can see
   ([ADR-0002](../adr/0002-multi-party-tenancy-with-row-level-security.md)).
2. **Permission.** A per-action policy decides what a user may do with those rows
   ([ADR-0009](../adr/0009-access-control-policy-model.md)).

A resource the caller cannot see returns `404 NOT_FOUND`, never `403`, so its existence is not revealed. A
visible resource on which the action is not permitted returns `403 FORBIDDEN`.

## 1. User roles

| Role | Purpose | Client |
| --- | --- | --- |
| `ADMIN` | Manages the tenant: users, locations, products, recalls | Dashboard |
| `WAREHOUSE_MANAGER` | Manages catalog data, lots, shipments, and pickup codes; receives deliveries | Dashboard |
| `DRIVER` | Picks up, records checkpoints, and receives alerts for assigned shipments | PWA |
| `INSPECTOR` (M2) | Uploads and reviews compliance documents for shipments the tenant inspects | Dashboard |

A user belongs to exactly one tenant and has exactly one role.

## 2. Policy matrix

Party is the caller tenant's relationship to the resource. The `lot OWNER` is the tenant that commissioned
the lot, and a `lot holder` is a tenant with a non-zero balance of the lot.

### M1

| Action | Party | Roles | Preconditions | Context checks |
| --- | --- | --- | --- | --- |
| Manage tenant profile | own tenant | ADMIN | — | — |
| Manage users | own tenant | ADMIN | — | not the caller's own role or active flag |
| List drivers | own tenant | ADMIN, WAREHOUSE_MANAGER | — | — |
| Change own password | self | any | — | current password |
| View catalog (locations, products) | own tenant | ADMIN, WAREHOUSE_MANAGER | — | — |
| Manage locations | own tenant | ADMIN | — | GLN prefix |
| Manage products | own tenant | ADMIN, WAREHOUSE_MANAGER | — | GTIN prefix |
| Look up the directory (GLN, tenant code) | any tenant | any | — | — |
| View lots | lot OWNER, lot holder | ADMIN, WAREHOUSE_MANAGER | — | — |
| Commission lot | own tenant | ADMIN, WAREHOUSE_MANAGER | product owned by tenant | location owned by tenant |
| View inventory | own tenant | ADMIN, WAREHOUSE_MANAGER | — | — |
| Create shipment | lot holder | ADMIN, WAREHOUSE_MANAGER | lot `ACTIVE`, sufficient balance | origin owned by tenant |
| Assign carrier | OWNER | ADMIN, WAREHOUSE_MANAGER | `CREATED`, no external carrier yet | — |
| Assign driver | CARRIER | ADMIN, WAREHOUSE_MANAGER | `CREATED` | driver is an active DRIVER of the carrier |
| Issue pickup code | OWNER | ADMIN, WAREHOUSE_MANAGER | `CREATED`, driver assigned | — |
| Confirm pickup | CARRIER | DRIVER (assigned only) | `CREATED` | SSCC match, valid code, origin geo-fence |
| Record checkpoint | CARRIER | DRIVER (assigned only) | `IN_TRANSIT` | SSCC match, facility geo-fence |
| Confirm delivery | CONSIGNEE | ADMIN, WAREHOUSE_MANAGER | `IN_TRANSIT` | SSCC match, destination geo-fence |
| Cancel shipment | OWNER | ADMIN, WAREHOUSE_MANAGER | `CREATED` | — |
| Recall lot | lot OWNER | ADMIN | lot `ACTIVE` | — |
| View shipment, events, and telemetry | any participant | ADMIN, WAREHOUSE_MANAGER, INSPECTOR; DRIVER only if assigned | — | — |

### M2

| Action | Party | Roles | Preconditions | Context checks |
| --- | --- | --- | --- | --- |
| Add inspector participant | OWNER | ADMIN | not `CANCELLED` | inspector tenant exists |
| Upload document | OWNER, INSPECTOR | ADMIN, WAREHOUSE_MANAGER, INSPECTOR | not `CANCELLED` | type and size limits |
| Read or decrypt document | any participant | ADMIN, WAREHOUSE_MANAGER, INSPECTOR | — | — |
| Issue label series | lot OWNER | ADMIN, WAREHOUSE_MANAGER | lot `ACTIVE` | — |

Any action that is not listed is denied.

Notes on the matrix:

- An admin cannot change its own role or deactivate itself. Admin changes to users of one tenant run one at a
  time, and each one checks the caller's current account, so a tenant always keeps an active admin and an
  admin who was just demoted cannot act on the rest of its token's lifetime.
- *List drivers* lets a warehouse manager pick a driver for a shipment (`GET /api/v1/users?role=DRIVER`).
- *View catalog*, *View lots*, and *Look up the directory* are the reads behind the dashboard and PWA screens:
  warehouse managers pick products and locations for lots and shipments, and drivers confirm a checkpoint
  facility by its GLN. Directory entries are published to every tenant and expose only public fields.
- Deactivating a user revokes its sessions. Role changes and deactivation take effect at the next token
  refresh, within 15 minutes ([ADR-0007](../adr/0007-token-authentication-with-eddsa-and-jwks.md)).

## 3. Pre-authentication and public operations

Tenant registration, login, token refresh, and M2 public trace endpoints run without a tenant context.
They reach the database only through dedicated `SECURITY DEFINER` functions that return the minimum data
required.
