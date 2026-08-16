---
name: tauri-ui-test
description: Use when verifying that buttons and features in a Tauri v2 desktop app on Windows actually work at runtime — clicking real buttons, reading the live UI, and proving an action had an effect. Covers "button does nothing when clicked", open-folder/save-file/dialog buttons, IPC-backed actions, and any claim that a UI change works that would otherwise rest only on a green build. Not for pure web apps (use a browser tool) and not for backend-only work.
---

Bấm nút THẬT trên app Tauri đang chạy và chứng minh nút có tác dụng.

## Quy tắc gốc: build xanh không phải bằng chứng

`cargo build` + `tsc` xanh chỉ nói code biên dịch được. Nút vẫn có thể chết vì
thiếu quyền ACL, đường dẫn sai, hoặc lỗi bị `catch {}` nuốt. Bằng chứng một nút
chạy được luôn là **hiệu ứng quan sát được**, xếp theo độ tin cậy giảm dần:

1. Thay đổi ngoài app: file/thư mục xuất hiện trên đĩa, cửa sổ Explorer mở, hộp
   thoại hệ thống hiện lên, HTTP endpoint đổi trạng thái.
2. Thay đổi dữ liệu trong UI: số đếm đổi (`2 model` → `3 model`), dòng mới trong
   bảng, badge đổi trạng thái.
3. Nhãn nút đổi (`Lưu` → `Đã lưu`). Yếu nhất: chỉ sống ~2 giây, đọc trễ là tưởng
   nút chết.

Đừng bao giờ báo "đã verify" khi chỉ có mức 3, hoặc khi chỉ đọc code.

## Chọn đường điều khiển (đọc trước khi thử)

| Cách | Kết luận | Vì sao |
|---|---|---|
| **UI Automation** | **DÙNG CÁI NÀY** | Đọc thẳng cây accessibility của WebView2, gọi `InvokePattern.Invoke()`, không cần toạ độ, không cần app ở foreground. |
| Trình duyệt + dev server `:1420` | Chỉ xem bố cục | Trang mở được nhưng `__TAURI_INTERNALS__` không tồn tại ⇒ mọi nút gọi IPC báo "Không có bridge Tauri". Không kiểm chứng được nút. |
| `--remote-debugging-port` (CDP) | Không mở được | Đã thử cả `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` lẫn đặt biến trong PowerShell; cổng 9222 không bao giờ lắng nghe. |
| Giả lập chuột `mouse_event` | Đừng dùng | Thất bại ÂM THẦM: Windows chặn `SetForegroundWindow`, cửa sổ tự dời làm lệch toạ độ, và có lần click trúng nút Close làm app thoát giữa chừng. |

## Quy trình

```bash
APP=app/src-tauri/target/debug/eightic.exe
S=su-code/skills/tauri-ui-test/scripts

# 1. Dev server + app (bản debug nạp UI từ :1420, thiếu nó là trang trắng)
(cd app && pnpm dev &) ; sleep 8
(./$APP &) ; sleep 15

# 2. Đọc toàn bộ UI hiện có — luôn làm trước khi bấm
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $S/uia.ps1 \
  -Action dump -Out "$PWD/runtime/uidump.txt"
grep -a "Button" runtime/uidump.txt

# 3. Ghi trạng thái TRƯỚC (baseline)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $S/winprobe.ps1 -Action count-explorer

# 4. Bấm — tên có dấu tiếng Việt phải qua file UTF-8
printf 'Mở thư mục' > runtime/btn.txt
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $S/uia.ps1 \
  -Action click -NameFile "$PWD/runtime/btn.txt"

# 5. Đo hiệu ứng
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $S/winprobe.ps1 -Action count-explorer
```

## Bẫy đã trả giá

- **Tên tiếng Việt qua dòng lệnh hỏng mã.** `-Name 'Mở thư mục'` từ Git Bash →
  `KHONG_THAY_NUT`. Luôn `printf ... > btn.txt` rồi `-NameFile`.
- **Output PowerShell qua pipe của Git Bash mất sạch** (0 dòng). Ghi ra file bằng
  `[System.IO.File]::WriteAllLines(path, lines, UTF8)` rồi `grep -a`.
- **Explorer không hiện trong `Shell.Application.Windows()` hay `MainWindowTitle`**
  — cả hai trả rỗng. Lọc theo class `CabinetWClass`/`ExploreWClass`.
- **Hộp thoại Save As là cửa sổ top-level class `#32770`**, không nằm trong cây
  UIA của app. Tìm từ app chỉ ra một Text trùng tên, không có ô nhập.
- **Bản debug cần dev server.** Quên `pnpm dev` ⇒ app hiện trang
  `ERR_CONNECTION_REFUSED`, mọi nút "biến mất" mà không có lỗi nào.
- **Windows khoá `.exe` khi app đang chạy** ⇒ tắt app trước `cargo build`.
- **Đừng dựa vào tiến trình `explorer.exe`.** Nó chạy rồi thoát ngay
  (`HasExited=True`), giao việc cho shell. Đếm CỬA SỔ, không đếm tiến trình.

## Kiểm chứng chéo khi kết quả mơ hồ

Nếu không quan sát được hiệu ứng, chạy cùng thao tác bằng lệnh chuẩn của HĐH
(`explorer.exe <path>`) rồi so sánh. Kết quả giống nhau ⇒ giới hạn của phép đo,
không phải lỗi nút. Kết quả khác nhau ⇒ nút thật sự hỏng.
