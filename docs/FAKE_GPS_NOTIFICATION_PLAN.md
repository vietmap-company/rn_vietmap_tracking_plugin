# Thông báo Fake GPS — vì sao React Native không hiện gì

Trace từ SDK đi lên, không phải từ plugin đi xuống. **Chưa thay đổi gì trong
code** — tài liệu này để kiểm định trước.

> Ghi chú: phần diễn giải bằng tiếng Việt, còn tên hàm, đường dẫn và đoạn code
> giữ nguyên tiếng Anh vì chúng được chép thẳng vào source.

## Trả lời ngắn

**SDK là nơi phát thông báo, không phải app.** React Native không hiện gì vì
**bốn cổng chặn độc lập**, mỗi cổng một mình đã đủ gây im lặng. Sửa một cổng
không đổi được gì khi ba cổng kia còn nguyên — đó chính là lý do triệu chứng
"không thấy thông báo" khó đọc.

Hai trong bốn cổng là thiếu sót của plugin/example. Hai cổng còn lại là **nghĩa
vụ mà app chủ nhà phải làm cho SDK** — example Flutter làm đủ, example RN thì
chưa.

## Cơ chế trong SDK

Cả hai nền đều tự đăng thông báo:

- iOS — `VietmapTrackingSDK.swift:3911`, hàm `showFakeGPSNotification(location:)`,
  gọi `UNUserNotificationCenter.current().add(...)`, dùng identifier cố định
  `vietmap.fakegps.alert` nên lần sau thay thế lần trước chứ không chồng đống.
- Android — `VietmapTrackingManager.java:1821`, hàm `showFakeGPSNotification`,
  tự tạo channel với `IMPORTANCE_HIGH`.

Chính doc comment của SDK iOS nói rõ hợp đồng:

> Requires host app to have already obtained UNUserNotificationCenter authorization.

Tức là SDK **đăng**, còn **app phải lo cho cái đăng đó được phép và nhìn thấy
được**.

Nơi gọi là `applyFakeGPSPolicy`, chỉ tới được sau khi qua cổng fake-GPS trong
`didUpdateLocations`, và **chỉ nhánh `"warn"` mới phát thông báo**:

```swift
switch fakeGPSPolicy {
case "warn":
    if isFirstDetection { showFakeGPSNotification(location: location) }
    processLocationForTracking(location: location, currentTime: now, isFake: true)
case "stopTracking": stopTracking { _, _ in }
case "logToServer":  processLocationForTracking(..., isFake: true)
case "skip": fallthrough
default:
    // print("🔕 [FakeGPS] Policy=skip — fake location silently dropped")
    break
}
```

Nhánh `skip` và `default` chỉ `break`: có phát hiện, có bắn callback ở đoạn phía
trên, nhưng không thông báo gì.

`isFirstDetection` chặn dội ở mức **một thông báo mỗi 30 giây**
(`fakeGPSNotifyIntervalSec` iOS `:891`; `FAKE_GPS_NOTIFY_INTERVAL_MS` trên
Android). Dòng fix giả liên tục sẽ ra một thông báo mỗi 30 giây, **không phải
mỗi fix một cái**.

## Bốn cổng chặn, theo thứ tự chúng chặn ta

### Cổng 1 — hoàn toàn không phát hiện, do `allowMockLocation: true`

Example mặc định `true`, nên `didUpdateLocations` không bao giờ đi vào nhánh
fake-GPS: không phát hiện, không có event `onFakeGPSDetected`, không thông báo,
và cũng không còn gì phía sau để cấu hình.

Mặc định này là cố ý và đã ghi chú: để `false` thì SDK loại bỏ mọi fix giả lập
và demo sẽ upload batch rỗng trên simulator. Nhưng hệ quả là **card Fake GPS
không bao giờ chạy được với cấu hình xuất xưởng**.

### Cổng 2 — policy đang là `skip`

`skip` là mặc định của SDK và cũng là mặc định của example. Nó phát hiện và báo
qua callback, nhưng **không thông báo gì**. Chỉ `"warn"` mới thông báo.

Nên dù đã mở cổng 1, policy vẫn phải là `warn`.

### Cổng 3 — chưa từng xin quyền thông báo

Không nền nào cấp ngầm quyền này.

- iOS: không có chỗ nào trong example gọi
  `UNUserNotificationCenter.requestAuthorization`. `add(...)` vì thế thất bại,
  và SDK chỉ `print` lỗi — vô hình ở bản release, rất dễ bỏ sót ở debug.
- Android 13+ (API 33): `POST_NOTIFICATIONS` là quyền runtime và **không được
  khai báo** trong `AndroidManifest.xml` của example. Đã kiểm chứng là thiếu.

Example Flutter làm cả hai: `permission_handler` trên Android, và
`IOSFlutterLocalNotificationsPlugin.requestPermissions(alert:sound:badge:)` trên
iOS (`tracking_provider.dart:937`).

### Cổng 4 — iOS ẩn thông báo khi app đang mở, nếu không có delegate

Đây là cổng tinh vi nhất, và là lý do **chỉ sửa quyền thôi thì lúc test vẫn thấy
hỏng**.

Trên iOS, một local notification đăng khi app đang ở **foreground** sẽ **không
được hiển thị** trừ khi có `UNUserNotificationCenterDelegate` cài đặt
`userNotificationCenter(_:willPresent:withCompletionHandler:)` và gọi completion
với `.banner`/`.list`/`.sound`. Không có delegate thì thông báo vẫn được giao
nhưng lặng lẽ không hiện.

`AppDelegate.swift` của example không set delegate nào — chỉ nối
`RCTReactNativeFactory`. Đã kiểm chứng.

Example Flutter có được điều này nhờ `flutter_local_notifications`, và comment
của chính nó nói đúng điểm này:

```dart
// defaultPresentAlert/Sound MUST be true so iOS shows banners when app is
// in the foreground. Per-notification presentAlert only overrides the default
// but the default must be enabled for the delegate to fire at all.
```

Chú ý điều này có nghĩa gì: Flutter **không** tự phát thông báo fake-GPS từ
Dart. Hàm `_onFakeGps` chỉ ghi lại event. Package đó có mặt để **xin quyền** và
**cung cấp delegate foreground**; SDK vẫn là nơi đăng thông báo.

## Kết quả kiểm định

Chạy ngày 2026-09-29. Cổng 1 và 2 đã được mở bằng tay trong example
(`allowMockLocation: false`, policy `warn`). **Không có pop-up xin quyền nào
xuất hiện.**

Đó là kết quả đúng như dự đoán, không phải lỗi, và được chốt bằng cách **đếm**
chứ không suy luận. Số chỗ gọi xin quyền thông báo:

| Tầng | `requestAuthorization` / `UNUserNotificationCenter` |
|---|---|
| `VietmapTrackingSDK.swift` | **0** |
| `RnVietmapTrackingPlugin.swift` (plugin) | **0** |
| `AppDelegate.swift` (example) | **0** |

Những chỗ `authorizationStatus` duy nhất trong SDK là của `CLLocationManager` —
quyền vị trí, không phải quyền thông báo.

**iOS không bao giờ bật pop-up khi gọi `add()`.** Với trạng thái
`.notDetermined`, bản đăng bị bỏ lặng lẽ; pop-up chỉ hiện khi có ai đó gọi
`requestAuthorization`. Không tầng nào gọi, nên với code xuất xưởng thì pop-up
**không thể** xuất hiện. Cổng 3 đã được xác nhận.

### Một chỗ trong plan trước viết sai, đã sửa

**Bước V3 không còn dùng được.** Nó đề xuất đưa app xuống background để tách lỗi
quyền khỏi lỗi hiển thị foreground — nhưng phép thử đó giả định quyền *có thể*
đã được cấp. Không thể: nó chưa từng được xin. Sẽ không có banner ở cả hai trạng
thái, nên V3 không phân biệt được gì cho tới khi C2 xong.

Hệ quả: **cổng 4 là chưa kiểm chứng, không phải đã loại trừ.** Nó vẫn có thật —
AppDelegate không set delegate, đã kiểm chứng — và sẽ lộ ra ngay khi C2 làm cho
việc đăng thông báo khả thi. **C2 và C3 phải làm cùng nhau**, nếu không thì sửa
xong quyền vẫn thấy hỏng y hệt khi app đang mở.

### Còn bỏ ngỏ

- [ ] **Cổng 1 đã thật sự mở chưa?** Xác nhận có phát hiện nào xảy ra không:
      card Fake GPS phải xuất hiện ít nhất một dòng, và log phải có
      `[VMBridge] onFakeGPSDetected from SDK`. Log simulator đã xoay vòng mất
      lúc kiểm tra nên chưa xác nhận được.
      Việc này quan trọng độc lập với thông báo: nếu SDK không phát hiện được
      trên phiên bản OS này thì làm bao nhiêu phần quyền cũng không ra banner.

## Kế hoạch triển khai

> **Trạng thái: C1–C5 đã hoàn tất ngày 2026-09-29.** iOS `BUILD SUCCEEDED`,
> Android `BUILD SUCCESSFUL`, `npm run validate` xanh (parity 41 → **43**
> selector, 42/42 test). Đã kiểm chứng `POST_NOTIFICATIONS` thật sự nằm trong
> APK bằng `aapt2 dump permissions`.
>
> **Vẫn còn một việc không code được:** mục "Còn bỏ ngỏ" ở trên — chưa xác nhận
> cổng 1 có mở không. Nếu SDK không phát hiện fake GPS trên phiên bản OS này thì
> toàn bộ C1–C5 vẫn không cho ra banner nào, và điều tra quay về cổng 1.

API đã kiểm chứng trước khi viết: `PermissionsAndroid.PERMISSIONS.POST_NOTIFICATIONS`
có trong React Native 0.79.6, và example đang `targetSdkVersion 35` nên luật
quyền runtime của Android 13 được áp dụng.

**Quyết định chủ sở hữu: đặt ở example, trừ một ngoại lệ.**
`UNUserNotificationCenter.delegate` là state cấp toàn app; thư viện giành lấy nó
sẽ xung đột với app chủ nhà vốn thường đã có delegate riêng. Flutter cũng chọn
như vậy: plugin của họ không ship code thông báo nào, example mới là nơi lo
quyền. Ngoại lệ là C2, chỗ mà một method trong plugin tốt hơn hẳn việc bắt mọi
khách hàng tự viết cùng một đoạn Swift.

### C1 — Quyền trên Android `[x]`

- [x] **C1.1** Khai báo trong `example/android/app/src/main/AndroidManifest.xml`:
      `<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />`
      Bắt buộc từ API 33. SDK tự tạo channel với `IMPORTANCE_HIGH` nên không cần
      làm gì thêm ở phía channel.
- [x] **C1.2** Xin quyền lúc chạy bằng
      `PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.POST_NOTIFICATIONS)`,
      chặn bằng `Platform.OS === 'android' && Platform.Version >= 33` — hằng số
      vẫn tồn tại ở bản cũ hơn nhưng lời gọi là no-op ở đó.
- [x] **C1.3** Không xin lúc khởi động. Xin đúng lúc policy được đổi sang giá trị
      có thông báo, để pop-up xuất hiện kèm một lý do người dùng nhìn thấy được.

### C2 — Quyền trên iOS, đặt trong plugin `[x]`

Phần này thuộc về plugin: SDK đăng thông báo và tự ghi rằng host phải có quyền,
vậy plugin nên cung cấp luôn lời gọi tương ứng thay vì để mỗi khách hàng tự viết
cùng một đoạn Swift.

- [x] **C2.1** Thêm `requestNotificationPermission(): Promise<boolean>` xuyên năm
      tầng, dùng
      `UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])`.
      Trên Android trả về kết quả của lời xin `POST_NOTIFICATIONS`, để một lời
      gọi dùng được cho cả hai nền.
- [x] **C2.2** Thêm `hasNotificationPermission(): Promise<boolean>` qua
      `getNotificationSettings`, để UI hiện được trạng thái thay vì đoán.
- [x] **C2.3** Cập nhật kỳ vọng của parity check — thêm hai selector, số đếm đi
      từ 41 lên 43.

### C3 — Hiển thị foreground trên iOS `[x]`

Phải làm cùng C2. Chỉ có quyền thôi thì các phát hiện vẫn vô hình khi app đang
mở, mà đó đúng là trạng thái lúc test.

- [x] **C3.1** Trong `example/ios/RnVietmapTrackingPluginExample/AppDelegate.swift`,
      cho `AppDelegate` conform `UNUserNotificationCenterDelegate` và gán
      `UNUserNotificationCenter.current().delegate = self` trong
      `didFinishLaunchingWithOptions`, **trước** `startReactNative`.
- [x] **C3.2** Cài đặt `userNotificationCenter(_:willPresent:withCompletionHandler:)`
      hoàn tất với `[.banner, .sound]` (dùng `.alert` cho dưới iOS 14).
      Thiếu cái này thì iOS vẫn giao thông báo mà không hiện gì khi app ở
      foreground — bản đăng của SDK thành công nhưng trông như thất bại.
- [x] **C3.3** Ghi chú rằng đây là phần riêng của example, kèm lý do plugin không
      làm: thư viện giành delegate cấp toàn app sẽ làm hỏng app chủ nhà nào đã có
      delegate riêng.

### C4 — Giao diện example `[x]`

- [x] **C4.1** Thêm một dòng trạng thái quyền thông báo trong card Fake GPS:
      trạng thái hiện tại kèm nút xin quyền, để nhìn thấy được thay vì phải đoán.
- [x] **C4.2** Khi policy là `warn` mà chưa có quyền thì nói rõ trong card — SDK
      vẫn nhận policy bình thường, và sự im lặng sau đó nếu không giải thích thì
      không ai hiểu vì sao.
- [x] **C4.3** Ghi rõ mức chặn dội 30 giây ngay trong card, để một banner mỗi 30
      giây dưới dòng mock liên tục không bị đọc nhầm thành hỏng.

### C5 — Ghi hợp đồng này vào tài liệu plugin `[x]`

Plugin hiện không nói gì về điều này, và đó chính là lý do gốc khiến phải trace
mới trả lời được.

- [x] **C5.1** README, mục Fake GPS: SDK là nơi đăng thông báo, app chủ nhà nợ nó
      quyền và — trên iOS — một delegate hiển thị foreground. Kèm luôn đoạn
      AppDelegate mẫu.
- [x] **C5.2** Ghi rõ rằng **event** `onFakeGPSDetected` bắn ở mọi policy, còn
      **thông báo** chỉ bắn ở `warn`. Hai kênh khác nhau và rất dễ nhầm làm một.

### Thứ tự

C1 và C2 làm trước, độc lập nhau. C3 làm cùng C2 — test trên app đang mở mà
thiếu nó thì kết quả đánh lừa. C4 sau C2 để UI có trạng thái mà hiện. C5 cuối.

**Trước tất cả: chốt mục "Còn bỏ ngỏ" ở trên.** Nếu SDK không phát hiện được
trên phiên bản OS này thì không có C1–C4 nào cho ra banner, và việc điều tra
quay về cổng 1.

## Những thứ đã loại trừ, không phải cổng chặn

- `setFakeGpsNotificationConfig` — tuỳ chọn. SDK có sẵn mặc định
  "Fake GPS Detected" / "Mock location detected", nên im lặng không phải do
  thiếu tiêu đề.
- Phần nối event phía RN — `addFakeGPSDetectedListener` đã nối trên cả hai nền và
  đã kiểm chứng trước đó. Event và thông báo là hai kênh tách biệt: event bắn ở
  mọi policy, thông báo chỉ ở `warn`.

## Các bước kiểm định ban đầu, giữ lại để tham khảo

- **V1 — có đang phát hiện không?** Đặt `allowMockLocation: false`, bật tracking
  trên simulator, xem card Fake GPS và log `[VMBridge] onFakeGPSDetected from SDK`.
- **V2 — policy có xuống tới SDK không?** Chọn `warn` và xác nhận log
  `-> SDK setFakeGPSPolicy | "warn"`.
- **V4 — đọc lỗi của chính SDK.** `[FakeGPS] Failed to show notification:` là
  `print` của Swift nên đi ra stdout, không phải `os_log`. `log stream` sẽ
  **không bao giờ** thấy — dùng console Xcode hoặc `simctl launch --console`.
- **V5 — Android.** Cùng luồng trên emulator API 33+. SDK tự tạo channel, nên
  thiếu banner ở đó là chỉ dấu của `POST_NOTIFICATIONS`.
- **V6 — xác nhận mức chặn dội 30 giây** thay vì đọc nhầm thành lỗi.

---

# Báo cáo đồng bộ Fake GPS giữa RN và Flutter

Trace ngày 2026-09-29, theo yêu cầu kiểm tra cơ chế debounce 30 giây có nhất
quán giữa hai plugin hay không, vì cả hai dùng chung một SDK bên dưới.

## Kết luận ngắn

**Cơ chế 30 giây hoàn toàn đồng bộ, và không thể lệch được** — nó nằm trong SDK,
không nằm ở tầng plugin. Không plugin nào tự throttle thêm.

Nhưng khi soi kỹ theo hướng đó, **tìm ra hai điểm lệch thật ở tầng plugin RN**,
trong đó một cái là lỗi hiển thị sai ngày trên iOS.

## Phần đã đồng bộ

### Debounce 30 giây — nằm trong SDK, hai nền giống hệt

| | Hằng số | Vị trí |
|---|---|---|
| iOS | `fakeGPSNotifyIntervalSec = 30.0` | `VietmapTrackingSDK.swift:891` |
| Android | `FAKE_GPS_NOTIFY_INTERVAL_MS = 30_000L` | `VietmapTrackingManager.java:58` |

Cùng một giá trị, cùng một cấu trúc điều khiển. Và điều quan trọng hơn con số:
**cùng một biến `isFirstDetection` chặn cả event lẫn notification**, chứ không
phải chỉ chặn notification:

```java
boolean isFirstDetection = (now - lastFakeGPSCallbackTime) >= FAKE_GPS_NOTIFY_INTERVAL_MS;
if (isFirstDetection) {
    lastFakeGPSCallbackTime = now;
    notifyFakeGPSCallbacks(location);     // event
}
switch (fakeGPSPolicy) {
    case "warn":
        if (isFirstDetection) {
            showFakeGPSNotification(location);   // notification
        }
```

Nghĩa là **danh sách "Detections" trong example cũng bị chặn dội 30 giây**, không
chỉ riêng banner. Ghi chú trong card RN hiện chỉ nói về notification — chưa sai
nhưng chưa đủ, đã sửa ở phần cuối.

Comment trong SDK viết "to prevent Flutter bridge flood". Câu đó có từ thời chỉ
có Flutter; hành vi thì không phụ thuộc plugin nào, RN hưởng y hệt.

### Không plugin nào tự throttle

| | Tầng native | Tầng app |
|---|---|---|
| Flutter | forward thẳng, không lọc | `fakeGpsHistory` giữ 20 phần tử |
| RN | forward thẳng, không lọc | `fakeGpsEvents` giữ 20 phần tử |

Giống nhau. Cả hai đều để SDK quyết nhịp.

### Dedup riêng của `logToServer`

Tách biệt với debounce 30s ở trên: policy `logToServer` còn bị khử trùng lặp
theo **60 giây VÀ 5 mét** (`FAKE_GPS_LOG_INTERVAL_MS = 60_000L`), để thiết bị
đứng yên với GPS giả không làm ngập HTTP. Cũng nằm trong SDK nên cả hai plugin
như nhau.

## Hai điểm lệch tìm được ở RN

### Lệch 1 — đơn vị `timestamp` không nhất quán, iOS hiện sai ngày

Đây là lỗi thật, không phải khác biệt phong cách.

| | Flutter | RN (trước khi sửa) |
|---|---|---|
| iOS | giây (SDK trả `timeIntervalSince1970`) | **giây** — forward nguyên si |
| Android | giây (`currentTimeMillis() / 1000.0`) | **mili giây** |

Flutter chuẩn hoá về **giây** ở cả hai nền, có chủ đích — `FakeGpsEvent` khai báo
`timestamp` là giây và fallback cũng `millisecondsSinceEpoch / 1000.0`.

RN thì **tự mâu thuẫn với chính nó**: iOS giây, Android mili giây. Và
`FakeGpsCard` đọc bằng `new Date(event.timestamp)`, mà `Date` của JS nhận mili
giây — nên **trên iOS card hiện ngày 1970**, còn trên Android đúng do trùng hợp.

Hướng sửa: RN chuẩn hoá về **mili giây** ở cả hai nền, không theo giây như
Flutter. Lý do: đó là quy ước của chính RN — `normalizeLocation()` đã quy đổi
`LocationData.timestamp` về mili giây, `TrackingStatus` cũng mili giây. Một
event dùng giây giữa một API toàn mili giây mới là thứ gây lỗi cho người dùng.

**Hai plugin khác đơn vị ở đây là chấp nhận được**, miễn mỗi bên nhất quán với
chính mình và có ghi tài liệu. Thứ bắt buộc phải giống nhau là **hành vi của
SDK** — nhịp debounce, ngữ nghĩa policy, điều kiện phát hiện — và những thứ đó
giống nhau vì chúng nằm trong SDK.

### Lệch 2 — Android RN thiếu `isFirstDetection`

Flutter đặt `"isFirstDetection" to true` trong payload Android, khớp với iOS nơi
SDK tự gửi trường này. RN Android không gửi, nên `event.isFirstDetection` là
`undefined` trên Android và `true` trên iOS.

Giá trị luôn là `true` theo thiết kế — callback chỉ bắn khi `isFirstDetection`,
nên trường này thực chất là hằng số. Nhưng thiếu nó làm kiểu dữ liệu lệch giữa
hai nền mà không vì lý do gì.

### Không phải lệch: thiếu `reason` trên Android

`reason` là thứ **SDK Android không có**, vì nó đến từ
`CLLocationSourceInformation` của iOS. Flutter ghi rõ trong code:
`// Note: Android SDK does not provide a "reason" field`. RN cũng vậy và đã ghi
chú tương tự. Đây là bất đối xứng của SDK, ảnh hưởng hai plugin như nhau.

## Việc cần làm — đã xong 2026-09-29

- [x] Chuẩn hoá `timestamp` của fake GPS về mili giây ở cả hai nền RN.
      iOS quy đổi từ giây sang mili giây ngay trong closure, dùng đúng ngưỡng
      như `normalizeLocation()`. Android vốn đã là mili giây, thêm chú thích.
- [x] Thêm `isFirstDetection` vào payload Android RN — luôn `true`, vì SDK chỉ
      gọi callback ở lần phát hiện đầu trong mỗi cửa sổ 30 giây.
- [x] Sửa ghi chú trong card: debounce 30 giây chặn **cả** danh sách phát hiện
      lẫn thông báo.
- [x] Ghi vào `types.ts` rằng `timestamp` của RN là mili giây còn Flutter là
      giây, kèm lý do — để người đọc sau không tưởng đây là lỗi.

`npm run validate` xanh sau khi sửa: parity 43/43, 0 error, 42/42 test.
