# Plan chuẩn bị release 0.2.0

Trace ngày 2026-09-30. **Chưa thực hiện gì** — để anh duyệt trước khi commit.

> Diễn giải tiếng Việt; tên file, lệnh và code giữ tiếng Anh vì chúng được chạy
> hoặc chép thẳng vào source.

## Hiện trạng đã trace

| | |
|---|---|
| Nhánh | `feat/update_SDK_tracking` |
| Commit gần nhất | `2be4ac9 feat: update 0.1.4` |
| `package.json` version | `0.1.4` |
| Thay đổi chưa commit | 25 sửa, 3 xoá, 9 chưa track |

**Version chỉ nằm ở một chỗ.** `package.json` là nguồn duy nhất; podspec đọc lại
qua `s.version = package["version"]`, và Android không khai báo version nào. Nên
bump chỉ là sửa một dòng — không có chỗ thứ hai để quên.

## Việc cần làm

### R1 — Gỡ credential thật khỏi source `[ ]`

Đây là việc gấp nhất và phải làm trước khi commit.

`example/src/GPSTrackingDemo.tsx:37` đang chứa **API key production thật**:

```
const API_KEY = '<48-ký-tự-key-production-thật>';
const BASE_URL = 'https://live.fleetwork.vn/api/v1';
```

Anh từng nói "dùng để test thôi, không commit" — nhưng nó đang nằm trong working
tree và `git add .` sẽ cuốn theo. Một key đã vào lịch sử git thì đổi file sau đó
không gỡ được; phải coi như đã lộ và cấp lại key.

- [ ] **R1.1** Đưa `API_KEY` về `'YOUR_API_KEY_HERE'`.
- [ ] **R1.2** Giữ `BASE_URL = 'https://live.fleetwork.vn/api/v1'` — đây là
      endpoint production công khai, không phải bí mật, và là mặc định của chính
      SDK. Xoá đi thì example mất giá trị tham chiếu.
- [ ] **R1.3** Kiểm lại toàn repo trước khi commit:
      `git diff --cached | grep -iE "API_KEY = '[a-f0-9]{32}"`
      Phải không ra gì.
- [ ] **R1.4** Xác nhận key **chưa từng vào lịch sử**:
      `git log -S '<8 ký tự đầu của key>' --oneline` → không ra commit nào.
      Nếu ra, phải cấp lại key chứ không chỉ sửa file.

### R2 — Xử lý các file plan `[ ]`

Bốn file plan hiện **chưa track** (`??`), nên chúng không tự vào commit — nhưng
`git add .` sẽ kéo vào.

| File | Nội dung | Đề xuất |
|---|---|---|
| `UPGRADE_PLAN.md` | 14 finding kỹ thuật + record Phase 0/1 | **Giữ** |
| `IMPLEMENTATION_PLAN.md` | 12 step, còn 26 mục cần máy thật | **Giữ** |
| `FAKE_GPS_NOTIFICATION_PLAN.md` | Hợp đồng notification giữa SDK và app | **Giữ** |
| `TIMESTAMP_FIX_PLAN.md` | Audit timestamp + quyết định T1-a/T3-B | **Giữ** |

Em đề xuất **giữ cả bốn, gom vào `docs/`**. Lý do: chúng không phải ghi chú tạm
mà là thứ duy nhất giải thích *vì sao* code hiện tại như vậy — chẳng hạn vì sao
`allowMockLocation` mặc định `true` ngược với SDK, vì sao iOS tự ráp health
status thay vì forward. Xoá đi thì lần sau có người "sửa lại cho đúng" và tái
tạo nguyên bug.

Chúng **không lọt vào gói npm**: trường `files` trong `package.json` chỉ liệt kê
`src`, `lib`, `android`, `ios`, `cpp`, `*.podspec`, `react-native.config.js`.
Nên giữ chúng không làm gói nặng thêm.

- [ ] **R2.1** `mkdir docs && git mv` bốn file vào đó.
- [ ] **R2.2** Thêm một mục trong README trỏ tới `docs/`, nói rõ đây là ghi chép
      kỹ thuật cho người bảo trì chứ không phải tài liệu người dùng.
- [ ] **R2.3** Còn `IMPLEMENTATION_PLAN.md` có 26 mục chưa xong — **giữ nguyên
      trạng thái chưa tick**. Đánh dấu khống cho đẹp commit là tự xoá dấu vết
      của việc chưa làm.

### R3 — Gỡ scaffolding đo đạc `[ ]`

`markJsAppState` là công cụ đo của Step 0, hiện **đang là API công khai** ở cả 5
tầng. Ship nó nghĩa là hứa hỗ trợ lâu dài cho một thứ sinh ra để xoá.

Đây là **quyết định anh chưa chốt** từ mấy lượt trước, và nó chặn release:

- **R3-a** — Chạy Step 0 trước rồi xoá. Cần máy thật. Có số liệu thì 6.6 và 6.7
  hoặc được giữ có bằng chứng, hoặc bị xoá theo đúng điều kiện bác bỏ đã ghi.
- **R3-b** — Xoá ngay, ship, đo sau. Nhanh, nhưng 6.6/6.7 đi kèm bản phát hành
  mà chưa ai đo.

- [ ] **R3.1** Chốt a hay b.
- [ ] **R3.2** Nếu xoá: bỏ khỏi `NativeRnVietmapTrackingPlugin.ts`, `index.tsx`,
      `.m`, `.swift`, `.kt`, và mock trong test. Parity check sẽ về 43 selector.
- [ ] **R3.3** Trace `[VMLife]` thì **giữ** — đã gate `#if DEBUG` và
      `BuildConfig.DEBUG`, không lọt vào release, và có ích khi gỡ lỗi lifecycle.

### R4 — README giữ nguyên format khởi tạo cũ `[ ]`

Đã kiểm: mục **Quick Start → Initial Configuration** vẫn nguyên như ảnh anh gửi,
em không đụng vào:

```typescript
import { configure, configureAlertAPI } from '@vietmap/rn_vietmap_tracking_plugin';

// Configure VietmapTrackingSDK with your API key
await configure('YOUR_VIETMAP_API_KEY');
```

Phần em sửa là **Configuration** (bên dưới) và **API Reference** — hai mục khác.

- [ ] **R4.1** Giữ nguyên khối này, **không** đổi sang `initializeTracking`.
- [ ] **R4.2** Thêm ngay dưới đó một ghi chú ngắn rằng `initializeTracking` là
      lựa chọn nên dùng cho app thật vì nó kiểm tra key với server trước, còn
      `configure` nhận credential không kiểm chứng. Chỉ bổ sung, không thay thế
      — người đang dùng `configure` không phải sửa gì.
- [ ] **R4.3** Cập nhật bảng "Native SDK versions" nếu có đổi (hiện Android
      1.5.3 / iOS 1.5.2, chưa đổi).

### R5 — CHANGELOG `[ ]`

Mục `[0.2.0]` đã viết sẵn nhưng **ghi ngày 2026-09-25**, trong khi công việc kéo
tới 30-09 và thêm nhiều thứ sau đó.

Một điểm cần biết trước: `package.json` cấu hình `release-it` với plugin
`@release-it/conventional-changelog` (preset angular). Plugin đó **tự sinh
CHANGELOG từ commit message**, và sẽ **ghi đè** lên mục viết tay.

- [ ] **R5.1** Đổi ngày mục `[0.2.0]` sang ngày phát hành thật.
- [ ] **R5.2** Bổ sung những thứ làm sau 25-09 mà mục hiện tại chưa có:
      - `requestNotificationPermission` / `hasNotificationPermission`
      - `addListener` / `removeListeners` (sửa cảnh báo `NativeEventEmitter`)
      - Sửa request quyền Android: chỉ xin foreground, vì gộp background làm hệ
        thống vứt bỏ toàn bộ request
      - Sửa `getTrackingHealthStatus` iOS trả sai hình dạng
      - Sửa `getTrackingStatus` Android thiếu `trackingDuration`
      - Bỏ `timestamp` sai đơn vị khỏi `onTrackingInterrupted`
      - Gate toàn bộ `Log.d` Android sau `BuildConfig.DEBUG`
      - GPX replay và lưu trạng thái trong example
- [ ] **R5.3** **Quyết định về `release-it`.** Hai hướng:
      - Bỏ plugin `@release-it/conventional-changelog` và giữ CHANGELOG viết tay
        (em đề xuất — mục 0.2.0 giải thích *vì sao* phá vỡ tương thích, thứ mà
        commit message sinh tự động không làm được)
      - Hoặc giữ plugin và chấp nhận mất phần viết tay
- [ ] **R5.4** Trong CHANGELOG nêu rõ **phiên bản React Native thấp nhất hỗ trợ**
      và cặp SDK native, vì đây là bản phá vỡ tương thích.

### R6 — Bump version `[ ]`

Chỉ sau khi R1–R5 xong.

Theo ghi nhớ của anh, **việc bump và publish là của anh, không phải của em** —
em chuẩn bị mọi thứ tới sát mép và dừng.

- [ ] **R6.1** `0.1.4` → `0.2.0`. Minor chứ không phải patch: có phá vỡ tương
      thích ở `LocationTrackingConfig`, nhưng gói còn ở `0.x` nên theo semver
      thì minor là đúng chỗ cho breaking change.
- [ ] **R6.2** Chỉ sửa `package.json`. Podspec tự theo.
- [ ] **R6.3** Chạy `npm run validate` lần cuối — 5 bước phải xanh.
- [ ] **R6.4** Build lại cả hai nền sau khi bump, để chắc podspec đọc đúng.

### R7 — Trước khi commit `[ ]`

- [ ] **R7.1** `git add -p` chứ không phải `git add .` — để nhìn từng thay đổi
      và chặn credential lọt vào.
- [ ] **R7.2** Kiểm 3 file đã xoá là cố ý: hai file 0 byte
      (`RnVietmapTrackingPluginModuleClean.kt`,
      `RnVietmapTrackingPluginModule_VietmapSDK.kt`) và codegen spec chết
      (`com/facebook/fbreact/specs/...`). Đều đúng.
- [ ] **R7.3** Hai script mới trong `scripts/` phải được track — chúng là một
      phần của `npm run validate`.
- [ ] **R7.4** Tách commit theo chủ đề thay vì một commit khổng lồ: native
      methods, example app, docs, fixes. Dễ review và dễ revert từng phần.

## Thứ tự thực hiện

```
R1 Gỡ credential        ← làm ngay, trước mọi git add
R2 Gom docs/
R3 Chốt markJsAppState  ← cần anh quyết
R4 README
R5 CHANGELOG            ← cần anh quyết chuyện release-it
R6 Bump version         ← việc của anh
R7 Commit
```

R1 không phụ thuộc gì và phải xong trước tiên. R3 và R5 chờ quyết định của anh.
R6 là của anh theo đúng thoả thuận.

## Hai việc cần anh chốt

1. **`markJsAppState`** — chạy Step 0 trước rồi xoá (R3-a), hay xoá luôn và đo
   sau (R3-b)?
2. **`release-it` + conventional-changelog** — bỏ plugin để giữ CHANGELOG viết
   tay, hay giữ plugin và chấp nhận nó ghi đè?

## Điều cần nói rõ về mức độ sẵn sàng

Build xanh cả hai nền và `npm run validate` xanh cả 5 bước. Nhưng **phần lớn code
mới chưa chạy thật lần nào**:

- Card Health trên iOS — phép thử trực tiếp cho T3
- Luồng notification đầy đủ: pop-up quyền, banner foreground, debounce 30s
- Cổng 1 fake GPS: **chưa xác nhận SDK có detect trên iOS 26 hay không**
- GPX replay, lưu trạng thái AsyncStorage
- Lifecycle observer native — phải tắt Metro mới chứng minh được không qua bridge

Trên Android anh đã verify được pop-up quyền. Phần còn lại chưa.

Ship hay không là quyết định của anh; em chỉ ghi lại để nó là một lựa chọn có ý
thức chứ không phải một giả định.
