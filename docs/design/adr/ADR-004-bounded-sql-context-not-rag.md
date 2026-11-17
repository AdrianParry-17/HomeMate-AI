# ADR-004: Build the AI context from a bounded SQL summary instead of vector retrieval (RAG)

Formalizes PA1 **AD-04** · Date: 2026-11-17 · Deciders: Team T08 · Related: FR-21, FR-22, NFR-02, NFR-07, UC-10, R05

| ADR | ADR-004: Build the AI context from a bounded SQL summary instead of vector retrieval (RAG) |
|---|---|
| Status | accepted |
| Context | FR-21 requires AI answers that use the owner's project records. The data is small and structured (the NFR-01 demo set is about 100 expenses and 20 workers), most questions are about totals and statuses, and every token sent to Gemini costs quota and time (NFR-02, R05). |
| Decision | The RPC `get_ai_project_context` returns a JSON snapshot: budget summary, category threshold states, stage statuses, the 10 latest expenses, 30-day labour totals and the last 6 chat turns, with workers shown only as aliases (ADR-006). In `ask-assistant`, `ProjectContextBuilder` keeps the context within 2,000 tokens, dropping the oldest chat turns first and then the oldest expenses. The context is rebuilt for every question and never stored. |
| Alternatives considered | (a) **Vector RAG** (embeddings in pgvector, similarity search): extra embedding calls, index upkeep and cost; poor at exact totals; unnecessary for small structured data. <br>(b) **Send all raw records**: exceeds the token budget and sends more personal data out. <br>(c) **No project context**: fails FR-21. |
| Consequences | **+** Exact numbers come from SQL, not from the model's memory. <br>**+** Cheap, deterministic and testable. <br>**−** The AI cannot see records outside the summary (for example, an expense from months ago); UC-10 A1 says the answer must state which records are missing. <br>**−** The snapshot must be updated when the schema changes. |
