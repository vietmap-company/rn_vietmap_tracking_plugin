# Implementation plan — closing the Flutter parity gap

Single executable plan for the 23 missing methods, the config layer, the two
missing events, the native lifecycle safety net and the example app. Derived from the audit in
[`UPGRADE_PLAN.md`](./UPGRADE_PLAN.md), which stays as the findings and debugging
record — this file is the one to work from.

**Mark each box as it lands.** The markers are the progress record; a half-done
step with an unticked box is easier to resume than a tidy summary.

Signatures below were read from the shipped artefacts, not from the Flutter
plugin's wrappers:

- iOS — `VietmapTrackingSDK.xcframework/.../arm64-apple-ios-simulator.swiftinterface`
  (pod 1.5.2), class `VietmapTrackingManager`
- Android — `vietmap-tracking-sdk/.../VietmapTrackingSDK.java` (1.5.3)

## Every method crosses five layers

```
src/types.ts                         types the caller sees
src/NativeRnVietmapTrackingPlugin.ts TurboModule spec  -> drives Android codegen
src/index.tsx                        public wrapper + guards
ios/RnVietmapTrackingPluginModule.m  RCT_EXTERN_METHOD  -> NOT compile-checked
ios/RnVietmapTrackingPlugin.swift    @objc implementation
android/.../RnVietmapTrackingPluginModule.kt   override fun
```

Two standing traps, both already paid for once:

- The `.m` declaration is not checked against the Swift implementation. A
  mismatch compiles and crashes at call time with `unrecognized selector`. Run
  the parity check in step 12 after every iOS change.
- Codegen maps an optional TS parameter to a nullable Kotlin one
  (`distanceFilter?: number` -> `Double?`). Get this wrong and the module stays
  abstract with a confusing error.

## Platform asymmetries to handle, not to paper over

| Method | iOS 1.5.2 | Android 1.5.3 | Plan |
|---|---|---|---|
| `setAutoUpload` | `setAutoUpload(enabled:)` | none | Android resolves `true` with a comment; uploads are automatic there |
| `getTrackingHealthStatus` | `getTrackingHealthStatus()` | none | Assemble module-side on Android from `trackingStartTime` / `lastLocationTimestamp`, which already exist |
| `setSmartBatteryConfig` | none | none | Plugin-side on both: iOS sets `CLLocationManager.activityType`, Android routes through `safeUpdateTrackingConfig` |
| `processExternalLocation` | `processExternalLocation(lat:lng:speed:heading:)` | none | Android uses `processLocationWithVehicleParams(lat, lng, speed, heading)` |
| `uploadCachedLocationsManually` | completion `(Bool, String?)` | `void`, no callback | Android resolves `true` after the call returns |
| `getHistory` | completion `(String?, String?, String?)` | `HistoryCallback` interface | Both resolve the raw JSON string; parse in TS |

---

## Step 0 — Prove the lifecycle assumptions before building on them `[~]`

> **Status: instrumented, not yet measured.**
>
> The logging in 0.1 is written and shipping on both platforms — `[VMLife]`
> traces on a monotonic clock, sequence-numbered transitions, and
> `markJsAppState` so a JS-observed transition can be stamped on the native
> clock. Steps 6.4–6.8 were built on the reasoning below rather than waiting,
> because every one of them is an improvement on its own terms; what the
> measurements decide is whether 6.6 and 6.7 stay.
>
> **Update 2026-09-30:** `markJsAppState` has been removed for the 0.2.0
> release (see 0.1.6). The `[VMLife]` traces remain, so every experiment except
> 0.3.1 can still be run as written.
>
> **What remains needs a person and a device** and cannot be done from here:
> backgrounding the app by hand, toggling airplane mode, running a long session
> that crosses a tunnel or a wifi handover, and reading a physical device's log.
> Each experiment below states what would refute it, so a result that
> contradicts the reasoning should delete the step rather than be explained
> away.

Steps 6.4-6.8 rest on claims about what happens to the app as it backgrounds and
returns. The claims are reasoned from source, not measured, and a plan built on
an unmeasured claim is how finding 11 in `UPGRADE_PLAN.md` ended up asserting a
root cause it had not confirmed.

So: instrument first, run the six experiments below, then decide. Each claim is
written with **what refutes it**, not only what confirms it — a log that can only
agree with me is not evidence.

### 0.1 A shared clock, or the numbers mean nothing `[ ]`

Hops are compared in milliseconds, so every layer must stamp the **same
monotonic** clock. Wall clock is unusable: it jumps, and JS `Date.now()` cannot
be compared to a native timestamp at all.

- [x] **0.1.1** Tag every lifecycle line `[VMLife]`, beside the existing
      `[VMBridge]`, so one `grep` gets the whole timeline.
- [x] **0.1.2** iOS — stamp `ProcessInfo.processInfo.systemUptime * 1000`.
      Android — `SystemClock.elapsedRealtime()`.
- [x] **0.1.3** Give each transition a sequence number assigned by the **native
      observer**, and carry it through every later line for that transition. Two
      quick background/foreground cycles otherwise interleave unreadably.
- [x] **0.1.4** JS cannot stamp this clock, so do not try. The JS `AppState`
      handler instead calls a temporary native probe,
      `markJsAppState(state, seq)`, and **native** logs the arrival time. The
      delta is then a true round-trip measured on one clock.
- [x] **0.1.5** Gate all of it: `#if DEBUG` on iOS (as `trace()` already does)
      and `BuildConfig.DEBUG` on Android. None of this ships enabled.

      **Initially only half done, caught on the pre-release check.** iOS was
      gated; Android had 44 ungated `Log.d` calls carrying driver ids and
      coordinates, which would have reached consumers' release builds — Android
      does not strip `Log.d` and a library cannot rely on the host app's R8
      rules. All now route through a `logDebug()` helper behind
      `BuildConfig.DEBUG`. `Log.w` and `Log.e` stay ungated on purpose: they
      carry no identity or position and are wanted in production.
- [x] **0.1.6** `markJsAppState` is scaffolding. Deleted before the 0.2.0
      release rather than after the experiments, because shipping it would have
      promised long-term support for a method that exists to be removed.

      **What this costs:** only experiment 0.3.1, which times the JS round trip
      against the native observer. Claims 2 through 6 need none of it — they read
      the `[VMLife]` traces, which stay (DEBUG-gated on both platforms). To run
      0.3.1 later, re-add the method temporarily from this file's 0.1.4.

### 0.2 Test conditions — get these wrong and every number is a lie `[ ]`

- [ ] **0.2.1** **Do not attach the Xcode debugger.** A debugger changes
      backgrounding: it suspends differently and defers the OS reaping the app.
      Launch from the home screen, not from Xcode.
- [ ] **0.2.2** **Kill Metro after the bundle loads.** A live Metro connection
      keeps the JS thread busy and hides exactly the stall being measured. This
      is also the check that separates the native path from the bridge: with
      Metro gone, anything that still fires proves it was never using JS.
- [ ] **0.2.3** Run every experiment on a **real device as well as** a simulator
      or emulator. Three of the six claims are specifically about the two
      disagreeing.
- [ ] **0.2.4** Capture with
      `xcrun simctl spawn booted log stream --predicate 'eventMessage CONTAINS "[VMLife]"'`
      and `adb logcat -s RnVietmapTracking`. For a physical iPhone use
      `log stream --device`.

### 0.3 Claim 1 — the native observer beats the JS path `[ ]`

**Claimed:** `AppState` costs three hops where a native observer costs one, so
the native path reaches the SDK measurably sooner.

- [ ] **0.3.1** Log at three points on one background transition:
      `native-observer fired`, `js-appstate received` (via `markJsAppState`),
      `sdk.onAppBackground returned`.
- [ ] **0.3.2** Repeat 10 backgrounds; record the deltas.

**Confirms:** native fires first by a consistent, non-trivial margin.

**Refutes:** the delta is in the noise — a few ms. Then the three hops cost
nothing in practice, and 6.4/6.5 are justified only by claim 2, not by latency.
Say so in the plan rather than keeping a reason that measurement killed.

### 0.4 Claim 2 — the JS hop can be dropped entirely, not merely delayed `[ ]`

This is the claim that actually matters. Latency is an argument; a signal that
never arrives is a defect.

- [ ] **0.4.1** With tracking on and Metro killed, background the app and leave
      it for 30 s, 2 min and 10 min. Log whether `js-appstate` arrives at all,
      and how late.
- [ ] **0.4.2** Repeat under memory pressure (open several heavy apps) so iOS
      has reason to suspend the JS thread promptly.
- [ ] **0.4.3** Android — repeat with battery optimisation **on** for the app,
      which is the default for most users and the case most likely to cut JS
      short.

**Confirms:** `native-observer` appears with no matching `js-appstate`, or with
one arriving far too late to matter.

**Refutes:** `js-appstate` always arrives promptly, on both platforms, in every
condition. Then dropping the JS path is a simplification rather than a fix —
still worth doing for the one-hop directness, but the plan must stop implying
the JS route loses events.

### 0.5 Claim 3 — Android `LifecycleEventListener` reaches the SDK without JS `[ ]`

**Claimed:** `onHostPause` / `onHostResume` fire natively, so RN holds on Android
the guarantee Flutter holds only on iOS.

- [ ] **0.5.1** Log `onHostPause` / `onHostResume` with the shared clock and the
      sequence number, plus the `SDK.onAppBackground()` return.
- [ ] **0.5.2** Confirm with Metro killed — the point is that no JS is involved.
- [ ] **0.5.3** Check the Activity cases that are not a real background:
      screen rotation, a permission dialog, split screen. Each raises
      `onHostPause`, and telling the SDK it is backgrounded because the user
      turned the phone sideways would be a regression.

**Confirms:** both fire with Metro gone, and 0.5.3 shows no spurious pauses — or
shows them, and 6.5 gains a filter before it is written.

**Refutes:** `onHostPause` does not fire for a real background, or fires so often
it is useless. Then Android keeps the JS path and 6.2 is only dropped on iOS.

### 0.6 Claim 4 — a module created while backgrounded never learns the state `[ ]`

**Claimed:** without 6.6's seed, a module initialised while the app is already
in the background sits believing it is in the foreground until the next
transition.

- [ ] **0.6.1** Log the state read at module init —
      `ReactContext.getLifecycleState()` on Android,
      `UIApplication.shared.applicationState` on iOS — on every launch, before
      any seeding is implemented.
- [ ] **0.6.2** Force the case: on Android, a background restart of the process;
      on iOS, a background launch. Log whether any lifecycle callback arrives
      before the user next foregrounds the app.

**Confirms:** init logs `background` while no callback has fired. 6.6 is needed.

**Refutes:** the module is never created before the first foreground, so the
state at init is always `active`. Then 6.6 is dead code — drop it rather than
carry a guard against a case that cannot occur.

### 0.7 Claim 5 — the SDK does not drain its own queue on foreground `[ ]`

**Claimed:** 6.7's post-foreground manual sync is needed because pending data
survives the SDK's own foreground handling.

- [ ] **0.7.1** Build a backlog deliberately: airplane mode with tracking on
      until `getCachedLocationsCount()` is clearly non-zero.
- [ ] **0.7.2** Restore the network, foreground the app, and log
      `getCachedLocationsCount()` and `isNetworkConnected()` at foreground+0 ms,
      +500 ms, +1500 ms, +5 s and +15 s — **without** triggering a manual sync.
- [ ] **0.7.3** Note where Flutter's 1.5 s lands on that curve and whether it is
      the right moment or a number copied from a different SDK version.

**Confirms:** the count is still non-zero at +15 s. 6.7 earns its place, and the
curve says when to fire rather than inheriting 1.5 s untested.

**Refutes:** the SDK drains on its own within a few seconds. Then 6.7 is a
redundant second trigger and should go, as 6.8 already does.

### 0.8 Claim 6 — the `NWPathMonitor` stall is simulator-only `[ ]`

This is the claim behind skipping the watchdog, and the one where being wrong
costs the most: a real-device stall means uploads silently stop.

- [ ] **0.8.1** Log `isNetworkConnected()` beside the real reachability of the
      upload host every 30 s while tracking, on a real device, for a long
      session that crosses wifi/cellular handover, a tunnel or lift, and
      airplane-mode toggles.
- [ ] **0.8.2** Log every disagreement — SDK says offline while a request
      succeeds — with the pending count at that moment.

**Confirms:** no disagreement on a real device over a long session. Skipping 6.8
is safe.

**Refutes:** even one disagreement with a non-zero pending count. Then 6.8 is not
a simulator workaround and must be reinstated — and the finding belongs upstream
in the SDK, not worked around in every plugin.

### 0.9 While instrumented, settle finding 11 `[ ]`

`UPGRADE_PLAN.md` finding 11 still carries two unresolved readings of the empty
upload batch, and the same run can close it at no extra cost.

- [ ] **0.9.1** Call `startTracking` explicitly, with a `userId` set, and confirm
      `-> SDK setAllowMockLocation` appears in the trace.
- [ ] **0.9.2** On a simulator with `allowMockLocation: false`, log whether
      `onFakeGPSDetected` fires. If it does, the gate is live and
      `sourceInformation` is populated. If it does not while fixes still flow,
      `sourceInformation` is nil there and the gate was never the cause.
- [ ] **0.9.3** Write the answer into finding 11, replacing both hypotheses with
      the measured one.

### 0.10 Record the results `[ ]`

- [ ] **0.10.1** Put the measured numbers in a `## Step 0 results` section in
      this file — the deltas, the drop rate, the drain curve — not a verdict on
      its own. A later reader needs to see what was measured.
- [ ] **0.10.2** Amend or delete any of 6.4-6.8 the measurements refute, and say
      which experiment did it. A step removed by evidence is a good outcome, not
      a loss.

---

## Step 1 — Config layer `[x]`

**Do this first.** Distance-based tracking is unreachable from RN until it lands,
and steps 9 and 11 depend on the presets.

`index.tsx` currently forces both trigger values:

```ts
const intervalMs = config.intervalMs || 5000;
const distanceFilter = config.distanceFilter || 10;
```

The SDK picks its trigger mode from which of the two it receives — interval only,
distance only, both (timer wins, distance ignored), or neither (SDK defaults).
Sending both pins RN to the third case permanently.

- [x] **1.1** `src/types.ts` — `LocationTrackingConfig` reaches Flutter's 11 fields:
      `intervalMs?: number | null`, `distanceFilter?: number | null`,
      `accuracy?`, `backgroundMode?` (default **`true`**, not `false`),
      `notificationTitle?`, `notificationMessage?`, `userId?`, `vehicleId?`,
      `apiEndpoint?`, `allowMockLocation?` (done), `enableSpeedFallback?`
      (default `true`).
      Nullable `intervalMs` / `distanceFilter` is a **breaking change** for
      TypeScript callers — changelog it.
- [x] **1.2** `src/presets.ts` — port `TrackingPresets`: `navigation` (5 s),
      `fitness` (10 s), `general` (30 s), `batterySaver` (300 s), each with a
      `*Distance` variant at 25 / 50 / 70 / 120 m. Interval presets leave
      `distanceFilter` null and vice versa. Document the SDK floors: 5000 ms and
      25 m, clamped natively.
- [x] **1.3** `createSdkDefaultConfig()` — both trigger values null, so the SDK
      runs its own 10 s / 25 m cadence.
- [x] **1.4** `startTracking` spec gains `enableSpeedFallback?: boolean` and
      `enableSmartBattery?: boolean` (opt-in, default `false`).
      Stop hardcoding `setEnableSpeedFallback(true)` in the Swift bridge.
- [x] **1.5** `index.tsx` — pass the trigger values through untouched. Send the
      SDK's own sentinel for "not provided" rather than substituting a number;
      pick it to match what the native handlers already treat as absent.
- [x] **1.6** Android — mirror Flutter's three-way branch in `startTracking`,
      including the **distance-mode bootstrap**: start with a real interval and
      `distanceFilter = 0`, then switch to the real distance filter on the first
      fix via `safeUpdateTrackingConfig`. Starting straight at a distance filter
      keeps the first fix from arriving while the device is still, the Foreground
      Service misses its 5 s promotion window, and tracking never starts.
- [x] **1.7** iOS — pass `nil` for an absent trigger value;
      `startTracking(enhancedBackgroundMode:intervalMs:distanceFilter:)` already
      takes `NSNumber?` and reads nil as "use the SDK default".

**Verify:** a distance-only config produces fixes gated by movement and none while
stationary; an interval-only config produces fixes on the timer while stationary;
`sdkDefault` produces roughly one per 10 s.

### 1.8 — Every mode reaches the channel; the example starts on the defaults

Two separate rules, easy to conflate:

- **The channel exposes every mode.** Anything the SDK can be told, the bridge
  can say. No option is left unreachable because the example happens not to use
  it — that is how `authMode` and `allowMockLocation` went missing.
- **The example picks the defaults an integrator would want.** It is the
  reference for someone evaluating the SDK, so it should run correctly with
  nothing configured and read as a template to copy.

Defaults read from the shipped SDK, not from the Flutter wrappers:

| Option | SDK default | Flutter plugin | RN example |
|---|---|---|---|
| `authMode` | `.header` (`VietmapTrackingSDK.swift:614`) | `header` (iOS only) | `header` |
| `autoUpload` | `true` (`configure(...autoUpload:)`) | `true` | `true` |
| `intervalMs` | 10 000 ms | null -> SDK decides | null -> SDK decides |
| `distanceFilter` | 25 m | null -> SDK decides | null -> SDK decides |
| `accuracy` | `high` | null | `high` |
| `enableSpeedFallback` | `true` (iOS `:583`, Android ctor) | `true` | `true` |
| `fakeGPSPolicy` | `skip` (iOS `:887`) | `skip` | `skip` |
| interrupted notification | enabled (iOS `:919`) | `true` | `true` |
| `backgroundMode` | **`false`** (`TrackingConfig()`) | **`true`** | **`true`** |
| `allowMockLocation` | **`false`** (iOS `:508`, Android ctor) | **`true`** | **`true`** |
| cache limits | 5000 records on Android, 10 000 on iOS; 50 MB; batch 50 | — | leave unset |

- [x] **1.8** Apply the table above as the example's defaults.

**The last two rows disagree with the raw SDK default, deliberately.** Both
follow the *plugin* default that Flutter established rather than the SDK's own,
and both are what makes the example work out of the box:

- `allowMockLocation: true` — accept fake GPS. At the SDK's `false` the example
  drops every fix on a simulator or emulator and uploads empty batches, which is
  exactly the failure recorded in `UPGRADE_PLAN.md` finding 11. An integrator
  evaluating the SDK almost always starts on a simulator.
- `backgroundMode: true` — the demo is meant to exercise the real path.

Document both in the example, next to the values, so a reader copying the config
into production knows to flip `allowMockLocation` to `false` and pick a
`setFakeGPSPolicy`. Leave the cache limits unset so the example demonstrates the
SDK's own behaviour rather than overriding it.

---

## Step 2 — Call-site guards `[x]`

Pure TypeScript, no native work, and it removes a class of duplicate-start bugs.
`VietmapTrackingController.startTracking` runs five guards; `startLocationTracking`
runs one.

- [x] **2.1** `requireConfigured()` — throw `SDK_NOT_CONFIGURED` when `configure()`
      or `initializeTracking()` never ran. Track it in a module-level flag set by
      both.
- [x] **2.2** `startInFlight` re-entrancy guard — a second concurrent start
      resolves `false` instead of racing the first.
- [x] **2.3** Check `isTrackingActive()` **before** requesting permissions, so a
      redundant start cannot raise a permission dialog at the user.
- [x] **2.4** Validate `userId` non-empty, rejecting with `MISSING_USER_ID`. The
      SDK refuses to start without it and reports the reason only on the status
      listener, which is easy to miss.
- [x] **2.5** Decide the identity contract and write it down either way:
      Flutter puts `userId` / `vehicleId` in the `startTracking` payload and calls
      `setDriverId` / `setVehicleId` natively at that moment; RN makes the caller
      do it beforehand. Accepting the config fields (step 1.1) and pushing them
      natively matches Flutter and removes the example's separate Apply step.

---

## Step 3 — Finish the event surface `[x]`

| Event | iOS | Android |
|---|---|---|
| `onFakeGPSDetected` | done | **missing** — `addFakeGPSCallback` |
| `onTrackingInterrupted` | **missing** — `onTrackingInterrupted` closure | **missing** — `addTrackingInterruptedCallback` |
| `onLocationError` | emitted | **declared, never emitted** |
| `onRouteUpdate` | emitted | **declared, never emitted** |

A listener attached to either of the last two on Android never fires — silently.

- [x] **3.1** Android `onFakeGPSDetected` — `addFakeGPSCallback { lat, lng }`.
      Android supplies no `reason`; document the field as iOS-only rather than
      inventing one.
- [x] **3.2** `onTrackingInterrupted` on both →
      `{ reason, recovered, isInBackground, secondsSinceLastFix }`
- [x] **3.3** Export the 8 reason constants: `locationUnavailable`,
      `providerDisabled`, `paused`, `authDowngraded`, `authDenied`,
      `locationServicesOff`, `permissionRevoked`, `staleNoUpdates`
- [x] **3.4** `addTrackingInterruptedListener` / `addFakeGPSDetectedListener`
      (the second already exists) in `index.tsx`
- [x] **3.5** Resolve `onLocationError` and `onRouteUpdate`: wire Android's
      emitters, or drop both from `supportedEvents()`. `onRouteUpdate` is
      alert-engine surface, so hiding it under `[ALERT-HIDDEN]` fits the standing
      decision; `onLocationError` is worth keeping and wiring.
- [x] **3.6** Document that apps must **not** auto stop-then-start on
      `onTrackingInterrupted`. 1.5.3 raises it from GPS silence, so a restart only
      costs a fresh first fix.

---

## Step 4 — Offline cache and upload `[x]` (6 methods)

Self-contained, native on both platforms, and the natural first batch of real
methods: nothing else depends on it and it is easy to verify by pulling the plug
on the network.

| TS spec | iOS 1.5.2 | Android 1.5.3 |
|---|---|---|
| `isNetworkConnected(): Promise<boolean>` | `isNetworkConnected() -> Bool` | `isNetworkAvailable(): boolean` |
| `getCachedLocationsCount(): Promise<number>` | `getCachedLocationsCount() -> Int` | `getCachedLocationsCount(): int` |
| `uploadCachedLocationsManually(): Promise<boolean>` | `uploadCachedLocationsManually(completion: (Bool, String?) -> Void)` | `uploadCachedLocationsManually(): void` |
| `clearCachedLocations(): Promise<boolean>` | `clearCachedLocations()` | `clearCachedLocations(): void` |
| `configureCacheLimits(maxRecords, maxDbSizeBytes, batchSize): Promise<boolean>` | `configureCacheLimits(maxRecords: Int, maxDbSizeBytes: Int64, batchSize: Int)` | `configureCacheLimits(int, long, int)` |
| `getDatabaseSizeBytes(): Promise<number>` | `getDatabaseSizeBytes() -> Int64` | `getDatabaseSizeBytes(): long` |

- [x] **4.1** `isNetworkConnected` — note the platform naming difference
- [x] **4.2** `getCachedLocationsCount`
- [x] **4.3** `uploadCachedLocationsManually` — iOS resolves the completion's
      `Bool`; Android returns void, so resolve `true` once it returns and say so
      in a comment
- [x] **4.4** `clearCachedLocations` — replaces the existing stub
- [x] **4.5** `configureCacheLimits` — a value of 0 means "keep the SDK's own".
      Those defaults are **not identical across platforms**: `maxRecords` is
      5000 on Android and 10 000 on iOS (`LocationDatabaseManager.swift:12`),
      while `maxDbSizeBytes` (50 MB) and `batchSize` (50) match. Do not document
      a single number for `maxRecords`; the earlier plan said a flat 5000 and
      that is wrong for iOS.
      `maxDbSizeBytes` exceeds 2^31: take it as `double` through the bridge and
      convert, never as `int`.
- [x] **4.6** `getDatabaseSizeBytes` — same `Int64` caution

Do **not** copy the Flutter reflection hack here (finding 1); these are public
SDK methods on both platforms.

**Verify:** airplane mode -> `getCachedLocationsCount` climbs, `getDatabaseSizeBytes`
grows; network back -> `uploadCachedLocationsManually` drains it to 0.

---

## Step 5 — Identity and payload `[x]` (4 methods)

| TS spec | iOS | Android |
|---|---|---|
| `setMetadata(metadata: Object): Promise<void>` | `setMetadata(_ metadata: NSDictionary?)` | `setMetadata(Map<String, Object>)` |
| `setPackages(packages: string[]): Promise<void>` | `setPackages(_ packages: [String]?)` | `setPackages(List<String>)` |
| `setAppSignature(signature: string): Promise<void>` | `setAppSignature(_ signature: String)` | `setAppSignature(String)` |
| `configureVehicle(vehicleId, vehicleType, seats, weight, maxProvision?): Promise<boolean>` | `configureVehicle(vehicleId:vehicleType:seats:weight:maxProvision:)` | `configureVehicle(String, int, int, double, int)` |

- [x] **5.1** `setMetadata` — `ReadableMap` -> `Map<String, Object>` on Android,
      `NSDictionary` on iOS
- [x] **5.2** `setPackages` — `ReadableArray` -> `List<String>`; reject non-string
      entries rather than coercing
- [x] **5.3** `setAppSignature`
- [x] **5.4** `configureVehicle` — Android's `maxProvision` overload takes an
      `int`; pick an explicit default and document it

---

## Step 6 — Lifecycle and upload policy `[x]` (3 methods)

| TS spec | iOS | Android |
|---|---|---|
| `onAppBackground(): Promise<void>` | `onAppBackground()` | `onAppBackground()` |
| `onAppForeground(): Promise<void>` | `onAppForeground()` | `onAppForeground()` |
| `setAutoUpload(enabled: boolean): Promise<boolean>` | `setAutoUpload(enabled:)` | none — resolve `true` |

- [x] **6.1** `onAppBackground` / `onAppForeground`
- [x] **6.2** ~~Wire `AppState` in `index.tsx`~~ — **dropped, superseded by 6.4
      and 6.5.** Reasoning below; the capability is not lost, it moves native.

### 6.4-6.6 — Lifecycle, done the React Native way

Flutter's iOS plugin registers `UIApplication` observers at plugin registration
(`VietmapTrackingPlugin.swift:88`), before Dart runs, and its own comment calls
the MethodChannel path "double safety". RN has nothing equivalent on either
platform: `NotificationCenter`, `didEnterBackgroundNotification` and
`onAppBackground` all return zero matches in both native modules.

**Why not simply port Flutter's design.** RN's `AppState` is not a JS-side
mechanism — `RCTAppState.mm:83-97` is itself an `NSNotificationCenter` observer
on the same five `UIApplication` notifications, which then calls
`sendEventWithName:@"appStateDidChange"`. Routing through it means:

```
UIApplication notification -> RCTAppState (native) -> bridge -> JS handler
  -> bridge -> our module (native) -> SDK.onAppBackground()
```

Three hops, the first of which already had the answer. The JS thread is exactly
what stops being dependable as the app backgrounds, so this puts the least
reliable link in the middle of the most time-sensitive signal. Registering in
the module directly is one hop and no JS:

```
UIApplication notification -> our module (native) -> SDK.onAppBackground()
```

**Where RN improves on Flutter.** Flutter's Android side has no native observer
at all — `VietmapTrackingPlugin.kt` implements `ActivityAware` but leaves
`handleOnAppBackground` to be called from Dart. RN has a first-class native API
Flutter's Android plugin does not use, verified present in the 0.79.6 artifact:

```
com.facebook.react.bridge.LifecycleEventListener
  void onHostResume() / onHostPause() / onHostDestroy()
ReactContext.addLifecycleEventListener / removeLifecycleEventListener
ReactContext.getLifecycleState()
```

So RN can hold the guarantee on **both** platforms where Flutter holds it on one.

**Nothing is lost by dropping the JS path.** `AppState` and the native observers
read the same two `UIApplication` notifications on iOS, and the same host
Activity transitions on Android. Keeping both would only risk double-firing.
Flutter runs both because its Android half has no native path to rely on; RN
does, so the redundancy buys nothing.

**Do not start 6.4-6.8 before Step 0 has run.** Every one of them rests on a
claim Step 0 tests, and two of them (6.6, 6.7) should be deleted rather than
built if the measurement goes the other way.

- [x] **6.4** iOS — observe `UIApplication.didEnterBackgroundNotification` and
      `willEnterForegroundNotification` in `init()`, forwarding to
      `trackingManager.onAppBackground()` / `onAppForeground()`.
      `requiresMainQueueSetup` is already `true`, so `init()` runs on the main
      queue and touching `UIApplication` there is safe. Remove the observers in
      the existing `deinit`.
- [x] **6.5** Android — implement `LifecycleEventListener` on the module and
      register it in `init`. `onHostPause` -> `onAppBackground()`,
      `onHostResume` -> `onAppForeground()`. `onHostDestroy` needs no SDK call;
      the existing `invalidate()` at line 1005 already tears down and is where
      `removeLifecycleEventListener` goes.
- [x] **6.6** Seed the state at registration, which Flutter does not do. A module
      created while the app is already backgrounded — a background restart, a
      headless task — would otherwise never fire until the next transition and
      leave the SDK believing it is in the foreground. Read the current state
      once at registration and push it: `ReactContext.getLifecycleState()` on
      Android, `UIApplication.shared.applicationState` on iOS (main-queue only,
      which 6.4 already guarantees).
- [x] **6.7** iOS — post-foreground sync, kept from Flutter because it earns its
      place. Flutter waits 1.5 s after foreground (the SDK restarts its network
      monitor internally first), then checks `getCachedLocationsCount()` and
      `isNetworkConnected()` and calls `uploadCachedLocationsManually()` when
      there is pending data on a live network. Depends on step 4.
      Worth mirroring on Android in `onHostResume`, which Flutter does not do.
- [x] **6.8** Sync watchdog — **skip for 0.2.0.** Flutter runs a 5 s timer plus a
      `URLSession` probe to catch the SDK reporting itself offline while a
      connection exists; its own comment pins this on the iOS Simulator, where
      `NWPathMonitor` can report `.satisfied` permanently or go stale. It costs a
      permanent 5 s timer in every host app, and 6.7 already drains the queue on
      the path that matters. Revisit only if the stall shows on a real device.

**Verify:** background the app with tracking on and confirm `onAppBackground`
reaches the SDK with no JS involved — kill the Metro connection first, so a
result that still works proves the native path rather than the bridge.

---

## Step 7 — Notification configuration `[x]` (3 methods)

| TS spec | iOS | Android |
|---|---|---|
| `setFakeGpsNotificationConfig(title, message): Promise<void>` | `setFakeGPSNotificationConfig(title:body:)` | `setFakeGPSNotificationConfig(String, String)` |
| `setTrackingInterruptedNotificationEnabled(enabled): Promise<void>` | `setTrackingInterruptedNotificationEnabled(_:)` | `setTrackingInterruptedNotificationEnabled(boolean)` |
| `setTrackingInterruptedNotificationConfig(title, message): Promise<void>` | `setTrackingInterruptedNotificationConfig(title:body:)` | `setTrackingInterruptedNotificationConfig(String, String)` |

The native parameter is `body`; the JS name stays `message` to match the rest of
the RN surface. Keep the mapping in one place so it cannot drift.

- [x] **7.1** `setFakeGpsNotificationConfig` — completes step 2D of the old plan
- [x] **7.2** `setTrackingInterruptedNotificationEnabled`
- [x] **7.3** `setTrackingInterruptedNotificationConfig`
- [x] **7.4** Note in the README that disabling the interrupted notification does
      **not** silence the `onTrackingInterrupted` event — the callback channel
      fires either way.

---

## Step 8 — History and health `[x]` (2 methods)

- [x] **8.1** `getTrackingHistory(userId, fromTimestamp?, toTimestamp?, pageNumber?, pageSize?, sortBy?, sortDescending?): Promise<string>`
      - iOS `getHistory(userId:fromTime:toTime:pageNumber:pageSize:sortBy:sortDescending:completion:)`,
        completion `(String?, String?, String?)` = (json, errorCode, message)
      - Android `getHistory(String, long, long, int, int, String, boolean, HistoryCallback)`
        with `onHistorySuccess(String)` / `onHistoryError(String, String)`
      - Both resolve the raw JSON string; parse in TS into `GpsLocation[]`
      - Defaults: `pageNumber` 1, `pageSize` 100, `sortDescending` false
      - Timestamps are milliseconds. The Android SDK converts a value under
        10 billion as if it were seconds, so send milliseconds explicitly.
- [x] **8.2** `getTrackingHealthStatus(): Promise<TrackingHealthStatus>`
      - iOS returns an `NSDictionary` directly
      - Android has no such method: assemble it from `isTracking()`,
        `hasLocationPermission()`, `hasBackgroundLocationPermission()`,
        `trackingStartTime` and `lastLocationTimestamp` — all already tracked in
        the module. Use `-1` for "no location yet", matching Flutter.
      - Shape: `{ isTracking, hasLocationPermission, hasBackgroundPermission,
        trackingDuration, timeSinceLastUpdate, isInitialized, lastLocationUpdate?, timestamp }`
      - Also add it to the TS spec, where it is currently missing entirely.

---

## Step 9 — Smart battery `[x]` (9.3 pending by decision)

Neither SDK exposes `setSmartBatteryConfig` — it is plugin-side on both.

- [x] **9.1** `setSmartBatteryConfig(enabled: boolean, preset: string): Promise<boolean>`
      - preset -> interval: `navigation` 5 s, `general` 30 s, `batterySaver` 300 s.
        Keep these in step by step 1.2's presets; two sources of truth will drift.
      - Android: `safeUpdateTrackingConfig(intervalMs, 0.0)` — interval-only, so
        no displacement filter. Reflection is required here (finding 2): the SDK's
        own setter restarts the Foreground Service and crashes with
        `ForegroundServiceDidNotStartInTimeException`.
      - iOS: `CLLocationManager.activityType = .automotiveNavigation` with
        `pausesLocationUpdatesAutomatically = true` when enabled, `.other` and
        `false` when not.
- [x] **9.2** `enableSmartBattery?: boolean` on `startTracking`, default `false`.
      Opt-in matters: left on it would immediately push its own preset over the
      cadence tracking just started with.
- [~] **9.3** `SmartBatteryManager` (387 lines) — **pending, deferred past 0.2.0.**

      Checked before deferring: the SDK's `DeviceInfoCollector` already collects
      and ships the device picture itself, on **both** platforms
      (`ios/VietmapTrackingSDK/DeviceInfoCollector.swift`,
      `android/.../DeviceInfoCollector.java`). Every upload already carries
      `battery`, `low_power_mode`, `background_refresh`,
      `location_services_enabled`, `location_auth`, `accuracy_authorization`,
      `mock_capable`, `network`, `model`, `manufacturer`, `os_version`,
      `sdk_version`, `platform`. So there is nothing to add on the reporting
      side, and a plugin-side battery reader would only duplicate what the
      payload already says.

      What the deferral does give up, stated so the decision stays informed:
      `SmartBatteryManager` does not report — it **reacts**, switching the
      tracking cadence from a motion state machine (stationary / moving /
      cornering) and from battery level. That adaptive behaviour is not covered
      by the collector and stays unavailable until it is ported. Porting it also
      costs a new runtime dependency (`expo-battery` or
      `react-native-device-info`) that 0.2.0 otherwise does not need.

      9.1 and 9.2 still ship, so an app can pick a battery preset by hand.

---

## Step 10 — Remaining methods `[x]` (3)

- [x] **10.1** `processExternalLocation(lat, lng, speed, heading): Promise<boolean>`
      - iOS `processExternalLocation(lat:lng:speed:heading:)`
      - Android has no such method: use
        `processLocationWithVehicleParams(lat, lng, speed, heading)`, as Flutter does
      - Speed: values at or below 30 are taken as m/s and converted once; above
        that, as km/h. Document it — it is easy to double-convert.
- [x] **10.2** `getPlatformVersion(): Promise<string>` — `"iOS <version>"` /
      `"Android <release>"`. Trivial, and it makes a bridge smoke test possible.
- [x] **10.3** `authMode` — **keep. The earlier recommendation to skip
      `configureTracking` was wrong**; tracing it found a real gap rather than an
      alias.

      Diffed against Flutter's `configure`, `configureTracking` differs in only
      three ways: it reads `baseUrl` instead of `baseURL`, it lets the caller set
      `autoUpload` instead of hardcoding `true`, and — the one that matters — it
      calls `trackingManager.configure(authMode:)`.

      `VMAuthMode` decides whether the API key travels as the `X-API-Key` header
      or as a `?apiKey=` query parameter. It is read at **8 call sites** in the
      iOS SDK, including every upload path (`uploadLocationsBatchFromDB`,
      `uploadSingleFromDB`, the direct send path and the fake-GPS report). Get it
      wrong against a gateway that wants query-param auth and **every upload
      returns 401** while tracking otherwise looks healthy — the same class of
      silent failure as the empty batch in `UPGRADE_PLAN.md` finding 11.

      RN has no way to reach it today: `configure` hardcodes
      `configure(apiKey:baseURL:autoUpload: true)` and never touches auth mode.

      Both platforms support it, despite Flutter wiring only one:

      - iOS — `configure(authMode: VMAuthMode)`, `.header` = 0, `.queryParam` = 1
      - Android — `VietmapTrackingSDK.setAuthMode(boolean isHeader)`, line 1202,
        forwarding to `VietmapTrackingManager.setAuthMode` → `LocationCacheManager`

      **Do not port `configureTracking` as its own method.** It is an iOS-only
      Flutter alias for a method RN already has. Instead add two optional
      parameters to `initializeTracking`, which already covers both platforms:

      ```ts
      initializeTracking(
        apiKey: string,
        baseURL?: string,
        authMode?: 'header' | 'queryParam',   // default 'header'
        autoUpload?: boolean,                 // default true
      ): Promise<void>
      ```

      iOS maps the string to `VMAuthMode` and calls `configure(authMode:)`;
      Android calls `setAuthMode(authMode !== 'queryParam')`. This closes the gap
      on **both** platforms, where Flutter closed it on one.

`isSpeedAlertActive` stays hidden under `[ALERT-HIDDEN]` with the rest of the
alert surface, per the standing decision.

---

## Step 11 — Example app `[~]`

Flutter's example is 3280 lines across 14 cards; RN's is 1079 in one 692-line
file exercising 13 APIs. Split it to mirror
`vietmap_flutter_tracking_plugin/example/lib/widgets/`, keeping zustand and the
existing store.

```
example/src/
├── App.tsx
├── store/trackingStore.ts        extend, do not replace
└── components/
    ├── HeaderCard.tsx              SDK status, platform version
    ├── PermissionCard.tsx
    ├── IdentityCard.tsx            exists as the Session Identity section
    ├── ConfigCard.tsx              interval / distance / accuracy / background / sdkDefault / presets
    ├── ControlsCard.tsx
    ├── LocationCard.tsx
    ├── LocationHistoryCard.tsx
    ├── TrackingStatusCard.tsx      getTrackingStatus + getTrackingHealthStatus
    ├── SessionStatsCard.tsx
    ├── CacheCard.tsx               step 4
    ├── PackagesCard.tsx            step 5
    ├── FakeGpsCard.tsx             step 3 + policy picker
    ├── TrackingInterruptedCard.tsx step 3
    ├── SmartBatteryCard.tsx        step 9
    └── HistoryCard.tsx             step 8, paginated
```

- [x] **11.1** Split the screen into cards; one zustand slice per card, per-field
      selectors only — an object selector returns a new reference each render and
      loops forever
- [x] **11.2** `CacheCard` — count, DB size, manual upload, clear, limits
- [x] **11.3** `PackagesCard` — add/remove, apply, dirty marker
- [x] **11.4** `FakeGpsCard` — policy picker, `allowMockLocation` toggle,
      detection log
- [x] **11.5** `TrackingInterruptedCard` — event log, reason, recovered marker
- [x] **11.6** `SmartBatteryCard` — enable toggle, preset picker
- [x] **11.7** `HistoryCard` — server history with pagination, mirroring
      `fetchServerHistory` / `fetchMoreServerHistory`
- [x] **11.8** `ConfigCard` — preset picker plus the three trigger modes, so
      step 1 is exercised by hand
- [x] **11.9** Show the current lifecycle state. The plugin handles app state
      natively now (6.4-6.6), so the example only displays it — it must not wire
      `AppState` to `onAppBackground`, which would double-fire.
- [x] **11.10** Persist userId, vehicleId and the applied package list across
      launches, via `@react-native-async-storage/async-storage`.

      **Pinned to `^2.1.2`, not 3.x.** AsyncStorage 3 requires Kotlin >= 2.1.0
      and this example is on 2.0.21; its version table has no entry for 2.0.x,
      so it falls back to a KSP built against Kotlin 2.1 APIs and
      `kspDebugKotlin` dies with `NoSuchMethodError: getChangedFiles$default`.
      Version 2 uses no KSP and builds clean. Revisit only alongside a Kotlin
      bump for the whole example.

      Credentials, policy and config are deliberately **not** persisted: they
      belong in source where they are reviewable, and a stale saved policy
      silently overriding the code is the kind of surprise this example exists
      to expose. Every read falls back to the in-memory default and every write
      is best effort, so a storage failure costs the convenience, not the run.
- [x] **11.11** GPX replay — `src/gpxReplay.ts` plus a card.

      **Not a port of `gpx_simulator.dart`.** That file is dead code in the
      Flutter example: nothing imports it, and it never calls the plugin — it
      fires a UI callback with a hardcoded speed of 2.78 m/s and heading 0, so
      it exercises nothing.

      This feeds `processExternalLocation`, which the SDK routes into the real
      tracking pipeline with `isExternalSource: true`, so replayed points are
      recorded and uploaded exactly like device fixes. That makes it useful on a
      physical device, where `simctl location` and `adb emu geo fix` do not
      exist.

      Speed and heading are derived from consecutive points, and speed is capped
      at 30 m/s: above that the SDK reads the value as km/h instead, and a
      motorway track would land about 3.6x too slow.
- [x] **11.12** Confirm no real API key is committed. The Flutter example shipped
      one by accident in 1.1.3; the RN example takes the key as a parameter, so
      keep it that way.

Alert UI stays out.

---

## Step 12 — Tests, validation and docs `[~]`

- [x] **12.1** iOS parity check in `npm run validate` — diff `RCT_EXTERN_METHOD`
      names in the `.m` against the `@objc` implementations in the `.swift`.
      A declaration with no implementation compiles and crashes at call time;
      this is how 14 methods stayed broken. The matcher must handle both
      `@objc(selector:)` and a bare `@objc` on the line above `func`.
- [x] **12.2** Jest coverage for the new methods — mock the TurboModule, assert
      method names and argument shapes, in the style of Flutter's
      `Method Name Verification`
- [x] **12.3** Argument-shape tests for the three-way trigger mode from step 1:
      interval-only, distance-only, neither
- [x] **12.4** `npm run validate` green — typecheck, lint, jest
- [ ] **12.5** Run the example on a physical device. **Not done — needs
      hardware.** Both platforms build clean (iOS `BUILD SUCCEEDED`, Android
      `BUILD SUCCESSFUL`) and `npm run validate` passes, but a build is not a
      run. This is the same gate as step 0.2.3.
- [x] **12.6** README — full API table, plus sections for Fake GPS, Tracking
      Interrupted, Cache, Smart Battery, History, and a native version table
- [x] **12.7** CHANGELOG 0.2.0 — lead with the `LocationTrackingConfig` breaking
      change (nullable trigger values, `backgroundMode` now defaulting to `true`),
      then the 23 new methods, the two new events, and the hidden alert surface

---

## Order and dependencies

```
0 Instrument ─── 6 Lifecycle          (0 decides what 6 contains)
0 Instrument ─── finding 11 closed

1 Config ──┬── 9 Smart battery ── 11 Example
           └── 11 Example
2 Guards ───── 11 Example
3 Events ───── 11 Example
4 Cache ──┬─── 11 Example
          └─── 6.7 post-foreground sync
5 Identity ─── 11 Example
6 Lifecycle ── 11 Example
7 Notifications
8 History ──── 11 Example
10 Remaining
                11 Example ── 12 Tests and docs
```

**Step 0 comes first**, and its long-running experiments (0.4, 0.8) can keep
collecting while steps 1-5 are written — they need a device left running, not
attention. Only step 6 waits on their answers.

Steps 4 through 8 and 10 are independent of each other and can land in any order,
or in parallel, except that 6.7 needs step 4's `getCachedLocationsCount`. Steps 1
and 2 come next because step 1 unblocks distance mode and both shape the surface
everything else is written against. Step 12 is last because 12.1 must pass over
the finished iOS surface.

| Step | Work | Estimate |
|---|---|---|
| 0 | Instrument + measure the lifecycle claims | 1.0 d |
| 1 | Config layer + presets | 1.0 d |
| 2 | Call-site guards | 0.5 d |
| 3 | Events | 0.5 d |
| 4 | Cache (6) | 1.0 d |
| 5 | Identity (4) | 0.5 d |
| 6 | Lifecycle (3) + native observers both platforms | 1.0 d |
| 7 | Notification config (3) | 0.5 d |
| 8 | History + health (2) | 1.0 d |
| 9 | Smart battery (9.1, 9.2) | 0.5 d |
| 10 | Remaining (2) + authMode on both platforms | 1.0 d |
| 11 | Example app | 2.5 d |
| 12 | Tests + docs | 1.5 d |
| | **Total** | **~12.5 d** |

Step 0's day is mostly waiting on devices, and it can pay for itself twice over:
it settles finding 11, and it may delete 6.6, 6.7 or both.

## Deliberately out of 0.2.0

Each was traced before being set aside, not skipped for convenience:

- **`SmartBatteryManager` (9.3)** — pending. The SDK's `DeviceInfoCollector`
  already ships battery and low-power state in every payload on both platforms,
  so nothing is lost on the reporting side. What stays unavailable is the
  adaptive cadence, and porting it would add a runtime dependency.
- **The sync watchdog (6.8)** — a workaround for an iOS Simulator
  `NWPathMonitor` defect, at the cost of a permanent 5 s timer in every host app.
  6.7 covers the case that matters on a real device.
- **The JS `AppState` path (6.2)** — replaced, not dropped: app state is handled
  natively on both platforms, one hop instead of three, with nothing lost.
- **`configureTracking` as its own method (10.3)** — the method is an iOS-only
  Flutter alias, but the `authMode` it carries is a real gap and **is** in scope,
  added to `initializeTracking` on both platforms instead.
- **`isSpeedAlertActive`** — alert engine, hidden by design.

On completion RN reaches 41 of the 42 methods on Flutter's method channel, and
goes past it in two places: `authMode` works on both platforms where Flutter
wired only iOS, and `getTrackingHealthStatus` gets an Android implementation the
Android SDK does not provide.
