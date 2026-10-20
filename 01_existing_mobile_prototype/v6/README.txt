POINTAGE CONTAINER V6 — Mobile prototype

1. Open index.html in Chrome. Navigate to Bons PDF.
2. Click a bon: a real PDF is downloaded and an optional PDF preview opens.
3. Print to any printer installed on the device from the PDF viewer.
4. Direct LAN printer option: run `python print_bridge.py` on the SAME computer as Chrome.
   In Bons PDF > Configurer imprimante reseau, set the printer IPv4 address and its IPP endpoint
   (often /ipp/print or /printers/queue; consult the printer manual). This is saved locally.
   Then use 'Impression directe' next to the relevant bon.

IMPORTANT: Direct IPP printing only works with printers supporting application/pdf through IPP.
It may fail on older printers or when IPP is disabled. A local helper is required because browsers
cannot directly send raw printer jobs to an arbitrary network IP. This demo is NOT cloud storage.
PDFs are saved to browser downloads. Popup blocking may prevent the preview, not the download.
