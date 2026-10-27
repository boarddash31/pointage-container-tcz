# SQL Server migration — first implementation slice

Target confirmed by the owner: **SQL Server 2025 on Windows Server**. Branch: `migration/sql-server`.

This branch starts the replacement backend. Flutter v3.1.0 still connects to the existing Supabase project. There is no production cutover in this phase.

## Included

- A catalog-only snapshot of the 22 `public`/`private` source tables, FK/unique/check constraints, indexes and extensions. No source rows or credentials are in Git.
- Reproducible SQL Server DDL and a transfer manifest. UUIDs, event/audit IDs, Unicode strings, JSON text and timestamp precision are retained. `profiles.initial_password` and the Supabase `auth` schema are excluded.
- A read-only, repeatable-read PostgreSQL exporter and a transactional .NET bulk importer. Export snapshots are private files under ignored `.migration-data/`.
- ASP.NET Core API for the current user, armateurs and EDO/ERO read/create/edit/increment operations. SQL enforces global reference uniqueness, item/carrier/ISO uniqueness, version conflicts and allocated-quantity/history protection. A stock-update guard enforces 24 hours from the receiving truck entry.
- Normal application accounts created only by Admin, salted ASP.NET Core Identity password hashing, mandatory initial password change, login/logout, session expiration/revocation, Admin reset/disable/role management and an offline first-Admin tool. AD/Entra is cancelled. These new .NET/SQL components are prepared locally but have **not been compiled or executed** on this workstation.
- SQL Server 2025 syntax checks, rollback-only database tests, transfer-conversion unit checks and a CI job using a temporary SQL Server container with synthetic fixtures.

## Remaining before production

1. Compile and validate the application-account slice on the IT machine, including SQL smoke tests, HTTP authorization and concurrent account changes. Then adapt Flutter login/session handling; the current client still uses Supabase. AD/Entra is cancelled.
2. Port gate entry, twin reservations, yard movements, gate exit, cancellation, reconciliation, Data/reporting and admin-user operations. All reservation writers must lock parent orders before items, in deterministic order, matching the order editor.
3. Port protected PDF generation/download/archive, transfer the actual Storage files, verify checksums and update the Windows print bridge. Exporting database metadata does not transfer PDFs.
4. Replace Flutter's Supabase repository/auth/storage calls with the new API, including the supervisor dashboard.
5. Run concurrency, authorization, DST/UTC, rollback and end-to-end acceptance tests on the actual Windows Server/SQL Server instance. The optional Linux CI example covers the engine/API/transfer slice, not IIS or physical printing; it has not been run.
6. Freeze writes for the final consistent export, reconcile row counts and documents, deploy the rebuilt client, monitor, and retain the old environment for rollback. No write freeze or export has been performed by creating these files.

## IT prerequisites

- SQL Server 2025, dedicated empty database, compatibility level 170, DBA deployment/import account and backup plan.
- Windows Server supported by the selected SQL Server and .NET releases, IIS if used, and .NET 10 Hosting Bundle for production. The **.NET 10 SDK** is needed on the build/validation machine, not necessarily on the production server.
- Internal application/API DNS names, trusted HTTPS certificates, a trusted SQL Server TLS certificate and firewall rules. Users will have normal application accounts managed by Admin; no corporate identity provider is required. PostgreSQL source connectivity is needed only by the migration workstation during transfer.
- Protected service-account configuration. Production API SQL credentials belong to the `pointage_api` database role, with procedure execution and no direct table permissions; do not use a DBA/sa account for the application.
- Protected backup storage for SQL backups (including application-account password hashes), PDF files and application configuration. Recovery objectives and retention must be agreed with the operations team. Do not export live session tokens.

The owner explicitly chose local retention and IT validation, not publication to the public repository. The local workstation has .NET runtimes but no SDK. Download of Microsoft's SDK archive was denied by the company File Transfer policy; no alternative download or local policy bypass is attempted. Use an IT-provisioned SDK for compilation/SQL integration validation. The optional CI example is stored under `it/`, outside `.github/workflows`, and is not active. No CI run has been started. See [the IT request](it/REQUEST-FOR-IT.md) for application-account and infrastructure requirements.

## Validate locally without a database

From the repository root, with Node installed and dependencies from `npm ci`:

```text
node migration/sqlserver/tools/generate-schema.cjs
node tests/sqlserver_migration_test.cjs
```

On a build machine with .NET 10 SDK, run from `backend/`:

```text
dotnet build Pointage.Checks -c Release
dotnet build Pointage.Migration -c Release
dotnet build Pointage.Admin -c Release
dotnet run --project Pointage.Checks -c Release
```

`Pointage.Checks` parses SQL Server 2025 syntax and exercises API order/account validation, real password hashing/verification, opaque-token generation and restrictions on anonymous/temporary-password identities. These checks are prepared but have not been compiled or executed on this workstation. They require no source account or production database; account-service HTTP/concurrency tests remain necessary.

## First test database

Have the DBA create an **empty** database named, for example, `TCZ_Pointage_Test`. Run the following in order using `sqlcmd -b` or SSMS configured to stop on error:

1. `001_schema.sql` — refuses system databases or any destination containing application tables. Creates 22 business tables, FK/check/unique constraints, indexes and the version table.
2. `002_order_api.sql` — procedures, guards and API database role. No login is created automatically.
3. `003_smoke_test.sql` — only permits an empty `_Test` database; all fixtures roll back. Do not run after importing a real snapshot.
4. `005_application_accounts.sql` — version 3: private account/session tables and login/Admin procedures. Apply with the DBA identity, not the API runtime account.
5. `006_account_smoke_test.sql` — only permits an empty `_Test` database. Exercises Admin-only creation, existing profile IDs, password change, lockout, reset/revocation, final-Admin protection, version conflicts and username uniqueness. All fixtures roll back. This has not been executed here.

Scripts 001/002 are bootstrap versions for a fresh destination, not upgrades to an existing application database; 005 requires versions 1 and 2 and records version 3. Use migration-versioned upgrades for subsequent changes. Source `auth.users` FKs become application profiles linked to local accounts; database cascading deletes are deliberately not enabled, preserving historical references. Legacy `BOOKING` rows remain importable; the new creation API only permits EDO/ERO. The superseded early identity-mapping scaffold was removed before any destination deployment; recreate the empty IT test database if it was provisioned from that older scaffold.

The stock-position unique index uses a persisted SHA-256 key for historically unbounded position strings. Per-slot active-container uniqueness is retained using computed keys because SQL Server filtered indexes cannot directly express the source OR predicate. Cross-slot/twin concurrency is part of the gate-operation port and must be tested before activation.

## Source export — explicit operator action

Configure `POINTAGE_SOURCE_CONNECTION` securely on the migration workstation. It must address the captured project (`iparzfqxopcvwqelxlad`), using a direct connection or session pooler. TLS certificate verification is required; `POINTAGE_SOURCE_CA_FILE` optionally names the trusted CA bundle. Do not put connection strings in chat, Git or command arguments.

```text
node migration/sqlserver/tools/export-source.cjs --out .migration-data/snapshot-YYYYMMDD
```

The exporter reads explicit manifest columns in one read-only snapshot and writes one NDJSON file per table plus row counts and SHA-256 hashes. `snapshot.json` is written only after all files complete. It never selects password hashes or `initial_password`. PostgreSQL JSON is preserved as original text inside each NDJSON record so large JSON numbers are not rounded by JavaScript. Bigint and decimal fields are strings; timestamps retain six fractional digits. Values that would truncate or change key comparisons stop the export instead of being corrected silently.

Safeguard these files as confidential operational data: they contain driver identifiers, phone numbers and audit history. Copy the completed folder to the protected migration workstation/server, retaining its integrity metadata.

## Destination import

Set `POINTAGE_TARGET_CONNECTION` through protected process configuration, with a dedicated database, encryption enabled and certificate verification enabled. From `backend/` (so its `global.json` selects the supported SDK):

```text
dotnet run --project Pointage.Migration -c Release -- --snapshot ../.migration-data/snapshot-YYYYMMDD --check
dotnet run --project Pointage.Migration -c Release -- --snapshot ../.migration-data/snapshot-YYYYMMDD --apply
```

Preflight verifies manifest/file hashes, source project, counts and types before connecting. Apply refuses non-empty business tables, locks them and imports all 22 tables in one transaction and FK dependency order. It preserves identity values, checks constraints, compares counts and reseeds identities. Historical data is loaded without replaying application triggers; new API operations use the new guards. An import failure rolls back the destination transaction. Do not run with `TrustServerCertificate=True`.

`create-test-snapshot.cjs` generates only synthetic transfer fixtures for CI. It refuses to overwrite an existing folder; use `--out .migration-data/new-fixture` to create a new local fixture without touching an older one. The folder must stay under ignored `.migration-data/`. A manifest change requires a fresh snapshot. `004_verify_import.sql` verifies those exact synthetic fixtures and is not a production data-comparison script.

## API configuration and normal accounts

Provide these through the Windows service/IIS protected configuration:

```text
ConnectionStrings__Pointage=<encrypted SQL connection with trusted certificate>
Accounts__SessionHours=8
Cors__Origins__0=<HTTPS application origin>
AllowedHosts=<internal API hostname>
```

The API uses 256-bit random opaque Bearer tokens: only SHA-256 token hashes are stored in `internal.application_sessions`. Every request checks session expiry and profile activation in SQL. No JWT issuer, signing-key service, AD or Entra configuration is required. Password hashes use ASP.NET Core Identity V3 with 600,000 PBKDF2 iterations and individual random salts. Passwords have 12-128 characters; normal ASCII identifiers/phone numbers have 3-100 characters and are unique ignoring case. There is no professional-email requirement or self-registration.

Login returns `access_token`, `token_type`, `expires_at`, `user_id` and `must_change_password`. The token belongs in the Authorization header; never use query strings, cookies, logs or URLs. A temporary password permits only password change/logout. After changing a password the client must log in again: all previous sessions are revoked. Five failed passwords lock an account for 15 minutes. Login/password endpoints are additionally limited to ten requests per minute per server-observed IP; validate this setting with IT for shared NAT/IIS, and do not trust arbitrary forwarded headers.

Admin-only procedures create/list/manage accounts and reset passwords. New/reset passwords require a change at the next login. Disabling or changing roles also revokes that user's sessions; updates require the current `version`. A serialized guard preserves at least one active Admin account. Audit records identify actors without recording password hashes or session tokens. `api` procedures are executable only by the protected backend database identity, not by end users directly. Session expiry cleanup runs for the logging-in account; IT should also schedule removal of expired sessions across the table.

After the historical import and validation, use the separate DBA console to bootstrap the first Admin:

```text
dotnet run --project Pointage.Admin -c Release -- admin01 "Terminal administrator" <existing-admin-profile-uuid>
```

Run from `backend/`, with `POINTAGE_TARGET_CONNECTION` set securely for the DBA. The UUID argument is optional for a new installation; for a migration, select the preserved Admin profile to retain history. The tool prompts twice for the password with hidden input, hashes it in memory and calls `internal.bootstrap_admin`. That procedure refuses any existing local account and is **not granted to the API runtime role**. There is no HTTP bootstrap route, default password or copied Supabase password. Subsequent existing profiles can be linked by Admin using `existing_profile_id` without changing their historical UUID/name.

Before activation, IT must run the prepared SQL/.NET checks and end-to-end HTTPS tests, including disabled/revoked/expired tokens, required password changes, non-Admin creation/reset, login failures and concurrent Admin changes. The Flutter adapter and first-Admin tool have not been run against a destination yet.

Implementation references: [Microsoft password hasher options](https://learn.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.identity.passwordhasheroptions.iterationcount?view=aspnetcore-10.0), [authentication handlers](https://learn.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.authentication.authenticationhandler-1.-ctor?view=aspnetcore-10.0), and [ASP.NET Core rate limiting](https://learn.microsoft.com/en-us/aspnet/core/performance/rate-limit?view=aspnetcore-10.0).

First routes:

| Method | Route | Role |
| --- | --- | --- |
| POST | `/api/auth/login` | Anonymous, rate limited |
| POST | `/api/auth/logout` | Authenticated session |
| POST | `/api/auth/password` | Authenticated session, rate limited |
| GET/POST | `/api/users/` | Admin |
| PUT | `/api/users/{id}` | Admin |
| POST | `/api/users/{id}/password` | Admin, another user's account |
| GET | `/api/me` | Any active application role |
| GET | `/api/operators` | Any active application role |
| GET | `/api/orders/items?direction=RESTITUTION` | Any active application role |
| POST | `/api/orders` | Entrée/Admin |
| PUT | `/api/orders/{id}` | Entrée/Admin |
| POST | `/api/orders/items/{id}/quantity` | Entrée/Admin |

JSON names use snake_case. Creation supplies `kind`, `reference` and `items` (`iso_code`, `armateur_id`, `quantity`). Direction derives from EDO/ERO. Edition supplies `expected_version` and the complete retained item list; existing items supply `id`. Increment supplies a positive `quantity`. Version/unique conflicts return HTTP 409; denied roles return 403; anonymous calls return 401. There are no automatic retries for writes. Idempotent gate commands and reservation concurrency belong to the next slice.
