# Data & Security Design (PA3 — Section C)

Owner: Trần Gia Huy · Jira: SCRUM-27, SCRUM-28, SCRUM-29

| File | Content |
|---|---|
| `schema.sql` | Tables, constraints, triggers (BR-01, BR-11), indexes, derived-data views |
| `rls-policies.sql` | RLS policies, permission helpers, RPC functions for crew-leader actions and the AI context |
| `erd.puml` / `erd.png` | Physical ERD (PlantUML source and rendered image) |
| `tests/00_supabase_shim.sql` | Minimal stand-in for Supabase Auth so the design runs on plain PostgreSQL. **Never run this on Supabase.** |
| `tests/10_verify_design.sql` | 47 checks for PA2 acceptance criteria, business rules and the access matrix |

## Run the verification locally (PostgreSQL 15+)

```bash
createdb homemate_verify
cat tests/00_supabase_shim.sql schema.sql rls-policies.sql | psql -v ON_ERROR_STOP=1 -d homemate_verify
psql -d homemate_verify -t -f tests/10_verify_design.sql | grep -c PASS   # expect 47, and no ERROR lines
```

Run the test script on a fresh database: it creates fixed test users and fails if they already exist.

## Use on Supabase (PA5)

Apply `schema.sql` and then `rls-policies.sql` as migrations (`supabase migration new ...`). Do not apply the files in `tests/`.
