//
//  RnVietmapTrackingPlugin.m
//  RnVietmapTrackingPlugin
//
//  Created by VietMap on 7/7/2025.
//
//  NOTE ON RCT_EXTERN_METHOD
//  -------------------------
//  RCT_EXTERN_METHOD registers a selector on the bridge; it does NOT verify that
//  the Swift class implements it. A declaration without a matching @objc func
//  compiles cleanly and crashes at call time with "unrecognized selector".
//  Every method declared below MUST have an implementation in
//  RnVietmapTrackingPlugin.swift. See UPGRADE_PLAN.md, finding 10.
//

#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

#ifdef RCT_NEW_ARCH_ENABLED
#import <RnVietmapTrackingPluginSpec/RnVietmapTrackingPluginSpec.h>
@interface RCT_EXTERN_MODULE(RnVietmapTrackingPlugin, RCTEventEmitter) <NativeRnVietmapTrackingPluginSpec>
#else
@interface RCT_EXTERN_MODULE(RnVietmapTrackingPlugin, RCTEventEmitter)
#endif

RCT_EXTERN_METHOD(getPlatformVersion:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

// ── Configuration ───────────────────────────────────────────────────────────

RCT_EXTERN_METHOD(configure:(NSString *)apiKey
                  baseURL:(NSString *)baseURL
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

// Validates the key against the server before configuring, unlike configure:.
// authMode is 'header' or 'queryParam' and decides how the key travels on every
// upload path; a mismatch with the gateway turns every upload into a 401.
RCT_EXTERN_METHOD(initializeTracking:(NSString *)apiKey
                  baseURL:(NSString *)baseURL
                  authMode:(NSString *)authMode
                  autoUpload:(BOOL)autoUpload
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(configureAlertAPI:(NSString *)apiKey
                  apiID:(NSString *)apiID
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

// ── Identity written into the GPS upload payload ────────────────────────────
// setDriverId maps to userId and is required before tracking starts.

RCT_EXTERN_METHOD(setDriverId:(NSString *)driverId
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(getDriverId:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(setVehicleId:(NSString *)vehicleId
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(getVehicleId:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(setMetadata:(NSDictionary *)metadata
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(setPackages:(NSArray *)packages
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(setAppSignature:(NSString *)signature
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(configureVehicle:(NSString *)vehicleId
                  vehicleType:(NSInteger)vehicleType
                  seats:(NSInteger)seats
                  weight:(double)weight
                  maxProvision:(NSInteger)maxProvision
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

// ── Tracking ────────────────────────────────────────────────────────────────
// startTracking takes a dictionary rather than positional arguments: it carries
// nine settings, and a selector that long is exactly how this declaration
// drifts out of step with its Swift implementation.

RCT_EXTERN_METHOD(startTracking:(NSDictionary *)config
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(stopTracking:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(updateTrackingConfig:(NSDictionary *)config
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(getCurrentLocation:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(isTrackingActive:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(getTrackingStatus:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(getTrackingHealthStatus:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

// Timestamps are milliseconds.
RCT_EXTERN_METHOD(getTrackingHistory:(NSString *)userId
                  fromTimestamp:(double)fromTimestamp
                  toTimestamp:(double)toTimestamp
                  pageNumber:(NSInteger)pageNumber
                  pageSize:(NSInteger)pageSize
                  sortBy:(NSString *)sortBy
                  sortDescending:(BOOL)sortDescending
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

// ── Permissions ─────────────────────────────────────────────────────────────

RCT_EXTERN_METHOD(requestLocationPermissions:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(hasLocationPermissions:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(requestAlwaysLocationPermissions:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

// ── Offline cache and upload ────────────────────────────────────────────────

RCT_EXTERN_METHOD(isNetworkConnected:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(getCachedLocationsCount:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(uploadCachedLocationsManually:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(clearCachedLocations:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

// maxDbSizeBytes exceeds 2^31, so it crosses as a double rather than an int.
RCT_EXTERN_METHOD(configureCacheLimits:(NSInteger)maxRecords
                  maxDbSizeBytes:(double)maxDbSizeBytes
                  batchSize:(NSInteger)batchSize
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(getDatabaseSizeBytes:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

// ── Lifecycle ───────────────────────────────────────────────────────────────
// Driven natively from UIApplication notifications; exposed for a host app that
// manages app state itself.

RCT_EXTERN_METHOD(onAppBackground:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(onAppForeground:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(setAutoUpload:(BOOL)enabled
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

// ── Notification permission ─────────────────────────────────────────────────
// The SDK posts its own notifications and requires the host app to hold
// authorization; iOS never prompts on post, so without this they are dropped.

RCT_EXTERN_METHOD(requestNotificationPermission:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(hasNotificationPermission:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

// ── Fake GPS ────────────────────────────────────────────────────────────────
// allowMockLocation is a startTracking key; these only shape what happens once
// detection is on.

RCT_EXTERN_METHOD(setFakeGPSPolicy:(NSString *)policy
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(setFakeGpsNotificationConfig:(NSString *)title
                  message:(NSString *)message
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

// ── Tracking interrupted ────────────────────────────────────────────────────

RCT_EXTERN_METHOD(setTrackingInterruptedNotificationEnabled:(BOOL)enabled
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(setTrackingInterruptedNotificationConfig:(NSString *)title
                  message:(NSString *)message
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

// ── Smart battery ───────────────────────────────────────────────────────────

RCT_EXTERN_METHOD(setSmartBatteryConfig:(BOOL)enabled
                  preset:(NSString *)preset
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

// ── External GPS injection ──────────────────────────────────────────────────

RCT_EXTERN_METHOD(processExternalLocation:(double)lat
                  lng:(double)lng
                  speed:(double)speed
                  heading:(double)heading
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

// ── Speed alert ─────────────────────────────────────────────────────────────

RCT_EXTERN_METHOD(turnOnAlert:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(turnOffAlert:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

// ── NativeEventEmitter conformance ──────────────────────────────────────────
// RCTEventEmitter already implements both; these declarations make them
// reachable from JS, which is what NativeEventEmitter checks for.

RCT_EXTERN_METHOD(addListener:(NSString *)eventName)
RCT_EXTERN_METHOD(removeListeners:(double)count)

// ============================================================================
// [ALERT-HIDDEN] Route processing and alert internals.
//
// Hidden, not removed. These wrap the C++ alert engine rather than the plugin
// layer's tracking surface, and the Flutter plugin does not expose them either.
// They were declared without a Swift implementation, so every one of them was a
// guaranteed crash. Restore this block if the alert surface is brought back.
// ============================================================================

// RCT_EXTERN_METHOD(processRouteData:(NSDictionary *)routeJson
//                   resolver:(RCTPromiseResolveBlock)resolve
//                   rejecter:(RCTPromiseRejectBlock)reject)
//
// RCT_EXTERN_METHOD(getCurrentRouteInfo:(RCTPromiseResolveBlock)resolve
//                   rejecter:(RCTPromiseRejectBlock)reject)
//
// RCT_EXTERN_METHOD(findNearestAlert:(double)latitude
//                   longitude:(double)longitude
//                   resolver:(RCTPromiseResolveBlock)resolve
//                   rejecter:(RCTPromiseRejectBlock)reject)
//
// RCT_EXTERN_METHOD(checkSpeedViolation:(double)currentSpeed
//                   resolver:(RCTPromiseResolveBlock)resolve
//                   rejecter:(RCTPromiseRejectBlock)reject)
//
// RCT_EXTERN_METHOD(setRouteAPIEndpoint:(NSString *)endpoint
//                   resolver:(RCTPromiseResolveBlock)resolve
//                   rejecter:(RCTPromiseRejectBlock)reject)
//
// RCT_EXTERN_METHOD(enableRouteBoundaryDetection:(double)threshold
//                   resolver:(RCTPromiseResolveBlock)resolve
//                   rejecter:(RCTPromiseRejectBlock)reject)
//
// RCT_EXTERN_METHOD(encodeLocationData:(NSDictionary *)locationDict
//                   resolver:(RCTPromiseResolveBlock)resolve
//                   rejecter:(RCTPromiseRejectBlock)reject)
//
// RCT_EXTERN_METHOD(decodeLocationData:(NSString *)base64String
//                   resolver:(RCTPromiseResolveBlock)resolve
//                   rejecter:(RCTPromiseRejectBlock)reject)

// ============================================================================
// [OUT-OF-SCOPE] setTrackingStatus.
//
// Exists in VietmapTrackingSDK 1.5.2 but the Flutter plugin does not expose it,
// and it had no Swift implementation here either. Left disabled.
// ============================================================================

// RCT_EXTERN_METHOD(setTrackingStatus:(NSString *)status
//                   resolver:(RCTPromiseResolveBlock)resolve
//                   rejecter:(RCTPromiseRejectBlock)reject)

@end

// NOTE: there is deliberately no category here.
//
// This file used to carry an `RnVietmapTrackingPlugin (Utils)` category
// redefining `requiresMainQueueSetup` and `supportedEvents`, both of which the
// Swift class already overrides. An Objective-C category method replaces the
// class's own implementation, and which one wins is not defined by the
// language — so the event list had two homes and adding an event in Swift
// alone could silently do nothing.
//
// Both live in RnVietmapTrackingPlugin.swift now, beside the sendEvent calls
// they describe. Do not reintroduce them here.
