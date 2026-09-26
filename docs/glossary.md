# Glossary

Terms used across VeriTrace documentation, code, and APIs. Use them with exactly these meanings.

| Term | Meaning |
| --- | --- |
| **Tenant** | A company using VeriTrace. All master data belongs to exactly one tenant. |
| **GCP** (GS1 Company Prefix) | The numeric prefix GS1 assigns to a company. Every GLN and GTIN a tenant registers must start with it. |
| **GLN** (Global Location Number) | 13-digit GS1 key of a physical location (warehouse, hub, headquarters). |
| **GTIN** (Global Trade Item Number) | GS1 key of a trade item. VeriTrace always uses the 14-digit form (GTIN-14). |
| **Lot** | A production batch of one product, identified by GTIN + lot number (GS1 AI 10). Recalls act on lots. |
| **SSCC** (Serial Shipping Container Code) | 18-digit GS1 key of one logistic unit (pallet or container). VeriTrace issues one per shipment. |
| **Serial** | Number of one consumer unit within a lot (GS1 AI 21), printed on signed labels (M2). |
| **Check digit** | The last digit of a GS1 key, computed with the Modulo 10 algorithm. |
| **GS1 Digital Link** | A web URI that encodes GS1 keys (`/01/{GTIN}/10/{LOT}/21/{SERIAL}`) so a QR code resolves to the public portal. |
| **Shipment** | Movement of a quantity of one lot, as one SSCC, from an origin to a destination location. |
| **Participant** | A tenant involved in a shipment, with a role: `OWNER` (sender), `CARRIER`, `CONSIGNEE` (receiver), or `INSPECTOR` (M2). |
| **Lot holder** | A tenant with, or that had, an inventory balance of a lot. It can see the lot and ship it onward. |
| **Inventory balance / movement** | Quantity of a lot at a location, and the append-only ledger entries that change it. |
| **Pickup code** | One-time 6-digit code issued by the origin and entered by the driver to take custody. |
| **Geo-fence** | Radius around a location within which a device must be for handover actions. |
| **Checkpoint** | A driver scan at an intermediate facility while in transit. |
| **Recall** | Emergency action on a lot that locks every shipment of it across all tenants. |
| **Excursion** | A temperature reading outside the product's `[min, max]` bounds. |
| **Episode** | A continuous run of excursions for one SSCC, with no gap over 15 s. |
| **Breach / incident** | An episode that lasted 30 s or more. It is recorded once as a cold-chain incident. |
| **Shipment projection** | The telemetry service's local copy of shipment data (bounds, participants, status), built from events. |
| **Event log** | The append-only, hash-chained list of a shipment's events. |
| **Canonical JSON** | JSON serialized per RFC 8785 so identical data always hashes identically. |
| **Hash chain** | Each event stores the hash of the previous event of the same shipment, so rewriting history is detectable. |
| **Outbox** | A table written in the same transaction as a state change and relayed to Kafka afterwards. |
| **RLS** (row-level security) | PostgreSQL policies that filter rows by the tenant set on the current transaction. |
| **Security-definer function** | A narrowly scoped database function that performs one cross-tenant operation with elevated rights. |
| **Leaf / Merkle root / batch** | Event or incident hashes (leaves) are grouped into a batch whose Merkle root is committed on-chain (M2). |
| **Manifest** | JSON list of a batch's leaves, pinned to IPFS, allowing independent verification (M2). |
| **Relayer** | The service that signs and pays for on-chain transactions on behalf of users (M2). |
| **Envelope encryption** | Each document is encrypted with its own data key, which is itself encrypted with a master key (M2). |
| **Local mode / cloud mode** | The two ways of running the same topology: on a workstation, or on a hosted VM (M2, optional). |
