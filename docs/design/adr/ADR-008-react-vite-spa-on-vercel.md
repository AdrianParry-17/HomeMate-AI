# ADR-008: Build the front end as a React + Vite single-page app hosted on Vercel

New in PA3 (framework and hosting, from PA1 §3.2) · Date: 2026-11-17 · Deciders: Team T08 · Related: NFR-05, NFR-09, F08 (Won't), R02

| ADR | ADR-008: Build the front end as a React + Vite single-page app hosted on Vercel |
|---|---|
| Status | accepted |
| Context | The product is a responsive web app used on desktop and on phones at the construction site (NFR-05, NFR-09); native apps are out of scope (F08 Won't). All server logic is in Supabase (ADR-001), so the front end only needs static hosting. Hosting must be free, and pull requests should be easy to review. |
| Decision | React + TypeScript single-page app built with Vite and styled with Tailwind CSS; TanStack Query for server state, Zod for form validation, Recharts for dashboard charts, supabase-js for all Supabase calls. The static build is deployed to Vercel: production from `main`, and a preview deployment for every pull request. |
| Alternatives considered | (a) **Next.js** (server rendering, API routes): its server features would go unused because Supabase is the back end, and it adds concepts the team does not need. <br>(b) **Native or cross-platform mobile app** (Flutter, React Native): out of scope (F08 Won't), and installation hurts crew-leader adoption. <br>(c) **GitHub Pages or Netlify**: GitHub Pages needs workarounds for single-page-app routing and has no pull-request previews; Netlify is equivalent to Vercel, and Vercel was chosen in PA1. |
| Consequences | **+** Free static hosting and preview links for pull-request reviews. <br>**+** One language (TypeScript) for the front end and the Edge Functions. <br>**−** All front-end code runs on the user's device and is untrusted, so every rule must also be enforced in the database (ADR-002). <br>**−** A larger first download than a server-rendered page; acceptable for a signed-in app with no SEO needs. |
