import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';
import type { LocationTrackingConfig } from './types';

export interface Spec extends TurboModule {
  multiply(a: number, b: number): number;

  // GPS Tracking methods
  startLocationTracking(config: LocationTrackingConfig): Promise<boolean>;
  stopLocationTracking(): Promise<boolean>;
  getCurrentLocation(): Promise<Object>;
  isTrackingActive(): boolean;
  getTrackingStatus(): Promise<Object>;

  // Configuration methods
  updateTrackingConfig(config: LocationTrackingConfig): Promise<boolean>;

  // Permission methods
  requestLocationPermissions(): Promise<string>;
  hasLocationPermissions(): Promise<boolean>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('RnVietmapTrackingPlugin');
