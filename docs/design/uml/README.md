# UML — Class Diagrams (PA3 — Section C)

Owner: Trần Gia Huy · Jira: SCRUM-30, SCRUM-31

| File | Content |
|---|---|
| `class-diagram-domain.puml` / `.png` | Package `domain`: entities, enums, WageCalculator (Strategy), BudgetThresholdEvaluator |
| `class-diagram-services.puml` / `.png` | Packages `client.services` and `edge-functions`: services, handlers, AIProvider/GeminiClient (Adapter), ProjectContextBuilder (Builder) |

Render: `java -jar plantuml.jar -tpng *.puml`

## Operations for the sequence diagrams (hand-off to SCRUM-35)

The PA3 template requires every message in a sequence diagram to match an operation in the class diagram. These are the main call chains:

| Use case | Main flow (caller → operation) | Suggested `alt` fragment |
|---|---|---|
| UC-04 Add expense | ExpenseForm → `ExpenseService.addExpense(input)` → `Expense.validate()` → `Expense.calculateLineTotal()` → `SupabaseGateway` insert `expenses` → `BudgetService.getDashboardSummary(projectId)` | invalid input → inline error / valid → saved |
| UC-06 AI stage plan | Planner screen → `StageService.requestAIDraft(projectId, input)` → `GenerateStagePlanHandler.handle(req)` → `authenticate(req)` → `PromptBuilder.buildStagePlanPrompt(input)` → `AIProvider.generateJson(prompt, schema, 20000)` → `StagePlanValidator.validate(raw)` → `SafetyPolicy.attachDisclaimer(...)`; owner confirms → `StageService.confirmDraft(projectId, drafts)` → RPC `confirm_stage_plan` | timeout / HTTP 429 / invalid JSON → `toErrorResponse` → manual planning |
| UC-09 Record attendance | Attendance screen → `AttendanceService.recordAttendance(projectId, date, entries)` → RPC `upsert_attendance` (trigger `snapshot_attendance_rate`) → `AttendanceService.getWageSummary(projectId, from, to)` | crew leader without permission → FORBIDDEN |
| UC-10 Ask AI | Chat screen → `AIAssistantService.askQuestion(projectId, q)` → `AskAssistantHandler.handle(req)` → RPC `get_ai_project_context` → `ProjectContextBuilder.fromSnapshot().sanitize().limitTokens().build()` → `PromptBuilder.buildQuestionPrompt(ctx, q)` → `AIProvider.generateText(prompt, 20000)` → `SafetyPolicy.attachDisclaimer(answer)` | Gemini error → fallback message; certification request → `SafetyPolicy.isCertificationRequest` refusal |
| UC-02 Invite crew leader | Access screen → `ProjectService.inviteCrewLeader(projectId, email, perms)` → `InviteCrewHandler.handle(req)` → Supabase Auth invite → insert `project_members`; crew leader → `ProjectService.acceptInvitation(projectId)` → RPC `accept_invitation` | not the owner → 403 |

Stage status transitions for the state machine (SCRUM-36): NOT_STARTED → IN_PROGRESS → COMPLETED; COMPLETED → IN_PROGRESS (reopen, UC-07 A1); IN_PROGRESS → NOT_STARTED (undo).
