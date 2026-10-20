# Pointage Container — progress

Updated: 2026-10-20 (Africa/Casablanca)

## Source audit

- Read `README_START_HERE.md` and `05_codex_instructions/PROMPT_FOR_CODEX.md`.
- Inspected V6 HTML, V2 reference, truck artwork, UI montage, six spreadsheet reports, 95 armateurs in `02_operator_logos/operators.json`, and the separate real-logo source pack. V6 is a localStorage demo, not a production backend. Every archive logo manifest entry is an unverified placeholder; keep text fallback.
- Parsed XLSX report layouts, including `REP_FREE_POOL`/`FREEPOOL JOURNALIER`. Original XLS formula-level review and reconciliation remain open.
- The TCZ Supabase project `iparzfqxopcvwqelxlad` had no public tables or Auth users before deployment. Six migrations (including the 95-armateur catalog) were applied on 2026-10-20; the Table Editor now lists the created tables. Both Edge Functions were deployed. The existing public schema was empty, but a database dump was unavailable because Docker/Podman is not installed.

## Milestones

| ID | Deliverable | Status | Verification |
|---|---|---|---|
| M0 | Source audit, architecture, executable plan | Partial | Source inventory and XLSX layouts reviewed; legacy XLS formulas pending |
| M1 | Supabase schema, roles, RLS, transactional Entrée/Engin/Sortie, 95 armateurs | Deployed to TCZ; authenticated E2E pending | Six migrations applied. Table Editor lists tables; service-role count is 95 armateurs, anonymous read returns zero; anonymous function calls return 401. Isolated PGlite lifecycle/RLS tests pass. Authenticated live workflow and concurrency tests pending |
| M2 | Native Flutter Entrée/Engin/Sortie + Auth, FIFO and checksum | Release builds pass; device validation pending | Flutter 3.47.2 `analyze` and 3 widget/unit tests pass. Configured web build succeeds; 56.1 MB Android release APK built and its v2 signature verified with package `ma.tcz.pointage_container`. Android/iOS device runs pending |
| M3 | Data, Bons PDF + private Storage and safe print flow | Partial | `generate-bon` deployed and anonymous calls denied. UI, Flutter-to-Node authenticated bridge, preferred-printer direct-print path and document-action audit present; two bridge tests pass. Authenticated PDF generation/share/printer verification pending |
| M4 | Web admin, clients, RBAC, assignments, analytics | Partial | Admin UI can invite agents with initial role through deployed `invite-user` Edge Function; first admin invitation and role created. Role matrix and browser acceptance pending |
| M5 | Freepool historical stock and Excel export | Partial | SQL report and workbook source present; synthetic XLSX round-trip test passes. Historical opening stock and source-report reconciliation pending |
| M6 | Deployment hardening and end-to-end acceptance | Partial | Netlify site and APK are public; external GET/HEAD return HTTP 200 and downloaded APK SHA-256 matches the signed local artifact. Supabase Auth Site URL and redirect allowlist point to Netlify. Admin activation, authenticated device and printer acceptance remain open |

## Architecture and implementation

Flutter widgets for Android/iOS and web. Supabase Auth authenticates each operator. RLS scopes reads; SQL RPCs make each state transition atomic and write visit events/audit. The client uses a publishable key only. Container master is separate from truck visits and container stock intervals. Entrée loaded -> Engin Dépose -> Sortie camion, or Entrée empty booking -> Engin Prise -> Sortie loaded. Sortie may complete a missing Engin step. A private Storage bucket holds generated PDFs; browser printing uses the normal dialog. Freepool distinguishes end-of-day stock from any-time presence and does not invent billing rates.

Generated Android, iOS and web platform projects with Flutter 3.47.2. Resolved a `printing`/`excel` dependency conflict by pinning `printing` to 5.14.3, fixed analyzer findings and a SQL reserved-word error in `freepool_rows`, and repaired stale lookup feedback/ISO form refresh on Entrée. Added admin-only forced pickup with reconciliation queue, active-carrier uniqueness, document access audit, audited manual container registration and optional automatic printing to a locally selected system printer. The Windows native-assets hook fails when SDK/project paths contain spaces; no-space junctions `E:\flutter_sdk_tcz` and `E:\pointage_tcz` enabled successful tests and build. `app/README.md` and `.env.example` document local setup without secrets.

On 2026-10-20, fixed the widget navigation fixture by disabling Supabase token auto-refresh; it had left a timer running after the test. Re-ran the full Flutter suite (3 passing), Flutter analyze (no issues), database smoke test, and two Node bridge tests. Rebuilt Flutter web successfully. The build still reports a non-blocking Wasm dry-run warning from the transitive `image` package and an icon-font warning; generated JavaScript web output succeeds.

Release work on 2026-10-20: created an ignored release keystore outside Git, replaced debug signing and example Android package ID, and built a v2-signed APK. The first Android build hit a Kotlin incremental-cache error; disabling Kotlin incremental compilation and using the in-process compiler resolved it. The configured web build and APK are copied into `site/` for Netlify. The release keystore at `E:\pointage_release_secrets` must be backed up securely before future updates.

## Open acceptance blockers

- The TCZ database is now migrated, but Auth invitation acceptance, authenticated workflow and private PDF Storage have not been exercised on a real client. No database dump is available because Docker/Podman is absent; the schema was empty before migration.
- The PDF Edge Function is deployed but no authenticated PDF has been generated. The authenticated Node bridge is implemented and tested for Supabase-authenticated shared-folder archiving, document audit and optional Windows printer submission; Flutter invokes it after save or from Bons when configured. It is not configured or deployed. `\\172.16.3.98\TCR PrintM` is an installed, reachable Windows **printer share**, not a PDF folder. The separate `\\172.17.18.218\pdf` archive share was read-only checked as reachable. A temporary write/read/delete probe was automatically rejected by environment policy, so archive write permissions remain unverified; real printer output is also unverified. Preferred local-system-printer direct printing is also untested with hardware. Browser silent printing is unsupported.
- TCR/port versus departed external lifecycle states and synchronization with the other operational database are not implemented; the current stock model tracks TCZ yard presence and truck visits. The exact event mapping and write authority need confirmation against Navis/other system before adding transitions.
- Freepool workbook has not been reconciled to supplied source figures. Unknown historical opening stock, EVP/billing policy, legal PDF footer, actual booking authority, and licensed logos require domain validation.
- iOS build needs macOS/Xcode; Android SDK and real devices are not configured here. Flutter web build succeeded with a non-blocking Wasm dry-run warning in a transitive `image` package; JS output was built.
- Private GitHub repository `boarddash31/pointage-container-tcz` has source on `main`. Netlify site `https://stalwart-travesseiro-1e8045.netlify.app/` was made public after user approval. External page GET and APK HEAD returned HTTP 200; downloading the full 58,854,286-byte APK produced SHA-256 `bbdb0bc1082919cde48e52a444ed503748d2a735e8a792af3727d9eb52691a00`, matching the local signed release. The public Flutter login renders and exposes the APK download button. Supabase Auth Site URL and the `/**` redirect are configured. A password-recovery email was sent to the first admin after the URL change; Supabase reports it is valid for 60 minutes. Human activation is still pending.

## Next action

Have the first admin open the recovery email within 60 minutes and set a password, then verify authenticated workflows, private PDF Storage, print bridge and Freepool reconciliation. Flutter tests (3), analyze, SQL smoke and bridge tests (2) passed again on 2026-10-20. Do not label this production-ready before these checks pass.

## Auth recovery follow-up (2026-10-20)

The user confirmed access to the first admin's email but had no TCZ password yet. Added a self-service "Mot de passe oublié ?" action that requests Supabase recovery by email, routes the callback to the public web app, and opens the password setup screen on recovery. Added the exact recovery callback to Supabase Auth's redirect allowlist. Flutter analyze and 4 tests pass. Rebuilt web and Android; the new APK is 58,887,054 bytes, SHA-256 `03eca7a576bc03c75b47a1b29998886231da782377f03d7fb4500628b485cb22`, with APK Signature Scheme v2 verified. First-admin activation and authenticated live workflow remain pending until the recipient sets their password. The new build still needs GitHub push and Netlify verification.








