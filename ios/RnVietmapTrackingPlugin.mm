#import "RnVietmapTrackingPlugin.h"
#import <React/RCTLog.h>

@implementation RnVietmapTrackingPlugin
RCT_EXPORT_MODULE()

- (instancetype)init {
    self = [super init];
    if (self) {
        self.locationManager = [[CLLocationManager alloc] init];
        self.locationManager.delegate = self;
        self.isTracking = NO;
        self.trackingStartTime = 0;
        self.lastLocationUpdate = 0;
    }
    return self;
}

+ (BOOL)requiresMainQueueSetup {
    return YES;
}

- (NSArray<NSString *> *)supportedEvents {
    return @[@"onLocationUpdate", @"onTrackingStatusChanged"];
}

- (NSNumber *)multiply:(double)a b:(double)b {
    NSNumber *result = @(a * b);
    return result;
}

RCT_EXPORT_METHOD(startLocationTracking:(NSDictionary *)config
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {

    // Check location permissions
    CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
    if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
        reject(@"PERMISSION_DENIED", @"Location permissions are required", nil);
        return;
    }

    // Request permissions if not granted
    if (status == kCLAuthorizationStatusNotDetermined) {
        [self.locationManager requestWhenInUseAuthorization];
        // Will be handled in delegate method
        reject(@"PERMISSION_PENDING", @"Location permission request pending", nil);
        return;
    }

    // Extract configuration values
    NSString *accuracy = config[@"accuracy"] ?: @"high";
    double distanceFilter = [config[@"distanceFilter"] doubleValue] ?: 10.0;
    BOOL backgroundMode = [config[@"backgroundMode"] boolValue] ?: NO;

    // Configure location manager
    self.locationManager.desiredAccuracy = [self getAccuracyFromString:accuracy];
    self.locationManager.distanceFilter = distanceFilter;

    // Start location updates
    [self.locationManager startUpdatingLocation];

    // Request background location if needed
    if (backgroundMode && status != kCLAuthorizationStatusAuthorizedAlways) {
        [self.locationManager requestAlwaysAuthorization];
    }

    if (backgroundMode) {
        [self.locationManager startMonitoringSignificantLocationChanges];
    }

    self.isTracking = YES;
    self.trackingStartTime = [[NSDate date] timeIntervalSince1970];

    [self sendTrackingStatusUpdate];
    resolve(@YES);
}

RCT_EXPORT_METHOD(stopLocationTracking:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {

    [self.locationManager stopUpdatingLocation];
    [self.locationManager stopMonitoringSignificantLocationChanges];

    self.isTracking = NO;
    [self sendTrackingStatusUpdate];

    resolve(@YES);
}

RCT_EXPORT_METHOD(getCurrentLocation:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {

    CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
    if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
        reject(@"PERMISSION_DENIED", @"Location permissions are required", nil);
        return;
    }

    CLLocation *location = self.locationManager.location;
    if (location) {
        NSDictionary *locationDict = [self locationToDictionary:location];
        resolve(locationDict);
    } else {
        reject(@"LOCATION_UNAVAILABLE", @"Unable to get current location", nil);
    }
}

RCT_EXPORT_METHOD(isTrackingActive:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(@(self.isTracking));
}

RCT_EXPORT_METHOD(getTrackingStatus:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {

    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval duration = self.isTracking ? (currentTime - self.trackingStartTime) : 0;

    NSDictionary *status = @{
        @"isTracking": @(self.isTracking),
        @"trackingDuration": @(duration * 1000), // Convert to milliseconds
        @"lastLocationUpdate": self.lastLocationUpdate > 0 ? @(self.lastLocationUpdate * 1000) : [NSNull null]
    };

    resolve(status);
}

RCT_EXPORT_METHOD(updateTrackingConfig:(NSDictionary *)config
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {

    if (!self.isTracking) {
        reject(@"NOT_TRACKING", @"Location tracking is not active", nil);
        return;
    }

    // Extract configuration values
    NSString *accuracy = config[@"accuracy"] ?: @"high";
    double distanceFilter = [config[@"distanceFilter"] doubleValue] ?: 10.0;

    // Update configuration
    self.locationManager.desiredAccuracy = [self getAccuracyFromString:accuracy];
    self.locationManager.distanceFilter = distanceFilter;

    resolve(@YES);
}

RCT_EXPORT_METHOD(requestLocationPermissions:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {

    CLAuthorizationStatus status = [CLLocationManager authorizationStatus];

    switch (status) {
        case kCLAuthorizationStatusAuthorizedWhenInUse:
        case kCLAuthorizationStatusAuthorizedAlways:
            resolve(@"granted");
            break;
        case kCLAuthorizationStatusDenied:
        case kCLAuthorizationStatusRestricted:
            resolve(@"denied");
            break;
        case kCLAuthorizationStatusNotDetermined:
             [self.locationManager requestWhenInUseAuthorization];
            resolve(@"pending");
            break;
    }
}

RCT_EXPORT_METHOD(hasLocationPermissions:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {

    CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
    BOOL hasPermission = (status == kCLAuthorizationStatusAuthorizedWhenInUse ||
                         status == kCLAuthorizationStatusAuthorizedAlways);

    resolve(@(hasPermission));
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *location = locations.lastObject;
    if (location) {
        self.lastLocationUpdate = [[NSDate date] timeIntervalSince1970];

        NSDictionary *locationDict = [self locationToDictionary:location];
        [self sendEventWithName:@"onLocationUpdate" body:locationDict];
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    RCTLogError(@"Location manager failed with error: %@", error.localizedDescription);
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    RCTLogInfo(@"Location authorization status changed to: %d", status);
}

#pragma mark - Helper Methods

- (CLLocationAccuracy)getAccuracyFromString:(NSString *)accuracy {
    if ([accuracy isEqualToString:@"high"]) {
        return kCLLocationAccuracyBest;
    } else if ([accuracy isEqualToString:@"medium"]) {
        return kCLLocationAccuracyHundredMeters;
    } else if ([accuracy isEqualToString:@"low"]) {
        return kCLLocationAccuracyKilometer;
    }
    return kCLLocationAccuracyBest;
}

- (NSDictionary *)locationToDictionary:(CLLocation *)location {
    return @{
        @"latitude": @(location.coordinate.latitude),
        @"longitude": @(location.coordinate.longitude),
        @"altitude": @(location.altitude),
        @"accuracy": @(location.horizontalAccuracy),
        @"speed": @(location.speed),
        @"bearing": @(location.course),
        @"timestamp": @([location.timestamp timeIntervalSince1970] * 1000)
    };
}

- (void)sendTrackingStatusUpdate {
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval duration = self.isTracking ? (currentTime - self.trackingStartTime) : 0;

    NSDictionary *status = @{
        @"isTracking": @(self.isTracking),
        @"trackingDuration": @(duration * 1000),
        @"lastLocationUpdate": self.lastLocationUpdate > 0 ? @(self.lastLocationUpdate * 1000) : [NSNull null]
    };

    [self sendEventWithName:@"onTrackingStatusChanged" body:status];
}

@end
