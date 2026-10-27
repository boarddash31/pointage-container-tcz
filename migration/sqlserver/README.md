# SQL Server migration — first implementation slice

Target confirmed by the owner: **SQL Server 2025 on Windows Server**. Branch: `migration/sql-server`.

This branch starts the replacement backend. Flutter v3.1.0 still connects to the existing Supabase project. There is no production cutover in this phase.

## Included

- A catalog-only snapshot of the 22 `public`/`private` source tables, FK/unique/check constraints, indexes and extensions. No source rows or credentials are in Git.
- Reproducible SQL Server DDL and a transfer manifest. UUIDs, event/audit IDs, Unicode strings, JSON text and timestamp precision are retained. `profiles.initial_password` and the Supabase `auth` schema are excluded.
- A read-only, repeatable-read PostgreSQL exporter and a transactional .NET bulk importer. Export snapshots are private files under ignored `.migration-data/`.
- ASP.NET Core API for the current user, armateurs and EDO/ERO read/create/edit/increment operations. SQL enforces global reference uniqueness, item/carrier/ISO uniqueness, version conflicts and allocated-quantity/history protection. A stock-update guard enforces 24 hours from the receiving truck entry.
- Corporate authentication handlers prepared for Entra ID or AD Windows/Negotiate. Entra checks a single tenant, the API audience, allowed client applications and a delegated scope; AD uses the Windows SID authenticated by IIS/Negotiate. The stable corporate identity must map to an active profile in `internal.identity_accounts`; application roles come from SQL. No default admin, shared password or anonymous business endpoint is provided.
- SQL Server 2025 syntax checks, rollback-only database tests, transfer-conversion unit checks and a CI job using a temporary SQL Server container with synthetic fixtures.

## Remaining before production

1. Corporate accounts have been selected. IT must confirm the available mechanism (AD Windows integrated or Entra ID), configure its domain/tenant/application IDs and validate the prepared API handlers. Implement the corresponding browser login flow and directory-provisioning process; the current Flutter login still uses Supabase.
2. Port gate entry, twin reservations, yard movements, gate exit, cancellation, reconciliation, Data/reporting and admin-user operations. All reservation writers must lock parent orders before items, in deterministic order, matching the order editor.
3. Port protected PDF generation/download/archive, transfer the actual Storage files, verify checksums and update the Windows print bridge. Exporting database metadata does not transfer PDFs.
4. Replace Flutter's Supabase repository/auth/storage calls with the new API, including the supervisor dashboard.
5. Run concurrency, authorization, DST/UTC, rollback and end-to-end acceptance tests on the actual Windows Server/SQL Server instance. Linux CI verifies the engine/API/transfer slice and does not prove IIS, AD or physical printing.
6. Freeze writes for the final consistent export, reconcile row counts and documents, deploy the rebuilt client, monitor, and retain the old environment for rollback. No write freeze or export has been performed by creating these files.

## IT prerequisites

- SQL Server 2025, dedicated empty database, compatibility level 170, DBA deployment/import account and backup plan.
- Windows Server supported by the selected SQL Server and .NET releases, IIS if used, and .NET 10 Hosting Bundle for production. The **.NET 10 SDK** is needed on the build/validation machine, not necessarily on the production server.
- Internal application/API DNS names, trusted HTTPS certificates, a trusted SQL Server TLS certificate, firewall rules and an agreed identity provider. PostgreSQL source connectivity is needed only by the migration workstation during transfer.
- Protected service-account configuration. Production API SQL credentials belong to the `pointage_api` database role, with procedure execution and no direct table permissions; do not use a DBA/sa account for the application.
- Protected backup storage for SQL backups, PDF files, application configuration and identity mappings. Recovery objectives and retention must be agreed with the operations team.

The owner explicitly chose local retention and IT validation, not publication to the public repository. The local workstation has .NET runtimes but no SDK. Download of Microsoft's SDK archive was denied by the company File Transfer policy; no alternative download or local policy bypass is attempted. Use an IT-provisioned SDK for compilation/SQL integration validation. The optional CI example is stored under `it/`, outside `.github/workflows`, and is not active. No CI run has been started. See [the IT request](it/REQUEST-FOR-IT.md) for corporate authentication requirements.

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
dotnet run --project Pointage.Checks -c Release
```

`Pointage.Checks` parses SQL Server 2025 syntax and exercises API order validation and corporate identity checks with synthetic claims. These checks are prepared but have not been compiled or executed on this workstation. They require no source account or production database; they do not replace real AD/Entra integration tests.

## First test database

Have the DBA create an **empty** database named, for example, `TCZ_Pointage_Test`. Run the following in order using `sqlcmd -b` or SSMS configured to stop on error:

1. `001_schema.sql` — refuses system databases or any destination containing application tables. Creates 22 business tables, FK/check/unique constraints, indexes and the identity mapping/version tables.
2. `002_order_api.sql` — procedures, guards and API database role. No login is created automatically.
3. `003_smoke_test.sql` — only permits an empty `_Test` database; all fixtures roll back. Do not run after importing a real snapshot.

Scripts 001/002 are bootstrap versions for a fresh destination, not upgrades to an existing application database. Use migration-versioned upgrades for subsequent schema changes. Source `auth.users` FKs become application profiles plus external identity mappings; database cascading deletes are deliberately not enabled, preserving historical references. Legacy `BOOKING` rows remain importable; the new creation API only permits EDO/ERO.

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

`create-test-snapshot.cjs` generates only synthetic transfer fixtures for CI. `004_verify_import.sql` verifies those exact synthetic fixtures and is not a production data-comparison script.

## API configuration and first identity

Provide these through the Windows service/IIS protected configuration:

```text
ConnectionStrings__Pointage=<encrypted SQL connection with trusted certificate>
Authentication__Mode=<EntraId or Windows>
Cors__Origins__0=<HTTPS application origin>
AllowedHosts=<internal API hostname>
```

Supply the additional mode-specific settings documented in [the IT request](it/REQUEST-FOR-IT.md). Startup fails if corporate identity settings, CORS origins or SQL connection are missing/insecure. The liveness endpoint is `/health/live`; IIS Windows authentication may additionally require an authenticated monitor. Business endpoints require an authenticated, mapped identity. The DBA maps the verified Entra tenant/oid or AD directory/SID to the intended preserved profile ID in `internal.identity_accounts`. Roles remain in `dbo.user_roles`; browser-supplied user IDs, names or role claims do not establish a mapping. Compilation and real corporate identity integration tests remain required before activation.

First routes:

| Method | Route | Role |
| --- | --- | --- |
| GET | `/api/me` | Any active application role |
| GET | `/api/operators` | Any active application role |
| GET | `/api/orders/items?direction=RESTITUTION` | Any active application role |
| POST | `/api/orders` | Entrée/Admin |
| PUT | `/api/orders/{id}` | Entrée/Admin |
| POST | `/api/orders/items/{id}/quantity` | Entrée/Admin |

JSON names use snake_case. Creation supplies `kind`, `reference` and `items` (`iso_code`, `armateur_id`, `quantity`). Direction derives from EDO/ERO. Edition supplies `expected_version` and the complete retained item list; existing items supply `id`. Increment supplies a positive `quantity`. Version/unique conflicts return HTTP 409; denied roles return 403; anonymous calls return 401. There are no automatic retries for writes. Idempotent gate commands and reservation concurrency belong to the next slice.
