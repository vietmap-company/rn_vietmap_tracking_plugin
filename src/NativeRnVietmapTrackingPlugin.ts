import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';
import type { PermissionResult } from './types';

export interface Spec extends TurboModule {
  getPlatformVersion(): Promise<string>;

  // ── Configuration ─────────────────────────────────────────────────
  configure(apiKey: string, baseURL?: string): Promise<boolean>;

  /**
   * Validate the API key against the server, then configure the SDK.
   *
   * This is what the Flutter plugin uses, and the entry point to prefer:
   * configure() sets credentials blind, while this one hits
   * GET {baseURL}/gps-tracking/users with an X-API-Key header first and
   * rejects with INVALID_API_KEY when the key or host is wrong, instead of
   * failing silently later at upload time.
   *
   * authMode picks how the key travels: 'header' sends X-API-Key, 'queryParam'
   * appends ?apiKey=. The SDK reads it on every upload path, so a mismatch with
   * the gateway turns every upload into a 401 while tracking still looks
   * healthy. Defaults to 'header', the SDK's own default.
   *
   * autoUpload defaults to true. Set it false to hold locations in the cache
   * and drive uploads with uploadCachedLocationsManually().
   */
  initializeTracking(
    apiKey: string,
    baseURL?: string,
    authMode?: string,
    autoUpload?: boolean
  ): Promise<void>;

  configureAlertAPI(apiKey: string, apiID: string): Promise<boolean>;

  // ── Identity written into the GPS upload payload ──────────────────
  // setDriverId maps to the payload's userId and is REQUIRED: the native SDK
  // refuses to start tracking without it, reporting
  // "userId is required before starting tracking" through the status callback.
  setDriverId(driverId: string): Promise<boolean>;
  getDriverId(): Promise<string>;
  setVehicleId(vehicleId: string): Promise<boolean>;
  getVehicleId(): Promise<string>;
  setMetadata(metadata: Object): Promise<boolean>;
  setPackages(packages: Array<string>): Promise<boolean>;
  setAppSignature(signature: string): Promise<boolean>;
  configureVehicle(
    vehicleId: string,
    vehicleType: number,
    seats: number,
    weight: number,
    maxProvision?: number
  ): Promise<boolean>;

  // ── Tracking ──────────────────────────────────────────────────────
  /**
   * Start tracking.
   *
   * Takes a config object rather than positional arguments: the SDK reads nine
   * separate settings here, and a positional selector that long is how an
   * RCT_EXTERN_METHOD declaration drifts out of step with its Swift
   * implementation — which compiles cleanly and crashes at call time.
   *
   * Recognised keys, all optional except where noted:
   *   backgroundMode       boolean, default true
   *   intervalMs           number | absent -> timer mode when present
   *   distanceFilter       number | absent -> displacement mode when present
   *   accuracy             'high' | 'medium' | 'low'
   *   notificationTitle    string
   *   notificationMessage  string
   *   userId               string, REQUIRED by the SDK
   *   vehicleId            string
   *   allowMockLocation    boolean, default true
   *   enableSpeedFallback  boolean, default true
   *   enableSmartBattery   boolean, default false
   *   smartBatteryPreset   'navigation' | 'general' | 'batterySaver'
   *
   * intervalMs and distanceFilter pick the SDK's trigger mode between them:
   * interval only is a timer, distance only is displacement, both gives the
   * timer priority and ignores the distance gate, and neither leaves the SDK on
   * its own 10s / 25m defaults. Omit the one you do not want rather than
   * passing a zero.
   */
  startTracking(config: Object): Promise<boolean>;
  stopTracking(): Promise<boolean>;
  updateTrackingConfig(config: Object): Promise<boolean>;

  getCurrentLocation(): Promise<Object>;
  isTrackingActive(): Promise<boolean>;
  getTrackingStatus(): Promise<Object>;
  getTrackingHealthStatus(): Promise<Object>;

  /**
   * Server-side history for a user. Resolves the SDK's raw JSON response; the
   * wrapper in index.tsx parses it. Timestamps are milliseconds — the Android
   * SDK treats a value under 10 billion as seconds and converts it.
   */
  getTrackingHistory(
    userId: string,
    fromTimestamp?: number,
    toTimestamp?: number,
    pageNumber?: number,
    pageSize?: number,
    sortBy?: string,
    sortDescending?: boolean
  ): Promise<string>;

  // ── Permissions ───────────────────────────────────────────────────
  requestLocationPermissions(): Promise<PermissionResult>;
  hasLocationPermissions(): Promise<PermissionResult>;
  requestAlwaysLocationPermissions(): Promise<string>;

  // ── Offline cache and upload ──────────────────────────────────────
  isNetworkConnected(): Promise<boolean>;
  getCachedLocationsCount(): Promise<number>;
  uploadCachedLocationsManually(): Promise<boolean>;
  clearCachedLocations(): Promise<boolean>;
  /**
   * A zero keeps the SDK's own limit for that field. Those differ per platform:
   * maxRecords is 5000 on Android and 10000 on iOS, while maxDbSizeBytes (50MB)
   * and batchSize (50) match. maxDbSizeBytes exceeds 2^31, so it crosses the
   * bridge as a double.
   */
  configureCacheLimits(
    maxRecords: number,
    maxDbSizeBytes: number,
    batchSize: number
  ): Promise<boolean>;
  getDatabaseSizeBytes(): Promise<number>;

  // ── Lifecycle ─────────────────────────────────────────────────────
  // The module drives these natively from UIApplication notifications (iOS) and
  // LifecycleEventListener (Android). They stay exposed so a host app with its
  // own lifecycle handling can drive them, but wiring AppState to them from JS
  // would double-fire.
  onAppBackground(): Promise<boolean>;
  onAppForeground(): Promise<boolean>;
  setAutoUpload(enabled: boolean): Promise<boolean>;

  // ── Notification permission ───────────────────────────────────────
  // The SDK posts the fake-GPS and tracking-interrupted notifications itself,
  // and documents that the host app must already hold authorization. Neither
  // platform grants it implicitly, and iOS never prompts on post — so without
  // one of these the notification is dropped in silence.
  requestNotificationPermission(): Promise<boolean>;
  hasNotificationPermission(): Promise<boolean>;

  // ── Fake GPS ──────────────────────────────────────────────────────
  // What the SDK does once it detects a fake fix. Only consulted while
  // allowMockLocation is false.
  setFakeGPSPolicy(policy: string): Promise<boolean>;
  setFakeGpsNotificationConfig(title: string, message: string): Promise<boolean>;

  // ── Tracking interrupted ──────────────────────────────────────────
  // Disabling the notification does NOT silence onTrackingInterrupted; the
  // callback channel fires either way.
  setTrackingInterruptedNotificationEnabled(enabled: boolean): Promise<boolean>;
  setTrackingInterruptedNotificationConfig(
    title: string,
    message: string
  ): Promise<boolean>;

  // ── Smart battery ─────────────────────────────────────────────────
  // Neither SDK exposes this; it is assembled in the module on both platforms.
  setSmartBatteryConfig(enabled: boolean, preset: string): Promise<boolean>;

  // ── External GPS injection ────────────────────────────────────────
  // speed at or below 30 is read as m/s and converted once; above that, km/h.
  processExternalLocation(
    lat: number,
    lng: number,
    speed: number,
    heading: number
  ): Promise<boolean>;

  // ── Speed alert ───────────────────────────────────────────────────
  turnOnAlert(): Promise<boolean>;
  turnOffAlert(): Promise<boolean>;

  // ── NativeEventEmitter conformance ────────────────────────────────
  //
  // NativeEventEmitter requires these on any module it wraps, and warns at
  // construction when they are absent:
  //
  //   `new NativeEventEmitter()` was called with a non-null argument without
  //   the required `addListener` method.
  //
  // On iOS RCTEventEmitter supplies them, but the TurboModule spec is what the
  // JS side checks, so they have to be declared here too. On Android with the
  // new architecture they must exist on the module or the emitter has nothing
  // to call — which is why this warned on every launch there.
  //
  // They carry no logic of their own: the native side tracks listener counts in
  // startObserving/stopObserving.
  addListener(eventName: string): void;
  removeListeners(count: number): void;

}

export default TurboModuleRegistry.getEnforcing<Spec>('RnVietmapTrackingPlugin');
