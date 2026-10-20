# Pointage Container · TCZ

Flutter mobile/web application backed by Supabase Auth, PostgreSQL, private PDF Storage and Edge Functions. The Node bridge is optional for archiving PDFs to a Windows network share and submitting print jobs to a Windows printer.

## Repository layout

- `app/`: Flutter client for Android, iOS and web.
- `supabase/migrations/`: transactional workflow, role/RLS, reporting and catalog schema.
- `supabase/functions/`: authenticated PDF generation and admin-only user invitations.
- `bridge/`: local Node process for private PDF archiving and optional printing.
- `tests/`: isolated database smoke tests; Flutter tests are in `app/test/`.
- `01_…` through `05_…`: supplied reference materials, reports, UI examples and implementation brief.

## Build and verification

Create a local `.env.local` from `.env.example` with the **publishable** Supabase key. Never put a service-role/secret key in Flutter or Git. Configure `app/android/key.properties` and keep the release keystore outside this repository. On the TCZ Windows build machine, `scripts/build_release.ps1` runs analysis/tests, creates a signed APK and web build, copies the APK to `app/build/web/downloads/`, and writes its SHA-256 checksum.

The build machine uses the Flutter, Android SDK and JDK already present under `E:\recovred\COMPLETED PROJECT\final project`, via no-space junctions `E:\flutter_sdk_tcz`, `E:\android_sdk_tcz`, `E:\jdk_tcz` and `E:\pointage_tcz`. The release signing key and backup configuration are in `E:\pointage_release_secrets`; **back up that directory securely** before distributing updates. Losing the key prevents installing an update over an existing APK.

```powershell
npm ci
npm run test:db
npm run test:bridge
& 'scripts/build_release.ps1'
```

For Netlify manual deployment, publish the generated `app/build/web` directory after the build. Its `downloads/pointage-tcz.apk` file is linked from the web login screen. Keep the Netlify site URL in Supabase Auth's Site URL and redirect allowlist so invitation and recovery links land on the web app.

The bridge must run on a Windows machine that can reach the PDF folder and printer. `\\172.16.3.98\TCR PrintM` is a **printer share**, not a writable PDF directory. The archive folder is separately configured using `PDF_SHARE_PATH`. Read `bridge/README.md` for TLS, JWT validation, idempotency and printer configuration.

## Deployment state

Read `PROGRESS.md` for tested behavior and remaining acceptance work. A successful build or deploy does not prove physical printing, mobile-device connectivity, or reconciliation with the external TCR/port system. Freepool billing figures require comparison with the source reports before billing use.
