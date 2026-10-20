# Changelog

## After v3 — 2026-10-20

- Gate-out now checks the booked ISO container length before accepting a pickup: 20-foot visits cannot take 40-foot containers, or vice versa.
- Validates the entered ISO, registered container ISO and open stock ISO before making changes; both twin containers must be 20-foot.
- Shows the reserved ISO on the gate-out form and explains size mismatches. Matching lengths with different heights remain allowed.
- Validated with 11 Flutter tests, database rejection/rollback tests and a rolled-back check on TCZ.

## v3 — 2026-10-20

- Data table with permanent transaction number, Réception/Livraison type, creator and last changer.
- Creation/change timestamps, transaction search, displayed counts and visit history.
- Both containers, bookings and armateurs shown for twin visits; canceled visits labeled correctly.
- Authorized transaction summary deployed to TCZ with restricted operator-name access.
- Updated web release; Android APK unchanged.

Validation: nine Flutter tests and extended database smoke tests pass. Static analysis reports only six existing style notices.
