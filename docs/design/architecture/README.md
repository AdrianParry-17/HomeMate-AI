# Architecture diagrams (PA3 — Section A)

Owner: Huỳnh Minh Hùng · Jira: SCRUM-21, SCRUM-22

| File | PA3 template heading | Content |
|---|---|---|
| `c4-context.puml` / `.png` | System Context Diagram (C4 level 1) | Update of PA1 Figure 3.1 |
| `c4-container.puml` / `.png` | Container Diagram (C4 level 2) | Web App, Auth Service, Data API, Edge Functions, Database; Gemini and Email outside |
| `component-web-app.puml` / `.png` | Component Diagram | Web App split by feature (F01–F04), names match `docs/design/uml` |
| `component-edge-functions.puml` / `.png` | Component Diagram | The three Edge Functions and the AI safety pipeline |
| `deployment.puml` / `.png` | Deployment Diagram | User device, Vercel, Supabase Cloud (Singapore), Google Cloud, GitHub |

Decisions behind these diagrams: `docs/design/adr`.

## Render

The diagrams use the C4-PlantUML library that ships with PlantUML (`!include <C4/...>`) and the built-in
`smetana` layout, so Graphviz is not needed.

```bash
java -jar plantuml.jar -tpng -charset UTF-8 *.puml
```

Element and class names must stay in sync with `docs/design/uml/class-diagram-services.puml` and
`docs/design/data/schema.sql`. If you rename a class, a table or an Edge Function, update the diagrams too.
