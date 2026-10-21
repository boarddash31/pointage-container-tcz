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

## Enregistrement entrée & Authentification résolus (2026-10-20)

- Identifié la cause du blocage initial ("enregistrer mkhdamach") :
  1. L'envoi des e-mails Supabase Auth était bloqué par le quota d'envoi du tier gratuit Supabase (`429 over_email_send_rate_limit`), empêchant la réinitialisation du mot de passe admin par e-mail.
  2. Comptes de test admin et agent activés via l'API Supabase Admin ; les JWT et accès RLS ont été vérifiés. Les anciens mots de passe ayant été publiés dans le code et l'historique Git, leur rotation est obligatoire avant usage en production.
  3. Les anciens boutons d'accès en un clic et les identifiants affichés sur la page de connexion ont été retirés du code courant.
- Résolution des blocages sur l'enregistrement de l'entrée (`EntryScreen`) :
  - Support du collage du numéro de conteneur complet (bouton "Coller" dédié et raccourci Ctrl+V / Cmd+V) distribuant les 11 caractères dans les cases respectives.
  - Calcul dynamique du chiffre de contrôle ISO 6346 (`ContainerNumber.expectedCheckDigit`) avec suggestion en temps réel ("Appliquer X" dès que 10 caractères sont saisis, badge vert "Numéro ISO 6346 conforme et vérifié", ou "Corriger en X" en cas d'erreur de saisie).
  - Suppression de la validation silencieuse sur la case 0 qui bloquait l'envoi sans message lisible.
  - Présélection automatique de l'armateur par défaut (Maersk `MAE`) pour ne plus bloquer la soumission.
  - Gestion explicite des erreurs SQL / contraintes de terminal (ex. conteneur déjà présent dans le terminal via `one_active_container_on_truck`).
- Tests et compilation :
  - Suite de tests Flutter (4 tests unitaires et widgets) validée à 100%.
  - `flutter analyze` : 0 avertissement, 0 erreur.
  - Build complet release exécuté : APK signée v2 (`site/downloads/pointage-tcz.apk`) et build Web de production (`site/`) prêts pour déploiement Netlify.









## Data transaction traceability (2026-10-20)

- Added a searchable Data table with transaction number, Reception/Livraison type, truck, both containers/bookings/armateurs, status, creator, last changer and creation/change timestamps. Clicking a transaction number opens the visit history. Counts describe the loaded window of the 500 newest visits.
- Numbers reuse the permanent ENTREE event identity; visits without an entry event fall back to their UUID. Creator comes from entered_by; last changer and timestamp come from the latest truck_visit audit record, with creator/entry time as fallback. Missing display names fall back to user UUIDs.
- Applied transaction_data to TCZ through ZENATA as migration 20261020155355. The guarded read-only RPC returns names only for readers authorized by can_do('read'); it does not grant general access to other profiles. Added a partial index for latest-visit audit lookup. Live authenticated summary returned seven rows with complete identity fields.
- Nine Flutter tests and extended isolated SQL smoke tests pass. SQL checks verify stable numbers, preserved creators, updated changer identity, authorized agent access, profile isolation and denial for unassigned users. Dart analysis has no errors/warnings and the same six existing style notices.
- Supabase Advisor flags data_transactions as an authenticated SECURITY DEFINER RPC; this is intentional for the limited profile-name lookup, with explicit read authorization and no anonymous execution. Existing unrelated advisor findings remain.
- Source and backend updated; the web release and APK have not been rebuilt or published for this change.

## v3 release (2026-10-20)

- Rebuilt the web release with the TCZ publishable configuration and copied it to site/. Verified local HTTP 200 for the page and compiled bundle; the bundle contains the transaction-summary endpoint. Opened the app at http://localhost:8787/.
- GitHub release marker: annotated tag v3. The Android APK is unchanged because this machine has no release signing configuration.

## Gate-out ISO length validation (2026-10-20)

- Added migration 20261020162717_gate_out_iso_length_check to TCZ through ZENATA. Pickup checks compare the original visit length code against submitted ISO, registered container ISO and open stock ISO before any upsert or movement. Twin pickups require two 20-foot containers; missing pickup details are rejected unless a previous Engin movement already completed. Empty cancellation and loaded deposit remain available.
- Added matching Flutter validation and reserved-ISO guidance. This checks container length, allowing different heights/types of the same length (for example 42G1 and 45G1 are both 40-foot).
- Eleven Flutter tests pass. Extended isolated database tests cover both mismatch directions, false ISO declarations, second twin mismatch, missing pickup, unchanged records after failure, valid same-length pickups, valid twins and empty cancellation. A live rolled-back authenticated test confirmed that a 20-foot visit rejects a 40-foot pickup.

## Gate truck visual and role separation update (2026-10-21)

- Added a responsive truck preview for Entrée and queue/action cards. It renders a dark container label with container number (or `?` when not yet entered), ISO code and armateur/line; Twin mode renders two labels side-by-side.
- Added Moroccan truck plate validation and normalization (`12345-A-06`, with scanner-friendly `12345A06` input). Invalid plate formats are rejected before the Entrée RPC.
- Role enforcement already scopes the shell and backend RPCs: an account with `entree` sees Entrée, an account with `sortie` sees Sortie, and an admin can assign either role from Admin > Profils. Separate one-click test accounts still need to be created in Supabase Auth and assigned their single role.
- Tests: full Flutter suite 13 tests passed; `flutter analyze --no-pub` completed with the existing six style infos and no errors.

## Truck diagram release (2026-10-21)

- Entrée now offers four horizontally scrolling truck choices: loaded mono/twin and empty mono/twin. A live diagram draws each container or empty slot above the chassis. Loaded containers are red with white number, ISO and line text; the truck plate appears on the cab. Missing required container details receive a yellow outline. Tapping the cab or either slot focuses the relevant form field.
- Single-role agents land directly on their permitted gate. Removed public one-click credential buttons and passwords from the current web and mobile code and this document. Previously published bundles and Git history exposed those credentials, so both Supabase Auth passwords still require rotation; removal from code alone is insufficient.
- Flutter analyze passed without issues; all 15 tests passed. Release script built the signed Android APK and production Flutter Web output. APK SHA-256: `b26b86a261f210b16fa09d09d0d46fd69ddb36bb7054e710535189863af4e696`.
- Authenticated end-to-end operation, private PDF output, archive writing and physical printing remain unverified. Do not mark production acceptance complete until these checks and credential rotation pass.

## Agent accounts and responsive truck cards (2026-10-21)

- Invited two initial Supabase Auth accounts using aliases of the owner's Gmail mailbox: one for Entrée and one for Sortie. Verified that each has exactly its intended role in `public.user_roles`; the profile display names were set accordingly and role setup was audited. Invitation acceptance remains pending. Replace the aliases with the actual operators' email addresses before handing out access.
- Disabled the legacy shared agent profile in Supabase and verified `active=false`; its old multi-role login can no longer pass app role checks or the backend `can_do` guard. The exposed admin password still requires rotation by the account owner.
- Redrew the truck as Flutter vector artwork with clearer cab/plate, chassis, wheels, red corrugated containers and outlined empty slots. The selected card now shows the live plate, container/booking, ISO and armateur, including missing-field highlighting and tap-to-focus. Removed the separate truck preview below the choice row; the four larger cards remain horizontally scrollable.
- Twin entry details use two columns on wide web screens and stack on mobile. Added a responsive widget test for both layouts. Flutter analyze passed and all 16 tests passed. The signed APK and production Web release both built successfully; APK SHA-256: `2710e2b673291e7b521338fece8b7008784ecb126d54ae959547ea5cffa55432`.
- Live browser review after disabling the exposed shared agent revealed that a disabled session landed on an access screen without a logout action. Added a visible sign-out button and a widget test so the operator can switch to a valid account. Flutter analyze and all 17 tests passed; rebuilt the signed APK and production Web release. New APK SHA-256: `d0470b6e95bbf2fbaa65f1412b422d2f0e44eb5c754cbab7d4d4863d16655c4f`.

## Safe quick access profiles (2026-10-21)

- Restored three prominent login shortcuts for Admin, Entrée and Sortie. Each selects the corresponding email and focuses the password field; it never stores or submits a public password. Agents can still edit the email to use their eventual individual account. A widget test checks all three shortcuts and verifies the password remains blank.
- The previous password-based one-click login cannot be safely restored because its credentials remain visible in historic public builds. The new invitations must be accepted before the two agent shortcuts can authenticate. Flutter analyze and all 18 tests passed; signed APK and production Web builds succeeded. APK SHA-256: `466f4e0a4becd7725d32dc05247d2dc5a42d55891b29d93d8aa427fd70e4f782`.
