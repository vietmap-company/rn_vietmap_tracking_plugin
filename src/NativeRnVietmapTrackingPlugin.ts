import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';
import type { PermissionResult } from './types';

export interface Spec extends TurboModule {
  multiply(a: number, b: number): number;

  // Configuration methods
  configure(apiKey: string, baseURL?: string, autoUpload?: boolean): Promise<boolean>;
  configureAlertAPI(url: string, apiKey: string): Promise<boolean>;

  // Enhanced tracking methods for background_location_2 strategy
  startTracking(backgroundMode: boolean, intervalMs: number, forceUpdateBackground?: boolean, distanceFilter?: number): Promise<string>;
  stopTracking(): Promise<string>;

  getCurrentLocation(): Promise<Object>;
  isTrackingActive(): boolean;
  getTrackingStatus(): Promise<Object>;

  // Configuration methods
  updateTrackingConfig(config: Object): Promise<boolean>;

  // Permission methods - Updated to return PermissionResult
  requestLocationPermissions(): Promise<PermissionResult>;
  hasLocationPermissions(): Promise<PermissionResult>;
  requestAlwaysLocationPermissions(): Promise<string>;

  // Speed alert methods
  turnOnAlert(): Promise<boolean>;
  turnOffAlert(): Promise<boolean>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('RnVietmapTrackingPlugin');
