# ADR-0024: Thermal exposure and dynamic shelf life

- **Status:** Accepted
- **Date:** 2026-11-21

## Context

A breach tells that the cold chain failed, not what the failure did to the goods. The consignee who receives a
pallet after a breach must decide whether to accept it, sell it sooner, or reject it. Today that decision rests on
the incident list alone: 40 seconds at 8.5 °C and three hours at 22 °C both show up as one incident.

Two established tools answer the question:

- **Mean kinetic temperature (MKT)**, defined in USP <1079> and ICH Q1A for pharmaceutical storage, condenses a
  fluctuating temperature history into the one constant temperature that would have the same kinetic effect.
- **Q10 kinetics**, used in food science for shelf-life prediction: the rate of quality loss multiplies by Q10 for
  every 10 °C. Shelf life that tracks the actual temperature history is known as dynamic shelf life, and it
  underlies first-expired-first-out by remaining life rather than by printed date.

The platform has the inputs: every reading, the product's bounds, and the lot's production and expiration dates.

## Decision

- **Thermal exposure per shipment**, computed by the telemetry service from the readings recorded while the
  shipment is monitored ([cold-chain-monitoring.md §8](../domain/cold-chain-monitoring.md#8-thermal-exposure-and-shelf-life)):
  covered and uncovered time, time-weighted mean temperature, MKT (ΔH = 83.144 kJ/mol), time above and below the
  bounds, and degree-minutes above and below them. It is served at
  `GET /api/v1/telemetry/shipments/{sscc}/thermal-exposure`.
- **Shelf-life model:**
  - The label shelf life holds while the goods stay within their bounds. Above the upper bound, the goods age
    faster by `Q10^((T − T_max) / 10)`. The extra aging moves the expiry earlier.
  - Time below the upper bound earns no credit, so the estimate never extends the label date.
  - Cold damage below the lower bound is a breach matter, outside the model.
- **Q10 is a product attribute** (`shelf_life_q10`, 1–10, default 3.0). Lots copy it at commissioning, and
  shipments copy it from the lot together with the production date, as they already copy the bounds. The default
  matches the activation energy that MKT assumes: 83.144 kJ/mol gives Q10 ≈ 3.1 between 20 and 30 °C.
- **Alerts:** the detector re-assesses shelf life when a breach ends and every 15 minutes while one lasts. When the
  status gets worse (`INTACT` → `REDUCED` → `EXPIRED`), it produces `cold_chain.shelf_life_reduced` on
  `telemetry.forecasts` and pushes it to the shipment's participants.
- **Computation in the database:** the sums behind the exposure are one aggregate over the shipment's readings,
  with window functions in TimescaleDB, so no reading leaves the database; the service derives MKT and the shelf
  life from them. Shared test vectors ([thermal-exposure.json](../contracts/test-vectors/thermal-exposure.json)),
  computed independently, check the result.

## Consequences

- The consignee sees, at delivery, how much shelf life the cold chain cost and the estimated expiration date.
  Breaches can be compared by their effect, not just their count.
- Q10 is an estimate per product family. The model is a decision aid, not a laboratory result, and the API says
  which Q10 it used.
- Dates are calendar dates without a time zone. The model reads them as whole days in UTC, which shifts the day
  boundary by the local offset; at the precision of a shelf life in days this is accepted.
- Shipments created before these fields existed have no production date in the telemetry projection. Their
  exposure is reported without the shelf-life part.
- The upper bound doubles as the reference temperature, so no second temperature has to be configured. A product
  whose label shelf life was established well below its upper bound gets an estimate that is too generous; a lower
  upper bound or a higher Q10 compensates.
