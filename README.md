# translate_hub_handler

The Flutter SDK for [TranslateHub](https://github.com/translate-hub). It fetches
your published translations straight from Firebase Storage — no backend in the
request path — caches them on device, and resolves the active language for you.

## Features

- Single HTTP GET on the SDK URL from your dashboard; the file is served
  publicly via a download token, so there is no per-request backend cost.
- On-device cache with ETag revalidation (`304 Not Modified` avoids
  re-downloading unchanged translations).
- Offline / bundled-asset fallback when the network or cache is unavailable.
- Automatic language resolution: saved choice → device locale → `en`.
- `String.translate` and `THLanguageItem.textDirection` extensions.

## Getting started

```yaml
dependencies:
  translate_hub_handler:
    git: https://github.com/translate-hub/flutter_sdk.git
```

## Usage

In the TranslateHub dashboard, each customer's API key shows an **owner id** and
a **token**. Pass those two values to `initialize`; the SDK builds the Storage
URL for you. Treat the token like an API key and keep it out of public
repositories.

```dart
import 'package:translate_hub_handler/translate_hub_handler.dart';

await TranslateHub.shared.initialize(
  const TranslateHubConfig(
    ownerId: 'AbC123...',       // from the dashboard
    token: '8f3c...-...-...',   // this app's download token
    fallbackFile: 'translations', // optional: assets/translations.json
  ),
);

// Read a value for the resolved language:
final title = 'welcome_title'.translate ?? 'Welcome';

// Switch language explicitly:
TranslateHub.shared.pickLanguage('he');
```

Pass `offline: true` to skip the network and load only the bundled asset.

## Additional information

Revoking a customer removes their token, after which the URL returns `403` and
the SDK falls back to its cache or the bundled asset.