/**
 * Contract tests for the native bridge.
 *
 * These assert method names and argument shapes against a mocked TurboModule,
 * in the style of the Flutter plugin's "Method Name Verification" suite. A
 * renamed method or a reordered argument is invisible to the type checker once
 * it crosses into native code, so it has to be pinned here.
 */

/**
 * Built inside the factory because jest.mock is hoisted above every const in
 * this file — a mock defined at module scope is still in its temporal dead zone
 * when the factory runs. jest.requireMock below hands the same object back.
 */
jest.mock('../NativeRnVietmapTrackingPlugin', () => {
  return {
    __esModule: true,
    default: {
    getPlatformVersion: jest.fn().mockResolvedValue('iOS 18.0'),
    configure: jest.fn().mockResolvedValue(true),
    initializeTracking: jest.fn().mockResolvedValue(undefined),
    configureAlertAPI: jest.fn().mockResolvedValue(true),
    setDriverId: jest.fn().mockResolvedValue(true),
    getDriverId: jest.fn().mockResolvedValue(''),
    setVehicleId: jest.fn().mockResolvedValue(true),
    getVehicleId: jest.fn().mockResolvedValue(''),
    setMetadata: jest.fn().mockResolvedValue(true),
    setPackages: jest.fn().mockResolvedValue(true),
    setAppSignature: jest.fn().mockResolvedValue(true),
    configureVehicle: jest.fn().mockResolvedValue(true),
    startTracking: jest.fn().mockResolvedValue(true),
    stopTracking: jest.fn().mockResolvedValue(true),
    updateTrackingConfig: jest.fn().mockResolvedValue(true),
    getCurrentLocation: jest.fn().mockResolvedValue({}),
    isTrackingActive: jest.fn().mockResolvedValue(false),
    getTrackingStatus: jest.fn().mockResolvedValue({ isTracking: false }),
    getTrackingHealthStatus: jest.fn().mockResolvedValue({}),
    getTrackingHistory: jest.fn().mockResolvedValue('[]'),
    requestLocationPermissions: jest.fn().mockResolvedValue({ granted: true }),
    hasLocationPermissions: jest.fn().mockResolvedValue({ granted: true }),
    requestAlwaysLocationPermissions: jest.fn().mockResolvedValue('granted'),
    isNetworkConnected: jest.fn().mockResolvedValue(true),
    getCachedLocationsCount: jest.fn().mockResolvedValue(0),
    uploadCachedLocationsManually: jest.fn().mockResolvedValue(true),
    clearCachedLocations: jest.fn().mockResolvedValue(true),
    configureCacheLimits: jest.fn().mockResolvedValue(true),
    getDatabaseSizeBytes: jest.fn().mockResolvedValue(0),
    onAppBackground: jest.fn().mockResolvedValue(true),
    onAppForeground: jest.fn().mockResolvedValue(true),
    setAutoUpload: jest.fn().mockResolvedValue(true),
    requestNotificationPermission: jest.fn().mockResolvedValue(true),
    hasNotificationPermission: jest.fn().mockResolvedValue(false),
    setFakeGPSPolicy: jest.fn().mockResolvedValue(true),
    setFakeGpsNotificationConfig: jest.fn().mockResolvedValue(true),
    setTrackingInterruptedNotificationEnabled: jest.fn().mockResolvedValue(true),
    setTrackingInterruptedNotificationConfig: jest.fn().mockResolvedValue(true),
    setSmartBatteryConfig: jest.fn().mockResolvedValue(true),
    processExternalLocation: jest.fn().mockResolvedValue(true),
    turnOnAlert: jest.fn().mockResolvedValue(true),
    turnOffAlert: jest.fn().mockResolvedValue(true),
    addListener: jest.fn(),
    removeListeners: jest.fn(),
    },
  };
});

jest.mock('react-native', () => ({
  NativeModules: { RnVietmapTrackingPlugin: {} },
  NativeEventEmitter: class {
    addListener = jest.fn().mockReturnValue({ remove: jest.fn() });
  },
  Platform: { OS: 'ios' },
}));

/**
 * The factory above defines every one of these, so indexing is safe. A
 * Record<string, jest.Mock> would be read as possibly-undefined under
 * noUncheckedIndexedAccess and force a `!` on every line below.
 */
type NativeMock = { [K in keyof typeof import('../NativeRnVietmapTrackingPlugin').default]: jest.Mock };

const mockNative = (
  jest.requireMock('../NativeRnVietmapTrackingPlugin') as { default: NativeMock }
).default;

import * as plugin from '../index';

const VALID_CONFIG = { userId: 'tester-1', intervalMs: 5000 };

/** configure() is the guard everything else needs to pass. */
async function configured() {
  await plugin.initializeTracking('key-1234567890', 'https://example.test/api/v1');
}

beforeEach(() => {
  jest.clearAllMocks();
});

/**
 * Silence an expected console call for the length of one test.
 *
 * Three tests below drive the code down its error paths on purpose, and the
 * warning each one prints is the proof the guard fired. Jest still collects
 * them into a `● Console` block that reads like failure next to a passing
 * suite — noise that looks like breakage teaches people to skim past output,
 * which is how a real error eventually slips through.
 *
 * Returns the spy, so a test can also assert *that* the warning happened
 * rather than only that it was quiet.
 */
function expectConsole(method: 'warn' | 'error') {
  return jest.spyOn(console, method).mockImplementation(() => {});
}

afterEach(() => {
  // Restores the spies above, so a failing assertion cannot leave console
  // muted for the rest of the run.
  jest.restoreAllMocks();
});

describe('configuration', () => {
  test('initializeTracking passes authMode and autoUpload, defaulting to the SDK values', async () => {
    await plugin.initializeTracking('key-1234567890', 'https://example.test/api/v1');
    expect(mockNative.initializeTracking).toHaveBeenCalledWith(
      'key-1234567890',
      'https://example.test/api/v1',
      'header',
      true
    );
  });

  test('initializeTracking forwards queryParam auth', async () => {
    await plugin.initializeTracking('key-1234567890', 'https://x.test', 'queryParam', false);
    expect(mockNative.initializeTracking).toHaveBeenCalledWith(
      'key-1234567890',
      'https://x.test',
      'queryParam',
      false
    );
  });
});

describe('startTracking guards', () => {
  test('rejects before the SDK is configured', async () => {
    // A fresh copy of the module, so the isConfigured flag is back to false.
    // The guard is module-level state, which the other tests have already set.
    jest.resetModules();
    const fresh = require('../index');
    await expect(fresh.startLocationTracking(VALID_CONFIG)).rejects.toThrow(
      /not configured/i
    );
  });

  test('rejects a blank userId', async () => {
    await configured();
    await expect(
      plugin.startLocationTracking({ intervalMs: 5000 })
    ).rejects.toThrow(/userId is required/i);
    expect(mockNative.startTracking).not.toHaveBeenCalled();
  });

  test('checks isTrackingActive before requesting permissions', async () => {
    await configured();
    const warn = expectConsole('warn');
    mockNative.isTrackingActive.mockResolvedValueOnce(true);

    const started = await plugin.startLocationTracking(VALID_CONFIG);

    expect(started).toBe(false);
    expect(warn).toHaveBeenCalledWith(expect.stringContaining('already active'));
    // The point of the ordering: a redundant start must not raise a permission
    // dialog at someone who is already being tracked.
    expect(mockNative.hasLocationPermissions).not.toHaveBeenCalled();
    expect(mockNative.startTracking).not.toHaveBeenCalled();
  });

  test('a second concurrent start is a no-op rather than a race', async () => {
    await configured();
    const warn = expectConsole('warn');
    let release: (value: boolean) => void = () => {};
    mockNative.startTracking.mockReturnValueOnce(
      new Promise<boolean>((resolve) => {
        release = resolve;
      })
    );

    const first = plugin.startLocationTracking(VALID_CONFIG);
    const second = await plugin.startLocationTracking(VALID_CONFIG);

    expect(second).toBe(false);
    expect(warn).toHaveBeenCalledWith(expect.stringContaining('already running'));
    release(true);
    expect(await first).toBe(true);
    expect(mockNative.startTracking).toHaveBeenCalledTimes(1);
  });
});

describe('startTracking trigger modes', () => {
  test('interval only omits distanceFilter entirely', async () => {
    await configured();
    await plugin.startLocationTracking({ userId: 'u', intervalMs: 8000 });

    const payload = mockNative.startTracking.mock.calls[0]![0];
    expect(payload.intervalMs).toBe(8000);
    // Absent, not zero: the SDK picks its trigger mode from which keys exist.
    expect('distanceFilter' in payload).toBe(false);
  });

  test('distance only omits intervalMs entirely', async () => {
    await configured();
    await plugin.startLocationTracking({ userId: 'u', distanceFilter: 25 });

    const payload = mockNative.startTracking.mock.calls[0]![0];
    expect(payload.distanceFilter).toBe(25);
    expect('intervalMs' in payload).toBe(false);
  });

  test('neither sends neither, leaving the SDK on its own defaults', async () => {
    await configured();
    await plugin.startLocationTracking({ userId: 'u' });

    const payload = mockNative.startTracking.mock.calls[0]![0];
    expect('intervalMs' in payload).toBe(false);
    expect('distanceFilter' in payload).toBe(false);
  });

  test('defaults match the plugin contract, not the raw SDK defaults', async () => {
    await configured();
    await plugin.startLocationTracking({ userId: 'u' });

    const payload = mockNative.startTracking.mock.calls[0]![0];
    // Both differ from the SDK's own defaults on purpose — see
    // LocationTrackingConfig.allowMockLocation.
    expect(payload.allowMockLocation).toBe(true);
    expect(payload.backgroundMode).toBe(true);
    expect(payload.enableSpeedFallback).toBe(true);
    expect(payload.enableSmartBattery).toBe(false);
    expect(payload.userId).toBe('u');
  });

  test('a zero distanceFilter is a value, not an absence', async () => {
    await configured();
    await plugin.startLocationTracking({ userId: 'u', distanceFilter: 0 });

    const payload = mockNative.startTracking.mock.calls[0]![0];
    expect(payload.distanceFilter).toBe(0);
  });
});

describe('argument shapes', () => {
  test('configureCacheLimits sends zeros for omitted fields', async () => {
    await configured();
    await plugin.configureCacheLimits({ batchSize: 25 });
    expect(mockNative.configureCacheLimits).toHaveBeenCalledWith(0, 0, 25);
  });

  test('getTrackingHistory applies its documented defaults', async () => {
    await configured();
    await plugin.getTrackingHistory({ userId: 'u', fromTimestamp: 1, toTimestamp: 2 });
    expect(mockNative.getTrackingHistory).toHaveBeenCalledWith(
      'u',
      1,
      2,
      1,
      100,
      undefined,
      false
    );
  });

  test('configureVehicle forwards positionally', async () => {
    await configured();
    await plugin.configureVehicle({
      vehicleId: 'v1',
      vehicleType: 2,
      seats: 7,
      weight: 1500,
      maxProvision: 3,
    });
    expect(mockNative.configureVehicle).toHaveBeenCalledWith('v1', 2, 7, 1500, 3);
  });

  test('processExternalLocation forwards positionally', async () => {
    await configured();
    await plugin.processExternalLocation({ lat: 10.5, lng: 106.6, speed: 12, heading: 45 });
    expect(mockNative.processExternalLocation).toHaveBeenCalledWith(10.5, 106.6, 12, 45);
  });
});

describe('history parsing', () => {
  test('reads rows from the top level, from data, and from data.items', async () => {
    await configured();

    mockNative.getTrackingHistory.mockResolvedValueOnce('[{"latitude":1}]');
    expect(await plugin.getTrackingHistory({ userId: 'u' })).toHaveLength(1);

    mockNative.getTrackingHistory.mockResolvedValueOnce('{"data":[{"latitude":2}]}');
    expect(await plugin.getTrackingHistory({ userId: 'u' })).toHaveLength(1);

    mockNative.getTrackingHistory.mockResolvedValueOnce(
      '{"data":{"items":[{"latitude":3}]}}'
    );
    expect(await plugin.getTrackingHistory({ userId: 'u' })).toHaveLength(1);
  });

  test('malformed JSON yields an empty list rather than throwing', async () => {
    await configured();
    const error = expectConsole('error');
    mockNative.getTrackingHistory.mockResolvedValueOnce('not json');

    expect(await plugin.getTrackingHistory({ userId: 'u' })).toEqual([]);
    // The log is part of the contract: swallowing bad JSON without a trace
    // would make a broken server response indistinguishable from an empty day.
    expect(error).toHaveBeenCalledWith(
      'Failed to parse tracking history:',
      expect.any(SyntaxError)
    );
  });
});

/**
 * These three bugs shared one cause: a native dictionary forwarded to JS without
 * anyone checking it against the type this API declares. The TurboModule spec
 * types those methods as `Promise<Object>`, which accepts anything, so the
 * compiler stayed silent while iOS returned six fewer fields than promised.
 *
 * The mocks below therefore return each PLATFORM's real shape, not an idealised
 * one — a test that mocks the shape it wants to see cannot catch this class of
 * bug.
 */
describe('object shapes match the declared types', () => {
  /** Milliseconds since the epoch are above this; seconds are far below it. */
  const MS_FLOOR = 1_000_000_000_000;

  test('getTrackingStatus carries trackingDuration on both platforms', async () => {
    await configured();

    // Android assembles this itself; iOS gets it from the SDK. Both in ms.
    mockNative.getTrackingStatus.mockResolvedValueOnce({
      isTracking: true,
      trackingDuration: 45_000,
      lastLocationUpdate: 1_790_000_000_000,
    });

    const status = await plugin.getTrackingStatus();
    expect(typeof status.trackingDuration).toBe('number');
    expect(status.lastLocationUpdate).toBeGreaterThan(MS_FLOOR);
  });

  test('getTrackingHealthStatus carries all eight declared fields', async () => {
    await configured();
    mockNative.getTrackingHealthStatus.mockResolvedValueOnce({
      isTracking: true,
      hasLocationPermission: true,
      hasBackgroundPermission: false,
      trackingDuration: 45_000,
      timeSinceLastUpdate: 3_000,
      isInitialized: true,
      lastLocationUpdate: 1_790_000_000_000,
      timestamp: 1_790_000_003_000,
      raw: { desiredAccuracy: -1 },
    });

    const health = await plugin.getTrackingHealthStatus();
    for (const field of [
      'isTracking',
      'hasLocationPermission',
      'hasBackgroundPermission',
      'trackingDuration',
      'timeSinceLastUpdate',
      'isInitialized',
      'timestamp',
    ] as const) {
      expect(health[field]).toBeDefined();
    }
    // Absolute timestamps are milliseconds; durations are millisecond spans and
    // are small, so only the former can be range-checked.
    expect(health.timestamp).toBeGreaterThan(MS_FLOOR);
    expect(health.lastLocationUpdate).toBeGreaterThan(MS_FLOOR);
  });

  test('-1 means no fix yet, not a 56-year-old one', async () => {
    await configured();
    mockNative.getTrackingHealthStatus.mockResolvedValueOnce({
      isTracking: false,
      hasLocationPermission: true,
      hasBackgroundPermission: false,
      trackingDuration: 0,
      timeSinceLastUpdate: -1,
      isInitialized: true,
      timestamp: 1_790_000_003_000,
    });

    const health = await plugin.getTrackingHealthStatus();
    // The SDK's own health dictionary subtracts an unset lastLocationUpdate from
    // now, which yields the whole epoch. The bridge derives this instead.
    expect(health.timeSinceLastUpdate).toBe(-1);
    expect(health.lastLocationUpdate).toBeUndefined();
  });
});

describe('notification permission', () => {
  test('request forwards to native', async () => {
    await expect(plugin.requestNotificationPermission()).resolves.toBe(true);
    expect(mockNative.requestNotificationPermission).toHaveBeenCalled();
  });

  test('has forwards to native', async () => {
    await expect(plugin.hasNotificationPermission()).resolves.toBe(false);
    expect(mockNative.hasNotificationPermission).toHaveBeenCalled();
  });

  test('neither requires the SDK to be configured', async () => {
    // Permission is a platform concern, not an SDK one: an app should be able
    // to ask before it has credentials.
    jest.resetModules();
    const fresh = require('../index');
    await expect(fresh.hasNotificationPermission()).resolves.toBe(false);
    await expect(fresh.requestNotificationPermission()).resolves.toBe(true);
  });
});

describe('fake GPS policy', () => {
  test.each(['skip', 'warn', 'stopTracking', 'logToServer'] as const)(
    'forwards %s',
    async (policy) => {
      await plugin.setFakeGPSPolicy(policy);
      expect(mockNative.setFakeGPSPolicy).toHaveBeenCalledWith(policy);
    }
  );
});
