# Current Progress

Updated: 2026-04-02 Asia/Shanghai

## What is already done

- Flutter watchlist refresh path was changed toward incremental updates instead of waiting for the full batch before repainting.
- `lib/services/market/ashare_market_data_service.dart` now has `fetchQuotesProgressively(...)`.
- `lib/services/background/monitor_service.dart` now updates `_latestQuotes` progressively and can notify the UI with `onQuotesUpdated`.
- `lib/core/router/app_router.dart` now passes `onQuotesUpdated` so the watchlist page can refresh as quotes arrive.
- History page now has a fallback display-name path using the watchlist repository.
- `lib/features/history/presentation/pages/history_page.dart` now sanitizes display text, history text, and spoken-text labels using readable watchlist names when possible.
- Native quote name sanitization is in place in `android/app/src/main/kotlin/com/stockpulse/radar/NativeMonitorEngine.kt` so unreadable API names can fall back to watchlist names or code.
- Flutter rule engine now skips percent-step alerts when the current band returns to `0`, which avoids `0.00%` style reminder entries from that path.
- Native/background alert generation in `android/app/src/main/kotlin/com/stockpulse/radar/NativeMonitorEngine.kt` now mirrors the current Flutter-side message rules more closely.
- Native percent step alerts now also skip the `currentIndex == 0` case, so the native path avoids `0.00%` threshold phrasing as well.
- Native short-window and step-alert messages now use stock name only, not `name(code)`, and prefer sanitized watchlist/local readable names.
- `dart analyze` was rerun successfully for the touched Dart files.
- A local `flutter build apk --release` completed successfully and produced `build/app/outputs/flutter-apk/app-release.apk`.

## What is still not finished

- `flutter test` is still not completing cleanly in this Windows environment. Multiple targeted runs timed out here without yielding per-test output, so there is still a local test-runtime verification gap.
- Device-level verification is still pending for native spoken text, reminder history wording, notification wording, and watchlist incremental refresh timing.

## Latest direct edits in this session

- Finished the native/background patch in `android/app/src/main/kotlin/com/stockpulse/radar/NativeMonitorEngine.kt`.
- Added the native percent-band guard so percent-step rules do not trigger when the current band is `0`.
- Rewrote native short-window and step-alert messages to use concise stock-name-first wording aligned with the Flutter-side behavior.
- Kept native quote-name sanitization so unreadable API names still fall back to watchlist names or stock code.
- Cleaned one Dart `analyze` info in `lib/features/history/presentation/pages/history_page.dart`.
- Verified the Android release build path by rebuilding the APK successfully.

## Notes on verification

- PowerShell plus the local `apply_patch` wrapper is still sensitive to UTF-8 argument handling on this machine.
- Terminal output still shows mojibake for some UTF-8 Chinese text, but the saved source content and `git diff` are correct.
- The practical workaround in this session was generating exact `apply_patch` payloads through short local Node scripts and passing them to the underlying Codex patch binary.

## Files currently modified in the worktree

- `.github/workflows/android-release.yml`
- `README.md`
- `android/app/src/main/kotlin/com/stockpulse/radar/NativeMonitorEngine.kt`
- `lib/core/router/app_router.dart`
- `lib/features/history/presentation/pages/history_page.dart`
- `lib/services/alerts/alert_message_builder.dart`
- `lib/services/alerts/alert_rule_engine.dart`
- `lib/services/background/monitor_service.dart`
- `lib/services/market/ashare_market_data_service.dart`
- `test/alert_message_builder_test.dart`
- `test/background_guard_stability_test.dart`
- `test/final_verification_test.dart`
- `test/monitor_market_hours_test.dart`
- `test/watchlist_swipe_delete_test.dart`
- `test/widget_test.dart`

## Recommended next steps

1. Investigate why `flutter test` hangs in this Windows environment and get the targeted test files to complete locally.
2. Verify on device that native spoken text, reminder history entries, and notifications now match the Flutter-side wording.
3. Verify watchlist incremental refresh behavior on device during active market polling.
4. If needed, run the signed release flow now that `flutter build apk --release` is passing.
