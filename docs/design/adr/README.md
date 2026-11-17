# Architecture Decision Records (PA3 — Section A)

Owner: Huỳnh Minh Hùng · Jira: SCRUM-23

One file per decision, using the PA3 template table (ADR, Status, Context, Decision, Alternatives considered, Consequences).
ADR-001 to ADR-007 formalize the short decisions AD-01 to AD-07 from PA1 §3.1 and PA2 (UC-06, UC-10, UC-13), so the earlier references stay valid.

| ADR | Title | Status | Formalizes |
|---|---|---|---|
| [ADR-001](ADR-001-supabase-backend-as-a-service.md) | Use Supabase as the Backend-as-a-Service | accepted | AD-01 |
| [ADR-002](ADR-002-authorization-rls-and-rpc.md) | Enforce authorization in the database with RLS and permission-checked RPC functions | accepted | AD-02 (and PA3-C ADR-00x) |
| [ADR-003](ADR-003-ai-stage-plan-draft-until-confirmed.md) | Keep AI stage plans as unsaved drafts until the owner confirms them | accepted | AD-03 |
| [ADR-004](ADR-004-bounded-sql-context-not-rag.md) | Build the AI context from a bounded SQL summary instead of vector retrieval (RAG) | accepted | AD-04 |
| [ADR-005](ADR-005-server-side-ai-provider-adapter.md) | Call Gemini only through a server-side AI provider adapter with a timeout and a mandatory disclaimer | accepted | AD-05 |
| [ADR-006](ADR-006-remove-personal-data-before-ai.md) | Remove personal data from the AI context in two layers | accepted | AD-06 |
| [ADR-007](ADR-007-in-app-alerts-only.md) | Show exception alerts in the app only | proposed | AD-07 |
| [ADR-008](ADR-008-react-vite-spa-on-vercel.md) | Build the front end as a React + Vite single-page app hosted on Vercel | accepted | — (new) |
| [ADR-009](ADR-009-money-as-bigint-vnd.md) | Store money as BIGINT whole VND and calculate totals in views | accepted | — (PA3-C ADR-00y) |

## Rules

- Status is one of `proposed`, `accepted`, `superseded`.
- An accepted ADR is not edited. To change a decision, add a new ADR and mark the old one `superseded by ADR-0xx`.
- Use the next free number and the file name `ADR-0xx-short-title.md`.
