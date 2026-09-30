import { useEffect } from 'react';
import { SafeAreaView, ScrollView, StatusBar, StyleSheet, Text, View } from 'react-native';
import {
  addLocationUpdateListener,
  addTrackingStatusListener,
  addLocationErrorListener,
  addFakeGPSDetectedListener,
  addTrackingInterruptedListener,
} from '@vietmap/rn_vietmap_tracking_plugin';
import { useTrackingStore } from './store/trackingStore';
import { Banner } from './components/ui';
import { PermissionCard } from './components/PermissionCard';
import { IdentityCard } from './components/IdentityCard';
import { ConfigCard } from './components/ConfigCard';
import { ControlsCard } from './components/ControlsCard';
import { LocationCard } from './components/LocationCard';
import { SessionStatsCard } from './components/SessionStatsCard';
import { LocationHistoryCard } from './components/LocationHistoryCard';
import { TrackingStatusCard } from './components/TrackingStatusCard';
import { CacheCard } from './components/CacheCard';
import { PackagesCard } from './components/PackagesCard';
import { FakeGpsCard } from './components/FakeGpsCard';
import { TrackingInterruptedCard } from './components/TrackingInterruptedCard';
import { SmartBatteryCard } from './components/SmartBatteryCard';
import { HistoryCard } from './components/HistoryCard';
import { GpxReplayCard } from './components/GpxReplayCard';

// Credentials live here, the way the Flutter example keeps them in main.dart:
// passed as parameters, not read from a module constant inside the plugin and
// not typed into the UI.
//
// Replace API_KEY before running. There is deliberately no placeholder check in
// render: initializeTracking validates the key against the server and rejects
// INVALID_API_KEY, which the initError banner below already shows — a real
// message from the server beats a string comparison, and comparing a `const`
// against a literal it can never equal is dead code the compiler rejects.
const API_KEY = 'YOUR_API_KEY_HERE';
const BASE_URL = 'YOUR_BASE_URL_HERE';

export default function GPSTrackingDemo() {
  const initialize = useTrackingStore((s) => s.initialize);
  const restorePersisted = useTrackingStore((s) => s.restorePersisted);
  const initError = useTrackingStore((s) => s.initError);
  const degradedReason = useTrackingStore((s) => s.degradedReason);
  const lastError = useTrackingStore((s) => s.lastError);
  const pushLocation = useTrackingStore((s) => s.pushLocation);
  const pushLocationError = useTrackingStore((s) => s.pushLocationError);
  const setIsTracking = useTrackingStore((s) => s.setIsTracking);
  const pushFakeGpsEvent = useTrackingStore((s) => s.pushFakeGpsEvent);
  const pushInterruptedEvent = useTrackingStore((s) => s.pushInterruptedEvent);

  useEffect(() => {
    // Restore first, so a saved userId is in place before anything reads it.
    // initialize() does not depend on it, but starting tracking does, and this
    // removes the retyping that made every test run start the same way.
    restorePersisted().finally(() => initialize(API_KEY, BASE_URL));
  }, [restorePersisted, initialize]);

  useEffect(() => {
    // No AppState wiring here on purpose. The plugin observes app state
    // natively on both platforms — UIApplication notifications on iOS,
    // LifecycleEventListener on Android — so adding a JS path would deliver
    // every transition twice.
    const subscriptions = [
      addLocationUpdateListener(pushLocation),
      addTrackingStatusListener((status) => setIsTracking(status.isTracking)),
      addLocationErrorListener((error) => pushLocationError(error.message)),
      addFakeGPSDetectedListener(pushFakeGpsEvent),
      addTrackingInterruptedListener(pushInterruptedEvent),
    ];
    return () => subscriptions.forEach((subscription) => subscription.remove());
  }, [
    pushLocation,
    setIsTracking,
    pushLocationError,
    pushFakeGpsEvent,
    pushInterruptedEvent,
  ]);

  return (
    <SafeAreaView style={styles.safe}>
      <StatusBar barStyle="dark-content" />
      <ScrollView contentContainerStyle={styles.scroll}>
        <View style={styles.titleWrap}>
          <Text style={styles.title}>Vietmap Tracking</Text>
          <Text style={styles.subtitle}>React Native plugin example</Text>
        </View>

        {initError && <Banner tone="error">Configure failed: {initError}</Banner>}
        {degradedReason && (
          <Banner tone="warn">
            Tracking runs, uploads may not. Key validation failed
            ({degradedReason}), so the SDK was configured without it. GPS
            collection and the on-device history work; fixes queue in the cache
            and drain only once the host is reachable. Watch "Pending uploads"
            below — if it only grows, nothing is landing on the server.
          </Banner>
        )}
        {lastError && <Banner tone="warn">{lastError}</Banner>}

        <PermissionCard />
        <IdentityCard />
        <ConfigCard />
        <ControlsCard />
        <HistoryCard />
        <LocationHistoryCard />
        <LocationCard />
        <SessionStatsCard />
        <TrackingStatusCard />
        <CacheCard />
        <PackagesCard />
        <FakeGpsCard />
        <TrackingInterruptedCard />
        <SmartBatteryCard />
        <GpxReplayCard />
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#f6f8fa' },
  scroll: { paddingVertical: 16 },
  titleWrap: { paddingHorizontal: 16, marginBottom: 16 },
  title: { fontSize: 24, fontWeight: '700', color: '#1f2328' },
  subtitle: { fontSize: 14, color: '#57606a', marginTop: 2 },
});
