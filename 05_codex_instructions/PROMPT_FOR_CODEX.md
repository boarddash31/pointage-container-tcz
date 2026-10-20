# CODEX TASK — POINTAGE CONTAINER (Flutter + Supabase)

You are responsible for implementing a production-quality container terminal application using the supplied references. These are REFERENCES, not a finished production app. Preserve functionality but improve UI/UX substantially. Do not simply wrap HTML in WebView: implement native Flutter widgets for Android/iOS and Flutter Web admin dashboard.

## First steps
1. Inspect `01_existing_mobile_prototype/v6/` (latest HTML demo) and `v2_reference/` (known to display in ChatGPT more reliably), screenshots, spreadsheets, and operator list.
2. Write an executable milestone plan in `PROGRESS.md` and create an organized Flutter + Supabase monorepo. Work incrementally and test each milestone; avoid giant untested changes.
3. Implement Supabase SQL migrations, indexes, RLS, Auth, secure role enforcement, audit/event logs, and seed/reference import. Never put service-role keys in client code.

## Mobile workflows
- Entrée: a SINGLE form with plate, CIN, truck loaded/empty selection with prominent accurate truck illustration, 11 separate editable boxes (4 letters, 7 digits, ISO 6346 checksum) for loaded container OR free-format booking for empty truck, ISO, searchable armateur selector with logo or text fallback. On selection/lookup auto-fill ISO/armateur but allow authorized corrections. Order: Plaque, CIN, Container/Booking, truck-image choice, ISO, Armateur.
- Engin: FIFO oldest entry first, list with unambiguous truck loaded/empty illustration, `À saisir`/`Validé` only, tap plate to open action popup directly; Dépose means container visibly ON GROUND next to EMPTY truck; Prise means container visibly ON TRUCK CHASSIS. For prise require container number, validate reference/ISO, allow authorized cancellation with reason/code.
- Sortie: all trucks still inside, even if Engin step incomplete; enable completing missing step then validating exit; log user/time/status and cancellation. FIFO.
- Bottom navigation: `Pointage`, `Data`, `Bons` (not duplicate Entrée/Engin/Sortie). Top process navigation can contain Entrée/Engin/Sortie.
- Data: searchable truck visits, container lifecycle, user action timeline, durations, client/armateur filters.
- Bons: entry/charge/décharge/sortie PDF, generate and download immediately on save, preview, choose printer with normal print dialog, optional direct network printing through an authenticated local bridge, store PDFs in private Supabase Storage with audit metadata, enable reprint. Persist preferred printer settings locally. Browser-only HTML cannot print silently to arbitrary network IP.

## Backend and business model
- PostgreSQL tables: users/profiles/roles, clients, armateurs, client_armateurs (effective dates), containers (canonical number, ISO, armateur), bookings (reference, client, armateur, ISO), truck_visits, yard_operations, visit_events, audit_logs, container_stock_intervals, generated_documents, printer_settings as appropriate.
- All mutations transactional, with RLS and server-side authorization; cancellation never deletes history; preserve before/after and actor timestamps.
- Separate container master data from immutable visit snapshots; container may be deposited by one truck and picked up by another. Prevent double-counting.
- Import the complete operator list from `02_operator_logos/operators.json` and support text fallback for all. `logo_manifest.csv` currently marks EVERY official logo unverified. SVG files under `name_fallback_svg` are name badges, NOT official brand marks. Search official sources to collect actual licensed brand assets where possible, and leave text fallback otherwise. Never label placeholders as verified logos.
- Booking numbers are free format, NOT constrained to ISO container regex. Use lookup/validation per operator.

## Web admin
- Auth and RBAC, dashboard, FIFO queues, searchable container and truck histories, hourly activity table with rows Entrée/Engin/Sortie and columns 00–23, truck dwell time and in-yard count, filters by client/armateur/date, user management, client-armateur assignment, audit log.
- Freepool stock report by client/date, end-of-day vs any-time-presence distinction, container types (20DV, 40DV ST/HC, 45DV, reefers, special), EVP conversion configurable and versioned, stock movements, historical inventory and client billing metrics. Reproduce reference Excel `REP_FREE_POOL`/`FREEPOOL JOURNALIER` layout and formulas as closely as possible after examining originals; do NOT guess financial logic, clearly flag assumptions and missing historical stock data.

## Acceptance criteria
- Flutter mobile app runs and major screens navigate with working state.
- Supabase migrations apply on a clean project; RLS tested; audit events correctly attributed.
- Entrée → Dépose/Prise → Sortie produces correct timeline and durations.
- PDF generated, downloaded, and archived; printer bridge is optional and safe.
- Exported Freepool workbook reconciles to test fixture stock movements.
- No hardcoded secrets. Provide README, .env.example, deploy instructions, smoke tests and Git commits.

Start with architecture, Supabase schema and Flutter Entrée/Engin/Sortie. Continue milestone-by-milestone with concise status updates. Do not claim completion without running tests.
