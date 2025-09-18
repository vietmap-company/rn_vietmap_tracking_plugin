//
//  RnVietmapTrackingPlugin.m
//  RnVietmapTrackingPlugin
//
//  Created by VietMap on 7/7/2025.
//

#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

#ifdef RCT_NEW_ARCH_ENABLED
#import <RnVietmapTrackingPluginSpec/RnVietmapTrackingPluginSpec.h>
@interface RCT_EXTERN_MODULE(RnVietmapTrackingPlugin, RCTEventEmitter) <NativeRnVietmapTrackingPluginSpec>
#else
@interface RCT_EXTERN_MODULE(RnVietmapTrackingPlugin, RCTEventEmitter)
#endif

// Support both naming conventions
@interface RCT_EXTERN_MODULE(RNVietmapTrackingPlugin, RCTEventEmitter)
@end

RCT_EXTERN_METHOD(multiply:(double)a b:(double)b)

// Enhanced tracking methods for background_location_2 strategy
RCT_EXTERN_METHOD(startTracking:(BOOL)backgroundMode
                  intervalMs:(int)intervalMs
                  distanceFilter:(double)distanceFilter
                  notificationTitle:(NSString *)notificationTitle
                  notificationMessage:(NSString *)notificationMessage
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(stopTracking:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(getCurrentLocation:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(isTrackingActive:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(getTrackingStatus:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(updateTrackingConfig:(NSDictionary *)config
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(requestLocationPermissions:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(hasLocationPermissions:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(requestAlwaysLocationPermissions:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

// Speed alert methods
RCT_EXTERN_METHOD(turnOnAlert:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(turnOffAlert:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

// Route and Alert Processing methods
RCT_EXTERN_METHOD(processRouteData:(NSDictionary *)routeJson
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(getCurrentRouteInfo:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(findNearestAlert:(double)latitude
                  longitude:(double)longitude
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(checkSpeedViolation:(double)currentSpeed
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

// Route boundary detection and API management methods
RCT_EXTERN_METHOD(setRouteAPIEndpoint:(NSString *)endpoint
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(enableRouteBoundaryDetection:(double)threshold
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

// Configuration methods
RCT_EXTERN_METHOD(configure:(NSString *)apiKey
                  baseURL:(NSString *)baseURL
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(configureAlertAPI:(NSString *)apiKey
                  apiID:(NSString *)apiID
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

// Data management methods
RCT_EXTERN_METHOD(encodeLocationData:(NSDictionary *)locationDict
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(decodeLocationData:(NSString *)base64String
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(getCachedLocationsCount:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(uploadCachedLocationsManually:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(clearCachedLocations:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

// Utility methods
RCT_EXTERN_METHOD(getTrackingHealthStatus:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(isNetworkConnected:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(setTrackingStatus:(NSString *)status
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(setAutoUpload:(BOOL)enabled
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

+ (BOOL)requiresMainQueueSetup
{
  return YES;
}

- (NSArray<NSString *> *)supportedEvents
{
  return @[@"onLocationUpdate", @"onTrackingStatusChanged", @"onLocationError", @"onPermissionChanged", @"onRouteUpdate"];
}

@end
