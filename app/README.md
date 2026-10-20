# Pointage Container · TCZ

Native Flutter client for Android, iOS and web. It requires a configured Supabase project; the app does not contain credentials or an offline database.

## Local run

Install Flutter 3.47.2 or compatible stable SDK. From this directory:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d chrome --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

For shared-folder archiving add `--dart-define=PDF_BRIDGE_URL=https://HOST:8848` after configuring `bridge/`; set `PDF_BRIDGE_AUTO_PRINT=true` only after a real printer test. Use the project URL and **publishable** key only. Never pass a service-role key to Flutter. On this Windows machine, SDK and project paths with spaces cause Dart native-assets hooks to fail; run through no-space directory junctions or place both in paths without spaces.

## Backend setup

Read root `PROGRESS.md` before deployment. Apply `supabase/migrations/202610190001_core.sql`, then `202610190002_reporting_admin.sql`, then `202610190003_forced_actions.sql`, then `202610190004_document_actions.sql`, then `202610190005_manual_containers.sql`, then `supabase/seed.sql` to a **clean staging** Supabase project. These migrations have not been tested against the existing TCZ schema. Inspect that schema and make a migration plan before touching it. Deploy `supabase/functions/generate-bon` with JWT verification enabled. Configure its service role secret server-side only. The private Storage bucket is created by SQL.

Create Auth users through Supabase administration. A profile is created by trigger, but an admin must grant roles (`entree`, `engin`, `sortie`, `viewer`, or `admin`) before users can work. Seed the first admin role using a trusted database/admin session; public sign-up does not grant roles. Verify Auth, RLS, PDF Storage and workflows in staging before production use.

## Current limitations

The UI and database are under active development; see `PROGRESS.md` for verified milestones. PDF generation needs a deployed Edge Function and valid session. A browser uses the normal print dialog. The optional `bridge/` service archives PDFs to a shared folder and can submit print jobs to an installed Windows printer when configured; it has not been deployed or paper-tested. Freepool export has not been reconciled to the supplied historical reports, so it must not be used for billing yet. iOS builds require a Mac with Xcode, and Android builds require a configured Android SDK.




