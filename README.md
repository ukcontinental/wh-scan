# Stock Lookup (wh-scan)

Internal mobile web tool for stock lookup. Access restricted by passcode.

- Data is AES-256-GCM encrypted; a passcode is required to unlock.
- Barcode engine: native BarcodeDetector (Android) / ZXing fallback (iPhone).
- Works offline (Service Worker cache).
- Read-only lookup. No backend, no external integrations.
