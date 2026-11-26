# Apex Agent

Apex Agent is an autonomous Android assistant built with Flutter and native Kotlin platform code (`com.apex.agent`), backed by a Cloudflare Workers AI agent endpoint.

## Repository Layout

- `lib/` - Flutter app (agent chat/live execution, visual workflow builder, universal auto-reply rules, settings)
- `android/` - Native Android project and Kotlin platform services
- `worker/` - Cloudflare Worker AI backend (`wrangler.toml`, `index.js`)
- `.github/workflows/build_apk.yml` - GitHub Actions workflow that builds and uploads release and debug APKs

## Android Capabilities

- Accessibility service for screen state, app launching, taps, typing, scrolling, and global actions
- Foreground background service for persistent agent/runtime support
- Notification listener for notification ingestion, auto-reply, approval flows, and sender phone extraction
- Phone/SMS/WhatsApp actions: call, SMS, WhatsApp deep link, and TTS speak
- Boot receiver to restore background service after reboot

## Cloudflare Worker

Configure and deploy from `worker/`:

1. Set `AUTH_TOKEN` as a Worker secret.
2. Create a KV namespace for persistent memory and set the `MEMORY` namespace `id` and `preview_id` in `wrangler.toml`.
3. Deploy with Wrangler (Workers AI binding configured in `wrangler.toml`).

Endpoints:
- `POST /` - agent tool-calling endpoint (memory-aware)
- `POST /auto-reply` - auto-reply suggestion endpoint
- `GET|POST|PUT|DELETE /memory` - persistent memory/context endpoint (KV-backed when configured)

## GitHub Actions APK Build

The workflow runs:
- `flutter pub get`
- `flutter build apk --release`
- `flutter build apk --debug`

It uploads both `app-release.apk` and `app-debug.apk` as workflow artifacts.
