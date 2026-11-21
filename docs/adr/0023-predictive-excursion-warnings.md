# ADR-0023: Predictive excursion warnings

- **Status:** Accepted
- **Date:** 2026-11-21

## Context

The breach rule ([ADR-0012](0012-cold-chain-detection-engine.md)) reports a breach 30 seconds after the temperature
has left its bounds. By then the goods are already exposed. Most breaches build up first: a reefer that fails or
loses power warms its load steadily for minutes before the bound is crossed. A forecast during that build-up gives
the driver and the operations team minutes to act (close a door, restart a unit, move the load) while action still
prevents the breach.

A forecast that is wrong too often trains people to ignore it, so its quality must be measured, not assumed. The
forecast has to run in the detector's hot path, per SSCC, on every reading, with the same at-least-once delivery,
partition moves, and rebuilds as the breach rule. The platform runs on a workstation at no cost, and the only data
available is the readings themselves: there is no history of labelled failures to train a model on.

## Decision

- **Model: a linear trend over a sliding window.** For each monitored SSCC the detector fits a straight line to the
  readings of the last 2 minutes by ordinary least squares and extrapolates it to the bound it approaches. This is
  the technique of Prometheus' `predict_linear` alerts: transparent, cheap (constant work per reading), and
  explainable to an operator ("rising 0.6 °C per minute, 8 °C expected at 14:35").
- **Guards against false alarms**, each a rule of
  [cold-chain-monitoring.md §7](../domain/cold-chain-monitoring.md#7-excursion-warnings):
  - a minimum slope and a significant trend (t-statistic of the slope ≥ 3), so that noise is not extrapolated;
  - the temperature must already have moved at least 0.3 °C away from the **operating level**, where the last 360
    in-bounds readings (30 minutes at the nominal interval) cluster most, so that a load recovering after a door was
    closed, or after a breach of hours, does not raise a warning about the opposite bound. A plain median of those
    readings is pulled up by the ramps of recent excursions; the densest 0.5 °C bin is not;
  - a horizon of 10 minutes;
  - two consecutive readings to issue a warning and three to clear it (hysteresis).
- **Warnings are advisory.** They never change the breach rule, and incidents never depend on them. A warning is
  issued, then closed with an outcome: `BREACHED` (a breach was confirmed while it was open, with the lead time),
  `CLEARED` (the trend turned), or `INCONCLUSIVE` (monitoring ended first).
- **Self-measured quality.** Every closed warning is a labelled forecast. The service reports precision, recall,
  lead time, and the error of the predicted excursion time over any period, from its own records
  (`GET /api/v1/telemetry/warnings/performance`).
- **Same engine discipline as incidents.** Forecast state lives in memory next to the episode, in the detector's
  batch transaction. Warning and event IDs are derived from `(sscc, issued_at)`, an SSCC has at most one open
  warning, and closing a warning is a conditional update, so reprocessing never duplicates a warning or an event.
  A rebuild refills the window from the database but does not issue or clear warnings for readings evaluated before.
- **Separate topic.** Warnings travel on a new Kafka topic, `telemetry.forecasts`, not on `telemetry.incidents`:
  incidents are facts that M2 anchors on chain, while forecasts are model estimates that are not anchored and need
  no unlimited retention.

## Alternatives considered

- **Holt's exponential smoothing or ARIMA:** better on long seasonal series, but harder to explain and to tune, and
  a reefer's minute-scale build-up is close to linear.
- **A trained classifier:** no labelled failure history exists, and one trained on simulated data would only learn
  the simulator.
- **Fixed pre-alarm threshold (for example 7 °C for 2–8 °C goods):** simple, but it warns late on a fast rise,
  too often on a load that sits near the bound, and carries no time estimate.

## Consequences

- Operators get minutes of lead time on breaches that build up, with an estimated excursion time.
- Abrupt failures (a door opened at 30 °C) still go straight to a breach: there is no trend to see first.
- The parameters trade lead time against false alarms. They are constants of the detector, and the evaluation run
  of the demonstration kit measures the effect of a change end to end.
- A `CLEARED` warning may be a breach that someone prevented after the warning. Precision measured in operation is
  therefore a lower bound; the evaluation run, where nobody intervenes, measures it exactly.
- The detector keeps up to 360 temperatures per SSCC in memory for the operating level, and a rebuild reads them
  from the database.
