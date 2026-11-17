# ADR-007: Show exception alerts in the app only

Formalizes **AD-07**, which PA2 UC-13 cites but PA1 did not define · Date: 2026-11-17 · Deciders: Team T08 · Related: FR-26 (Could), UC-13, BR-06, BR-07

| ADR | ADR-007: Show exception alerts in the app only |
|---|---|
| Status | proposed |
| Context | F07 (proactive budget and stage-delay alerts) is a Could feature and may be deferred. If it is built, it must not add paid services or new infrastructure, and the built-in Supabase mailer is rate-limited. |
| Decision | If F07 is implemented, alerts are evaluated when the dashboard loads or a record changes, using the fixed 85 % / 100 % thresholds (BR-06) and overdue, not-completed stages (UC-13), and shown as an in-app badge and list. No push notifications, e-mail or SMS. |
| Alternatives considered | (a) **Web push notifications**: needs a service worker, permission prompts and more testing. <br>(b) **E-mail or SMS**: cost, mailer rate limits and an extra provider. <br>(c) **A scheduled server job** (pg_cron or scheduled functions): more moving parts for a Could feature. |
| Consequences | **+** No extra service or cost; easy to remove if F07 is dropped. <br>**−** The owner only sees alerts when opening the app. <br>**−** Stays "proposed" until the team decides whether F07 is in PA5. |
