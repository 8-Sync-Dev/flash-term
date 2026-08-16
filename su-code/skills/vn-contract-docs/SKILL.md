---
name: vn-contract-docs
description: Draft Vietnamese contracts, cooperation agreements, and quotations (hợp đồng, thỏa thuận hợp tác, báo giá) as print-ready PDFs, legally correct for an individual WITHOUT business registration (cá nhân chưa ĐKKD/ĐKDN). Use when the user asks to write/fix/render a hợp đồng, thỏa thuận, báo giá, phụ lục, or asks about tax/legal framing for 8 Sync Dev deals. Covers auto-research of Vietnamese law, validated HTML→WeasyPrint pipeline, and the tax decision tree.
---

# vn-contract-docs

Soạn văn bản ký kết VN chuẩn (thỏa thuận hợp tác, hợp đồng dịch vụ/license, báo giá)
→ HTML → WeasyPrint → PDF A4. Validated 2026-07-07 trên Thỏa thuận AcoLeads (7 trang)
và Báo giá cho thuê nền tảng IELTS.

## 0. STOP gates

- **Bên A (8 Sync Dev) hiện là CÁ NHÂN, CHƯA đăng ký hộ kinh doanh/doanh nghiệp.**
  Mọi văn bản PHẢI định danh chủ thể là *"Ông Nguyễn Phương Anh Tú — cá nhân, CCCD …,
  MST = chính số CCCD đó (Thông tư 86/2024/TT-BTC, từ 01/7/2025 — cá nhân KHÔNG cần
  đăng ký MST riêng), hoạt động dưới thương hiệu 8 Sync Dev"*. CẤM ghi "8 SYNC DEV" như một
  đơn vị/pháp nhân độc lập, CẤM "Mã số thuế: …" kiểu doanh nghiệp, CẤM hứa "xuất hóa đơn"
  (cá nhân chưa ĐKKD không xuất được hóa đơn), CẤM "đóng dấu" ở khối ký Bên A.
- Số liệu/giá phải do user chốt hoặc có nguồn; số tiền LUÔN ghi số + (Bằng chữ: …) và
  phải khớp nhau — mẫu thật đã từng lệch (xem `references/samples.md`).
- Căn cứ pháp lý phải CÒN HIỆU LỰC tại ngày ký. Bộ chuẩn 2026:
  BLDS 91/2015/QH13 · Luật Thương mại 36/2005/QH11 · Luật Giao dịch điện tử 20/2023/QH15 ·
  Luật Bảo vệ DLCN 91/2025/QH15 + NĐ 356/2025/NĐ-CP. KHÔNG copy căn cứ từ mẫu cũ
  (mẫu thật 2026 vẫn dẫn BLDS 2005 — sai).

## 1. Auto-research luật (bắt buộc khi đụng thuế/nghĩa vụ mới)

1. Đọc `references/law-2026.md` trước — đã có kết luận + số điều khoản cho các case phổ biến.
2. Điểm chưa có → `web_search` query tiếng Việt + số văn bản. **Thứ tự nguồn bắt buộc:**
   (1) **nguồn chính phủ**: vanban.chinhphu.vn · congbao.chinhphu.vn · xaydungchinhsach.chinhphu.vn
   · cổng Bộ Tài chính/Tổng cục Thuế (mof.gov.vn, gdt.gov.vn) — đây là bản gốc, luôn ưu tiên
   kiểm chứng hiệu lực + bản mới nhất tại đây; (2) thuvienphapluat.vn / luatvietnam.vn để tra
   nhanh toàn văn + tình trạng hiệu lực; đọc qua `read` URL.
3. Mọi kết luận phải kèm (số văn bản, điều/khoản). Văn bản mới chỉ thấy qua báo chí, chưa
   thấy bản gốc trên nguồn chính phủ → đánh dấu ⚠️ và KHÔNG viện dẫn trong hợp đồng;
   chỉ cam kết theo mốc luật đã kiểm chứng bản gốc.
4. Trước khi giao văn bản: re-check từng căn cứ trích dẫn còn hiệu lực ở thời điểm ký
   (luật VN thay nhanh — GTGT/TNCN đổi 2024–2026 liên tục).
5. Cập nhật phát hiện mới vào `references/law-2026.md` (append, giữ nguồn).

## 2. Cây quyết định thuế — cá nhân chưa ĐKKD (chi tiết: references/law-2026.md)

| Bản chất giao dịch | Khung | Thuế | Điều khoản phải viết vào văn bản |
|---|---|---|---|
| Cung cấp SaaS/dịch vụ vận hành liên tục (AcoLeads) | HĐ dịch vụ — bên chi trả khấu trừ tại nguồn | 10% TNCN mỗi lần trả ≥2tr (điểm i k1 Đ25 TT 111/2013) | "Bên B khấu trừ 10% thuế TNCN trước khi chi trả và cấp chứng từ khấu trừ (NĐ 123/2020) cho Bên A; giá tại Điều X là giá trước thuế TNCN. Hồ sơ chi phí của Bên B: Thỏa thuận này + chứng từ thanh toán + chứng từ khấu trừ (Đ4 TT 96/2015)." |
| Cho thuê nền tảng/white-label = chuyển quyền sử dụng phần mềm có thời hạn (IELTS) | HĐ license (bản quyền) | TNCN 5% phần vượt 10tr/hợp đồng (Đ13 + điểm d k1 Đ25 TT 111/2013); KHÔNG GTGT (phần mềm miễn GTGT — Đ5 Luật 48/2024) | Điều khoản license (phạm vi, thời hạn, không chuyển nhượng), khấu trừ 5% tại nguồn, chứng từ khấu trừ |
| Doanh thu lớn / nhiều khách / dài hạn | Đăng ký HKD, kê khai + HĐĐT (khuyến nghị nêu trong văn bản như lộ trình) | Dịch vụ phần mềm: 0% GTGT + 2% TNCN; ≤200tr/năm: miễn cả hai (k25 Đ5 Luật 48/2024, từ 01/01/2026) | Khi có HKD: chuyển sang xuất HĐĐT, bỏ điều khoản khấu trừ hộ |

Rủi ro phải cảnh báo user (không tự quyết im lặng): SaaS định kỳ kéo dài = kinh doanh
thường xuyên → nghĩa vụ đăng ký HKD (k2 Đ79 NĐ 01/2021), không đăng ký phạt 5–10tr
(k1 Đ62 NĐ 122/2021) + rủi ro truy thu. Ghi khuyến nghị này vào summary gửi user.

## 2b. Nguyên tắc soạn thảo nghiêng về Bên A (BẮT BUỘC — đọc kỹ trước khi viết điều khoản)

Văn bản phải đọc lên là **Bên B thắng lớn** (ưu đãi sâu, miễn phí khởi tạo, quyền lợi tiên
phong) nhưng cấu trúc quyền — nghĩa vụ để **Bên A giữ lợi thế và quyền kiểm soát dài hạn**.
Mọi cơ chế đều hợp pháp, viết rõ trên giấy — sức nghiêng nằm ở THIẾT KẾ điều khoản, không
nằm ở che giấu. KHÔNG bao giờ dùng phí ẩn, điều khoản vô hiệu (Đ123, Đ405 BLDS 2015) hay
lừa dối (Đ127 BLDS) — vừa phi pháp vừa vô hiệu hóa hợp đồng.

Hộp công cụ (chọn theo deal, rải đều vào các Điều khác nhau để không dồn "mùi" một chỗ):

| Cơ chế | Bên B đọc thấy | Giá trị thật cho Bên A |
|---|---|---|
| Ưu đãi sâu "năm đầu/khách hàng đầu tiên" trên giá niêm yết do A tự công bố | Giảm 40–60%, tổng "tiết kiệm" lớn | Neo giá (anchor): giá gia hạn = bảng giá công bố **tại thời điểm gia hạn** − chiết khấu nhỏ; A tự do tăng niêm yết |
| Ưu đãi gắn điều kiện hạnh kiểm: "hưởng ưu đãi khi thanh toán đúng hạn" | Câu hiển nhiên, ai cũng định trả đúng hạn | Chậm hạn = mất ưu đãi kỳ đó → đòn bẩy thu hồi công nợ mạnh hơn phạt lãi |
| Hạng mục miễn phí "không quy đổi hoàn tiền khi chấm dứt sớm" | Được miễn phí là quà | Khóa chân (sunk cost) — B rời sớm là "mất quà", A không phải hoàn gì |
| Quyền lợi tiên phong: nêu tên, case study, "đối tác chiến lược đầu tiên" | Vinh dự, được quảng bá miễn phí | A lấy social proof + tư liệu bán hàng cho mọi khách sau |
| Số liệu đo đếm (học viên hoạt động, token, uptime) "theo hệ thống của nền tảng" | Câu kỹ thuật trung tính | A nắm cân — căn cứ đối soát duy nhất là số A đo |
| Trần trách nhiệm: bồi thường tối đa = phí B đã trả 03 tháng gần nhất | Ít ai đọc kỹ điều bồi thường | Rủi ro của A bị chặn trần; của B thì theo thiệt hại thực tế |
| "Mục tiêu phản hồi 04 giờ" (không phải "cam kết") + SLA % chỉ ở gói cao nhất | Nghe như có SLA | Không có chế tài nếu trễ; SLA thật chỉ bán kèm gói đắt |
| Nghiệm thu tự động: dùng quá X ngày không khiếu nại bằng văn bản = đã nghiệm thu | Điều khoản thủ tục | Chặn khiếu nại muộn, chốt công nợ sớm |
| Lộ trình tính năng "do Bên A quyết định, ưu tiên lắng nghe Bên B" | Được ưu tiên lắng nghe | A toàn quyền roadmap, không nợ cam kết tính năng |
| Non-compete + cấm dịch ngược 24 tháng sau kết thúc | Điều bảo mật thông thường | Chặn B tự xây bản nhái sau khi học được quy trình |
| Phụ phí vượt hạn mức = chi phí gốc + % quản trị, "lập Phụ lục xác nhận trước khi áp dụng" | Minh bạch, có đối soát | Chi phí biến động của A được pass-through trọn + biên lợi nhuận |

Quy tắc hành văn: điều có lợi cho A viết bằng giọng **thủ tục — kỹ thuật — hiển nhiên**
(càng nhàm càng tốt); điều có lợi cho B viết bằng giọng **quyền lợi — con số — in đậm**.
Không nói dối về bất kỳ con số/sự kiện nào. Checklist mục 6 có mục đối chiếu riêng.

## 2c. Pattern "khách hàng đầu tiên" (first-customer)

Khi Bên B là khách hàng triển khai đầu tiên của một nền tảng:
- Ghi NHẬN VỊ THẾ rõ trong Điều mục đích: "Bên B là khách hàng/đối tác triển khai đầu tiên"
  + quyền lợi tiên phong (giá khóa 12 tháng, ưu tiên đề xuất tính năng, hỗ trợ ưu tiên).
- Đổi lại (viết như vinh dự): A được nêu tên B làm đối tác ra mắt, case study, số liệu
  ẩn danh — cần chấp thuận nội dung cụ thể nhưng KHÔNG được từ chối bất hợp lý.
- Nền tảng mới → điều khoản nghiệm thu theo danh mục bàn giao + nghiệm thu tự động sau
  X ngày sử dụng; sự cố giai đoạn đầu xử lý theo kênh hỗ trợ, không mặc nhiên là vi phạm.
- Trung thực về trạng thái sản phẩm với USER (pre-launch thì nói pre-launch trong summary);
  trong văn bản không claim gì chưa có thật (số khách, uptime lịch sử…).

## 2d. Chiến lược giá — thâm nhập, thấp hơn thị trường 3–4 lần (BẮT BUỘC khi báo giá)

Sản phẩm của user cạnh tranh bằng GIÁ THẤP: mục tiêu **rẻ hơn mặt bằng thị trường 3–4 lần**
(càng thấp càng tốt), không định giá theo "giá trị" hay ngang thị trường.

1. **Research giá thị trường TRƯỚC khi đặt số** (`web_search` tiếng Việt, sản phẩm cùng
   phân khúc VN, ghi nguồn + ngày khảo sát): lấy dải giá phổ biến làm mốc.
2. **Đặt giá niêm yết = mốc thị trường ÷ 3~4**; giá ưu đãi năm đầu/khách hàng đầu tiên
   thấp hơn niêm yết thêm ~30–50%.
3. **Neo so sánh NGAY TRONG văn bản** ("thị trường X–Ytr/năm, giá này = 1/3–1/4") — giá rẻ
   phải đọc ra là chiến lược thâm nhập có chủ đích, không phải hàng kém.
4. **Bảo vệ biên khi giá thấp** (đi cặp với mục 2b): chi phí biến đổi (AI token, hạ tầng
   vượt hạn mức) LUÔN pass-through cost+%, không bao trọn; ưu đãi gắn điều kiện đúng hạn;
   neo giá gia hạn theo bảng giá công bố mới.
5. **Liệt kê ĐỦ mọi gói** trong văn bản với ô tích chọn (khách chốt gói sau khi ký) +
   điều khoản **tự do chuyển đổi gói**: nâng gói hiệu lực ngay (thu chênh lệch pro-rata),
   hạ gói hiệu lực từ đầu kỳ thanh toán kế tiếp — giữ doanh thu kỳ hiện tại (nghiêng-A).
6. **Chào kèm phương án MUA ĐỨT** khi sản phẩm cho thuê (khách muốn brand riêng vĩnh viễn):
   giá mua đứt ≈ 2,5–3× giá thuê năm niêm yết, ưu đãi đối tác đầu tiên giảm sâu (~40%);
   **bảo trì & cải tiến là NGHĨA VỤ GẮN LIỀN** — 2 track cho khách chọn, đổi được theo năm:
   (a) bảo trì nền (feat cũ) ~15%/năm giá mua, (b) đồng hành roadmap ~25%/năm; ngừng bảo
   trì = A hết trách nhiệm lỗi/bảo mật, khôi phục >90 ngày kèm phí rà soát. Custom feat =
   Phụ lục ngày công riêng (niêm yết ~2tr/ngày công, năm đầu −30%), IP custom thuộc A,
   khách dùng vô thời hạn. Ở giá thâm nhập KHÔNG kèm mã nguồn, KHÔNG độc quyền thị trường
   — khách đòi 2 thứ đó là bảng giá khác hẳn (nói rõ với user trước khi hứa). Hạ tầng sau
   mua đứt: khách đứng tên chi trả, hoặc A vận hành hộ pass-through cost+20%.

## 3. Giải phẫu văn bản (chuẩn rút từ 3 mẫu đã ký — references/samples.md)

Thứ tự bắt buộc: Quốc hiệu-tiêu ngữ → Tên VB + Số `NN/NĂM/LOẠI-VIẾTTẮT` → "Căn cứ:"
(luật còn hiệu lực, có số hiệu + "Nhu cầu và năng lực thực tế của hai Bên") → "Hôm nay,
ngày… tại…, chúng tôi gồm:" → Bên A/Bên B → các Điều → khối ký.

- Định danh **cá nhân**: Họ tên + ngày sinh + CCCD (số/ngày/nơi cấp) + địa chỉ + SĐT
  + MST (= chính số CCCD theo TT 86/2024 — ghi "là số định danh cá nhân nêu trên", KHÔNG để trống) + STK/ngân hàng. **Pháp nhân**: tên + địa chỉ trụ sở + MST +
  Đại diện + Chức vụ (+ số Giấy ủy quyền nếu người ký không phải đại diện pháp luật).
- Điều cuối luôn gồm: hiệu lực từ ngày ký · số bản + "giá trị pháp lý như nhau" ·
  "Phụ lục là bộ phận không tách rời". Câu tự thanh lý (HĐ mua bán gọn): "Hợp đồng sẽ
  tự động thanh lý sau khi 02 bên hoàn thành nghĩa vụ của mình."
- Khối ký: cá nhân = "BÊN A" + "(Ký, ghi rõ họ tên)" + tên — KHÔNG chức vụ, KHÔNG dấu.
  Tổ chức = "ĐẠI DIỆN BÊN B" + chức danh + "(Ký, ghi rõ họ tên, đóng dấu)".
- Bảng giá (báo giá/HĐ mua bán): `STT | Hạng mục | SL | Đơn giá | Thành tiền` + dòng
  thuế riêng + Tổng cộng (số + bằng chữ).
- Báo giá thêm: hiệu lực báo giá (30 ngày), điều kiện thanh toán, timeline triển khai,
  ghi chú cơ chế thuế để bên nhận hạch toán được.

## 4. Pipeline render (validated — KHÔNG cần pandoc/latex/typst)

Máy không có pandoc/latex/libreoffice; dùng **HTML + WeasyPrint qua uv**:

```bash
# mỗi văn bản 1 thư mục: docs/legal/<slug>/{document.html,build.sh}
uv run --with weasyprint python -m weasyprint document.html output.pdf
```

- Template CSS chuẩn VN (A4, footer số trang, quốc hiệu, party-grid, bảng, khối ký):
  copy từ `~/Projects/startup/AcoLeads/docs/legal/thoa-thuan-hop-tac-acoleads/agreement.html`
  (đã validated 7 trang). Font: "Times New Roman" alias → Liberation Serif qua fontconfig.
- `@page` có `@bottom-left` (số VB) + `@bottom-right` "Trang N/M"; `tr { page-break-inside:
  avoid }`; khối ký `.sig-table` + `.sig-space` 30mm; `.keep { page-break-inside: avoid }`.
- Verify sau render: (1) số trang như dự kiến (pypdf), (2) `pdftotext | grep` các chuỗi
  then chốt (tên chủ thể, số tiền, điều khoản thuế), (3) đối chiếu tiền số ↔ bằng chữ,
  (4) mở PNG/screenshot xem tràn trang nếu sửa layout.

## 5. Checklist trước khi giao

- [ ] Chủ thể đúng tư cách pháp lý (cá nhân ≠ thương hiệu ≠ pháp nhân)
- [ ] Căn cứ luật còn hiệu lực, có số hiệu
- [ ] Điều khoản thuế đúng cây quyết định mục 2 + nêu ai khấu trừ, chứng từ gì
- [ ] Tiền: số = bằng chữ, cộng dồn đúng
- [ ] Điều thi hành: hiệu lực, số bản, phụ lục không tách rời
- [ ] Khối ký đúng vai (cá nhân không dấu/chức vụ)
- [ ] PDF render đúng số trang, không tràn/vỡ bảng
- [ ] Pass nghiêng-A (mục 2b): mỗi ưu đãi cho B có đối trọng cho A ở điều KHÁC; trần trách
      nhiệm + neo giá gia hạn + điều kiện hưởng ưu đãi + nghiệm thu tự động có mặt; giọng
      văn điều-lợi-A là thủ tục/kỹ thuật, điều-lợi-B là quyền lợi/in đậm
- [ ] Căn cứ trích dẫn đã kiểm chứng trên nguồn chính phủ (mục 1) — không dẫn văn bản ⚠️
- [ ] Summary gửi user: các giả định + cảnh báo nghĩa vụ đăng ký HKD

## 6. Vị trí skill

Skill tự viết của dự án đặt tại `writter-ai/skills/<name>/` (KHÔNG đặt trong
`su-code/skills/` — folder đó được sync từ `~/Projects/tools/su-code/`, sẽ bị ghi đè).
Mirror thêm vào `~/.omp/skills/` để dùng cross-project.
