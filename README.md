# Apex Agent

Apex Agent is an autonomous Android assistant built with Flutter and native Kotlin platform code (`com.apex.agent`), backed by a Cloudflare Workers AI agent endpoint.

## Repository Layout

- `lib/` - Flutter app (dark UI, agent chat, universal auto-reply rules, settings)
- `android/` - Native Android project and Kotlin platform services
- `worker/` - Cloudflare Worker AI backend (`wrangler.toml`, `index.js`)
- `.github/workflows/build_apk.yml` - GitHub Actions workflow that builds and uploads the release APK

## Android Capabilities

- Accessibility service for screen state, app launching, taps, typing, scrolling, and global actions
- Foreground background service for persistent agent/runtime support
- Notification listener for notification ingestion, auto-reply, and approval flows
- Boot receiver to restore background service after reboot

## Cloudflare Worker

Configure and deploy from `worker/`:

1. Set `AUTH_TOKEN` as a Worker secret.
2. Deploy with Wrangler (Workers AI binding configured in `wrangler.toml`).

Endpoints:
- `POST /` - agent tool-calling endpoint
- `POST /auto-reply` - auto-reply suggestion endpoint

## GitHub Actions APK Build

The workflow runs:
- `flutter pub get`
- `flutter build apk --release`

It uploads `build/app/outputs/flutter-apk/app-release.apk` as a build artifact.
