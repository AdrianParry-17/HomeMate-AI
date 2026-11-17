# ADR-006: Remove personal data from the AI context in two layers

Formalizes **AD-06**, which PA2 UC-10 cites but PA1 did not define · Date: 2026-11-17 · Deciders: Team T08 · Related: FR-22, NFR-07, UC-10 E2, PA0 §3.6 (confidentiality)

| ADR | ADR-006: Remove personal data from the AI context in two layers |
|---|---|
| Status | accepted |
| Context | Worker names and phone numbers are personal data and must not be sent to an external AI service (FR-22, NFR-07; PA0 team rule on confidentiality). Users can also type phone numbers or e-mail addresses into free text such as expense notes or chat questions. |
| Decision | **Layer 1, SQL:** the RPC `get_ai_project_context` never selects `workers.full_name` or `workers.phone`; workers appear only as aliases such as "Worker_01 (Mason)". **Layer 2, Edge Function:** `PiiSanitizer` removes phone-number and e-mail patterns from all free text before the prompt is built, and `ProjectContextBuilder.build()` refuses to run if `sanitize()` was not called. |
| Alternatives considered | (a) **Tell the model in the prompt not to repeat names**: the data still leaves the system. <br>(b) **Remove personal data in the browser**: can be bypassed. <br>(c) **SQL layer only**: misses personal data typed into notes. |
| Consequences | **+** The outgoing payload can be inspected in tests (NFR-07; the PA3-C test checks for "Worker_01 (Mason)"). <br>**−** The AI can only refer to workers by alias, so it cannot answer questions that name a worker. <br>**−** Pattern matching can miss unusual formats; this is a documented limitation. |
