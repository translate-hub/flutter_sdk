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

Copy the **SDK URL** for a customer from the TranslateHub dashboard — it embeds
the download token that guards the file. Treat it like an API key.

```dart
import 'package:translate_hub_handler/translate_hub_handler.dart';

await TranslateHub.shared.initialize(
  'https://firebasestorage.googleapis.com/v0/b/<bucket>/o/'
  'public_translations%2F<ownerId>%2Ftranslations.json?alt=media&token=<token>',
  fallbackFile: 'translations', // optional: assets/translations.json
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