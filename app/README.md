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

Read root `PROGRESS.md` before deployment. Apply the six migrations in `supabase/migrations/` in filename order to a clean project. They were applied to the initially empty TCZ project on 2026-10-20; new environments still need their own acceptance tests. Deploy `supabase/functions/generate-bon` and `supabase/functions/invite-user` with JWT verification enabled. Configure service-role secrets server-side only. The private Storage bucket is created by SQL.

The first admin was invited in the TCZ Supabase project and given the `admin` role. A password-recovery email was sent after Supabase Auth was pointed to the public Netlify site; the recipient must accept it before the first authenticated acceptance test. An active admin can invite further users with a role (`entree`, `engin`, `sortie`, `viewer`, or `admin`) from the web UI. A profile is created by trigger; public sign-up does not grant roles. Verify Auth, RLS, PDF Storage and workflows on actual devices before production use.

## Current limitations

The UI and database are under active development; see `PROGRESS.md` for verified milestones. PDF generation needs a valid authenticated session. A browser uses the normal print dialog. The optional `bridge/` service archives PDFs to a shared folder and can submit print jobs to an installed Windows printer when configured; it has not been deployed or paper-tested. Freepool export has not been reconciled to the supplied historical reports, so it must not be used for billing yet. An Android release APK was built and signed on Windows; real-device validation remains open. iOS builds require a Mac with Xcode.




