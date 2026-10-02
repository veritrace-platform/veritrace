# Messaging Contracts

Asynchronous contracts between devices, services, and clients. Field names are `snake_case`. Timestamps
are RFC 3339 in UTC (`2026-09-01T14:30:00.123456Z`). Temperatures are in °C and coordinates are WGS-84
decimal degrees.

Compatibility rule:

- Consumers ignore unknown fields.
- Producers may add optional fields within a version.
- Removing or renaming a field, or changing its meaning, requires incrementing `event_version`. During a
  migration, both versions are published.

---

## 1. MQTT: device telemetry

| Property | Value |
| --- | --- |
| Broker | Eclipse Mosquitto 2, MQTT 5 (3.1.1 also accepted from devices) |
| Topic | `veritrace/v1/devices/{device_id}/telemetry` |
| QoS | 1 (at least once); retain disabled |
| Authentication | Username and password per device. Local development also has the shared user `fleet-simulator`. |
| Authorization (ACL) | A device may publish only to its own topic (`%u` pattern). `telemetry-ingest` may subscribe to `veritrace/v1/devices/+/telemetry`. |
| Consumer | `telemetry-stream-service` through the shared subscription `$share/telemetry-ingest/veritrace/v1/devices/+/telemetry` |

Payload (compact, because it is sent by constrained devices):

```json
{
  "sscc": "089300010000000018",
  "ts": 1788273000123,
  "temperature_c": 9.4,
  "humidity_pct": 65.2,
  "lat": 10.870500,
  "lng": 106.803500
}
```

| Field | Type | Rule |
| --- | --- | --- |
| `sscc` | string | Valid SSCC-18 |
| `ts` | integer | Device time, Unix epoch milliseconds |
| `temperature_c` | number | −50…80 |
| `humidity_pct` | number | 0…100; optional |
| `lat`, `lng` | number | valid WGS-84 |

The device ID is taken from the topic, never from the payload.

Ingestion acknowledges a message only after Kafka has acknowledged its reading, and keeps its MQTT session
across restarts, so the broker redelivers what was not acknowledged. A reading delivered twice is stored once.
A reading that breaks a rule of [cold-chain-monitoring.md §2](../domain/cold-chain-monitoring.md#2-reading-validation)
is acknowledged, counted, and logged, but not forwarded.

---

## 2. Kafka: conventions

| Property | Value |
| --- | --- |
| Cluster | Apache Kafka 4 in KRaft mode. Automatic topic creation is disabled; topics are created by infrastructure. |
| Encoding | UTF-8 JSON value; the key is a UTF-8 string |
| Headers | `traceparent` (W3C Trace Context), `content-type: application/json`, `event-type` |
| Producer | Idempotent, `acks=all` |
| Delivery | At least once. Consumers are idempotent. |

| Topic | Key | Partitions | Retention | Producer | Consumers |
| --- | --- | --- | --- | --- | --- |
| `iot.telemetry.raw` | `sscc` | 6 | 7 days | telemetry ingest | telemetry processor |
| `iot.telemetry.dlq` | `sscc` | 1 | 14 days | telemetry processor | operators |
| `shipment.events` | `sscc` | 6 | unlimited | core (outbox relay) | telemetry projection, relayer (M2) |
| `telemetry.incidents` | `sscc` | 6 | unlimited | telemetry processor | relayer (M2) |

Consumer group IDs follow `<service>.<purpose>`: `telemetry-stream-service.processor` reads
`iot.telemetry.raw`, and `telemetry-stream-service.projection` reads `shipment.events`. Consumers commit
offsets only after a batch is processed, so a batch may be processed again after a crash; processing is
idempotent.

### 2.1 Domain event envelope

`shipment.events` and `telemetry.incidents` share this envelope:

```json
{
  "event_id": "01927c6e-8a1b-7c3d-9e4f-5a6b7c8d9e0f",
  "event_type": "shipment.pickup_confirmed",
  "event_version": 1,
  "occurred_at": "2026-09-01T14:35:00.000000Z",
  "producer": "core-business-service",
  "subject": {
    "shipment_id": "01927c6e-0000-7000-8000-000000000001",
    "sscc": "089300010000000018",
    "status": "IN_TRANSIT"
  },
  "actor": {
    "tenant_id": "01927c6e-0000-7000-8000-00000000000a",
    "user_id": "01927c6e-0000-7000-8000-00000000000b"
  },
  "sequence": 3,
  "prev_event_hash": "…64 hex…",
  "event_hash": "…64 hex…",
  "data": { }
}
```

- `sequence`, `prev_event_hash`, and `event_hash` are present on shipment events only. Incidents carry
  `data.incident_hash` instead.
- `actor` is `null` for system-produced events.

**Hash input:** RFC 8785 canonical JSON of the object
`{event_id, event_type, event_version, occurred_at, subject, actor, sequence, prev_event_hash, data}`.
`event_hash` is its SHA-256 in lowercase hex. `producer` and transport headers are not hashed.

---

## 3. Kafka topic `shipment.events`

Payload (`data`) per event type. All events are `event_version` 1.

**`shipment.created`**

```json
{
  "owner_tenant_id": "uuid",
  "lot_id": "uuid",
  "gtin": "08930001000018",
  "product_name": "Pasteurized Fresh Milk 1L",
  "lot_number": "LOT-2026-0901",
  "expiration_date": "2026-09-15",
  "quantity": 480,
  "min_temp_celsius": 2.0,
  "max_temp_celsius": 8.0,
  "origin": { "location_id": "uuid", "gln": "8930001001015", "name": "Binh Duong DC" },
  "destination": { "location_id": "uuid", "gln": "8934567000017", "name": "District 7 Store Hub" },
  "participants": [
    { "tenant_id": "uuid", "role": "OWNER" },
    { "tenant_id": "uuid", "role": "CARRIER" },
    { "tenant_id": "uuid", "role": "CONSIGNEE" }
  ],
  "assigned_driver_id": null
}
```

**`shipment.participant_added`**: `{ "tenant_id": "uuid", "role": "CARRIER" | "INSPECTOR" }`. A new `CARRIER`
replaces the owner, which carried the shipment until then, and ends any driver assignment.

**`shipment.driver_assigned`**: `{ "driver_user_id": "uuid" }`

**`shipment.pickup_confirmed`**

```json
{
  "driver_user_id": "uuid",
  "position": { "latitude": 10.870512, "longitude": 106.803488, "accuracy_meters": 12.0 },
  "distance_meters": 18.4
}
```

**`shipment.checkpoint_recorded`**: `{ "facility": { "gln": "…", "name": "…" }, "position": {…}, "distance_meters": 25.1 }`

**`shipment.delivery_confirmed`**: `{ "receiver_user_id": "uuid", "position": {…}, "distance_meters": 9.7 }`

**`shipment.cancelled`**: `{ "reason": "Customer order withdrawn" }`

**`shipment.recalled`**

```json
{
  "recall_id": "uuid",
  "lot_id": "uuid",
  "gtin": "08930001000018",
  "lot_number": "LOT-2026-0901",
  "reason": "Supplier reported contamination",
  "previous_status": "IN_TRANSIT"
}
```

**`shipment.document_attached`** (M2)

```json
{
  "document_id": "uuid",
  "document_type": "CERTIFICATE_OF_QUALITY",
  "plaintext_sha256": "…64 hex…",
  "ciphertext_cid": "bafy…"
}
```

---

## 4. Kafka topic `iot.telemetry.raw`

Normalized readings, one message per reading. This topic has no domain envelope, because it carries raw
data rather than domain events.

```json
{
  "device_id": "REEFER-0001",
  "sscc": "089300010000000018",
  "recorded_at": "2026-09-01T14:30:00.123Z",
  "received_at": "2026-09-01T14:30:00.410Z",
  "temperature_celsius": 9.4,
  "humidity_percent": 65.2,
  "latitude": 10.8705,
  "longitude": 106.8035
}
```

- Values are rounded to the precision that the database stores: two decimals for temperature and humidity,
  six for coordinates. `humidity_percent` is `null` when the device has no humidity sensor.
- Timestamps carry milliseconds, the precision of device clocks.
- Headers are `traceparent` (a new trace per reading) and `content-type`. Raw readings are not domain
  events, so they carry no `event-type`.

`iot.telemetry.dlq` wraps a record that the processor cannot store as
`{ "error": "…", "failed_at": "…", "record": { … } }`, with the original key and a span in the original trace.
`record` is the original value, or a JSON string when the value is not JSON. A record that fails validation is
dead-lettered at once; a reading that the database refuses is tried three more times first.

---

## 5. Kafka topic `telemetry.incidents`

Envelope from §2.1 with `producer = "telemetry-stream-service"` and `actor = null`.

**`cold_chain.breach_confirmed`**

```json
{
  "incident_id": "uuid",
  "shipment_id": "uuid",
  "sscc": "089300010000000018",
  "device_id": "REEFER-0001",
  "started_at": "2026-09-01T14:30:00.000Z",
  "confirmed_at": "2026-09-01T14:30:30.000Z",
  "min_temp_celsius": 2.0,
  "max_temp_celsius": 8.0,
  "temperature_celsius": 9.4,
  "latitude": 10.8705,
  "longitude": 106.8035,
  "incident_hash": "…64 hex…"
}
```

`incident_hash` is the SHA-256 of the RFC 8785 canonical JSON of this object without `incident_hash`
([test vectors](test-vectors/incident-hash.json)). Times in incident data are device times with milliseconds.

**`cold_chain.breach_resolved`**

```json
{
  "incident_id": "uuid",
  "sscc": "089300010000000018",
  "ended_at": "2026-09-01T14:36:10.000Z",
  "duration_seconds": 370,
  "extreme_temperature_celsius": 11.2
}
```

- `occurred_at` is `confirmed_at` or `ended_at`, and `subject.status` is the shipment's status at that point.
- `ended_at` is the first reading back in bounds, the last reading before a gap, or the last reading before the
  shipment stopped being monitored ([cold-chain-monitoring.md §4](../domain/cold-chain-monitoring.md#4-breach-rule)).
  `duration_seconds` counts whole seconds from `started_at`.
- `event_id` and `incident_id` are derived from the incident, so an event produced again after a failure is
  identical to the first and consumers can drop it. Records carry the `traceparent` of the reading or shipment
  event that caused them.

---

## 6. WebSocket: real-time notifications

| Property | Value |
| --- | --- |
| Endpoint | `GET /ws/v1/notifications` (telemetry-stream-service, behind the gateway) |
| Subprotocols | The client offers `["veritrace.v1", "bearer.<access_token>"]`; the server selects `veritrace.v1` |
| Origin | Same origin as the frontend (through the gateway), or an origin listed in `WS_ALLOWED_ORIGINS` (cloud mode); other origins are rejected before the upgrade |
| Authorization | Tenant and role from the token. Notifications go only to participant tenants of the affected shipment. `DRIVER` connections receive only their assigned shipments. |
| Heartbeat | Server ping every 30 s; the connection is closed if no pong arrives within 10 s |
| Token expiry | The server closes the connection with `4401` at token expiry; the client reconnects with a fresh token |
| Close codes | `4400` bad message, `4401` unauthenticated or expired, `4403` forbidden subscription, `4408` too many subscriptions (max 20), `1001` server shutdown |
| Delivery | Every instance reads `telemetry.incidents`, `shipment.events`, and `iot.telemetry.raw` from the end, in a consumer group of its own, and delivers to its own connections ([ADR-0012](../adr/0012-cold-chain-detection-engine.md)). Nothing is replayed after a reconnect: clients read the current state through the REST API. |

The handshake is refused before the upgrade with `400` when `veritrace.v1` is not offered and with `403` for
another origin. After the upgrade:

- A missing, invalid, or expired token closes the connection with `4401`, so the client refreshes its token
  and reconnects. The server closes with `1013` while tokens cannot be verified (core's keys are unreachable).
- A frame that is not a JSON text message of at most 4 KiB closes the connection with `4400`.
- A connection that falls more than 256 messages behind is closed with `1008`; the client reconnects.

### 6.1 Server → client

Every message:

```json
{ "type": "…", "id": "uuid", "sent_at": "…", "data": { … } }
```

| `type` | Delivered to | `data` |
| --- | --- | --- |
| `cold_chain.breach_confirmed` | participants and the assigned driver | §5 payload plus `product_name` and `gtin` |
| `cold_chain.breach_resolved` | same | §5 payload |
| `shipment.recalled` | participants of the recalled shipment | `{shipment_id, sscc, recall_id, gtin, lot_number, product_name, reason}` |
| `telemetry.reading` | subscribers of the SSCC | §4 payload without `received_at` |
| `subscribed` / `unsubscribed` | requester | `{ "channel": "telemetry", "sscc": "…" }` |
| `error` | requester | `{ "code": "FORBIDDEN" \| "NOT_FOUND" \| "INVALID_MESSAGE", "message": "…" }` |

For breaches and recalls, `id` is the `event_id` of the Kafka event, so a client can drop a repeated message.
The telemetry service's OpenAPI document describes these messages as the `NotificationMessage` and
`ClientMessage` schemas, so clients can generate their types.

### 6.2 Client → server

```json
{ "type": "subscribe", "channel": "telemetry", "sscc": "089300010000000018" }
{ "type": "unsubscribe", "channel": "telemetry", "sscc": "089300010000000018" }
```

Subscriptions are allowed only for shipments that the caller may view
([access-control.md](../domain/access-control.md)):

- A malformed message, an unknown `type` or `channel`, or an invalid SSCC answers `error` `INVALID_MESSAGE`.
- A shipment that the telemetry service does not know, or in which the caller's tenant takes no part, answers
  `error` `NOT_FOUND`. The connection stays open; the projection may not have the shipment yet.
- A visible shipment that a driver is not assigned to answers `error` `FORBIDDEN`, and the connection closes
  with `4403`.
- Following the same SSCC again is not another subscription; a 21st one closes the connection with `4408`.
