# Plan sửa bug timestamp và kiểm chứng `isFirstDetection`

Trace ngày 2026-09-29. **Chưa sửa gì** — để anh duyệt trước.

> Phần diễn giải bằng tiếng Việt; tên hàm, đường dẫn và code giữ tiếng Anh vì
> chúng được chép thẳng vào source.

## Phần 2 trả lời trước: `isFirstDetection` có đúng như anh hiểu không?

Anh hỏi: *"field này dùng để bắn noti trực tiếp lần đầu khi thu thập dữ liệu
fake GPS đúng chứ"*.

**Đúng một nửa, và nửa còn lại quan trọng.**

### Biến `isFirstDetection` bên trong SDK — đúng như anh nói

Nó chính là thứ quyết định có bắn notification hay không:

```java
boolean isFirstDetection = (now - lastFakeGPSCallbackTime) >= FAKE_GPS_NOTIFY_INTERVAL_MS;
if (isFirstDetection) {
    lastFakeGPSCallbackTime = now;
    notifyFakeGPSCallbacks(location);        // event
}
switch (fakeGPSPolicy) {
    case "warn":
        if (isFirstDetection) {
            showFakeGPSNotification(location);   // notification
        }
```

Nên mô tả "lần đầu trong cửa sổ 30 giây thì bắn" là chính xác. Chỉ cần nói thêm
cho đủ: nó **không phải** lần đầu tuyệt đối kể từ khi bật tracking, mà là **lần
đầu trong mỗi cửa sổ 30 giây** — cứ 30 giây lại có một "lần đầu" mới.

### Nhưng *field* trong payload thì không điều khiển gì cả

Đây là chỗ khác biệt. Callback **chỉ được gọi khi `isFirstDetection == true`**.
Nên tới lúc payload được dựng, giá trị đó luôn là `true` — không có đường nào để
nó mang `false`.

Kiểm chứng trên iOS, `VietmapTrackingSDK.swift:3836`, giá trị được **viết cứng**
chứ không lấy từ biến:

```swift
let payload: NSDictionary = [
    "isFake": true,
    "isFirstDetection": true,      // hằng số, không phải biến isFirstDetection
    ...
]
```

Nghĩa là field này **thuần thông tin, luôn `true`**. Nó không bắn gì, không bật
gì. Tầng JS đọc nó cũng không quyết định được điều gì.

### Vậy nó có thật sự thiếu không?

**Có thiếu, nhưng là thiếu về hình dạng dữ liệu, không phải thiếu chức năng.**
Phân biệt này quan trọng để khỏi ghi sai vào changelog:

| | iOS | Android |
|---|---|---|
| SDK cung cấp | có, trong `NSDictionary` | **không** — callback chỉ có `(double lat, double lng)` |
| Flutter plugin gửi lên | có (forward) | có — viết cứng `"isFirstDetection" to true` |
| RN plugin gửi lên (trước) | có (forward) | **không có** |

Nên trước khi sửa: `event.isFirstDetection` là `true` trên iOS và `undefined`
trên Android. Cùng một sự kiện, hai hình dạng khác nhau — đó mới là cái sai.
Không có tính năng nào hỏng vì nó.

**Kết luận: sửa là đúng, nhưng phải mô tả đúng.** Đây là đồng bộ hình dạng
payload giữa hai nền, không phải "khôi phục thông báo lần đầu bị mất". Em đã sửa
ở lượt trước và đã mô tả hơi quá — plan này ghi lại cho đúng.

---

## Phần 1: audit toàn bộ timestamp

Chuẩn: **mili giây kể từ epoch**, ở mọi nơi, trên cả hai nền — khớp với chuẩn
server và với `normalizeLocation()` vốn đã quy đổi `LocationData` về mili giây.

Đã rà từng chỗ plugin phát ra timestamp. Kết quả:

| Nơi phát | iOS | Android | Trạng thái |
|---|---|---|---|
| `onLocationUpdate.timestamp` | `normalizeLocation()` → ms | `VMLocation.timestamp` = `Location.getTime()` → ms | ✅ đúng |
| `onLocationError.timestamp` | `* 1000` → ms | `currentTimeMillis()` → ms | ✅ đúng |
| `onPermissionChanged.timestamp` | `* 1000` → ms | ms | ✅ đúng |
| `onFakeGPSDetected.timestamp` | quy đổi → ms | ms | ✅ vừa sửa hôm nay |
| `onTrackingInterrupted.timestamp` | **giây**, forward nguyên si | **thiếu hẳn** | ❌ **Bug 1** |
| `getTrackingStatus()` | SDK trả ms sẵn | **thiếu `trackingDuration` và `lastLocationUpdate`** | ❌ **Bug 2** |
| `getTrackingHealthStatus()` | SDK trả **hình dạng hoàn toàn khác** | module tự ráp, ms | ❌ **Bug 3** |

Ba bug, và chúng nặng dần.

### Bug 1 — `onTrackingInterrupted`

SDK iOS gửi `"timestamp": now`, với `now = Date().timeIntervalSince1970` — tức
**giây**. Plugin RN forward nguyên si nên JS nhận giây, trong khi mọi event khác
đều mili giây.

Android thì payload em dựng **không có `timestamp`**, chỉ có `reason`,
`recovered`, `isInBackground`, `secondsSinceLastFix`.

Kết quả: cùng một event, iOS có trường này (sai đơn vị), Android không có.

`secondsSinceLastFix` thì **đúng và giữ nguyên** — tên đã nói rõ là giây, và cả
hai nền đều giây. Không quy đổi trường này; đổi sẽ làm sai tên.

### Bug 2 — `getTrackingStatus()` khác hình dạng giữa hai nền

Type đang khai báo:

```ts
export interface TrackingStatus {
  isTracking: boolean;
  lastLocationUpdate?: number;
  trackingDuration: number;     // bắt buộc
}
```

iOS trả đủ, đơn vị ms (SDK tự nhân 1000 sẵn ở `VietmapTrackingSDK.swift:1443`).

Android trả `isTracking`, `status`, `timestamp` — **không có `trackingDuration`,
không có `lastLocationUpdate`**. Nên `status.trackingDuration` là `undefined`
trên Android dù type nói là bắt buộc. Code nào làm phép tính trên nó sẽ ra `NaN`.

Module Android **đã có sẵn** `trackingStartTime` và `lastLocationTimestamp` —
chính hai biến `getTrackingHealthStatus` đang dùng — nên chỉ là ráp lại.

### Bug 3 — `getTrackingHealthStatus()` iOS trả sai hẳn hình dạng

Nặng nhất, và là **lỗi của em ở bước 8.2**. Lúc đó em viết "iOS returns an
NSDictionary directly" rồi forward thẳng, mà không đối chiếu hình dạng đó với
type đã khai báo.

Thực tế SDK iOS trả **17 trường**, và không trùng với type:

```
isTracking, isSpeedAlertActive, timeSinceLastUpdate, locationServicesEnabled,
authorizationStatus, isInBackground, backgroundTaskActive,
allowsBackgroundLocationUpdates, pausesLocationUpdatesAutomatically,
desiredAccuracy, distanceFilter, lastLocationAge, lastLocationAccuracy, ...
```

Đối chiếu với `TrackingHealthStatus` đang khai báo:

| Trường trong type | iOS | Android |
|---|---|---|
| `isTracking` | ✅ | ✅ |
| `hasLocationPermission` | ❌ thiếu | ✅ |
| `hasBackgroundPermission` | ❌ thiếu | ✅ |
| `trackingDuration` | ❌ thiếu | ✅ ms |
| `timeSinceLastUpdate` | ⚠️ có, nhưng **giây** | ✅ ms |
| `isInitialized` | ❌ thiếu | ✅ |
| `lastLocationUpdate` | ❌ thiếu | ✅ ms |
| `timestamp` | ❌ thiếu | ✅ ms |

Nên trên iOS gần như mọi trường của type đều `undefined`, và trường duy nhất
trùng tên thì sai đơn vị. Card "Health" trong example vì thế hiện gần như trống
trên iOS — đúng thứ em lẽ ra phải phát hiện khi chạy thử.

---

## Kế hoạch sửa

> **Trạng thái: T1–T4 đã xong ngày 2026-09-29.** iOS `BUILD SUCCEEDED`, Android
> `BUILD SUCCESSFUL`, `npm run validate` xanh — parity 43/43, **45/45 test**
> (thêm 3 test khẳng định hình dạng object).
>
> Hai quyết định em tự chốt theo đề xuất vì anh chưa trả lời: **T1-a** (bỏ hẳn
> `timestamp`) và **T3 hướng B** (iOS ráp cho khớp type). Cả hai đều đảo lại
> được dễ.
>
> Còn một việc cần máy thật: mở example trên iOS và xác nhận card **Health giờ
> hiện đủ trường** — trước đây gần như trống. Đó là phép thử trực tiếp cho T3.

Thứ tự theo mức rủi ro: T1 rẻ nhất, T3 cần quyết định thiết kế.

### T1 — `onTrackingInterrupted` `[x]` — chọn **T1-a**

Quyết định: bỏ hẳn `timestamp`, khớp model 4 field của Flutter. Trường này hiện
không ai đọc, `secondsSinceLastFix` đã đủ cho mọi thứ card hiển thị, và giữ hai
plugin cùng hình dạng đáng giá hơn một field chưa ai cần.

Lưu ý: `TrackingInterruptedEvent` trong `types.ts` **vốn đã đúng** — 4 field, không
khai báo `timestamp`. Bug nằm ở chỗ iOS gửi kèm một field thừa mà type không hứa,
đơn vị lại là giây. Nên việc cần làm là cho payload thực tế khớp lại với type,
không phải sửa type.

- [x] **T1.1** iOS: loại `timestamp` khỏi dict trước khi gửi lên JS, để payload
      thực tế khớp đúng `TrackingInterruptedEvent` trên cả hai nền.
- [x] **T1.2** Ghi chú ngay tại chỗ: SDK có gửi trường này trên iOS nhưng không
      gửi trên Android, và đơn vị là giây — để người sau không tưởng là bỏ sót.
- [x] **T1.3** **Không** đụng `secondsSinceLastFix` — tên đã nói là giây và cả
      hai nền đều đúng.

### T2 — `getTrackingStatus()` trên Android `[x]`

- [x] **T2.1** Ráp `trackingDuration` từ `trackingStartTime` đã có sẵn:
      `if (isActive && trackingStartTime > 0) now - trackingStartTime else 0`,
      đơn vị ms, khớp iOS.
- [x] **T2.2** Thêm `lastLocationUpdate` từ `lastLocationTimestamp`, bỏ trường
      này khi chưa có fix nào — iOS trả `NSNull()` trong trường hợp đó, nên
      optional trong type là đúng.
- [x] **T2.3** Bỏ trường `status` chỉ có ở Android: nó trùng thông tin với
      `isTracking` và không có trong type.

### T3 — `getTrackingHealthStatus()` `[x]` — chọn **hướng B**

Quyết định: chuẩn hoá ở iOS cho khớp type, như Android đang làm.

**Hướng A — sửa type cho khớp iOS.** Rẻ về công, nhưng hỏng: Android không có
`backgroundTaskActive`, `allowsBackgroundLocationUpdates`,
`pausesLocationUpdatesAutomatically` — chúng là khái niệm riêng của CoreLocation.
Type sẽ đầy trường chỉ chạy một nền, và người dùng không biết trường nào dùng
được ở đâu.

**Hướng B — chuẩn hoá ở iOS cho khớp type, như Android đang làm.** Plugin iOS tự
ráp `TrackingHealthStatus` từ những gì nó biết, thay vì forward dict của SDK.
Hợp đồng khi đó giống nhau hai nền và đúng như type đã hứa.

- [x] **T3.1** iOS: thay `resolve(trackingManager.getTrackingHealthStatus())`
      bằng một dict tự ráp đúng 8 trường của `TrackingHealthStatus`:
      - `isTracking` ← `trackingManager.isTrackingActive()`
      - `hasLocationPermission` ← `trackingManager.hasLocationPermissions()`
      - `hasBackgroundPermission` ← `authorizationStatus == .authorizedAlways`
      - `trackingDuration` ← lấy từ `getTrackingStatus()` của SDK, vốn đã ms
      - `timeSinceLastUpdate` ← `timeSinceLastUpdate` của SDK **× 1000**, và giữ
        `-1` khi chưa có fix, khớp quy ước Android
      - `isInitialized` ← `isInitialized` của module
      - `lastLocationUpdate` ← từ `getTrackingStatus()`, đã ms
      - `timestamp` ← thời điểm hiện tại, ms
- [x] **T3.2** Giữ nguyên dict gốc của SDK dưới khoá `raw`, để 9 trường chẩn
      đoán riêng của iOS không bị mất — chúng có ích khi gỡ lỗi CoreLocation.
      Khai báo `raw?: Record<string, unknown>` trong type và ghi rõ là tuỳ nền.
- [x] **T3.3** Kiểm tra `timeSinceLastUpdate` khi `lastLocationUpdate == 0`:
      SDK iOS tính `currentTime - lastLocationUpdate` nên ra một con số khổng lồ
      chứ không phải `-1`. Phải chặn riêng, nếu không card Health sẽ hiện "56 năm
      kể từ fix cuối".

### T4 — Chặn tái diễn `[x]`

Ba bug này cùng một gốc: **forward dict của native lên JS mà không đối chiếu với
type đã khai báo**. Type checker không bắt được vì `Promise<Object>` trong spec
TurboModule nhận mọi thứ.

- [x] **T4.1** Thêm test cho từng phương thức trả object, khẳng định hình dạng
      thật: `getTrackingStatus`, `getTrackingHealthStatus`, và payload của cả
      năm event. Mock trả về hình dạng của **từng nền**, không phải một hình
      dạng lý tưởng.
- [x] **T4.2** Thêm một test khẳng định mọi trường tên `timestamp` đều nằm trong
      khoảng mili giây hợp lý (`> 1e12`), để một giá trị tính bằng giây lọt vào
      sẽ làm đỏ test thay vì hiện ngày 1970 trên UI.
- [x] **T4.3** Ghi vào `UPGRADE_PLAN.md` như một finding: hễ forward dict của SDK
      thẳng lên JS thì phải đối chiếu từng trường với type, vì `Object` trong
      spec không kiểm tra gì cả.

### Kiểm chứng sau khi sửa

- [ ] `npm run validate` xanh
- [ ] Build cả hai nền
- [ ] Chạy example: card Health phải hiện đủ trường **trên iOS** — hiện đang gần
      như trống, đó là phép thử trực tiếp cho T3
- [ ] Gây một interruption (tắt Location Services khi đang tracking) và xác nhận
      `timestamp` trong event là mili giây trên cả hai nền

## Phạm vi: RN hay cả Flutter? — đã trace lại

**Đính chính.** Bản đầu của plan này viết "ba bug đều nằm trong RN, Flutter không
dính". Trace lại từng cái thì **chỉ đúng với bug 2**.

| Bug | Bất đối xứng gốc | Flutter | RN |
|---|---|---|---|
| 1 — `timestamp` của interrupted | **Có ở cả hai**: SDK iOS gửi `timestamp` tính bằng giây, Android không gửi gì | Payload kênh **cũng lệch y hệt**, nhưng model `TrackingInterruptedEvent` chỉ có 4 field và **không khai báo `timestamp`** → không phơi ra ngoài | **Phơi ra**, vì forward nguyên dict lên JS |
| 2 — `getTrackingStatus` Android | Không có; là thiếu sót tầng plugin | **Sạch** — `handleGetTrackingStatus` ráp `trackingDuration` và `lastLocationUpdate` từ `trackingStartTime` / `lastLocationTimestamp` | **Thiếu** |
| 3 — health status iOS | **Có ở cả hai**: SDK iOS trả 17 trường CoreLocation, Android không có method này nên plugin tự ráp | `result(trackingManager.getTrackingHealthStatus())` — **forward thô y như RN**, hai nền hai hình dạng. Nhưng Dart khai báo `Future<Map<String, dynamic>>`, **không hứa hình dạng nào** | **Hứa 8 field trong `TrackingHealthStatus` rồi không giao** trên iOS |

### Điều rút ra

Bug 1 và 3 **không phải RN tự gây ra**. Bất đối xứng nằm ở SDK, và Flutter cũng
mang nguyên nó trong payload kênh. Khác biệt là **Flutter không hứa gì**: một
model bỏ qua field, một method trả map không kiểu. Không hứa thì không thất hứa.

RN thì khai báo kiểu TypeScript rồi không đáp ứng. Đó mới là bug — không phải vì
RN tệ hơn, mà vì RN **hứa nhiều hơn**. Kiểu mạnh là điểm tốt; hướng sửa là làm
cho hiện thực khớp với kiểu, **không phải làm yếu kiểu đi** cho bằng Flutter.

Riêng bug 2 là RN đi sau thật: Flutter đã ráp đúng từ trước, T2 chỉ là làm lại
điều Flutter đã làm.

### Hệ quả cho T1

Flutter né bug 1 bằng cách **không có field `timestamp`** trong model. Nên T1.3
(thêm `timestamp` vào `TrackingInterruptedEvent` của RN) sẽ khiến RN phơi ra
nhiều hơn Flutter. Hai lựa chọn, cần anh chốt:

- **T1-a — bỏ hẳn `timestamp` khỏi event**, khớp đúng model 4 field của Flutter.
  Gọn nhất, xoá luôn bất đối xứng, và `secondsSinceLastFix` vốn đã cho biết
  thời điểm tương đối.
- **T1-b — chuẩn hoá về mili giây và phơi ra ở cả hai nền** (như plan đang viết).
  Cho người dùng một mốc thời gian tuyệt đối mà `secondsSinceLastFix` không có.

Em nghiêng về **T1-a**: trường này hiện không ai đọc, `secondsSinceLastFix` đã đủ
cho mọi thứ card đang hiển thị, và giữ hai plugin cùng hình dạng có giá trị hơn
một field chưa ai cần.

### Đáng báo lên SDK

Gốc của bug 1 và 3 nằm ở SDK, không ở plugin nào:

- `onTrackingInterrupted` gửi `timestamp` trên iOS mà không gửi trên Android, và
  đơn vị là giây trong khi các payload khác của SDK dùng mili giây.
- `getTrackingHealthStatus` chỉ tồn tại trên iOS, trả 17 trường riêng của
  CoreLocation. Android không có gì tương ứng nên mỗi plugin phải tự ráp một
  hình dạng khác nhau.

Cả hai plugin đều đang tự vá quanh. Sửa ở SDK sẽ gỡ cho cả hai cùng lúc.
