# ADR-003: Keep AI stage plans as unsaved drafts until the owner confirms them

Formalizes PA1 **AD-03** · Date: 2026-11-17 · Deciders: Team T08 · Related: FR-13, FR-14, BR-08, NFR-08, AC-05, UC-06 E3, R03

| ADR | ADR-003: Keep AI stage plans as unsaved drafts until the owner confirms them |
|---|---|
| Status | accepted |
| Context | Gemini can return a wrong or unsafe stage plan (risk R03). The owner must review and edit it before it becomes part of the schedule (FR-14, BR-08), and UC-06 E3 requires that the database contains **zero** unconfirmed AI stages, even if the owner closes the browser. |
| Decision | The `generate-stage-plan` Edge Function returns `StageDraft[]`, a transient object checked by `StagePlanValidator` and carrying the safety disclaimer. Nothing is written to the database. The draft lives only in the Web App's memory while the owner edits it. On "Confirm & Save", `StageService.confirmDraft` calls the RPC `confirm_stage_plan`, which inserts all stages in **one transaction**: all stages are saved or none are. The draft's key tasks are shown during review but not stored; only stage name, order and planned dates are saved. |
| Alternatives considered | (a) **Save draft rows with a "draft" status**: breaks the "zero unconfirmed rows" rule, needs a clean-up job, and drafts could leak into dashboards and AI context. <br>(b) **A separate draft table**: same clean-up problem plus extra RLS policies. <br>(c) **Insert confirmed stages one by one from the client**: a network failure could leave half a schedule saved. |
| Consequences | **+** The rule is simple to test: cancel a draft, then check the `stages` table (AC-05). <br>**+** Saving is atomic. <br>**−** A draft is lost if the browser closes before confirmation; the owner regenerates it (accepted by UC-06 E3). <br>**−** Each regeneration is another Gemini call against the free quota. |
