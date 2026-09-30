import { NativeEventEmitter, NativeModules } from 'react-native';
import RnVietmapTrackingPlugin from './NativeRnVietmapTrackingPlugin';
import type {
  LocationTrackingConfig,
  LocationData,
  TrackingStatus,
  TrackingHealthStatus,
  LocationUpdateCallback,
  TrackingStatusCallback,
  PermissionResult,
  FakeGpsEvent,
  TrackingInterruptedEvent,
  FakeGpsPolicy,
  SmartBatteryPreset,
  AuthMode,
  GpsLocation,
} from './types';

const eventEmitter = new NativeEventEmitter(
  NativeModules.RnVietmapTrackingPlugin
);

// ── Module state backing the call-site guards ──────────────────────────
//
// The Flutter controller runs five guards before it touches the SDK and this
// layer ran one. The missing four each cover a failure that is silent from JS:
// an unconfigured SDK rejects deep in native code, a duplicate start races the
// first, a redundant start raises a permission dialog the user did not ask for,
// and a missing userId is refused by the SDK on the status listener where it is
// easy to miss.

let isConfigured = false;
let startInFlight = false;

/** Throw early rather than letting the SDK reject from deep in native code. */
function requireConfigured(): void {
  if (!isConfigured) {
    const error = new Error(
      'VietmapTrackingSDK is not configured. Call initializeTracking() or configure() first.'
    );
    error.name = 'SDK_NOT_CONFIGURED';
    throw error;
  }
}

// ── Configuration ──────────────────────────────────────────────────────

/**
 * Configure the SDK without validating the key.
 *
 * Prefer {@link initializeTracking}, which checks the key against the server
 * first. This one accepts whatever it is given and the mistake surfaces later,
 * at upload time.
 */
export async function configure(
  apiKey: string,
  baseURL?: string
): Promise<boolean> {
  try {
    const result = await RnVietmapTrackingPlugin.configure(apiKey, baseURL);
    isConfigured = result;
    return result;
  } catch (error) {
    console.error('Failed to configure VietmapTrackingSDK:', error);
    throw error;
  }
}

/**
 * Validate the API key against the server, then configure the SDK.
 *
 * Calls `GET {baseURL}/gps-tracking/users` with an `X-API-Key` header and
 * rejects with `INVALID_API_KEY` when the key or host is wrong, rather than
 * accepting bad credentials and failing later at upload time. This is the entry
 * point the Flutter plugin uses.
 *
 * @param authMode How the key travels. `'header'` sends `X-API-Key`,
 *   `'queryParam'` appends `?apiKey=`. The SDK reads this on every upload path,
 *   so a mismatch with the gateway turns every upload into a 401 while tracking
 *   still looks healthy. Defaults to `'header'`, the SDK's own default.
 * @param autoUpload Defaults to true. Set false to hold locations in the cache
 *   and drive uploads yourself with {@link uploadCachedLocationsManually}.
 * @throws `INVALID_API_KEY` when the server rejects the key
 */
export async function initializeTracking(
  apiKey: string,
  baseURL?: string,
  authMode: AuthMode = 'header',
  autoUpload: boolean = true
): Promise<void> {
  await RnVietmapTrackingPlugin.initializeTracking(
    apiKey,
    baseURL,
    authMode,
    autoUpload
  );
  isConfigured = true;
}

export async function configureAlertAPI(
  apiKey: string,
  apiID: string
): Promise<boolean> {
  try {
    return await RnVietmapTrackingPlugin.configureAlertAPI(apiKey, apiID);
  } catch (error) {
    console.error('Failed to configure Alert API:', error);
    throw error;
  }
}

export function getPlatformVersion(): Promise<string> {
  return RnVietmapTrackingPlugin.getPlatformVersion();
}

// ── Permissions ────────────────────────────────────────────────────────

export async function requestLocationPermissions(): Promise<PermissionResult> {
  try {
    return await RnVietmapTrackingPlugin.requestLocationPermissions();
  } catch (error) {
    console.error('Failed to request location permissions:', error);
    throw error;
  }
}

export async function hasLocationPermissions(): Promise<PermissionResult> {
  try {
    return await RnVietmapTrackingPlugin.hasLocationPermissions();
  } catch (error) {
    console.error('Failed to check location permissions:', error);
    throw error;
  }
}

/** Always-on permission, required for background tracking. */
export function requestAlwaysLocationPermissions(): Promise<string> {
  return RnVietmapTrackingPlugin.requestAlwaysLocationPermissions();
}

// ── Identity ───────────────────────────────────────────────────────────

/**
 * Set the driver identity written into every GPS upload as `userId`.
 *
 * Required before tracking starts. {@link startLocationTracking} also accepts
 * `userId` in its config and pushes it for you, which is the path to prefer.
 */
export async function setDriverId(driverId: string): Promise<boolean> {
  try {
    return await RnVietmapTrackingPlugin.setDriverId(driverId);
  } catch (error) {
    console.error('Failed to set driver id:', error);
    throw error;
  }
}

/** Driver id previously set, or '' if none. */
export function getDriverId(): Promise<string> {
  return RnVietmapTrackingPlugin.getDriverId();
}

/** Set the vehicle identity written into the GPS upload payload. Optional. */
export async function setVehicleId(vehicleId: string): Promise<boolean> {
  try {
    return await RnVietmapTrackingPlugin.setVehicleId(vehicleId);
  } catch (error) {
    console.error('Failed to set vehicle id:', error);
    throw error;
  }
}

/** Vehicle id previously set, or '' if none. */
export function getVehicleId(): Promise<string> {
  return RnVietmapTrackingPlugin.getVehicleId();
}

/** Arbitrary key-value data attached to every upload. */
export function setMetadata(
  metadata: Record<string, unknown>
): Promise<boolean> {
  requireConfigured();
  return RnVietmapTrackingPlugin.setMetadata(metadata);
}

/** Package codes attached to every upload. */
export function setPackages(packages: string[]): Promise<boolean> {
  requireConfigured();
  return RnVietmapTrackingPlugin.setPackages(packages);
}

/** App signature attached to every upload. */
export function setAppSignature(signature: string): Promise<boolean> {
  requireConfigured();
  return RnVietmapTrackingPlugin.setAppSignature(signature);
}

/** Vehicle characteristics used by the alert engine. */
export function configureVehicle(params: {
  vehicleId: string;
  vehicleType: number;
  seats: number;
  weight: number;
  maxProvision?: number;
}): Promise<boolean> {
  requireConfigured();
  return RnVietmapTrackingPlugin.configureVehicle(
    params.vehicleId,
    params.vehicleType,
    params.seats,
    params.weight,
    params.maxProvision
  );
}

// ── Tracking ───────────────────────────────────────────────────────────

/**
 * Start GPS tracking.
 *
 * `config.intervalMs` and `config.distanceFilter` pick the SDK's trigger mode
 * between them — see {@link LocationTrackingConfig}. Omit the one you do not
 * want; passing `0` is a value, not an absence, and gets clamped up to the
 * SDK's floor.
 *
 * `config.userId` is required. It is pushed to the SDK before the start, so
 * there is no need to call {@link setDriverId} separately.
 *
 * Returns `false` rather than throwing when a start is already running or
 * tracking is already active, so a duplicate tap is a no-op.
 *
 * @throws `SDK_NOT_CONFIGURED` when configure() or initializeTracking() has not run
 * @throws `MISSING_USER_ID` when config.userId is absent or blank
 * @throws when permissions are denied
 */
export async function startLocationTracking(
  config: LocationTrackingConfig
): Promise<boolean> {
  requireConfigured();

  const userId = config.userId?.trim();
  if (!userId) {
    const error = new Error(
      'userId is required to start tracking. The SDK refuses to start without it.'
    );
    error.name = 'MISSING_USER_ID';
    throw error;
  }

  // Read and set with no await between, so two synchronous callers cannot both
  // see false.
  if (startInFlight) {
    console.warn('startLocationTracking skipped: a start is already running');
    return false;
  }
  startInFlight = true;

  try {
    // Checked before permissions on purpose: a redundant start must not raise a
    // permission dialog at someone who is already being tracked.
    if (await RnVietmapTrackingPlugin.isTrackingActive()) {
      console.warn('startLocationTracking skipped: tracking is already active');
      return false;
    }

    const permissionStatus = await hasLocationPermissions();
    if (!permissionStatus.granted) {
      const permissionResult = await requestLocationPermissions();
      if (!permissionResult.granted) {
        throw new Error('Location permission denied');
      }
    }

    // Absent trigger values are left out of the payload entirely rather than
    // substituted, so the native side can tell "not provided" from a number.
    const payload: Record<string, unknown> = {
      backgroundMode: config.backgroundMode ?? true,
      userId,
      vehicleId: config.vehicleId?.trim() ?? '',
      allowMockLocation: config.allowMockLocation ?? true,
      enableSpeedFallback: config.enableSpeedFallback ?? true,
      enableSmartBattery: config.enableSmartBattery ?? false,
    };
    if (config.intervalMs != null) payload.intervalMs = config.intervalMs;
    if (config.distanceFilter != null)
      payload.distanceFilter = config.distanceFilter;
    if (config.accuracy != null) payload.accuracy = config.accuracy;
    if (config.notificationTitle != null)
      payload.notificationTitle = config.notificationTitle;
    if (config.notificationMessage != null)
      payload.notificationMessage = config.notificationMessage;
    if (config.smartBatteryPreset != null)
      payload.smartBatteryPreset = config.smartBatteryPreset;

    return await RnVietmapTrackingPlugin.startTracking(payload);
  } catch (error) {
    console.error('Failed to start location tracking:', error);
    throw error;
  } finally {
    startInFlight = false;
  }
}

export async function stopLocationTracking(): Promise<boolean> {
  try {
    return await RnVietmapTrackingPlugin.stopTracking();
  } catch (error) {
    console.error('Failed to stop location tracking:', error);
    return false;
  }
}

/**
 * Change the cadence while tracking runs.
 *
 * `backgroundMode` cannot be changed mid-session — the SDK reads it only at
 * start. Stop and start again to change it.
 */
export function updateTrackingConfig(
  config: LocationTrackingConfig
): Promise<boolean> {
  requireConfigured();
  return RnVietmapTrackingPlugin.updateTrackingConfig(config);
}

export async function getCurrentLocation(): Promise<LocationData> {
  const location = await RnVietmapTrackingPlugin.getCurrentLocation();
  return location as LocationData;
}

export function isTrackingActive(): Promise<boolean> {
  return RnVietmapTrackingPlugin.isTrackingActive();
}

export async function getTrackingStatus(): Promise<TrackingStatus> {
  const status = await RnVietmapTrackingPlugin.getTrackingStatus();
  return status as TrackingStatus;
}

/** Diagnostics: permissions, uptime and time since the last fix. */
export async function getTrackingHealthStatus(): Promise<TrackingHealthStatus> {
  const status = await RnVietmapTrackingPlugin.getTrackingHealthStatus();
  return status as TrackingHealthStatus;
}

/**
 * Server-side history for a user.
 *
 * Timestamps are milliseconds. The Android SDK treats a value under 10 billion
 * as seconds and converts it, so passing seconds silently shifts the window by
 * decades.
 */
export async function getTrackingHistory(params: {
  userId: string;
  fromTimestamp?: number;
  toTimestamp?: number;
  pageNumber?: number;
  pageSize?: number;
  sortBy?: string;
  sortDescending?: boolean;
}): Promise<GpsLocation[]> {
  requireConfigured();
  const json = await RnVietmapTrackingPlugin.getTrackingHistory(
    params.userId,
    params.fromTimestamp,
    params.toTimestamp,
    params.pageNumber ?? 1,
    params.pageSize ?? 100,
    params.sortBy,
    params.sortDescending ?? false
  );
  return parseHistory(json);
}

/**
 * The SDK returns the server's response verbatim, and the rows have been seen
 * both at the top level and under `data`. Handle both rather than assuming.
 */
function parseHistory(json: string): GpsLocation[] {
  if (!json) return [];
  try {
    const parsed = JSON.parse(json);
    const rows = Array.isArray(parsed)
      ? parsed
      : Array.isArray(parsed?.data)
        ? parsed.data
        : Array.isArray(parsed?.data?.items)
          ? parsed.data.items
          : [];
    return rows as GpsLocation[];
  } catch (error) {
    console.error('Failed to parse tracking history:', error);
    return [];
  }
}

// ── Offline cache and upload ───────────────────────────────────────────

/** Whether the SDK believes it has a usable network. */
export function isNetworkConnected(): Promise<boolean> {
  return RnVietmapTrackingPlugin.isNetworkConnected();
}

/** Locations held on device, waiting to upload. */
export function getCachedLocationsCount(): Promise<number> {
  return RnVietmapTrackingPlugin.getCachedLocationsCount();
}

/**
 * Drain the cache now.
 *
 * iOS reports whether the upload succeeded. Android's SDK method returns
 * nothing, so there it resolves true once the call returns — which means the
 * request was started, not that it landed. Check
 * {@link getCachedLocationsCount} afterwards to see what actually drained.
 */
export function uploadCachedLocationsManually(): Promise<boolean> {
  requireConfigured();
  return RnVietmapTrackingPlugin.uploadCachedLocationsManually();
}

/** Discard everything waiting to upload. */
export function clearCachedLocations(): Promise<boolean> {
  requireConfigured();
  return RnVietmapTrackingPlugin.clearCachedLocations();
}

/**
 * Resize the on-device cache.
 *
 * A zero keeps the SDK's own value for that field, and those differ per
 * platform: `maxRecords` is 5000 on Android and 10000 on iOS, while
 * `maxDbSizeBytes` (50MB) and `batchSize` (50) match.
 */
export function configureCacheLimits(params: {
  maxRecords?: number;
  maxDbSizeBytes?: number;
  batchSize?: number;
}): Promise<boolean> {
  requireConfigured();
  return RnVietmapTrackingPlugin.configureCacheLimits(
    params.maxRecords ?? 0,
    params.maxDbSizeBytes ?? 0,
    params.batchSize ?? 0
  );
}

/** On-disk size of the cache database. */
export function getDatabaseSizeBytes(): Promise<number> {
  return RnVietmapTrackingPlugin.getDatabaseSizeBytes();
}

// ── Lifecycle ──────────────────────────────────────────────────────────
//
// The plugin drives these natively — UIApplication notifications on iOS,
// LifecycleEventListener on Android — so an app does not have to. They stay
// exported for a host that manages app state itself.
//
// Do NOT wire React Native's AppState to them. AppState is itself a native
// observer of the same notifications that then crosses the bridge, so doing so
// delivers each transition twice: once natively and once three hops later.

/** Tell the SDK the app went to the background. Normally driven natively. */
export function onAppBackground(): Promise<boolean> {
  return RnVietmapTrackingPlugin.onAppBackground();
}

/** Tell the SDK the app came back. Normally driven natively. */
export function onAppForeground(): Promise<boolean> {
  return RnVietmapTrackingPlugin.onAppForeground();
}

/**
 * Turn automatic uploading on or off.
 *
 * iOS has a native setting for this. Android has none — uploads are always
 * automatic there, and the call resolves true without changing anything.
 */
export function setAutoUpload(enabled: boolean): Promise<boolean> {
  requireConfigured();
  return RnVietmapTrackingPlugin.setAutoUpload(enabled);
}

// ── Notification permission ────────────────────────────────────────────
//
// The SDK posts the fake-GPS and tracking-interrupted notifications itself and
// documents that the host app must already hold authorization. Neither platform
// grants it implicitly, and iOS never prompts when a notification is posted — a
// post with authorization still `.notDetermined` is dropped in silence. So one
// of these has to be called, or those notifications can never appear.
//
// On iOS this covers the whole permission story. It does NOT cover display:
// a notification posted while the app is in the foreground is delivered but not
// shown unless the app sets a UNUserNotificationCenterDelegate that completes
// `willPresent` with `.banner`. That delegate is app-wide state, so the plugin
// deliberately leaves it to the host app — see the Fake GPS section of the
// README for the snippet.

/**
 * Ask for permission to show notifications.
 *
 * iOS requests alert and sound. Android below API 33 has nothing to request and
 * resolves true.
 *
 * Ask in context — when the user turns on something that notifies — rather than
 * at startup, so the prompt arrives with a visible reason. iOS only ever shows
 * the prompt once; later calls resolve the existing answer.
 */
export function requestNotificationPermission(): Promise<boolean> {
  return RnVietmapTrackingPlugin.requestNotificationPermission();
}

/** Whether notifications are currently authorized. */
export function hasNotificationPermission(): Promise<boolean> {
  return RnVietmapTrackingPlugin.hasNotificationPermission();
}

// ── Fake GPS ───────────────────────────────────────────────────────────

/**
 * Choose what the SDK does when it detects a fake fix.
 *
 * Only consulted while tracking runs with `allowMockLocation: false`; at the
 * default `true` the SDK lets simulated fixes through and never reaches the
 * policy.
 */
export function setFakeGPSPolicy(policy: FakeGpsPolicy): Promise<boolean> {
  return RnVietmapTrackingPlugin.setFakeGPSPolicy(policy);
}

/** Title and body of the local notification raised by the `'warn'` policy. */
export function setFakeGpsNotificationConfig(
  title: string,
  message: string
): Promise<boolean> {
  return RnVietmapTrackingPlugin.setFakeGpsNotificationConfig(title, message);
}

// ── Tracking interrupted ───────────────────────────────────────────────

/**
 * Show or hide the interruption notification.
 *
 * This does **not** silence {@link addTrackingInterruptedListener}; the
 * callback channel fires either way.
 */
export function setTrackingInterruptedNotificationEnabled(
  enabled: boolean
): Promise<boolean> {
  return RnVietmapTrackingPlugin.setTrackingInterruptedNotificationEnabled(
    enabled
  );
}

export function setTrackingInterruptedNotificationConfig(
  title: string,
  message: string
): Promise<boolean> {
  return RnVietmapTrackingPlugin.setTrackingInterruptedNotificationConfig(
    title,
    message
  );
}

// ── Smart battery ──────────────────────────────────────────────────────

/**
 * Switch the tracking cadence to a battery-aware preset.
 *
 * Neither native SDK exposes this; the plugin assembles it. Android reroutes
 * the interval without restarting the foreground service, iOS sets
 * CoreLocation's activity type so the OS can pause updates when the vehicle is
 * parked.
 */
export function setSmartBatteryConfig(
  enabled: boolean,
  preset: SmartBatteryPreset = 'general'
): Promise<boolean> {
  requireConfigured();
  return RnVietmapTrackingPlugin.setSmartBatteryConfig(enabled, preset);
}

// ── External GPS injection ─────────────────────────────────────────────

/**
 * Feed a fix from a source other than the device, such as a hardware GPS unit.
 *
 * `speed` at or below 30 is read as m/s and converted once; above that it is
 * taken as km/h. Convert before calling if that guess would be wrong for you.
 */
export function processExternalLocation(params: {
  lat: number;
  lng: number;
  speed: number;
  heading: number;
}): Promise<boolean> {
  requireConfigured();
  return RnVietmapTrackingPlugin.processExternalLocation(
    params.lat,
    params.lng,
    params.speed,
    params.heading
  );
}

// ── Speed alert ────────────────────────────────────────────────────────

export async function turnOnAlert(): Promise<boolean> {
  try {
    return await RnVietmapTrackingPlugin.turnOnAlert();
  } catch (error) {
    console.error('Failed to turn on speed alert:', error);
    return false;
  }
}

export async function turnOffAlert(): Promise<boolean> {
  try {
    return await RnVietmapTrackingPlugin.turnOffAlert();
  } catch (error) {
    console.error('Failed to turn off speed alert:', error);
    return false;
  }
}

// ── Events ─────────────────────────────────────────────────────────────

export function addLocationUpdateListener(callback: LocationUpdateCallback) {
  return eventEmitter.addListener('onLocationUpdate', callback);
}

export function addTrackingStatusListener(callback: TrackingStatusCallback) {
  return eventEmitter.addListener('onTrackingStatusChanged', callback);
}

export function addLocationErrorListener(
  callback: (error: { message: string; timestamp: number }) => void
) {
  return eventEmitter.addListener('onLocationError', callback);
}

/**
 * Fake GPS detections. Fires only while tracking runs with
 * `allowMockLocation: false`.
 */
export function addFakeGPSDetectedListener(
  callback: (event: FakeGpsEvent) => void
) {
  return eventEmitter.addListener('onFakeGPSDetected', callback);
}

/**
 * Tracking interruptions and recoveries.
 *
 * Do **not** stop and restart tracking in response. The SDK raises this from
 * GPS silence, so a restart only costs a fresh first fix and can loop.
 */
export function addTrackingInterruptedListener(
  callback: (event: TrackingInterruptedEvent) => void
) {
  return eventEmitter.addListener('onTrackingInterrupted', callback);
}

// ── Config helpers ─────────────────────────────────────────────────────

/**
 * A timer-driven config at the given interval.
 *
 * Leaves `distanceFilter` unset on purpose: setting both would make the SDK
 * favour the timer and ignore the distance gate anyway, so naming only one
 * keeps what you asked for and what happens the same thing.
 */
export function createDefaultConfig(
  intervalMs: number = 5000
): LocationTrackingConfig {
  return {
    intervalMs,
    accuracy: 'high',
    backgroundMode: true,
    notificationTitle: 'GPS Tracking Active',
    notificationMessage: 'Your location is being tracked',
  };
}

/** A config that leaves the cadence to the SDK: its own 10s timer, 25m floor. */
export function createSdkDefaultConfig(): LocationTrackingConfig {
  return {
    accuracy: 'high',
    backgroundMode: true,
    notificationTitle: 'GPS Tracking Active',
    notificationMessage: 'Your location is being tracked',
  };
}

// ── Aliases and re-exports ─────────────────────────────────────────────

export const startTracking = startLocationTracking;
export const stopTracking = stopLocationTracking;

export { TrackingPresets, LocationUtils, TrackingSession } from './utils';
export * from './constants';
export * from './validation';

export type {
  LocationTrackingConfig,
  LocationData,
  TrackingStatus,
  TrackingHealthStatus,
  LocationUpdateCallback,
  TrackingStatusCallback,
  PermissionResult,
  FakeGpsEvent,
  TrackingInterruptedEvent,
  FakeGpsPolicy,
  SmartBatteryPreset,
  AuthMode,
  GpsLocation,
};
