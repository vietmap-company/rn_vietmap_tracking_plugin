#import <RnVietmapTrackingPluginSpec/RnVietmapTrackingPluginSpec.h>
#import <CoreLocation/CoreLocation.h>
#import <React/RCTEventEmitter.h>

// Swift integration
#if __has_include("RnVietmapTrackingPlugin-Swift.h")
#import "RnVietmapTrackingPlugin-Swift.h"
#endif

@interface RnVietmapTrackingPlugin : RCTEventEmitter <NativeRnVietmapTrackingPluginSpec, CLLocationManagerDelegate>

@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, assign) BOOL isTracking;
@property (nonatomic, assign) NSTimeInterval trackingStartTime;
@property (nonatomic, assign) NSTimeInterval lastLocationUpdate;

@end
