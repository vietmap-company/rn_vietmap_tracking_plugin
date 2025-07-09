import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export interface Spec extends TurboModule {
  multiply(a: number, b: number): number;

  // Enhanced tracking methods for background_location_2 strategy
  startTracking(backgroundMode: boolean, intervalMs: number): Promise<string>;
  stopTracking(): Promise<string>;

  getCurrentLocation(): Promise<Object>;
  isTrackingActive(): boolean;
  getTrackingStatus(): Promise<Object>;

  // Configuration methods
  updateTrackingConfig(config: Object): Promise<boolean>;

  // Permission methods
  requestLocationPermissions(): Promise<string>;
  hasLocationPermissions(): Promise<boolean>;
  requestAlwaysLocationPermissions(): Promise<string>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('RnVietmapTrackingPlugin');
