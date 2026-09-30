# Upgrade plan — 0.1.4 → 0.2.0

Bring the React Native plugin up to the native SDK versions the Flutter plugin
ships (`vietmap_tracking_plugin` 1.1.5) and close the method gap for everything
tracking-related.

**Status legend:** `[ ]` todo · `[x]` done · `[~]` in progress · `[-]` skipped (reason inline)

| | Android native | iOS native | Methods exposed |
|---|---|---|---|
| Before | `1.1.6` | `1.1.6` | 13 |
| Target | `1.5.3` | `1.5.2` | 37 |

---

## Supported React Native versions

For the README and the 0.2.0 changelog.

| | Version | Why |
|---|---|---|
| **Declared floor** (`peerDependencies`) | `>=0.79.0` | What is built and tested |
| **Technical API floor** | `0.74.0` | `BaseReactPackage` — used by `RnVietmapTrackingPluginPackage.kt` — first shipped in 0.74 (absent in 0.73, verified by fetching the file from each release). Untested below 0.79, so not declared. |
| **Built and tested against** | `0.79.6` | Pinned exactly in the root `devDependencies` and in `example` |
| **React** | `>=19.0.0` | RN 0.79's own peer requirement is `^19.0.0` |
| **Minimum iOS** | `15.1` | RN's `min_ios_version_supported` since 0.76. VietmapTrackingSDK itself only needs 12.0. |
| **Minimum Android** | `minSdk 24` | From the example's `android/build.gradle` |

`peerDependencies` was `{"react": "*", "react-native": "*"}` — no constraint at
all, which would let the plugin install into an RN version where it cannot
compile. It is now a real range.

### The version split that was fixed

The root pinned `react-native` at `0.79.2` while `example` asked for `^0.79.5`,
so yarn installed **two** copies: the library was typechecked and linted against
0.79.2 while the example compiled and ran against 0.79.6. The caret also kept
drifting onto new patches, which is what invalidated `example/ios/Podfile.lock`
and produced the hermes-engine version mismatch. Both are now pinned exactly to
`0.79.6`.

### Why not upgrade further

Release history as of 2026-09-23:

| Minor | Patches | First | Last patch | Age |
|---|---|---|---|---|
| 0.79.x | 8 | 2025-04-08 | 2025-10-21 | 17.5 mo |
| 0.80.x | 4 | 2025-06-12 | 2026-01-26 | 15.4 mo |
| 0.81.x | 7 | 2025-08-12 | 2026-02-05 | 13.4 mo |
| 0.82.x | **2** | 2025-10-08 | 2025-10-20 | 11.5 mo |
| 0.83.x | 11 | 2025-12-10 | 2026-06-25 | 9.4 mo |

Avoid **0.82.x** if the pin is ever moved: two patches and nothing since twelve
days after release, which reads as an abandoned line.

Moving the pin to **0.81.6** — the most mature option that is not the newest —
would require `react ^19.1.4`, Node `>= 20.19.4` (the repo's `.nvmrc` is
`v20.19.0`), and `compileSdk`/`targetSdk` 35 → 36. It does **not** remove the fmt
workaround in finding 8; only 0.83 ships fmt 12.

Consumers are not limited by the pin — `peerDependencies` governs what they can
install, and the range already admits 0.83. Phase 5 should add a CI matrix that
builds against more than the pinned version before the range is widened
downwards.

---

## Scope

**In scope** — tracking, identity payload, offline cache, app lifecycle, fake GPS,
tracking-interrupted.

**Out of scope — alert engine.** Not deleted; hidden behind
`// [ALERT-HIDDEN]` markers so it can be restored in one pass:
`configureVehicle`, `isSpeedAlertActive`, `processExternalLocation`
(maps to `processLocationWithVehicleParams`), `configureZoneNetworkV2` / `reset`,
speed-sign bitmaps, TTS, and the route-processing internals
(`processRouteData`, `getCurrentRouteInfo`, `findNearestAlert`,
`checkSpeedViolation`, `setRouteAPIEndpoint`, `enableRouteBoundaryDetection`,
`encodeLocationData`, `decodeLocationData`).

**Left working, untouched:** `configureAlertAPI`, `turnOnAlert`, `turnOffAlert`.

`setDriverId` maps to the payload's **userId** — same as the Flutter plugin,
where `handleGetDriverId` returns `userId`. `setVehicleId` / `getVehicleId` are
kept as plain pass-throughs.

---

## Reference findings

Verified against the real binaries, not local source — the `map-sdk-tracking`
checkout is at 1.4.11 / 1.4.9 and does not match what is published.

- Android: `javap` over `~/.gradle/caches/.../vietmap-tracking-sdk-android-1.5.3.aar`
- iOS: `arm64-apple-ios-simulator.swiftinterface` inside
  `vietmap_tracking_sdk_ios/VietmapTrackingSDK.xcframework` (1.5.2)

### 1. Do not copy the Flutter reflection hack for cache limits

The Flutter plugin reaches `configureLimits` / `getDatabaseSizeBytes` through
reflection because older SDKs did not expose them. In 1.5.3 both are public:

```java
public void configureCacheLimits(int, long, int);
public long getDatabaseSizeBytes();
```

Call them directly.

### 2. `safeUpdateTrackingConfig` reflection IS still required

`setTrackingConfig()` internally calls `setDistanceFilter()`, which does
`stopTracking() + startTracking()`. That tears down and re-creates the Foreground
Service and throws `ForegroundServiceDidNotStartInTimeException` on rapid config
changes. Work around it the way Flutter does: call `setTrackingInterval()`, set
the `distanceFilter` field directly, call `updateLocationRequest()`, and never
touch `enhancedBackgroundMode` while tracking.

If the reflection fails, log and return. Never fall back to `setTrackingConfig()`.

### 3. Signatures that changed between 1.1.6 and 1.5.x

| API | 1.1.6 | 1.5.3 / 1.5.2 |
|---|---|---|
| iOS `startTracking` | `intervalMs: Int, distanceFilter: Double` | `intervalMs: NSNumber?, distanceFilter: NSNumber?` |
| Android `LocationUpdateCallback` | `onLocationUpdate(android.location.Location)` | `onLocationUpdate(VMLocation)` |
| Android `LocationResultCallback` | `onResult(Location, String)` | `onResult(VMLocation, String, long)` |

A `nil` / null `intervalMs` or `distanceFilter` means "use the SDK cadence"
(10 s timer, 25 m floor) — this is how Flutter implements `sdkDefault()`.

### 4. Two methods are asymmetric across platforms

- `setAutoUpload` — iOS has `setAutoUpload(enabled:)`. Android has no such
  method; acknowledge the call and return `true`, as Flutter does.
- `getTrackingHealthStatus` — iOS has it natively. Android does not; build the
  map from `isTracking()`, `trackingStartTime`, `lastLocationTimestamp` and the
  permission flags.

### 5. The committed codegen spec is dead

`android/src/main/java/com/facebook/fbreact/specs/NativeRnVietmapTrackingPluginSpec.java`
is a stale build artifact, not a publish requirement. Codegen runs on the
**consuming app's** build, driven by `codegenConfig` in `package.json` and
`react { codegenJavaPackageName }` in `android/build.gradle`; the npm package
only needs to ship `src/NativeRnVietmapTrackingPlugin.ts`.

The committed copy is in package `com.facebook.fbreact.specs`, while
`RnVietmapTrackingPluginModule.kt` sits in `com.rnvietmaptrackingplugin` and
references `NativeRnVietmapTrackingPluginSpec` unqualified with no import — so it
binds to the generated class, never this one. Its signatures are also stale
(`startTracking` still carries `forceUpdateBackground`, `configure` and
`configureAlertAPI` are missing, `isTrackingActive()` is sync).

Confirmed by a real build in Phase 0. Codegen emitted
`android/build/generated/source/codegen/java/com/rnvietmaptrackingplugin/NativeRnVietmapTrackingPluginSpec.java`
with `package com.rnvietmaptrackingplugin;`, and its 14 abstract methods match
the current TS spec exactly — including `configure` and `configureAlertAPI`,
which the committed copy did not have.

Workflow when adding a method:

1. Edit `src/NativeRnVietmapTrackingPlugin.ts`
2. `cd example/android && ./gradlew :vietmap_rn_vietmap_tracking_plugin:generateCodegenArtifactsFromSchema`
   then read back the generated signature from the path above
3. Write the matching `override fun` in `RnVietmapTrackingPluginModule.kt`

Gradle module name for the library is `:vietmap_rn_vietmap_tracking_plugin`.

### 6. Location event payloads differ per platform

Found while wiring Phase 1.2. Android now emits the shape declared by
`LocationData` in `src/types.ts` — `latitude`, `longitude`, `altitude`,
`accuracy`, `speed`, `bearing`, `timestamp` — which is what the example app
reads. iOS forwards the SDK's `NSDictionary` straight through without
normalising it, so the two platforms may not agree on key names.

**Resolved during Phase 1 verification.** The SDK reports `lat` / `lng` /
`heading`; the TypeScript contract and the example use `latitude` / `longitude` /
`bearing`. So on iOS `location.bearing` was `undefined` and the example crashed
on `currentLocation.bearing.toFixed(2)`.

Evidence: the Flutter plugin's `LocationData.fromJson` accepts **both** spellings
(`lat`|`latitude`, `lng`|`longitude`, `heading`|`bearing`, `time`|`timestamp`) —
it hit the same thing and normalises in Dart. `strings` over
`VietmapTrackingSDK.framework` shows `heading` but no `bearing`.

`normalizeLocation()` in `RnVietmapTrackingPlugin.swift` now maps the raw
dictionary onto the `LocationData` shape for both `onLocationUpdate` and
`getCurrentLocation`. It accepts either spelling on input, so it survives a
future SDK rename, and converts a seconds timestamp to milliseconds using the
same rule as Flutter's `_readTimestampMillis`.

### 7. `updateTrackingConfig` cannot change `backgroundMode` mid-session

Applying it calls `setEnhancedBackgroundMode()`, which starts the background
service a second time while tracking is active. Interval and distance are
applied; `backgroundMode` is ignored and stays whatever `startTracking()` set.
Document this in the README in Phase 5.

### 8. fmt 11.0.2 does not build under Xcode 26 — workaround in the example Podfile

Hit while verifying Phase 0 on iOS. Not caused by this upgrade; it blocks any
iOS build of this example on Xcode 26 regardless of the SDK version.

Five errors, all inside fmt itself
(`Pods/fmt/include/fmt/format-inl.h` lines 59, 60, 1387, 1391, 1394):

```
call to consteval function 'fmt::basic_format_string<...>' is not a constant expression
```

`fmt/base.h` only blacklists Apple clang **< 14** before enabling consteval, so
Apple clang 21 (Xcode 26.4.1) falls through to the `defined(__cpp_consteval)`
branch and turns it on — then fails in fmt's own header.

**Upgrading React Native does not fix this short of 0.83.** Checking each
release's `third-party-podspecs/fmt.podspec`:

| React Native | fmt |
|---|---|
| 0.79.7 · 0.80.3 · 0.81.0 · 0.81.6 · 0.82.1 | 11.0.2 |
| 0.83.10 | 12.1.0 |

**`-DFMT_USE_CONSTEVAL=0` does not work on 11.0.2.** That version's block opens
with `#if !defined(__cpp_lib_is_constant_evaluated)` and always redefines the
macro, so a command-line define is overridden. fmt 12.1.0 opens with
`#ifdef FMT_USE_CONSTEVAL` and does honour it — which is why this advice
circulates but fails here.

The `post_install` hook in `example/ios/Podfile` therefore patches the guard in
place, making the Apple-clang branch unconditional. That is the same code path
old Apple clang already took; the only loss is compile-time format-string
checking inside fmt. The hook restores CocoaPods' read-only `0444` mode after
writing, is idempotent, and warns instead of silently doing nothing if fmt is
ever upgraded and the guard no longer matches.

Remove the hook when React Native reaches 0.83+.

### 9. SSL pinning is the SDK's business — the plugin must never touch it

**Rule: neither the plugin nor the example may call `setSslFingerprints`.**
Verified by grep across `rn_vietmap_tracking_plugin` and
`vietmap_flutter_tracking_plugin`: neither calls it, in the library or the
example. The SDK owns pinning end to end — it fetches the pins itself from
`baseURL + "/app-config"` and feeds them to its own `setSslFingerprints`.
Anything the plugin sets would fight that.

`setSslFingerprints` stays out of scope for the same reason
(it sits in the out-of-scope security group above), and any future exposure of
it needs a deliberate decision, not a debugging shortcut.

#### Why uploads silently produced nothing on iOS

Worth recording, because the symptom looks like "GPS is broken" and is not.

Observed: `configure(apiKey, 'https://staging.fleetwork.vn/api/v1')`, tracking
active, CoreLocation delivering ~1 fix/second — and zero rows on the server.
Every upload died as `NSURLErrorDomain -999 "cancelled"`, 0/0 bytes.

The request URL was correct throughout
(`https://staging.fleetwork.vn/api/v1/gps-tracking/events`), and the TLS trace
shows the handshake reaching `read_server_certificate_verify`, then
`boringssl_context_evaluate_trust_async → "Performing external trust
evaluation"`, then an immediate cancel. That is the SDK's own
`URLSessionDelegate` rejecting the certificate:

```swift
} else {
    print("[SSLPinning] Fingerprint mismatch — possible MitM attack. Computed: \(computed)")
    completionHandler(.cancelAuthenticationChallenge, nil)   // -> -999
}
```

Where the wrong pins came from, by request timeline:

```
14:43:14  live.fleetwork.vn/api/v1/app-config       <- production
14:43:15  live.fleetwork.vn/api/v1/app-config       <- production
14:43:15  staging.fleetwork.vn/api/v1/app-config
14:43:45  live.fleetwork.vn/api/v1/app-config       <- production again, last write wins
14:51:53  staging.../gps-tracking/events            <- cancelled, -999
```

The SDK's baseURL defaults to production, hardcoded:

```swift
// VietmapTrackingSDK.swift:491
private var baseURL: String = "https://live.fleetwork.vn/api/v1"
```

Its init runs `fetchAppConfig(force: true)` against that default **before** the
app's `configure()` has supplied the real baseURL, so it installs **production**
pins. The app's own `configure(apiKey, staging)` follows and triggers a second
app-config fetch against staging — but on the runs observed the staging fetch
never completed (both requests hung for 31 s and were cancelled), leaving the
production pins in place. Uploads to staging are then rejected.

**A first hypothesis that turned out wrong, recorded so it is not re-tried:**
the SDK also persists `tracking_base_url` / `tracking_api_key` to the Keychain
(`VietmapKeychainManager`) and restores them via `restoreSslPinningCache()`, so
the obvious theory was a stale production URL left over from an earlier run,
with the added wrinkle that deleting an iOS app does not clear its Keychain.
Disproved directly: after `xcrun simctl erase` — empty Keychain, app freshly
installed — the very first requests were still

```
16:01:13.481  live.fleetwork.vn/api/v1/app-config      <- production
16:01:13.492  staging.fleetwork.vn/api/v1/app-config
```

so the production URL comes from the hardcoded default, not from restored state.

**The SDK cannot recover from this on its own.** Its self-healing path only
reacts to SSL error codes:

```swift
let sslCodes = (-1206)...(-1200)
if sslCodes.contains(nsError.code) { /* re-fetch config */ }
```

`cancelAuthenticationChallenge` produces `-999`, outside that range, so the
lazy re-fetch never fires and the SDK stays wedged.

This is a native-SDK defect, not a plugin one, and nothing in the plugin layer
can work around it. Report it upstream. Candidate fixes, in order of how much
they address the root:

1. Do not fetch app-config — and therefore do not install pins — until
   `configure()` has supplied a baseURL. Pins fetched against the hardcoded
   default are for the wrong host by construction.
2. Key pins per host, so changing baseURL invalidates the previous host's pins
   instead of leaving them to reject the new one.
3. Widen the self-heal range to include `-999`, so a pinning rejection at least
   triggers a config re-fetch rather than wedging.

Erasing the simulator does **not** work around it: verified above.

Diagnostic note: the SDK logs pinning failures with Swift `print()`, which goes
to stdout, not `os_log`. `log show` will never surface `[SSLPinning]` lines —
use the Xcode console or `simctl launch --console`.

**Correction — scope of "nothing in the plugin layer can work around it".**
That sentence was written about the *staging* pinning wedge above and is
accurate only there. It was then wrongly carried over to the production
endpoint, where uploads returned HTTP 200 with an empty batch. Two separate
plugin bugs caused that, both fixed:

- `configure()` called the SDK's split `configure(apiKey:)` and
  `configure(baseURL:)`, where the combined
  `configure(apiKey:baseURL:autoUpload:)` was required.
- The plugin never set `allowMockLocation` — see finding 11.

Neither was an SDK defect. Check the plugin boundary before blaming the SDK.

### 11. `allowMockLocation` was never set — the plugin skipped a gate Flutter sets

**Status: a real parity gap, fixed. Not confirmed as the cause of the empty
upload batch** — see the measurement note at the end of this finding.

`VietmapTrackingSDK.swift:4202`, inside `didUpdateLocations`:

```swift
if (sourceInfo.isSimulatedBySoftware || sourceInfo.isProducedByAccessory)
   && !allowMockLocation {
    applyFakeGPSPolicy(location: location, reason: reason)
    return // Skip fake location from normal tracking pipeline
}
```

`allowMockLocation` defaults to `false` in the SDK (iOS
`VietmapTrackingSDK.swift:508`, Android `TrackingConfig()` ctor), and every fix
from `simctl location` or `adb emu geo fix` reports
`isSimulatedBySoftware == true`. So the SDK discarded **every** point before
tracking saw it. Measured on a simulated 20 m/s route:
`didUpdateLocations: 123` → `onLocationUpdate: 0`, and the upload POST went out
at 243 bytes — an empty batch — which the server answered `200`. The symptom
reads as "the SDK is broken"; it is the fake GPS filter doing its job.

The Flutter plugin never hit this because it passes the flag on every start,
defaulting to `true`:

```swift
// vietmap_flutter_tracking_plugin/ios/Classes/VietmapTrackingPlugin.swift:891
trackingManager.setAllowMockLocation(allowMockLocation)   // default true
```

The RN plugin called neither `setAllowMockLocation` (iOS) nor set
`TrackingConfig.allowMockLocation` (Android). Fixed in Phase 2 by threading
`allowMockLocation` through all five layers with the same `true` default, and
by exposing `setFakeGPSPolicy` plus the `onFakeGPSDetected` event so a
production app can turn detection on deliberately.

**What the confirming run actually showed.** On the run after the fix, uploads
worked — `POST /gps-tracking` at 1338-1343 bytes answered `204`, once per
`onLocationUpdate`, against 243 bytes for the earlier empty batch. But that run
never called `startTracking`: the SDK resumed tracking from restored state, so
`setAllowMockLocation(true)` never executed and fixes passed the gate anyway.
Two readings survive that evidence and this finding does not pick between them:

- `location.sourceInformation` may be nil on this simulator/iOS version, so the
  gate never triggers there and something else caused the empty batch.
- The empty batch came from tracking not actually being active — `startTracking`
  was refused for a missing `userId`, which would leave `isTracking` false and
  `processLocationForTracking` unreached, which reads identically from outside.

To settle it, run with `startTracking` called explicitly and watch for
`-> SDK setAllowMockLocation` followed by `onFakeGPSDetected`.

### 14. `pod install` must be run from `example/ios`, and a green build can hide it

The codegen script phase fails with:

```
/bin/sh: .../example/ios/../../../../../../../../../../../../node_modules/react-native/scripts/xcode/with-environment.sh: No such file or directory
Command PhaseScriptExecution failed with a nonzero exit code
```

Twelve `../` from `example/` climbs past the filesystem root, so the path
resolves to `/node_modules/react-native`.

The cause is in `react-native/scripts/cocoapods/codegen_utils.rb`:

```ruby
relative_installation_root = Pod::Config.instance.installation_root.relative_path_from(Pathname.pwd)
```

The path baked into `Pods.xcodeproj` is computed **relative to the working
directory of the `pod install` process**. Run from `example/ios` it is `.` and
the result is `./../node_modules/react-native`. Run from anywhere else it is
whatever `relative_path_from` produces — here, twelve levels of `..`.

**Rule: always `cd example/ios` before `pod install`.** Anything that installs
pods on your behalf — an IDE action, a wrapper script, a tool invoked from the
repo root — can reintroduce this.

#### The part that made it hard to see

A local build can pass while the checked-in project is broken. `xcodebuild
-derivedDataPath build` reported `BUILD SUCCEEDED` against a DerivedData that
still held a correct, cached `Script-*.sh` from an earlier install; Xcode
considered the phase up to date and never re-ran it. Meanwhile
`Pods.xcodeproj` on disk carried the broken path, and `yarn ios` — which uses
the developer's own DerivedData — failed immediately.

**So "BUILD SUCCEEDED" on a warm DerivedData is not evidence the project is
sound.** To check the project rather than the cache, grep it directly:

```bash
grep -o 'RCT_SCRIPT_RN_DIR=[^;]*' example/ios/Pods/Pods.xcodeproj/project.pbxproj | head -1
```

One `../` is correct. More than one means `pod install` ran from the wrong
directory and the next clean build will fail.

### 13. `Promise<Object>` in the spec checks nothing

Three bugs shipped from one habit: forwarding a native dictionary to JS without
checking it against the type this API declares.

`getTrackingHealthStatus` was the worst. The iOS SDK returns 17
CoreLocation-specific fields; `TrackingHealthStatus` declares eight. Exactly one
name overlaps — `timeSinceLastUpdate` — and it is in seconds where the type says
milliseconds. So six of eight fields were `undefined` on iOS and the health card
rendered almost empty, while Android, which assembles its own, was correct.

Alongside it: `getTrackingStatus` on Android returned neither `trackingDuration`
nor `lastLocationUpdate` although the type marks the first required, and
`onTrackingInterrupted` carried an iOS-only `timestamp` in seconds that the type
never declared.

Nothing caught any of it, because the TurboModule spec types these as
`Promise<Object>` and `Object` accepts anything. TypeScript cannot check a value
that crosses the bridge; the cast at the wrapper (`status as TrackingStatus`) is
an assertion, not a verification.

**Rule: a native dictionary forwarded to JS must be checked field by field
against the declared type, on both platforms.** Where the platforms disagree,
assemble the declared shape in the bridge rather than widening the type to
whatever each one happens to return — and keep the platform's own dictionary
under a documented key like `raw` so nothing is lost.

Worth noting what Flutter does here, since it looks like it has no such bug: it
does not promise. `getTrackingHealthStatus` returns `Map<String, dynamic>`, and
`TrackingInterruptedEvent` simply omits the field iOS sends. The asymmetry is
identical in both plugins; only React Native declared a contract and then broke
it. The stronger typing is the feature — the fix is to meet the contract, not to
weaken it.

`scripts/check-ios-parity.js` cannot catch this: it compares selectors, not
payloads. Shape assertions in `src/__tests__/index.test.tsx` do, mocking each
platform's real shape rather than an idealised one.

### 12. An Objective-C category was shadowing the Swift class

Found at runtime, after the event surface was already "finished":

```
`onFakeGPSDetected` is not a supported event type for RnVietmapTrackingPlugin.
Supported events are: `onLocationUpdate`, `onTrackingStatusChanged`,
`onLocationError`, `onPermissionChanged`, `onRouteUpdate`
```

`onRouteUpdate` had been removed from both source files, so the list being
reported existed nowhere on disk.

Two causes, stacked. The immediate one was a stale native binary: Metro
hot-reloads JS, so new JS calling `addFakeGPSDetectedListener` ran against a
native build from before the change. Reinstalling the app fixes that.

The one worth recording is underneath it. `RnVietmapTrackingPluginModule.m`
carried a category:

```objc
@implementation RnVietmapTrackingPlugin (Utils)
+ (BOOL)requiresMainQueueSetup { return YES; }
- (NSArray<NSString *> *)supportedEvents { return @[ ... ]; }
@end
```

while `RnVietmapTrackingPlugin.swift` overrides both of the same methods. An
Objective-C category method **replaces** the class's own implementation, and
which one wins is not defined by the language — it depends on load order. So the
event list had two homes, and adding an event to the Swift list alone could
reach the bridge or silently do nothing depending on how the binary was linked.

Fixed by deleting the category; both live in Swift, beside the `sendEvent` calls
they describe. `scripts/check-ios-parity.js` now fails the build when
`supportedEvents`, `requiresMainQueueSetup`, `constantsToExport` or `moduleName`
appear in both a category and the Swift class.

**Rule for anything that looks like a stale-build symptom:** reinstall first,
then look for a second definition. This one produced a list that matched no
file in the repository, which is the signature of two definitions rather than
one stale file.

### 10. `RCT_EXTERN_METHOD` is not compile-checked

The iOS side registers selectors manually and bypasses conformance to the
codegen protocol, so a method declared in the `.m` with no Swift implementation
compiles cleanly and crashes at call time with `unrecognized selector`. That is
how 14 methods stayed broken. Phase 5 adds a parity check to `npm run validate`.

---

## Phase 0 — Cleanup and native bump `[x]`

- [x] **0.1** `android/build.gradle` — `vietmap-tracking-sdk-android` `1.1.6` → `1.5.3`
- [x] **0.2** `rn_vietmap_tracking_plugin.podspec` — `VietmapTrackingSDK` `1.1.6` → `1.5.2`
- [x] **0.3** Delete dead files
  - [x] `android/.../RnVietmapTrackingPluginModuleClean.kt` (0 bytes)
  - [x] `android/.../RnVietmapTrackingPluginModule_VietmapSDK.kt` (0 bytes)
  - [x] `android/src/main/java/com/facebook/fbreact/specs/NativeRnVietmapTrackingPluginSpec.java` (stale codegen artifact — recoverable from git)
- [x] **0.4** `ios/RnVietmapTrackingPluginModule.m` — comment out all 14
      declared-but-unimplemented methods so none of them can crash. Split three
      ways: 8 `[ALERT-HIDDEN]` (route/alert internals), 1 `[OUT-OF-SCOPE]`
      (`setTrackingStatus` — exists in 1.5.2 but Flutter does not expose it),
      5 `[PHASE-2]` (cache/network, uncommented as the Swift side lands).
      Declared/implemented parity afterwards: 15 / 15 / 0 orphans.
- [x] **0.5** `android/.../RnVietmapTrackingPluginModule.kt` — comment out
      `findNearestAlert` (returned a placeholder string)
- [x] **0.6** `ios/RnVietmapTrackingPlugin.swift` — wrap `intervalMs` /
      `distanceFilter` in `NSNumber` for the 1.5.2 `startTracking` signature
- [x] **0.7** Verified every SDK symbol the current code calls still exists in
      1.5.3 / 1.5.2 — `startTracking` is the only breaking change

**Exit criteria:** both platforms build; no behaviour change expected yet.

---

## Phase 1 — Fix the four live bugs `[x]`

No codegen change needed in this phase — the public TS spec is untouched.

- [x] **1.1** Android `getCurrentLocation()` returned hardcoded `0,0`. Replaced
      with `vietmapSDK.getCurrentLocation(maxAgeMs, timeoutMs, LocationResultCallback)`
      using the 1.5.3 three-argument `onResult(VMLocation, String, long)`.
      Defaults: `maxAgeMs = 10_000`, `timeoutMs = 5_000`. Public signature kept
      at no-arg; optional parameters land in Phase 3.
- [x] **1.2** Android never emitted `onLocationUpdate` / `onTrackingStatusChanged`
      — the module never registered `addLocationCallback` / `addStatusCallback`,
      so `addLocationUpdateListener` was dead on Android. Added
      `setupSDKCallbacks()` / `clearSDKCallbacks()`, wired into `configure()` and
      `invalidate()`. Also records `lastLocationTimestamp` and `trackingStartTime`
      for Phase 2's `getTrackingHealthStatus`.
- [x] **1.3** `updateTrackingConfig` called `setTrackingConfig()` while tracking
      was active, which restarts the Foreground Service. Ported
      `safeUpdateTrackingConfig()`.
- [x] **1.4** iOS declared-but-unimplemented methods — neutralised in 0.4;
      real implementations arrive in Phase 2.

**Exit criteria:** on Android, `addLocationUpdateListener` receives real fixes,
`getCurrentLocation()` returns real coordinates, and changing config mid-session
does not crash.

### Verification run for Phases 0 and 1

| Check | Result |
|---|---|
| `tsc --noEmit` | pass |
| `eslint src/**` | 0 errors (9 pre-existing `any` warnings) |
| `jest` | 16 passed, 1 todo |
| `:vietmap_rn_vietmap_tracking_plugin:compileDebugKotlin` against SDK 1.5.3 | BUILD SUCCESSFUL |
| iOS `.m` / `.swift` parity | 15 declared / 15 implemented / 0 orphans |
| Reflection targets present in 1.5.3 | `trackingManager`, `setTrackingInterval(long)`, `distanceFilter` (float), `updateLocationRequest()` |
| iOS `xcodebuild` against SDK 1.5.2 (Xcode 26.4.1) | builds, after the fmt workaround in finding 8 |

The iOS build produced `RnVietmapTrackingPluginExample.app` with
`Frameworks/VietmapTrackingSDK.framework` embedded, and compiled
`RnVietmapTrackingPlugin.o` for both arm64 and x86_64 — so **0.6 (the `NSNumber`
change for the 1.5.2 `startTracking` signature) is confirmed by the compiler**.
The Swift source was last edited at 11:29:38 and the object was produced at
14:27:20, so the compile covered the change rather than a stale cache.

### Runtime verification on the Android emulator

All three fixes confirmed on `Android_13_API33` with the example app, driving
GPS through `adb emu geo fix` and tapping with `adb shell input tap`.

| Fix | Evidence |
|---|---|
| **1.1** `getCurrentLocation` | Dialog showed `10.776898, 106.700900` — the coordinates fed to the emulator, not the old hardcoded `0,0` |
| **1.2** status events | `📊 Status update: { message: 'Tracking started successfully', isTracking: true }` |
| **1.2** location events | Three `📍 New location` deliveries tracking the simulated route, in the exact `LocationData` shape: `{ latitude, longitude, altitude, accuracy, speed, bearing, timestamp }` |
| **1.3** `safeUpdateTrackingConfig` | `D RnVietmapTracking: safeUpdateTrackingConfig \| interval=5000ms distance=10.0m` — the success line, so all four reflection targets resolved. No "reflection failed", no crash. Location events kept arriving after the change (15:41:53, 15:41:58 against a 15:41:29 tap), so the session survived |

**Caveat on 1.3.** The run used `backgroundMode: false`, so no Foreground
Service was active and the specific
`ForegroundServiceDidNotStartInTimeException` path was never entered. What is
proven is that the reflection resolves against SDK 1.5.3 and that a mid-session
config change does not interrupt tracking. Re-run with `backgroundMode: true`
to exercise the original crash scenario end to end.

The iOS side compiles and the app runs, configures the SDK
(`[V2][Configure] done`) and reports permissions granted, but its buttons were
not exercised: this machine has neither `idb` nor `cliclick`, and `simctl` has
no tap command. All three Phase 1 bugs were Android-only, so the Android run is
the one that matters; what remains unverified on iOS is `normalizeLocation`
against a live SDK payload.

### Two further bugs found by running it

Neither is visible to the compiler — both platforms built green throughout.

**`startTracking()` reported success when the SDK had refused.** The Android SDK
exposes `public boolean startTracking()`, but the module discarded the return
value and always resolved `true`. Fixed: the promise now carries the SDK's own
result, and `trackingStartTime` is only recorded on a real start.

**Tracking cannot start without a userId.** The SDK rejects it and says so
through the status callback:

```
'📊 Status update:', { message: 'userId is required before starting tracking', isTracking: false }
```

`setDriverId` fills that field, so it is not optional. The identity group
(`setDriverId` / `getDriverId` / `setVehicleId` / `getVehicleId`) was pulled
forward from Phase 2A to unblock verification, and the example now calls
`setDriverId` before `startTracking`. Verified:
`'✅ Identity set:', 'demo-driver-001', 'demo-vehicle-001'`.

### Known issue, not blocking — `NativeEventEmitter` conformance

Both platforms log at startup:

```
'`new NativeEventEmitter()` was called with a non-null argument without the required `addListener` method.'
'... without the required `removeListeners` method.'
```

`src/index.tsx` builds the emitter from `NativeModules.RnVietmapTrackingPlugin`,
but neither the TurboModule spec nor the native modules declare `addListener` /
`removeListeners`, which the New Architecture requires (the example runs with
`fabric: true`).

Events still arrive on Android — `NativeEventEmitter` there listens on the
global `RCTDeviceEventEmitter` rather than through the module — which is why
1.2 verified despite the warning. It is still the source of the "Open debugger
to view warnings" toast on both platforms, and iOS, where the module extends
`RCTEventEmitter`, is the riskier side. Add both methods to the spec and
implement them in Phase 2.

---

## Phases 2-5 — moved

The remaining work is now a single executable plan in
[`IMPLEMENTATION_PLAN.md`](./IMPLEMENTATION_PLAN.md): 12 ordered steps covering
the 23 missing methods, the config layer, the two missing events and the example
app, with the exact native signature for each method on both platforms.

The old Phase 2-5 breakdown lived here and was superseded by the full re-trace
below, which found the gap to be wider than a method count: the config shape,
the call-site guards and two dead Android event declarations were all missing
from it. Progress markers belong in the new file.

What this file keeps: the reference findings above, the Phase 0 and Phase 1
records, and the parity audit below.

---

# Flutter parity audit — full re-trace

Re-done from the native method-channel contract rather than from the Dart API,
after the first pass proved incomplete. Sources: the `case "..."` arms in
`ios/Classes/VietmapTrackingPlugin.swift` (42) and the `"..." ->` arms in
`android/.../VietmapTrackingPlugin.kt` (43), minus `batterySaver` / `navigation`
which are preset names, not methods.

**Flutter exposes 42 methods. RN exposes 19. 23 are missing, and the gap is
wider than the method count** — config shape, event channels, call-site guards
and the example app all diverge.

## A. Missing methods (23)

| # | Method | Group | Native support |
|---|---|---|---|
| 1 | `getPlatformVersion` | misc | both |
| 2 | `configureTracking` | config | iOS only — `configure` covers it on Android |
| 3 | `configureVehicle` | identity | both — `(vehicleId, vehicleType, seats, weight, maxProvision?)` |
| 4 | `setMetadata` | identity | both |
| 5 | `setPackages` | identity | both |
| 6 | `setAppSignature` | identity | both |
| 7 | `isNetworkConnected` | cache | both |
| 8 | `getCachedLocationsCount` | cache | both |
| 9 | `uploadCachedLocationsManually` | cache | both |
| 10 | `clearCachedLocations` | cache | both |
| 11 | `configureCacheLimits` | cache | both |
| 12 | `getDatabaseSizeBytes` | cache | both |
| 13 | `onAppBackground` | lifecycle | both |
| 14 | `onAppForeground` | lifecycle | both |
| 15 | `setAutoUpload` | lifecycle | iOS native, Android no-op |
| 16 | `setFakeGpsNotificationConfig` | fake GPS | both |
| 17 | `setTrackingInterruptedNotificationEnabled` | interrupted | both |
| 18 | `setTrackingInterruptedNotificationConfig` | interrupted | both |
| 19 | `getTrackingHistory` | history | both — paginated server fetch |
| 20 | `getTrackingHealthStatus` | diagnostics | iOS native; Android needs module-side assembly |
| 21 | `setSmartBatteryConfig` | battery | both |
| 22 | `processExternalLocation` | external GPS | both |
| 23 | `isSpeedAlertActive` | alert | both — out of scope, keep hidden |

## B. Config shape — the deepest divergence

`LocationTrackingConfig` has 11 fields in Flutter, 8 in RN after
`allowMockLocation`. Missing: `userId`, `vehicleId`, `apiEndpoint`,
`enableSpeedFallback`.

**`intervalMs` and `distanceFilter` are nullable in Flutter and required in RN.**
That is not cosmetic. The SDK picks a trigger mode from which of the two is
supplied:

- interval only → timer mode
- distance only → displacement mode
- both → **the SDK gives the timer priority and ignores the distance gate**
- neither → the SDK's own defaults (10s / 25m)

`index.tsx` does `config.intervalMs || 5000` and `config.distanceFilter || 10`,
so RN always sends both and can therefore only ever reach the "both" mode.
Distance-based tracking is unreachable from RN today, and
`LocationTrackingConfig.sdkDefault` has no equivalent.

Two more defaults disagree: `backgroundMode` is `|| false` in RN against `true`
in Flutter, and `enableSpeedFallback` is hardcoded `true` in the iOS bridge
instead of being configurable.

Also absent: **`TrackingPresets`** — 8 entries (`navigation`, `fitness`,
`general`, `batterySaver`, each with a `*Distance` variant), carrying the SDK's
floors (5000ms, 25m) and the per-preset accuracy tuning.

## C. Events

| Event | Flutter | RN iOS | RN Android |
|---|---|---|---|
| location updates | `EventChannel` | yes | yes |
| tracking status | `EventChannel` | yes | yes |
| `onFakeGPSDetected` | `invokeMethod` | yes | **missing** — SDK has `addFakeGPSCallback` |
| `onTrackingInterrupted` | `invokeMethod` | **missing** | **missing** — SDK has `addTrackingInterruptedCallback` |
| `onLocationError` | — | declared | **never emitted** |
| `onRouteUpdate` | — | declared | **never emitted** |

The last two are declared in `supportedEvents()` on both platforms but Android
emits neither, so a listener attached on Android silently never fires.

## D. Call-site guards missing in RN

`VietmapTrackingController.startTracking` runs five guards before touching the
SDK. `startLocationTracking` runs one (permissions):

All five have since been implemented, in step 2 of
[`IMPLEMENTATION_PLAN.md`](./IMPLEMENTATION_PLAN.md). Ticked here so this audit
is not mistaken for open work — it records what was missing when it was written,
not what is missing now.

- [x] `requireConfigured()` — throws `SDK_NOT_CONFIGURED` when neither
      `configure()` nor `initializeTracking()` has run
- [x] `startInFlight` — a second concurrent start resolves `false` rather than
      racing the first
- [x] `isTrackingActive()` checked **before** asking for permissions, so a
      redundant start cannot raise a permission dialog
- [x] `userId` non-empty validation, rejected as `MISSING_USER_ID`
- [x] `enableSmartBattery` opt-in, default `false`

Flutter also pushes `userId` / `vehicleId` **inside** the `startTracking` args
and calls `setDriverId` / `setVehicleId` natively at that moment. RN requires
the caller to invoke them separately beforehand — a different contract, and the
reason the example needs its own Apply Identity step.

## E. Missing plugin-side services

- **`SmartBatteryManager`** (387 lines) — vehicle activity state machine
  (stationary / moving / cornering), `battery_plus` integration, profile
  switching with an `onSmartBatteryProfileChanged` stream.
- **Lifecycle observer** — `registerLifecycleObserver()` wires
  `didChangeAppLifecycleState` to `onAppBackground` / `onAppForeground`
  automatically. RN would use `AppState`.
- **`VietmapPreference`** (89 lines) — persistence helper.
- **Structured native logging** — `logSection()` / `nativeLog()` bracket every
  operation on both platforms. RN's `[VMBridge]` traces are iOS-only and
  DEBUG-only.

## F. Example app

Flutter: 3280 lines, 14 cards. RN: 1079 lines, 7 sections.

Present in Flutter, absent in RN: Header (SDK status), Packages, Fake GPS,
Tracking Interrupted, Smart Battery, Cache, plus `gpx_simulator.dart` for
replaying routes. Also absent: server-history fetch with pagination
(`fetchServerHistory` / `fetchMoreServerHistory`), notification permission
handling, and persistence of the email and package list across launches.

Speed Alert stays out of scope per the alert decision.
