# Các bước anh thực hiện để phát hành 0.2.0

Mọi việc chuẩn bị đã xong. Còn lại là commit, merge, bump và publish — những
bước cần quyết định hoặc quyền của anh.

Trạng thái hiện tại: nhánh `feat/update_SDK_tracking`, **25 file sửa, 3 xoá,
7 chưa track**, `package.json` vẫn `0.1.4`.

---

## 1. Xem lại thay đổi

```bash
cd /Volumes/240GB/Vietmap_SDK/rn_vietmap_tracking_plugin
git status
git diff
```

**Dùng `git add -p`, đừng dùng `git add .`** — để nhìn từng đoạn một. Em đã kiểm
không còn credential nào, nhưng thói quen này là thứ ngăn lần sau.

Kiểm lần cuối cho chắc:

```bash
grep -rnE "API_KEY = '[a-f0-9]{20,}'" --exclude-dir=node_modules --exclude-dir=.git .
```

Không ra gì là đúng.

### Ba file bị xoá — đều cố ý

| File | Vì sao |
|---|---|
| `RnVietmapTrackingPluginModuleClean.kt` | 0 byte, chưa bao giờ có nội dung |
| `RnVietmapTrackingPluginModule_VietmapSDK.kt` | 0 byte |
| `com/facebook/fbreact/specs/NativeRnVietmapTrackingPluginSpec.java` | Codegen spec đã chết — sai package, chữ ký cũ. Gradle sinh lại bản đúng vào `android/build/` |

### Bảy thứ chưa track — đều cần commit

```
docs/                              5 tài liệu kỹ thuật
example/src/components/            15 card của example
example/src/store/                 zustand store
example/src/gpxReplay.ts           GPX replay
scripts/check-ios-parity.js        nằm trong npm run validate
scripts/check-pods-codegen-path.js nằm trong npm run validate
RELEASING.md                       hướng dẫn phát hành lần sau
MERGE_AND_RELEASE_0.2.0.md         file này — xoá sau khi xong
```

---

## 2. Commit

Tách theo chủ đề thay vì một commit khổng lồ — dễ review và dễ revert từng phần:

```bash
# Tầng native + JS: 23 method mới, 2 event, config layer
git add src/ ios/ android/src/
git commit -m "feat: add 23 SDK methods, fake GPS and tracking-interrupted events"

# Các lỗi tìm ra khi chạy thật
git add src/__tests__/ scripts/
git commit -m "fix: permission dialog on Android, health status shape on iOS, timestamp units"

# Example app
git add example/
git commit -m "feat(example): split into cards, add GPX replay and persistence"

# Tài liệu
git add docs/ README.md CHANGELOG.md RELEASING.md package.json
git commit -m "docs: record findings, add release guide, drop changelog plugin"
```

> `package.json` nằm ở commit cuối vì thay đổi trong đó là **bỏ plugin
> `@release-it/conventional-changelog`** — plugin này tự sinh CHANGELOG từ commit
> message và sẽ **ghi đè** mục 0.2.0 viết tay. Từ nay CHANGELOG viết tay trước
> mỗi lần phát hành.

---

## 3. Merge vào `main`

```bash
git checkout main
git pull
git merge feat/update_SDK_tracking
```

Hoặc mở Pull Request nếu repo yêu cầu review — cách này nên hơn cho một bản có
phá vỡ tương thích.

Sau khi merge, chạy lại kiểm tra trên `main`:

```bash
npm run validate
```

---

## 4. Bump version

`0.1.4` → **`0.2.0`**. Minor chứ không phải patch: có phá vỡ tương thích, nhưng
gói còn ở `0.x` nên minor là chỗ đúng.

**Chỉ sửa `package.json`.** Podspec đọc lại qua `s.version = package["version"]`,
Android không khai báo version nào.

```bash
npm version 0.2.0 --no-git-tag-version
```

Rồi build lại để chắc podspec đọc đúng số mới:

```bash
cd example/ios && bundle exec pod install && cd ../..
```

> `pod install` **phải** chạy từ `example/ios`. Chạy từ chỗ khác thì đường dẫn
> codegen trong `Pods.xcodeproj` leo quá gốc filesystem và bản build sạch kế
> tiếp chết. `npm run validate` có bước bắt lỗi này.

---

## 5. Publish

```bash
npm run release
```

`release-it --only-version` sẽ hỏi xác nhận, tạo commit `chore: release 0.2.0`,
gắn tag `v0.2.0`, publish lên npm và tạo GitHub release.

Muốn tự làm từng bước:

```bash
git add package.json && git commit -m "chore: release 0.2.0"
git tag v0.2.0
git push origin main --tags
npm publish
```

CocoaPods lấy version từ git tag, nên **tag phải được push**.

---

## 6. Sau khi phát hành

```bash
npm view @vietmap/rn_vietmap_tracking_plugin version   # phải là 0.2.0
npm pack --dry-run                                     # xem gói có gì
```

`docs/` và `example/` **không** vào gói — trường `files` trong `package.json`
chỉ liệt kê `src`, `lib`, `android`, `ios`, `cpp`, `*.podspec`,
`react-native.config.js`.

Xoá file này sau khi xong; [`RELEASING.md`](RELEASING.md) là bản dùng lâu dài.

---

## Cần biết trước khi bấm publish

**Phần lớn code mới chưa chạy thật.** Build xanh cả hai nền và `npm run validate`
xanh cả 5 bước, nhưng đó không phải là đã chạy. Anh đã verify được pop-up quyền
trên Android. Chưa verify:

- Card Health trên iOS — phép thử trực tiếp cho bản sửa `getTrackingHealthStatus`
- Luồng notification: pop-up quyền, banner foreground, chặn dội 30 giây
- Cổng phát hiện fake GPS — **chưa biết SDK có detect trên iOS 26 hay không**
- GPX replay, lưu trạng thái AsyncStorage
- Lifecycle observer native — phải tắt Metro mới chứng minh được không qua bridge

Và 26 mục trong [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) còn
treo, phần lớn là thí nghiệm Step 0 cần máy thật.

Phát hành hay chờ test xong là quyết định của anh. Ghi ra đây để nó là lựa chọn
có ý thức.
