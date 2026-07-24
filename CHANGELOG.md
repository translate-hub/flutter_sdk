## 0.1.0

* **Breaking:** `initialize` now takes a `TranslateHubConfig(ownerId, token)`
  instead of an API key. The SDK builds the Firebase Storage URL from those two
  values and fetches the file directly over a single HTTP GET; the old
  `getPublicTranslations` Cloud Function call is removed.
* Added ETag revalidation (`If-None-Match` / `304 Not Modified`).
* Fixed the on-device cache lifetime, which was effectively 5 seconds; it is now
  3 days as intended.
* Revoked customers (dropped token → `403`) now fall back to cache or the
  bundled asset.

## 0.0.1

* Initial release.