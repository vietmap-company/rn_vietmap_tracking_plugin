# Hướng dẫn sử dụng GPS Tracking Package

## Tổng quan

Package `rn_vietmap_tracking_plugin` cung cấp các chức năng theo dõi GPS chạy nền cho React Native với hiệu suất tối ưu thông qua implementation native.

## Các tính năng chính

✅ **Theo dõi GPS chạy nền** - Hoạt động ngay cả khi app không active
✅ **Cấu hình linh hoạt** - Có thể config thời gian cập nhật, độ chính xác
✅ **Hiệu suất cao** - Implementation native cho Android & iOS
✅ **Quản lý permission** - Tự động xử lý quyền truy cập location
✅ **Event-driven** - Nhận updates real-time qua event listeners
✅ **Tối ưu pin** - Smart power management

## Cài đặt và setup

### 1. Cài đặt package

```bash
npm install rn_vietmap_tracking_plugin
# hoặc
yarn add rn_vietmap_tracking_plugin
```

### 2. Setup iOS

Thêm vào file `Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>App cần quyền truy cập vị trí để theo dõi GPS</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>App cần quyền truy cập vị trí để theo dõi GPS ngay cả khi app chạy nền</string>
<key>NSLocationAlwaysUsageDescription</key>
<string>App cần quyền truy cập vị trí để theo dõi GPS chạy nền</string>
```

### 3. Setup Android

Thêm vào `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
```

## Sử dụng cơ bản

### 1. Import các functions cần thiết

```typescript
import {
  startLocationTracking,
  stopLocationTracking,
  getCurrentLocation,
  addLocationUpdateListener,
  requestLocationPermissions,
  createDefaultConfig,
  type LocationData,
  type LocationTrackingConfig
} from 'rn_vietmap_tracking_plugin';
```

### 2. Xin quyền truy cập location

```typescript
const requestPermissions = async () => {
  try {
    const result = await requestLocationPermissions();
    if (result === 'granted') {
      console.log('Đã cấp quyền truy cập location');
      return true;
    } else {
      console.log('Người dùng từ chối quyền truy cập');
      return false;
    }
  } catch (error) {
    console.error('Lỗi khi xin quyền:', error);
    return false;
  }
};
```

### 3. Bắt đầu theo dõi GPS

```typescript
const startTracking = async () => {
  // Tạo config mặc định (cập nhật mỗi 5 giây)
  const config = createDefaultConfig(5000);

  // Hoặc config tùy chỉnh
  const customConfig: LocationTrackingConfig = {
    intervalMs: 10000,              // Cập nhật mỗi 10 giây
    distanceFilter: 50,             // Chỉ cập nhật khi di chuyển >= 50m
    accuracy: 'high',               // Độ chính xác cao
    backgroundMode: true,           // Chạy nền
    notificationTitle: 'Đang theo dõi',
    notificationMessage: 'Ứng dụng đang theo dõi vị trí của bạn'
  };

  try {
    const success = await startLocationTracking(customConfig);
    if (success) {
      console.log('Bắt đầu theo dõi GPS thành công');
    }
  } catch (error) {
    console.error('Lỗi khi bắt đầu theo dõi:', error);
  }
};
```

### 4. Lắng nghe cập nhật vị trí

```typescript
import { useEffect } from 'react';

const LocationTracker = () => {
  useEffect(() => {
    // Lắng nghe cập nhật vị trí
    const locationSubscription = addLocationUpdateListener((location: LocationData) => {
      console.log('Vị trí mới:', {
        latitude: location.latitude,
        longitude: location.longitude,
        accuracy: location.accuracy,
        speed: location.speed,
        timestamp: new Date(location.timestamp)
      });

      // Xử lý dữ liệu location ở đây
      // Ví dụ: gửi lên server, lưu vào database, etc.
    });

    // Cleanup khi component unmount
    return () => {
      locationSubscription.remove();
    };
  }, []);

  return null;
};
```

### 5. Dừng theo dõi GPS

```typescript
const stopTracking = async () => {
  try {
    const success = await stopLocationTracking();
    if (success) {
      console.log('Đã dừng theo dõi GPS');
    }
  } catch (error) {
    console.error('Lỗi khi dừng theo dõi:', error);
  }
};
```

## Ví dụ component hoàn chỉnh

```typescript
import React, { useState, useEffect } from 'react';
import { View, Text, Button, Alert } from 'react-native';
import {
  startLocationTracking,
  stopLocationTracking,
  getCurrentLocation,
  addLocationUpdateListener,
  requestLocationPermissions,
  hasLocationPermissions,
  createDefaultConfig,
  type LocationData
} from 'rn_vietmap_tracking_plugin';

const GPSTracker = () => {
  const [isTracking, setIsTracking] = useState(false);
  const [currentLocation, setCurrentLocation] = useState<LocationData | null>(null);
  const [hasPermission, setHasPermission] = useState(false);

  useEffect(() => {
    checkPermissions();

    const locationSubscription = addLocationUpdateListener((location: LocationData) => {
      setCurrentLocation(location);
      console.log('New location:', location);
    });

    return () => {
      locationSubscription.remove();
    };
  }, []);

  const checkPermissions = async () => {
    const permissions = await hasLocationPermissions();
    setHasPermission(permissions);
  };

  const handleRequestPermissions = async () => {
    const result = await requestLocationPermissions();
    if (result === 'granted') {
      setHasPermission(true);
      Alert.alert('Thành công', 'Đã cấp quyền truy cập vị trí');
    }
  };

  const handleStartTracking = async () => {
    if (!hasPermission) {
      Alert.alert('Lỗi', 'Cần cấp quyền truy cập vị trí trước');
      return;
    }

    try {
      const config = createDefaultConfig(5000); // 5 giây
      const success = await startLocationTracking(config);
      if (success) {
        setIsTracking(true);
        Alert.alert('Thành công', 'Đã bắt đầu theo dõi GPS');
      }
    } catch (error) {
      Alert.alert('Lỗi', 'Không thể bắt đầu theo dõi GPS');
    }
  };

  const handleStopTracking = async () => {
    try {
      const success = await stopLocationTracking();
      if (success) {
        setIsTracking(false);
        Alert.alert('Thành công', 'Đã dừng theo dõi GPS');
      }
    } catch (error) {
      Alert.alert('Lỗi', 'Không thể dừng theo dõi GPS');
    }
  };

  const handleGetCurrentLocation = async () => {
    try {
      const location = await getCurrentLocation();
      setCurrentLocation(location);
      Alert.alert('Vị trí hiện tại', `${location.latitude}, ${location.longitude}`);
    } catch (error) {
      Alert.alert('Lỗi', 'Không thể lấy vị trí hiện tại');
    }
  };

  return (
    <View style={{ padding: 20 }}>
      <Text style={{ fontSize: 20, marginBottom: 20 }}>GPS Tracker</Text>

      <Text>Quyền truy cập: {hasPermission ? 'Đã cấp' : 'Chưa cấp'}</Text>
      <Text>Trạng thái: {isTracking ? 'Đang theo dõi' : 'Không theo dõi'}</Text>

      {!hasPermission && (
        <Button title="Xin quyền truy cập" onPress={handleRequestPermissions} />
      )}

      <Button
        title={isTracking ? 'Dừng theo dõi' : 'Bắt đầu theo dõi'}
        onPress={isTracking ? handleStopTracking : handleStartTracking}
        disabled={!hasPermission}
      />

      <Button
        title="Lấy vị trí hiện tại"
        onPress={handleGetCurrentLocation}
        disabled={!hasPermission}
      />

      {currentLocation && (
        <View style={{ marginTop: 20 }}>
          <Text>Vị trí hiện tại:</Text>
          <Text>Latitude: {currentLocation.latitude.toFixed(6)}</Text>
          <Text>Longitude: {currentLocation.longitude.toFixed(6)}</Text>
          <Text>Độ chính xác: {currentLocation.accuracy.toFixed(2)}m</Text>
          <Text>Tốc độ: {currentLocation.speed.toFixed(2)} m/s</Text>
          <Text>Thời gian: {new Date(currentLocation.timestamp).toLocaleString()}</Text>
        </View>
      )}
    </View>
  );
};

export default GPSTracker;
```

## Các config thường dùng

### 1. Cho navigation/chỉ đường
```typescript
const navigationConfig = {
  intervalMs: 1000,          // Cập nhật mỗi 1 giây
  distanceFilter: 5,         // Cập nhật khi di chuyển >= 5m
  accuracy: 'high',          // Độ chính xác cao nhất
  backgroundMode: true,
  notificationTitle: 'Đang dẫn đường',
  notificationMessage: 'Ứng dụng đang theo dõi lộ trình'
};
```

### 2. Cho theo dõi thể dục
```typescript
const fitnessConfig = {
  intervalMs: 5000,          // Cập nhật mỗi 5 giây
  distanceFilter: 10,        // Cập nhật khi di chuyển >= 10m
  accuracy: 'high',          // Độ chính xác cao
  backgroundMode: true,
  notificationTitle: 'Đang ghi lại bài tập',
  notificationMessage: 'Theo dõi quãng đường và tốc độ'
};
```

### 3. Cho theo dõi tổng quát (tiết kiệm pin)
```typescript
const generalConfig = {
  intervalMs: 30000,         // Cập nhật mỗi 30 giây
  distanceFilter: 50,        // Cập nhật khi di chuyển >= 50m
  accuracy: 'medium',        // Độ chính xác trung bình
  backgroundMode: true,
  notificationTitle: 'Theo dõi vị trí',
  notificationMessage: 'Ứng dụng đang theo dõi vị trí'
};
```

## Lưu ý quan trọng

1. **Quyền truy cập**: Luôn kiểm tra và xin quyền truy cập location trước khi bắt đầu tracking
2. **Battery optimization**: Sử dụng config phù hợp để tối ưu pin
3. **Cleanup**: Nhớ remove event listeners khi component unmount
4. **Error handling**: Luôn handle errors khi gọi async functions
5. **Background mode**: Trên iOS, background location yêu cầu quyền "Always" location

## Troubleshooting

### Lỗi thường gặp:

1. **"Permission denied"**: Kiểm tra quyền truy cập location
2. **"Location unavailable"**: Kiểm tra GPS có bật không
3. **Background không hoạt động**: Kiểm tra cài đặt background app refresh (iOS) hoặc battery optimization (Android)

### Tips:

- Test trên thiết bị thật, không phải simulator
- Kiểm tra settings GPS/Location services đã bật
- Trên Android, tắt battery optimization cho app
- Trên iOS, cấp quyền "Always" location cho background tracking
