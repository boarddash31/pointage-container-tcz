# Pointage Container · TCZ

Flutter mobile/web application backed by Supabase Auth, PostgreSQL, private PDF Storage and Edge Functions. The Node bridge is optional for archiving PDFs to a Windows network share and submitting print jobs to a Windows printer.

The web app is deployed at [pointage-container-tcz.pages.dev](https://pointage-container-tcz.pages.dev/). The custom domain `https://marsa.digital` is attached and awaits DNS delegation. The public site is web-only; no APK is linked or included in the release. Source is in the GitHub repository `boarddash31/pointage-container-tcz`. The first admin must complete the Supabase password-recovery flow; never share its link or password in this repository.

## Repository layout

- `app/`: Flutter client for Android, iOS and web.
- `supabase/migrations/`: transactional workflow, role/RLS, reporting and catalog schema.
- `supabase/functions/`: authenticated PDF generation and admin-only user invitations.
- `bridge/`: local Node process for private PDF archiving and optional printing.
- `tests/`: isolated database smoke tests; Flutter tests are in `app/test/`.
- `01_…` through `05_…`: supplied reference materials, reports, UI examples and implementation brief.

## Build and verification

Create a local `.env.local` from `.env.example` with the **publishable** Supabase key and `AUTH_SITE_URL=https://marsa.digital`. Never put a service-role/secret key in Flutter or Git. On the TCZ Windows build machine, `scripts/build_release.ps1` runs analysis/tests, builds the Flutter web release, and copies only the web files into `site/`.

The build machine uses the Flutter SDK under `E:\recovred\COMPLETED PROJECT\final project`, through the no-space junction `E:\flutter_sdk_tcz` and app junction `E:\pointage_tcz`.

```powershell
npm ci
npm run test:db
npm run test:bridge
& 'scripts/build_release.ps1'
```

The release script copies only the generated web app into `site/`. Run `scripts/deploy_cloudflare.ps1` to upload that folder to Cloudflare Pages. Keep `https://marsa.digital` in Supabase Auth's Site URL and redirect allowlist so invitation and recovery links return to the web app. The custom domain must resolve publicly before it can be considered live.

The bridge must run on a Windows machine that can reach the PDF folder and printer. `\\172.16.3.98\TCR PrintM` is a **printer share**, not a writable PDF directory. The archive folder is separately configured using `PDF_SHARE_PATH`. Read `bridge/README.md` for TLS, JWT validation, idempotency and printer configuration.

## Deployment state

Read `PROGRESS.md` for tested behavior and remaining acceptance work. A successful build or deploy does not prove physical printing, mobile-device connectivity, or reconciliation with the external TCR/port system. Freepool billing figures require comparison with the source reports before billing use.
