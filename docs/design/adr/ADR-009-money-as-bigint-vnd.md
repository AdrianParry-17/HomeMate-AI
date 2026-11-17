# ADR-009: Store money as BIGINT whole VND and calculate totals in views

Based on ADR-00y proposed in PA3-C (Trần Gia Huy) · Date: 2026-11-17 · Deciders: Team T08 · Related: FR-09, FR-10, FR-20, BR-04, BR-11, NFR-01, NFR-06, AC-07

| ADR | ADR-009: Store money as BIGINT whole VND and calculate totals in views |
|---|---|
| Status | accepted |
| Context | NFR-06 requires 1-VND precision and BR-04 an exact representation. Floating-point numbers can introduce rounding errors, and totals stored separately from their records can drift out of sync. Historical wage estimates must not change when a worker's rate changes (BR-11). |
| Decision | All money columns are `BIGINT` in whole VND; quantities are `NUMERIC(12,3)`. `expenses.line_total` is a generated column, `round(quantity × unit_price)`. Spent amounts, remaining balance, threshold state and wage estimates are calculated in the views `v_category_spending`, `v_project_financial_summary` and `v_attendance_wages`. Each attendance record copies the worker's rate when it is created (trigger `snapshot_attendance_rate`), and that copy cannot be changed. |
| Alternatives considered | (a) **`NUMERIC(14,2)` money**: VND has no minor unit, so decimals add nothing. <br>(b) **Store totals in project or category rows, updated by triggers**: faster reads, but the totals can become inconsistent. <br>(c) **Calculate wages from the current rate**: rewrites history when a rate changes; violates BR-11. |
| Consequences | **+** Totals are correct by construction; AC-07 (2,250,000 VND) is checked in SQL. <br>**+** `BIGINT` values are safe in JavaScript up to about 9 × 10^15 VND. <br>**−** Dashboards add up values when read; fast enough for the NFR-01 data size thanks to the indexes. <br>**−** `captured_rate` is a deliberate denormalisation, documented in the PA3-C normalisation section. |
