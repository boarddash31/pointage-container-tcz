# Local PDF archive and printer bridge

This optional Node.js process runs on the workstation that can access the shared folder and installed printer. Flutter sends a **document ID and the current Supabase user JWT**, never arbitrary PDF bytes. The bridge checks the JWT with Supabase Auth, reads the document through user-scoped RLS, downloads the PDF from private Storage and archives it idempotently. The shared folder contains the original Supabase PDF. The browser cannot write to a UNC folder or print to an arbitrary IP printer by itself.

## Configure

Node 20+ is required. Set environment variables for the process account:

- `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`: project URL and publishable key. Never use a service-role key here.
- `PDF_SHARE_PATH`: existing, writable folder, for example `\\172.17.18.218\pdf`. The bridge process account must have write permission.
- `BRIDGE_HOST` / `BRIDGE_PORT`: default `127.0.0.1:8848`. For phone or LAN access, set a reachable host and **both** `BRIDGE_TLS_CERT` and `BRIDGE_TLS_KEY`. A non-loopback listener refuses to start without TLS.
- `BRIDGE_ALLOWED_ORIGINS`: comma-separated Flutter Web origins, for example `https://pointage.example`. Native mobile requests have no browser Origin header.
- `BRIDGE_STATE_PATH`: local durable folder for print-request markers. Back it up with bridge configuration; it suppresses duplicate automatic printing on retries.
- `SUMATRA_PDF_PATH` and `PDF_PRINTER_NAME`: optional direct printing. Install SumatraPDF from its official source on the Windows workstation and set its full executable path and the **exact Windows printer name**. Use `Get-Printer` to inspect names. Do not set these until the intended device has been selected and a paper test is approved.

Start from this directory with `node server.mjs`. Configure the workstation's normal per-user startup so its printer driver and network share are available. Keep the process account limited to the needed share/printer. Check `node --test test/*.test.mjs` before deployment.

Build Flutter with `--dart-define=PDF_BRIDGE_URL=https://HOST:8848`. Set `--dart-define=PDF_BRIDGE_AUTO_PRINT=true` only after the printer is configured and physically tested. On save, the PDF is first generated in private Supabase Storage, then sent to the bridge for shared-folder archiving and optional printing. Bons has an archive/retry action. A print-request marker avoids duplicate automatic jobs; if a print command fails, inspect the marker and spooler before manually retrying.

The bridge's successful print response means SumatraPDF submitted the job to the Windows printer. It cannot prove that paper emerged: offline/out-of-paper failures may occur later in the spooler. SumatraPDF documents `-print-to` exit codes and this limit at [Command line arguments](https://www.sumatrapdfreader.org/docs/Command-line-arguments).
