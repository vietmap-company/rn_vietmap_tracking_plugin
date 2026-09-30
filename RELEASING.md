# Hướng dẫn phát hành phiên bản mới

Quy trình để bump và publish `@vietmap/rn_vietmap_tracking_plugin`. Viết cho
người bảo trì tự chạy, không cần hỏi lại.

> Tên file, lệnh và code giữ tiếng Anh vì chúng được gõ thẳng vào terminal.

## Version nằm ở đâu

**Chỉ một chỗ: `package.json`.**

```jsonc
{ "version": "0.2.0" }
```

Những nơi khác đều tự suy ra, không cần sửa tay:

| Nơi | Cách lấy |
|---|---|
| `rn_vietmap_tracking_plugin.podspec` | `s.version = package["version"]` |
| Git tag | `release-it` tạo `v${version}` |
| Android | không khai báo version nào |

Nếu sau này có ai thêm version vào `android/gradle.properties` hay hardcode vào
podspec, bảng này sai — kiểm lại bằng:

```bash
grep -rn '"version"\|s.version\|VERSION_NAME' package.json *.podspec android/gradle.properties
```

## Chọn số version

Gói đang ở `0.x`, nên theo semver:

| Thay đổi | Bump |
|---|---|
| Phá vỡ tương thích API (đổi kiểu, bỏ method, đổi giá trị mặc định) | **minor** — `0.1.4` → `0.2.0` |
| Thêm method, thêm event, không phá vỡ gì | minor |
| Chỉ sửa lỗi, không đổi bề mặt API | patch — `0.2.0` → `0.2.1` |

Ở `0.x`, minor là chỗ dành cho breaking change. Chỉ lên `1.0.0` khi API được
coi là ổn định và cam kết giữ.

Đổi giá trị mặc định cũng là phá vỡ tương thích — ví dụ `backgroundMode` từ
`false` thành `true` ở 0.2.0 làm app đang dùng đổi hành vi mà không sửa dòng nào.

## Trước khi bump: danh sách kiểm

### 1. Không có credential trong source

```bash
grep -rn "API_KEY = '" example/src/ | grep -v 'YOUR_API_KEY_HERE'
```

Phải không ra gì. Key thật trong `example/src/GPSTrackingDemo.tsx` là lỗi hay
gặp nhất vì nó cần thiết khi test.

Nếu key đã lỡ vào lịch sử git:

```bash
git log -S '<vài ký tự đầu của key>' --oneline
```

Ra commit nào thì **phải cấp lại key**. Sửa file ở commit sau không gỡ được nó
khỏi lịch sử.

### 2. `npm run validate` xanh cả 5 bước

```bash
npm run validate
```

Chạy lần lượt:

| Bước | Bắt lỗi gì |
|---|---|
| `check:ios-parity` | Selector khai báo trong `.m` mà Swift không có → crash lúc gọi, compile vẫn sạch |
| `check:pods-path` | Đường dẫn codegen hỏng do `pod install` chạy sai thư mục |
| `typecheck` | |
| `lint` | |
| `test` | Hình dạng object và tên method qua bridge |

Hai check đầu tồn tại vì chúng bắt những lỗi mà **compiler không bắt được** và
chỉ lộ ra lúc chạy hoặc trên máy người khác. Đừng bỏ qua khi vội.

### 3. Build sạch cả hai nền

```bash
cd example/ios && bundle exec pod install     # PHẢI chạy từ example/ios
cd example && yarn ios
cd example/android && ./gradlew assembleDebug
```

**`pod install` phải chạy từ `example/ios`.** React Native nướng đường dẫn tới
`react-native` vào `Pods.xcodeproj` **tương đối với thư mục làm việc** lúc
install. Chạy từ chỗ khác thì đường dẫn leo quá gốc filesystem và bản build sạch
kế tiếp chết với `with-environment.sh: No such file or directory`.

Một bản build local vẫn có thể xanh dù project đã hỏng, vì DerivedData còn giữ
script cũ và Xcode bỏ qua phase đó. `check:pods-path` đọc thẳng project file nên
bắt được. Chi tiết ở `docs/UPGRADE_PLAN.md` finding 14.

### 4. Chạy thật, không chỉ build

Build xanh **không phải** là đã chạy. Tối thiểu nên kiểm:

- Xin quyền vị trí → pop-up hiện, cấp được
- Bắt đầu tracking → điểm về, lịch sử tăng
- Card Health hiện đủ trường trên **cả hai** nền
- Dừng tracking → dừng thật

## Cập nhật CHANGELOG

`CHANGELOG.md` theo định dạng [Keep a Changelog](https://keepachangelog.com/).
Thêm mục mới **lên trên cùng**, dưới phần mở đầu:

```markdown
## [0.3.0] - 2026-11-15

Một dòng tóm tắt bản này mang lại gì.

### Breaking

- Thay đổi gì, và **vì sao** — kèm cách người dùng sửa.

### Added
### Fixed
### Internal
```

Mục **Breaking** nên nói *vì sao*, không chỉ *cái gì*. Người đọc đang tìm hiểu
mình phải sửa gì và có đáng không.

### Lưu ý về `release-it`

`package.json` **từng** cấu hình plugin `@release-it/conventional-changelog`,
vốn tự sinh CHANGELOG từ commit message và **ghi đè** phần viết tay. Plugin đó
đã được gỡ ở 0.2.0:

```jsonc
"release-it": {
  "git": { "commitMessage": "chore: release ${version}", "tagName": "v${version}" },
  "npm": { "publish": true },
  "github": { "release": true }
}
```

Lý do: mục CHANGELOG cần giải thích **vì sao** một thay đổi phá vỡ tương thích
và người dùng phải sửa gì — commit message sinh tự động không nói được điều đó.

Đổi lại, **CHANGELOG phải viết tay trước mỗi lần phát hành**. Không có gì tự
điền hộ nữa.

Gói `@release-it/conventional-changelog` vẫn còn trong `devDependencies`; gỡ
được nếu chắc chắn không quay lại hướng tự sinh.

## Bump và publish

```bash
# 1. Sửa version trong package.json
#    (release-it cũng hỏi được, nhưng sửa tay thì thấy rõ hơn)

# 2. Kiểm lần cuối sau khi đổi số
npm run validate

# 3. Build lại để chắc podspec đọc đúng version mới
cd example/ios && bundle exec pod install && cd ../..

# 4. Phát hành
npm run release
```

> **Tag phải là `0.2.0`, không phải `v0.2.0`.** Podspec khai
> `:tag => "#{s.version}"`, nên CocoaPods đi tìm đúng chuỗi version, không có
> tiền tố. Các bản trước đều tag như vậy: `0.1.2`, `0.1.3`, `0.1.4`.
>
> Cấu hình `release-it` từng để `v${version}` và chưa ai dùng tới — đã sửa ở
> 0.2.0. Nếu sau này đổi sang có tiền tố thì phải đổi cả podspec, nếu không
> CocoaPods sẽ không tải được source.

`npm run release` chạy `release-it --only-version`, và nó sẽ:

1. Hỏi xác nhận version
2. Tạo commit `chore: release ${version}`
3. Tạo tag `${version}` — không tiền tố, khớp podspec
4. Publish lên npm
5. Tạo GitHub release

Cần quyền publish trên npm và quyền push tag lên repo.

### Nếu chỉ muốn bump mà chưa publish

```bash
npm version 0.3.0 --no-git-tag-version   # chỉ sửa package.json
```

Rồi commit tay. Dùng khi muốn tách bước bump khỏi bước publish.

## Sau khi phát hành

- [ ] Kiểm gói đã lên: `npm view @vietmap/rn_vietmap_tracking_plugin version`
- [ ] Kiểm nội dung gói không thừa: `npm pack --dry-run`
      Trường `files` trong `package.json` quyết định cái gì vào gói —
      `src`, `lib`, `android`, `ios`, `cpp`, `*.podspec`,
      `react-native.config.js`. Tài liệu và example **không** vào gói.
- [ ] CocoaPods lấy version từ git tag, nên tag phải được push, và tên tag
      phải khớp `s.version` trong podspec — `0.2.0`, không phải `v0.2.0`
- [ ] Cài thử vào một app sạch bằng version vừa publish

## Những chỗ hay sai

**Quên `pod install` từ `example/ios`.** Xem phần 3 ở trên. Máy anh vẫn build
được trong khi CI và máy đồng nghiệp thì không.

**Tin vào "BUILD SUCCEEDED" trên DerivedData ấm.** Nó có thể xanh trong khi
project đã hỏng. Kiểm project file, đừng kiểm cache.

**`git add .` khi đang có key thật trong example.** Dùng `git add -p` để nhìn
từng thay đổi.

**Đánh dấu xong cho các mục chưa làm.** Các file trong `docs/` ghi lại việc gì
còn treo; tick khống là tự xoá dấu vết của chính mình.

**Bump patch cho một thay đổi phá vỡ tương thích.** Ở `0.x`, breaking change
thuộc về minor. Đổi giá trị mặc định cũng tính là breaking.

## Tài liệu liên quan

| File | Nội dung |
|---|---|
| `docs/UPGRADE_PLAN.md` | 14 finding kỹ thuật — vì sao code hiện tại như vậy |
| `docs/IMPLEMENTATION_PLAN.md` | Kế hoạch 12 step, kèm những mục còn treo |
| `docs/FAKE_GPS_NOTIFICATION_PLAN.md` | Hợp đồng notification giữa SDK và app |
| `docs/TIMESTAMP_FIX_PLAN.md` | Quy ước timestamp và audit hình dạng object |

Đọc `UPGRADE_PLAN.md` trước khi "sửa cho đúng" một chỗ trông lạ — phần lớn
những chỗ đó lạ là có lý do, và lý do nằm ở đó.
