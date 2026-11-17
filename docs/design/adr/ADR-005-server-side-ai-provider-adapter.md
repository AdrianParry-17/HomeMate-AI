# ADR-005: Call Gemini only through a server-side AI provider adapter with a timeout and a mandatory disclaimer

Formalizes PA1 **AD-05** · Date: 2026-11-17 · Deciders: Team T08 · Related: FR-23, NFR-02, NFR-04, NFR-08, BR-12, UC-06 E1/E2, UC-10 E1/E3, R03, R05

| ADR | ADR-005: Call Gemini only through a server-side AI provider adapter with a timeout and a mandatory disclaimer |
|---|---|
| Status | accepted |
| Context | The Gemini API key must never reach the browser (NFR-04). Requests can hang, hit the free-tier quota (HTTP 429) or fail, and the app must stop waiting after 20 seconds and offer a retry or manual alternative (NFR-02). Every AI answer and draft must carry a safety limitation (FR-23, BR-12). The provider or model may have to change if Gemini becomes unavailable (R05), and tests must run without spending quota. |
| Decision | Only the Edge Functions call Gemini, and only through the `AIProvider` interface. `GeminiClient` implements it: the key comes from the Edge Function secret `GEMINI_API_KEY`, the model name from an environment variable, every call has a 20,000 ms timeout, and HTTP 429, 5xx and timeouts are mapped to `AIUnavailableError`, which the Web App shows as a fallback message with retry. `MockAIProvider` implements the same interface for tests. `SafetyPolicy` attaches the disclaimer on the server and detects structural-certification requests (UC-10 E1). |
| Alternatives considered | (a) **Call Gemini from the browser**: exposes the API key; violates NFR-04. <br>(b) **Use the Gemini SDK directly in each handler**: no seam for tests or for switching provider. <br>(c) **Add the disclaimer only in the UI**: a client bug could omit it; adding it on the server guarantees it is in every stored answer. |
| Consequences | **+** The key never leaves the server; changing provider or model touches one class or one variable. <br>**+** AI flows can be tested without quota. <br>**−** The extra hop through an Edge Function adds latency. <br>**−** Edge Function invocations count against the free-tier limits. |
