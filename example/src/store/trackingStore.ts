import { create } from 'zustand';
import AsyncStorage from '@react-native-async-storage/async-storage';
import {
  configure,
  initializeTracking,
  startTracking,
  stopTracking,
  getCurrentLocation,
  getTrackingStatus,
  getTrackingHealthStatus,
  updateTrackingConfig,
  requestLocationPermissions,
  hasLocationPermissions,
  isNetworkConnected,
  getCachedLocationsCount,
  getDatabaseSizeBytes,
  uploadCachedLocationsManually,
  clearCachedLocations,
  configureCacheLimits,
  setPackages as sdkSetPackages,
  setMetadata as sdkSetMetadata,
  setFakeGPSPolicy,
  requestNotificationPermission,
  hasNotificationPermission,
  setSmartBatteryConfig,
  getTrackingHistory,
  getPlatformVersion,
  LocationUtils,
  TrackingSession,
  TRACKING_PRESETS,
  type LocationData,
  type LocationTrackingConfig,
  type TrackingHealthStatus,
  type FakeGpsEvent,
  type TrackingInterruptedEvent,
  type FakeGpsPolicy,
  type SmartBatteryPreset,
  type GpsLocation,
} from '@vietmap/rn_vietmap_tracking_plugin';

// Credentials are not stored here. initialize() receives them from the screen,
// mirroring the Flutter example where main.dart calls
// provider.configureSdk(apiKey, baseURL: ...) and the provider holds no defaults.

/**
 * Defaults an integrator would want.
 *
 * Two of these follow the *plugin* default rather than the raw SDK default, and
 * both are what make the example work out of the box:
 *
 *  - allowMockLocation true. At the SDK's own `false` the example drops every
 *    fix on a simulator or emulator and uploads empty batches, and evaluating
 *    the SDK almost always starts on one. Production apps set this to false and
 *    pick a fake GPS policy.
 *  - backgroundMode true, so the demo exercises the path that actually matters.
 *
 * intervalMs is set and distanceFilter is not, on purpose: supplying both makes
 * the SDK favour the timer and ignore the distance gate, so a config that named
 * both would not do what it says.
 */
const DEFAULT_CONFIG: LocationTrackingConfig = {
  intervalMs: 5000,
  accuracy: 'high',
  backgroundMode: true,
  notificationTitle: 'GPS Tracking',
  notificationMessage: 'Your location is being tracked',
  allowMockLocation: true,
  enableSpeedFallback: true,
};

/**
 * How the config card names the three trigger modes.
 *
 * The default is 'sdkDefault', matching the Flutter example: it returns
 * LocationTrackingConfig.sdkDefault() unless the tester opts into a custom
 * config, so the interval lives in exactly one place — the native SDK — and
 * this app cannot drift from it the way a pinned preset would.
 */
export type TriggerMode = 'interval' | 'distance' | 'sdkDefault';

/**
 * One id per app launch, so a run is easy to pick out in the backend. Not a
 * security token — a human-readable marker.
 */
function newSessionId(): string {
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, '0');
  const stamp =
    `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}` +
    `-${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
  return `${stamp}-${Math.random().toString(36).slice(2, 6)}`;
}

type SessionStats = ReturnType<TrackingSession['getStats']> | null;

/**
 * What survives a restart: the two fields a tester retypes constantly.
 *
 * Deliberately not the credentials, the policy or the config — those belong in
 * source where they are reviewable, and a stale persisted policy silently
 * overriding the code would be the kind of surprise this example exists to
 * avoid.
 */
const STORAGE_KEYS = {
  userId: 'vietmap.example.userId',
  vehicleId: 'vietmap.example.vehicleId',
  packages: 'vietmap.example.packages',
} as const;

/**
 * Storage failures are never fatal here. A private-mode browser, cleared site
 * data or a denied disk write should cost the convenience, not the session — so
 * every read falls back to the in-memory default and every write is best effort.
 */
async function loadPersisted(): Promise<{
  userId: string;
  vehicleId: string;
  packages: string[];
}> {
  try {
    const [userId, vehicleId, packages] = await Promise.all([
      AsyncStorage.getItem(STORAGE_KEYS.userId),
      AsyncStorage.getItem(STORAGE_KEYS.vehicleId),
      AsyncStorage.getItem(STORAGE_KEYS.packages),
    ]);
    let parsedPackages: string[] = [];
    if (packages) {
      const decoded = JSON.parse(packages);
      // Guard the shape: a corrupted value should not put a number into a list
      // the SDK expects to be strings.
      if (Array.isArray(decoded)) {
        parsedPackages = decoded.filter((item): item is string => typeof item === 'string');
      }
    }
    return {
      userId: userId ?? '',
      vehicleId: vehicleId ?? '',
      packages: parsedPackages,
    };
  } catch {
    return { userId: '', vehicleId: '', packages: [] };
  }
}

function persist(key: string, value: string): void {
  AsyncStorage.setItem(key, value).catch(() => {
    // Best effort; losing the convenience is not worth surfacing an error.
  });
}

interface TrackingStore {
  // ── Session identity ──────────────────────────────────────────────
  sessionId: string;
  userId: string;
  vehicleId: string;

  // ── SDK / permissions ─────────────────────────────────────────────
  isInitialized: boolean;
  isConfiguring: boolean;
  /** Last configure failure, surfaced instead of blocking the flow. */
  initError: string | null;
  /** The credentials the SDK actually holds, to detect an edit that has not applied. */
  configuredWith: { apiKey: string; baseURL?: string } | null;
  /**
   * Set when key validation failed but the SDK was configured anyway, so
   * tracking runs while uploads probably do not. Null when everything is well.
   */
  degradedReason: string | null;
  hasPermissions: boolean;
  platformVersion: string;

  // ── Tracking ──────────────────────────────────────────────────────
  isTracking: boolean;
  currentLocation: LocationData | null;
  locationHistory: LocationData[];
  sessionStats: SessionStats;
  health: TrackingHealthStatus | null;

  // ── Config ────────────────────────────────────────────────────────
  triggerMode: TriggerMode;
  customInterval: string;
  customDistance: string;
  customBackgroundMode: boolean;
  allowMockLocation: boolean;
  presetName: string | null;

  // ── Cache ─────────────────────────────────────────────────────────
  cachedCount: number;
  dbSizeBytes: number;
  isOnline: boolean;
  maxRecords: string;
  maxDbSizeMb: string;
  batchSize: string;

  // ── Packages and metadata ─────────────────────────────────────────
  packages: string[];
  appliedPackages: string[];

  // ── Fake GPS ──────────────────────────────────────────────────────
  fakeGpsPolicy: FakeGpsPolicy;
  fakeGpsEvents: FakeGpsEvent[];
  /** Whether notifications are authorized. The 'warn' policy is silent without it. */
  hasNotificationPermission: boolean;

  // ── Tracking interrupted ──────────────────────────────────────────
  interruptedEvents: TrackingInterruptedEvent[];

  // ── Smart battery ─────────────────────────────────────────────────
  smartBatteryEnabled: boolean;
  smartBatteryPreset: SmartBatteryPreset;

  // ── Server history ────────────────────────────────────────────────
  serverHistory: GpsLocation[];
  isFetchingHistory: boolean;
  historyPage: number;
  hasMoreHistory: boolean;

  // ── Actions ───────────────────────────────────────────────────────
  setUserId: (value: string) => void;
  setVehicleId: (value: string) => void;
  regenerateSession: () => void;
  /** Reload the identity and packages saved by a previous run. */
  restorePersisted: () => Promise<void>;

  initialize: (apiKey: string, baseURL?: string) => Promise<void>;
  checkPermissions: () => Promise<void>;
  requestPermissions: () => Promise<boolean>;
  refreshTrackingStatus: () => Promise<void>;
  refreshHealth: () => Promise<void>;

  getActiveConfig: () => LocationTrackingConfig;
  setTriggerMode: (mode: TriggerMode) => void;
  setCustomInterval: (value: string) => void;
  setCustomDistance: (value: string) => void;
  setCustomBackgroundMode: (value: boolean) => void;
  setAllowMockLocation: (value: boolean) => void;
  applyPreset: (name: keyof typeof TRACKING_PRESETS) => void;

  start: () => Promise<{ ok: boolean; message: string }>;
  stop: () => Promise<{ ok: boolean; message: string }>;
  fetchCurrentLocation: () => Promise<LocationData>;
  applyConfig: () => Promise<boolean>;

  refreshCacheStats: () => Promise<void>;
  applyCacheLimits: () => Promise<boolean>;
  uploadCache: () => Promise<boolean>;
  clearCache: () => Promise<boolean>;

  addPackages: (raw: string) => number;
  removePackage: (code: string) => void;
  applyPackages: () => Promise<boolean>;

  setFakeGpsPolicyValue: (policy: FakeGpsPolicy) => Promise<void>;
  checkNotificationPermission: () => Promise<void>;
  requestNotificationPermissionValue: () => Promise<boolean>;
  pushFakeGpsEvent: (event: FakeGpsEvent) => void;
  clearFakeGpsEvents: () => void;

  pushInterruptedEvent: (event: TrackingInterruptedEvent) => void;
  clearInterruptedEvents: () => void;

  setSmartBattery: (enabled: boolean, preset?: SmartBatteryPreset) => Promise<void>;

  fetchServerHistory: (reset?: boolean) => Promise<void>;

  pushLocation: (location: LocationData) => void;
  pushLocationError: (message: string) => void;
  setIsTracking: (value: boolean) => void;
  clearHistory: () => void;
  totalDistanceMeters: () => number;
  lastError: string | null;
}

// Kept outside the store: a mutable helper, not rendered state.
const trackingSession = new TrackingSession();

const HISTORY_PAGE_SIZE = 50;

export const useTrackingStore = create<TrackingStore>((set, get) => ({
  sessionId: newSessionId(),
  // Empty by default: the tester types the ids they want to look up in the
  // backend. The session id above is only a display marker.
  userId: '',
  vehicleId: '',

  isInitialized: false,
  isConfiguring: false,
  initError: null,
  configuredWith: null,
  degradedReason: null,
  hasPermissions: false,
  platformVersion: '',

  isTracking: false,
  currentLocation: null,
  locationHistory: [],
  sessionStats: null,
  health: null,

  triggerMode: 'sdkDefault',
  customInterval: String(DEFAULT_CONFIG.intervalMs),
  customDistance: '25',
  customBackgroundMode: DEFAULT_CONFIG.backgroundMode ?? true,
  allowMockLocation: DEFAULT_CONFIG.allowMockLocation ?? true,
  presetName: null,

  cachedCount: 0,
  dbSizeBytes: 0,
  isOnline: true,
  // Left blank so the example shows the SDK's own limits rather than
  // overriding them. A zero in configureCacheLimits keeps the SDK default.
  maxRecords: '',
  maxDbSizeMb: '',
  batchSize: '',

  packages: [],
  appliedPackages: [],

  fakeGpsPolicy: 'skip',
  fakeGpsEvents: [],
  hasNotificationPermission: false,

  interruptedEvents: [],

  smartBatteryEnabled: false,
  smartBatteryPreset: 'general',

  serverHistory: [],
  isFetchingHistory: false,
  historyPage: 1,
  hasMoreHistory: true,

  lastError: null,

  // ── Identity ────────────────────────────────────────────────────
  setUserId: (value) => {
    set({ userId: value });
    persist(STORAGE_KEYS.userId, value);
  },
  setVehicleId: (value) => {
    set({ vehicleId: value });
    persist(STORAGE_KEYS.vehicleId, value);
  },
  regenerateSession: () => set({ sessionId: newSessionId() }),

  // ── Bootstrap ───────────────────────────────────────────────────
  restorePersisted: async () => {
    const saved = await loadPersisted();
    // Only fill fields the user has not already typed into: a restore arriving
    // late must not overwrite what they just entered.
    set((state) => ({
      userId: state.userId || saved.userId,
      vehicleId: state.vehicleId || saved.vehicleId,
      packages: state.packages.length > 0 ? state.packages : saved.packages,
    }));
  },

  initialize: async (apiKey, baseURL) => {
    // Re-entrancy and duplicate guards, mirroring the Flutter example's
    // configureSdk: React 19 StrictMode mounts effects twice in dev, and a
    // second configure() would re-run the SDK's whole init.
    if (get().isConfiguring) {
      return;
    }
    if (get().isInitialized) {
      // Editing the credentials and saving re-runs this effect, but the store
      // lives in its own module so Fast Refresh does not reset isInitialized —
      // the call would return here and the old credentials would stay in the
      // SDK while the source says otherwise. Say so rather than skipping in
      // silence, and say which restart is actually needed.
      const configured = get().configuredWith;
      if (configured && (configured.apiKey !== apiKey || configured.baseURL !== baseURL)) {
        const message =
          configured.baseURL !== baseURL
            ? 'Credentials changed, but the SDK still holds the previous ones. ' +
              'The baseURL changed, so a JS reload is not enough: the native SDK ' +
              'is a singleton that survives it and keeps the app-config and SSL ' +
              'pins it fetched from the old host. Quit the app and relaunch it.'
            : 'API key changed, but the SDK still holds the previous one. ' +
              'Reload JS (press R twice, or Cmd+R) to apply it.';
        console.warn(message);
        set({ initError: message });
      }
      return;
    }

    set({ isConfiguring: true, initError: null });
    try {
      // authMode 'header' and autoUpload true are the SDK's own defaults,
      // stated here so the example reads as a template to copy.
      await initializeTracking(apiKey, baseURL, 'header', true);
      // Remembered so a later call with different credentials can say what it
      // would take to apply them, instead of returning silently.
      set({
        isInitialized: true,
        initError: null,
        degradedReason: null,
        configuredWith: { apiKey, baseURL },
      });

      const version = await getPlatformVersion().catch(() => '');
      set({ platformVersion: version });

      await get().checkPermissions();
      await get().checkNotificationPermission();
      await get().refreshTrackingStatus();
      await get().refreshCacheStats();
    } catch (error) {
      // Validation failed. That is not always a bad key: it also happens when
      // the host cannot be reached at all — a staging server whose certificate
      // iOS refuses, for instance, where the TLS handshake fails before any
      // request completes.
      //
      // The local half of the SDK works regardless, so fall back to configure(),
      // which sets credentials without a network round trip. GPS collection,
      // onLocationUpdate and the on-device history all run; uploads queue in the
      // cache and drain if and when the host becomes reachable.
      //
      // This is deliberately NOT silent. Hiding it would leave tracking looking
      // healthy while every upload failed — the exact failure this example is
      // meant to make visible. The pending count in the cache card is the
      // honest signal: if it only grows, uploads are not landing.
      const message = error instanceof Error ? error.message : String(error);
      try {
        await configure(apiKey, baseURL);
        set({
          isInitialized: true,
          initError: null,
          degradedReason: message,
          configuredWith: { apiKey, baseURL },
        });
        await get().checkPermissions();
        await get().refreshTrackingStatus();
        await get().refreshCacheStats();
      } catch (fallbackError) {
        const fallbackMessage =
          fallbackError instanceof Error ? fallbackError.message : String(fallbackError);
        set({ isInitialized: false, initError: fallbackMessage, degradedReason: null });
      }
    } finally {
      set({ isConfiguring: false });
    }
  },

  checkPermissions: async () => {
    try {
      const permissions = await hasLocationPermissions();
      set({ hasPermissions: permissions.granted });
    } catch (error) {
      set({
        hasPermissions: false,
        lastError: `Permission check failed: ${error instanceof Error ? error.message : String(error)}`,
      });
    }
  },

  requestPermissions: async () => {
    try {
      const result = await requestLocationPermissions();
      set({ hasPermissions: result.granted, lastError: null });
      if (!result.granted) {
        // Denial is not an error, but silence about it is: the button looks
        // broken otherwise, which is exactly how the Android bug below read.
        set({ lastError: `Location permission ${result.status ?? 'denied'}` });
      }
      return result.granted;
    } catch (error) {
      // Was a bare `catch { return false }`. The native side rejects with real
      // reasons — NO_ACTIVITY, INVALID_ACTIVITY, PERMISSION_REQUEST_FAILED —
      // and swallowing them made a failed request indistinguishable from a
      // refused one, with nothing on screen either way.
      const message = error instanceof Error ? error.message : String(error);
      set({ hasPermissions: false, lastError: `Permission request failed: ${message}` });
      return false;
    }
  },

  refreshTrackingStatus: async () => {
    try {
      const status = await getTrackingStatus();
      set({ isTracking: status.isTracking });
    } catch {
      set({ isTracking: false });
    }
  },

  refreshHealth: async () => {
    try {
      set({ health: await getTrackingHealthStatus() });
    } catch {
      set({ health: null });
    }
  },

  // ── Config ──────────────────────────────────────────────────────
  getActiveConfig: () => {
    const {
      triggerMode,
      customInterval,
      customDistance,
      customBackgroundMode,
      allowMockLocation,
      userId,
      vehicleId,
    } = get();

    const base: LocationTrackingConfig = {
      accuracy: 'high',
      backgroundMode: customBackgroundMode,
      notificationTitle: DEFAULT_CONFIG.notificationTitle,
      notificationMessage: DEFAULT_CONFIG.notificationMessage,
      allowMockLocation,
      enableSpeedFallback: true,
      userId: userId.trim(),
      vehicleId: vehicleId.trim(),
    };

    // Exactly one trigger, never both: naming both makes the SDK favour the
    // timer and silently ignore the distance gate.
    switch (triggerMode) {
      case 'interval':
        return {
          ...base,
          intervalMs: parseInt(customInterval, 10) || DEFAULT_CONFIG.intervalMs,
        };
      case 'distance':
        return { ...base, distanceFilter: parseInt(customDistance, 10) || 25 };
      case 'sdkDefault':
        // Neither trigger set, so the SDK runs its own 10s / 25m defaults.
        return base;
    }
  },

  setTriggerMode: (mode) => set({ triggerMode: mode, presetName: null }),
  setCustomInterval: (value) => set({ customInterval: value, presetName: null }),
  setCustomDistance: (value) => set({ customDistance: value, presetName: null }),
  setCustomBackgroundMode: (value) => set({ customBackgroundMode: value }),
  setAllowMockLocation: (value) => set({ allowMockLocation: value }),

  applyPreset: (name) => {
    const preset = TRACKING_PRESETS[name];
    if (!preset) return;
    if ('intervalMs' in preset && preset.intervalMs != null) {
      set({
        triggerMode: 'sdkDefault',
        customInterval: String(preset.intervalMs),
        presetName: name,
      });
    } else if ('distanceFilter' in preset && preset.distanceFilter != null) {
      set({
        triggerMode: 'distance',
        customDistance: String(preset.distanceFilter),
        presetName: name,
      });
    }
  },

  // ── Tracking ────────────────────────────────────────────────────
  start: async () => {
    const { hasPermissions, userId } = get();

    if (!userId.trim()) {
      return { ok: false, message: 'Set a User ID before starting' };
    }
    if (!hasPermissions) {
      const granted = await get().requestPermissions();
      if (!granted) {
        return { ok: false, message: 'Location permissions required' };
      }
    }

    try {
      const started = await startTracking(get().getActiveConfig());
      if (started) {
        trackingSession.start();
        set({ isTracking: true, lastError: null });
        return { ok: true, message: `Tracking started as ${userId}` };
      }
      // startTracking reports the SDK's real answer, so false means it refused
      // or a start was already running. The reason arrives on the status listener.
      await get().refreshTrackingStatus();
      return { ok: false, message: 'Start refused — check the status log' };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ isTracking: false, lastError: message });
      return { ok: false, message };
    }
  },

  stop: async () => {
    try {
      const stopped = await stopTracking();
      if (stopped) {
        trackingSession.clear();
        set({ isTracking: false, sessionStats: null });
        return { ok: true, message: 'Tracking stopped' };
      }
      await get().refreshTrackingStatus();
      return { ok: false, message: 'Stop returned false — status refreshed' };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ lastError: message });
      return { ok: false, message };
    }
  },

  fetchCurrentLocation: async () => {
    const location = await getCurrentLocation();
    set({ currentLocation: location });
    return location;
  },

  applyConfig: async () => {
    if (!get().isTracking) return false;
    return updateTrackingConfig(get().getActiveConfig());
  },

  // ── Cache ───────────────────────────────────────────────────────
  refreshCacheStats: async () => {
    try {
      const [count, size, online] = await Promise.all([
        getCachedLocationsCount(),
        getDatabaseSizeBytes(),
        isNetworkConnected(),
      ]);
      set({ cachedCount: count, dbSizeBytes: size, isOnline: online });
    } catch {
      // Leave the last known values rather than zeroing a panel mid-read.
    }
  },

  applyCacheLimits: async () => {
    const { maxRecords, maxDbSizeMb, batchSize } = get();
    // A blank field means "keep the SDK's own value", which configureCacheLimits
    // expresses as a zero.
    const ok = await configureCacheLimits({
      maxRecords: parseInt(maxRecords, 10) || 0,
      maxDbSizeBytes: (parseInt(maxDbSizeMb, 10) || 0) * 1024 * 1024,
      batchSize: parseInt(batchSize, 10) || 0,
    });
    await get().refreshCacheStats();
    return ok;
  },

  uploadCache: async () => {
    const ok = await uploadCachedLocationsManually();
    // Android resolves true once the request starts, not once it lands, so the
    // count is the real answer.
    await get().refreshCacheStats();
    return ok;
  },

  clearCache: async () => {
    const ok = await clearCachedLocations();
    await get().refreshCacheStats();
    return ok;
  },

  // ── Packages ────────────────────────────────────────────────────
  addPackages: (raw) => {
    const incoming = raw
      .split(/[\s,;]+/)
      .map((code) => code.trim())
      .filter(Boolean);
    if (incoming.length === 0) return 0;
    const existing = get().packages;
    const merged = Array.from(new Set([...existing, ...incoming]));
    set({ packages: merged });
    return merged.length - existing.length;
  },

  removePackage: (code) =>
    set((state) => ({ packages: state.packages.filter((c) => c !== code) })),

  applyPackages: async () => {
    const { packages, sessionId } = get();
    // Persisted on apply rather than on every keystroke: applied is the state
    // worth restoring, a half-typed list is not.
    persist(STORAGE_KEYS.packages, JSON.stringify(packages));
    await sdkSetPackages(packages);
    // Metadata rides along so the example exercises both in one action.
    await sdkSetMetadata({ session: sessionId, source: 'rn-example' });
    set({ appliedPackages: [...packages] });
    return true;
  },

  // ── Fake GPS ────────────────────────────────────────────────────
  setFakeGpsPolicyValue: async (policy) => {
    await setFakeGPSPolicy(policy);
    set({ fakeGpsPolicy: policy });

    // Ask in context: 'warn' is the only policy that raises a notification, so
    // this is the moment the permission has a visible reason. Asking at startup
    // instead would produce a prompt nobody can connect to anything.
    //
    // iOS shows its prompt once and only once; later calls resolve the earlier
    // answer without showing anything, which is why this is safe to call again.
    if (policy === 'warn' && !get().hasNotificationPermission) {
      await get().requestNotificationPermissionValue();
    }
  },

  checkNotificationPermission: async () => {
    try {
      set({ hasNotificationPermission: await hasNotificationPermission() });
    } catch {
      set({ hasNotificationPermission: false });
    }
  },

  requestNotificationPermissionValue: async () => {
    try {
      const granted = await requestNotificationPermission();
      set({ hasNotificationPermission: granted });
      return granted;
    } catch (error) {
      set({ lastError: error instanceof Error ? error.message : String(error) });
      return false;
    }
  },

  pushFakeGpsEvent: (event) =>
    set((state) => ({ fakeGpsEvents: [event, ...state.fakeGpsEvents].slice(0, 20) })),

  clearFakeGpsEvents: () => set({ fakeGpsEvents: [] }),

  // ── Tracking interrupted ────────────────────────────────────────
  pushInterruptedEvent: (event) =>
    set((state) => ({
      interruptedEvents: [event, ...state.interruptedEvents].slice(0, 20),
    })),

  clearInterruptedEvents: () => set({ interruptedEvents: [] }),

  // ── Smart battery ───────────────────────────────────────────────
  setSmartBattery: async (enabled, preset) => {
    const chosen = preset ?? get().smartBatteryPreset;
    await setSmartBatteryConfig(enabled, chosen);
    set({ smartBatteryEnabled: enabled, smartBatteryPreset: chosen });
  },

  // ── Server history ──────────────────────────────────────────────
  fetchServerHistory: async (reset = false) => {
    const { userId, isFetchingHistory, historyPage, hasMoreHistory } = get();
    if (isFetchingHistory || !userId.trim()) return;
    if (!reset && !hasMoreHistory) return;

    const page = reset ? 1 : historyPage;
    set({ isFetchingHistory: true });
    try {
      const rows = await getTrackingHistory({
        userId: userId.trim(),
        // Milliseconds. The Android SDK reads a value under 10 billion as
        // seconds, so a seconds value would shift the window by decades.
        fromTimestamp: Date.now() - 24 * 60 * 60 * 1000,
        toTimestamp: Date.now(),
        pageNumber: page,
        pageSize: HISTORY_PAGE_SIZE,
        sortDescending: true,
      });
      set((state) => ({
        serverHistory: reset ? rows : [...state.serverHistory, ...rows],
        historyPage: page + 1,
        hasMoreHistory: rows.length >= HISTORY_PAGE_SIZE,
      }));
    } catch (error) {
      set({ lastError: error instanceof Error ? error.message : String(error) });
    } finally {
      set({ isFetchingHistory: false });
    }
  },

  // ── Location stream ─────────────────────────────────────────────
  pushLocation: (location) => {
    trackingSession.addLocation(location.latitude, location.longitude, location.timestamp);
    set((state) => ({
      currentLocation: location,
      locationHistory: [...state.locationHistory.slice(-49), location],
      sessionStats: trackingSession.getStats(),
    }));
  },

  pushLocationError: (message) => set({ lastError: message }),

  setIsTracking: (value) => set({ isTracking: value }),

  clearHistory: () => {
    trackingSession.clear();
    set({ locationHistory: [], sessionStats: null });
  },

  totalDistanceMeters: () => {
    const history = get().locationHistory;
    let total = 0;
    for (let i = 1; i < history.length; i++) {
      const prev = history[i - 1];
      const current = history[i];
      if (prev && current) {
        total += LocationUtils.calculateDistance(
          prev.latitude,
          prev.longitude,
          current.latitude,
          current.longitude
        );
      }
    }
    return total;
  },
}));
