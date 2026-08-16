# Cấu trúc server Discord — 8 Sync Forum: hiện trạng và đích đến

**Cách đọc file này.** Mọi dòng có nhãn `[QUAN SÁT]` là thứ nhìn thấy trực tiếp trên ảnh chụp
màn hình founder gửi ngày **02/08/2026** (tài khoản `8 Sync Dev`, server **8 Sync Forum**).
Mọi dòng có nhãn `[ĐỀ XUẤT]` là khuyến nghị của skill này, **chưa ai duyệt**, founder chốt thì
mới làm. Không trộn hai loại — quyết định sai hay bắt đầu từ chỗ tưởng đề xuất là sự thật.

---

## 1. Hiện trạng `[QUAN SÁT]`

| Nhóm | Kênh | Ghi chú quan sát |
|---|---|---|
| Thông tin | `quy-tắc` · `nguồn-tự-học` · `câu-hỏi` · `thông-báo-mới` | Đủ bộ khung tối thiểu |
| Cập nhật tin tức mới | `lập-trình-công-nghệ-mới` · `lập-trình-website` · `kĩ-thuật-lập-trình` · `lập-trình-ứng-dụng-ai` · `bài-tập-lập-trình` · `lập-trình-game` | 6 kênh nội dung, chia theo chủ đề |
| Trao đổi và Giúp đỡ | `thảo-luận-trên-post` · `sửa-lỗi-lập-trình` · `sửa-lỗi-deployment` | `sửa-lỗi-lập-trình`: tin nhắn cuối **25/4/2026** |
| Kênh Thoại | `Giao lưu chia sẻ` · `pygenai-010225-lớp-python-cơ-...` · `py-dsa-genai-02` | 2/3 kênh thoại là phòng lớp cũ |
| Lớp học | `django-course` · `py-a-z-and-genai-10t62025` · `pygenai-010225-lớp-python-cơ-...` | Tên kênh gắn khoá đã kết thúc |

**Hai sự thật nặng nhất `[QUAN SÁT]`:**

1. **Server không được kiểm duyệt.** Kênh `sửa-lỗi-lập-trình` còn nguyên **spam chèn link
   Telegram bán tài khoản kèm ảnh scam rút tiền USDT**, chưa ai xoá. Người mới vào thấy cảnh này
   trước khi thấy nội dung tử tế — đây là lỗ hổng uy tín, không phải chuyện dọn dẹp cho gọn.
2. **Kênh chết.** Tin nhắn gần nhất ở kênh trao đổi chính là **25/4/2026** — hơn 3 tháng. Kênh
   im mà vẫn để hiện là tín hiệu "chỗ này bỏ hoang" gửi tới mọi khách mới.

---

## 2. Thiếu gì so với một server cộng đồng dev VN chạy được

Đối chiếu thẳng với bảng ở §1. Cột cuối nói **vì sao thiếu nó thì đau**, không phải "nên có cho
đủ bộ".

| Thiếu | Trạng thái | Hậu quả đang chịu |
|---|---|---|
| Kênh **onboarding / giới thiệu bản thân** | `[QUAN SÁT]` không có | Người mới vào không có việc gì để làm ở phút đầu → thoát. Không có chỗ này thì cũng không đo được ai thực sự đang vào |
| Kênh **video mới từ YouTube** | `[QUAN SÁT]` không có | Kênh `@Dev8Sync` có **313 video · 2.490 người đăng ký** (verify 02/08/2026) mà server không có đường dẫn về. Theo doctrine 02/08/2026, YouTube là **đích của phễu** — thiếu kênh này là cắt đứt mắt xích chính |
| Kênh **khoe thành quả** (show-your-work) | `[QUAN SÁT]` không có | Không có nơi nào chứa bằng chứng học viên làm được gì → mất luôn kho nội dung xã hội chứng thực, thứ đắt nhất và không mua được |
| Kênh **việc làm / cơ hội** | `[QUAN SÁT]` không có | Lý do người ta ở lại một server dev lâu dài. Không có thì họ ở lại nhóm khác |
| **AutoMod** chặn link Telegram/scam | `[QUAN SÁT]` chưa bật (spam còn nguyên) | Spam sống nhiều ngày trong kênh kỹ thuật |
| **Role tự chọn** (ngôn ngữ/mảng quan tâm) | `[QUAN SÁT]` không thấy | Không nhắm được thông báo → mọi tin đều @everyone hoặc không ai thấy |
| **Archive kênh lớp đã kết thúc** | `[QUAN SÁT]` 3 kênh `Lớp học` + 2 kênh thoại mang tên khoá cũ | Sidebar dài, kênh im, khách tưởng server chết |
| **Quy tắc có hiệu lực** | `[QUAN SÁT]` có kênh `quy-tắc`, nhưng spam vẫn tồn tại | Quy tắc không được thi hành thì bằng không có |

---

## 3. Sơ đồ kênh mục tiêu `[ĐỀ XUẤT]`

Nguyên tắc: **ít kênh, mỗi kênh có một việc rõ ràng, kênh nào không có người nói trong 30 ngày
thì gộp hoặc archive.** Thà 12 kênh sống còn hơn 20 kênh im.

```
BẮT ĐẦU Ở ĐÂY
  #quy-tắc            (giữ)   read-only, thêm 3 dòng về scam DM
  #chào-hỏi           (MỚI)   giới thiệu 1 dòng: tên · đang học gì · mục tiêu
  #thông-báo-mới      (giữ)   read-only, chỉ mod đăng

HỌC VÀ LUYỆN
  #video-mới          (MỚI)   video mới của @Dev8Sync — đích của phễu, đăng đều
  #tin-công-nghệ      (gộp)   từ lập-trình-công-nghệ-mới + lập-trình-website
                              + kĩ-thuật-lập-trình + lập-trình-ứng-dụng-ai + lập-trình-game
  #bài-tập-lập-trình  (giữ)   đề từ coding.8syncdev.com, mỗi ngày 1 đề
  #nguồn-tự-học       (giữ)   read-only + ghim, chỉ mod thêm

HỎI VÀ GỠ
  #câu-hỏi            (giữ)   hỏi gì cũng được, bot trả lời câu lặp
  #sửa-lỗi-lập-trình  (giữ)   dùng Forum channel, mỗi lỗi 1 post, giải xong đổi tag
  #sửa-lỗi-deployment (giữ)

CỘNG ĐỒNG
  #khoe-thành-quả     (MỚI)   ảnh/link sản phẩm, chỉ đăng kèm thứ chạy được
  #việc-làm           (MỚI)   tin tuyển + tìm việc, 1 post 1 tin, cấm môi giới
  #chuyện-ngoài-lề    (MỚI)   để chuyện phiếm không tràn vào kênh kỹ thuật

THOẠI
  🔊 Giao lưu chia sẻ  (giữ)
  🔊 Học chung         (MỚI)   phòng im lặng học cùng, thay 2 phòng lớp cũ

LƯU TRỮ  (category riêng, quyền read-only, thu gọn cuối sidebar)
  #django-course · #py-a-z-and-genai-10t62025 · #pygenai-010225-...
```

**Vì sao gộp 5 kênh tin thành `#tin-công-nghệ`:** cả 5 kênh cùng nguồn news.8syncdev.com và cùng
tệp người đọc; chia nhỏ chỉ làm mỗi kênh có 1 bài/tuần, nhìn như bỏ hoang. Muốn lọc chủ đề thì
dùng **tag của Forum channel** hoặc role tự chọn, đừng dùng thêm kênh.

**Role tự chọn `[ĐỀ XUẤT]`** — 6 role, gắn vào một tin nhắn có nút ở `#chào-hỏi`:
`Người mới` · `Web` · `AI/ML` · `Backend` · `Thuật toán` · `Đang tìm việc`. Thông báo bắn theo
role, không @everyone. `@everyone` chỉ dùng cho việc thật sự cả server cần biết (tối đa 1 lần/tuần).

**AutoMod `[ĐỀ XUẤT]`** — bật ở Server Settings → AutoMod, 4 luật, tất cả đặt hành động
**chặn tin nhắn + báo vào kênh mod**:

| Luật | Nội dung chặn | Vì sao |
|---|---|---|
| Chặn link mời ngoài | `t.me/`, `telegram.me`, `discord.gg/` (trừ link mời của chính server) | Đúng loại spam đang nằm trong `sửa-lỗi-lập-trình` |
| Từ khoá tài chính | `usdt`, `rút tiền`, `kèo`, `bán acc`, `bán tài khoản`, `nạp tiền`, `sàn` | Ảnh scam rút tiền USDT đã xuất hiện thật |
| Spam mention | Quá 5 mention trong một tin | Kiểu tấn công kèm theo của cùng nhóm spam |
| Thành viên mới | Người vào dưới 24 giờ không được đăng link | Bot spam luôn đăng ngay sau khi vào |

Ba tầng còn lại, không có thì AutoMod vẫn thủng: bật **Verification Level = Medium** (email đã
xác thực + ở Discord ≥5 phút), bật **quét media của mọi thành viên**, và tắt DM từ người lạ ở
`Privacy Settings` cấp server.

---

## 4. Thứ tự thực hiện `[ĐỀ XUẤT]`

Làm từ trên xuống. Mỗi bước xong thì dừng lại xem kết quả, đừng làm một lượt cả 7 bước.

1. **Dọn spam (làm ngay hôm nay).** Xoá bài Telegram + ảnh scam USDT ở `sửa-lỗi-lập-trình`, ban
   tài khoản đăng, xoá luôn mọi tin nhắn khác của tài khoản đó. Đây là việc duy nhất không cần
   chờ ai duyệt.
2. **Bật AutoMod + Verification Level** theo bảng §3. Khoảng 10 phút, chặn được lần tái diễn.
3. **Dựng category `LƯU TRỮ`** rồi chuyển 3 kênh lớp cũ + 2 phòng thoại lớp cũ vào, đặt read-only.
   Không xoá — lịch sử lớp là tài sản, chỉ cần thôi chiếm chỗ.
4. **Mở 4 kênh mới**: `#chào-hỏi`, `#video-mới`, `#khoe-thành-quả`, `#việc-làm`. Mở kênh xong phải
   có sẵn 3–5 bài mẫu, kênh trống là kênh chết ngay từ ngày đầu.
5. **Gộp 5 kênh tin** thành `#tin-công-nghệ`, ghim thông báo gộp ở kênh cũ 7 ngày rồi mới archive.
6. **Viết lại `#quy-tắc`** — 7 dòng, có 3 dòng về scam DM (không ai của team nhắn riêng mời mua
   gì) và 1 dòng về cách hỏi lỗi đúng chuẩn.
7. **Mời bot** (`scripts/discord-bot.mjs`) vào, chạy `--dry-run` một ngày ở `#câu-hỏi` để xem nó
   định trả lời gì, chỉnh `brand-answers.md`, rồi mới cho gửi thật.

---

## 5. Đo bằng gì `[ĐỀ XUẤT]`

Không có Insights thì cũng đếm tay được, quan trọng là đếm cùng một cách mỗi tuần:

- **Số người tự giới thiệu ở `#chào-hỏi`/tuần** — đại lượng gần nhất với "người mới thật".
- **Số ngày liên tiếp `#câu-hỏi` có tin nhắn của người ngoài team** — 0 nghĩa là server vẫn chết.
- **Số bài ở `#khoe-thành-quả`/tháng** — nguồn nội dung xã hội chứng thực cho MKT.
- **Số click sang YouTube/coding**, đọc từ trang analytics riêng khi founder dựng xong
  (`org-core/products.md` §KPI: chưa có nguồn số, không bịa).
- **Số lần AutoMod chặn/tuần** — có số này mới biết luật ở §3 có đúng chỗ không.

**Sổ cái bài đăng — có một lỗ đã kiểm chứng.** `post-ledger.js` chốt cứng 7 nền tảng
(`facebook`, `facebook_group`, `instagram`, `threads`, `linkedin`, `tiktok`, `youtube`) và
**không có `discord`**, nên `add --platform discord` bị từ chối ngay. Trong lúc chờ chủ file đó
thêm nền tảng, chống trùng cho Discord dựa vào chính lịch sử kênh: trước khi đăng thì tìm slug
bài trong kênh đích (Discord có search theo kênh), trùng thì bỏ. Đừng ghi bừa sang nền tảng khác
cho "có ghi" — sổ sai còn tệ hơn sổ trống.
