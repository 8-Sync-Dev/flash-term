# Kho câu trả lời chuẩn brand — Discord 8 Sync Dev

File này là **thứ duy nhất** bot `scripts/discord-bot.mjs` được phép nói. Bot không sinh chữ,
không gọi LLM: nó khớp câu hỏi → trả nguyên văn phần thân của mục khớp nhất. Sửa file này =
sửa mồm bot, không cần đụng code.

Sự thật lấy từ `org-core/products.md` + `org-core/brand.md` (đọc lại trước khi sửa số).
Giọng và danh sách cụm cấm: cổng canonical là
`../../org-social-ops/references/prompt-library-mkt02.md` PHẦN 1 — không chép sang đây.

## Cách dùng file này

<!-- Mục này không có dòng `keywords:` nên bot bỏ qua. Dùng để ghi luật cho người sửa. -->

Luật viết một mục (vi phạm là bot nói sai brand):

1. Tiêu đề `## <chủ đề>` — đặt như tên việc, không phải câu quảng cáo.
2. Dòng `keywords:` — các cụm cách nhau bởi dấu phẩy. Bot bỏ dấu tiếng Việt trước khi so, nên
   viết có dấu cho người đọc là đủ. Một cụm chỉ tính khớp khi **đủ mọi từ** của nó có trong câu
   hỏi (không cần đúng thứ tự), và ăn **điểm bằng số từ** — cụm 3 từ thắng cụm 1 từ. Ngưỡng mặc
   định là 2 ⇒ **một từ đơn lẻ không bao giờ đủ để bot mở miệng**. Đừng thêm cụm 1 từ quá chung
   (`học`, `code`, `lỗi`) — nó kéo mọi câu hỏi về một mục.
3. Phần thân: **tối đa 4 câu**, tiếng Việt 100%, giọng người thật. Không "hãy", không "đừng bỏ
   lỡ", không giọng PR, **KHÔNG câu comment** ("inbox mình", "comment để nhận link").
4. **Link đặt ở DÒNG CUỐI, và YouTube đứng đầu** (doctrine 02/08/2026: YouTube là đích của
   phễu). Discord không bóp reach link nên link nằm thẳng trong body — đây là ngoại lệ so với
   Facebook/Threads.
5. Số nào không có trong `org-core/` thì không được viết ra.

Kênh YouTube: `youtube.com/@Dev8Sync` (2.490 người đăng ký · 313 video, verify 02/08/2026).
Handle `@8syncdev` trên YouTube **không tồn tại** — dùng là ra 404.

## ZUS AI IDE là gì

keywords: zus, zus là gì, zus ide, ai ide, ide 8 sync, zus dùng làm gì, zus có gì

ZUS là AI IDE do 8 Sync Dev tự làm: đủ workbench kiểu VS Code (Monaco, terminal, Source Control
kèm git graph, search project) nhưng installer chỉ **22,3 MB**, nhẹ khoảng 9 lần, vì lõi là
Tauri 2 + Rust chứ không nhúng Chromium. Agent trong ZUS tự lập plan, chạy tool rồi verify ngay
trong editor, có 3 mức tự chủ (hỏi trước / được sửa file / tự chạy) và chat tiếng Việt ngay cạnh
code. Index và embedding chạy local nên code ở lại máy bạn, chỉ câu hỏi mới rời máy. Bản free có
quota AI mỗi ngày, license MIT.
Video demo: https://www.youtube.com/@Dev8Sync · Tải: https://zus.8syncdev.com

## Cài ZUS thế nào

keywords: cài zus, tải zus, download zus, winget zus, scoop zus, cài đặt zus, link tải zus, cài đặt ide

Trên Windows đường chắc ăn nhất lúc này là scoop: `scoop bucket add zus https://github.com/8syncdev/scoop-zus`
rồi `scoop install zus`. Bản winget mang id `8syncdev.ZUS` (`winget install 8syncdev.ZUS`) đang
trên đường ra, chưa chốt ngày, nên gặp lỗi "no package found" thì quay về scoop. Không dùng
package manager thì tải thẳng installer 22,3 MB ở trang release — có `SHA256SUMS` và chữ ký
minisign để đối chiếu trước khi chạy. Cài xong mở lên dùng luôn, không cần key.
Hướng dẫn bằng video: https://www.youtube.com/@Dev8Sync/videos · Release: https://github.com/8syncdev/zus-releases

## Lỗi khi cài ZUS

keywords: lỗi cài, zus lỗi, không cài được, cài không được, lỗi khi cài, smartscreen, chặn cài, mở không lên, cài xong không chạy

Ba lỗi hay gặp nhất: Windows SmartScreen chặn file lạ (bấm **More info → Run anyway**), scoop báo
không thấy package (chạy `scoop update` rồi `scoop bucket add zus ...` lại), và file tải dở làm
app mở không lên (đối chiếu `SHA256SUMS` ở trang release, sai thì tải lại). Máy chặn theo chính
sách công ty thì cài bản portable từ release thay vì installer. Vẫn hỏng thì chụp màn hình lỗi +
phiên bản Windows, đăng vào kênh `sửa-lỗi-lập-trình`, đừng gửi tin nhắn riêng cho ai.
Video hướng dẫn cài: https://www.youtube.com/@Dev8Sync/videos · Release: https://github.com/8syncdev/zus-releases

## Bài tập luyện code free

keywords: bài tập, bài tập free, luyện code, luyện thuật toán, thuật toán, dsa, chấm bài, làm bài ở đâu, coding 8syncdev

Có **1.000 bài** luyện thuật toán, free hết, không pay-to-win: 477 dễ · 325 trung bình · 174 khó ·
24 expert, chia theo Cơ bản, Toán/Số học, Chuỗi, Cấu trúc & Giải thuật, Phỏng vấn. Bạn viết
JS/TS/Python thẳng trong trình duyệt, judge chấm ngay theo test mẫu, đúng thì ăn XP và giữ chuỗi
ngày. Đề mang màu Việt Nam (Đà Lạt, Sa Pa, Chợ Rẫy) nên đọc đỡ khô. Muốn có người chữa thì đăng
bài mình làm vào kênh `bài-tập-lập-trình`.
Video chữa bài và nền tảng: https://www.youtube.com/@Dev8Sync · Luyện: https://coding.8syncdev.com

## Đọc tin công nghệ ở đâu

keywords: tin tức, tin công nghệ, tin lập trình, đọc tin, cập nhật công nghệ, news 8syncdev, có gì mới

news.8syncdev.com gom tin công nghệ từ nhiều nguồn rồi cho AI tóm tắt lại **bằng tiếng Việt**, có
cả TTS đọc to nếu bạn lười đọc. Chia 9 danh mục: ai-ml, frontend, backend, devops, security,
mobile, opensource, career, other — lọc đúng thứ mình theo. Backend chạy cron mỗi ngày nên sáng
nào cũng có bài mới. Bài nào thấy hay thì thả vào kênh `lập-trình-công-nghệ-mới` để mọi người
cùng bàn.
Video điểm tin và giải thích sâu: https://www.youtube.com/@Dev8Sync · Đọc: https://news.8syncdev.com

## Học 1 kèm 1 với mentor

keywords: 1 kèm 1, kèm riêng, mentor, gia sư, học kèm, giáo viên, giảng viên, khóa học, có người dạy, học có người kèm

Có lớp 1-kèm-1 với kỹ sư đang đi làm thật: Nguyễn Quang Linh (AI/ML), Nguyễn Nho Chí Thiện
(Backend Java/RAG), Nguyễn Trọng Đức (Backend/Kafka/DSA), Lã Huy Hoàng (DevOps). Buổi đầu là
**học thử FREE 60 phút** để xem có hợp cách dạy không, không cần trả gì trước. Trong khoá có video
bài giảng, quiz chấm tự động, AI tutor gợi ý ngay trong bài và lộ trình riêng theo trình độ bạn.
Chưa muốn đăng ký thì xem trước 26 bài học mở, không cần tài khoản.
Video bài giảng mẫu: https://www.youtube.com/@Dev8Sync · Khoá học: https://course.8syncdev.com

## Học phí bao nhiêu

keywords: học phí, phí bao nhiêu, giá bao nhiêu, bao nhiêu tiền, chi phí, gói học, bảng giá, giá khóa

Buổi lẻ 149k/90 phút; gói 8 buổi 990k (khoảng 124k một buổi, tặng 1 tháng Pro luyện code); gói 24
buổi 2.690k (khoảng 112k một buổi, tặng 3 tháng Pro và đồ án có review). Lộ trình trọn gói 799k
đến 1.099k tuỳ hướng (Backend Java, Fullstack JS, Nền tảng → DSA); lớp nhóm tối đa 6 người
690k/4 tuần sắp mở. Thanh toán online chưa bật nên chốt lớp vẫn qua trao đổi trực tiếp. Trước khi
tính tiền thì cứ học thử free 60 phút đã.
Xem cách dạy: https://www.youtube.com/@Dev8Sync · Bảng giá: https://course.8syncdev.com

## Liên hệ với 8 Sync Dev

keywords: liên hệ, số điện thoại, zalo, hotline, tư vấn, gặp ai, nhắn cho ai, email liên hệ

Zalo 0768 691 901 hoặc email atus@8syncdev.com, hai đường này đều có người đọc. Hỏi chuyện học
hành thì cứ đăng thẳng vào kênh `câu-hỏi`, trả lời công khai để người sau đọc lại được. Không ai
bên 8 Sync Dev nhắn riêng trước để mời mua gì cả.
Kênh video: https://www.youtube.com/@Dev8Sync · Trang liên hệ: https://8syncdev.com/vi/bio

## Người mới nên bắt đầu từ đâu

keywords: người mới, mới bắt đầu, bắt đầu từ đâu, học từ đâu, lộ trình, mất gốc, newbie, nên học gì, chưa biết gì, học code từ đầu

Ba bước, không tốn đồng nào ở hai bước đầu: xem playlist nền tảng trên kênh YouTube để nắm cú
pháp và cách nghĩ, rồi mở nhóm đề **Cơ bản** trên coding.8syncdev.com làm mỗi ngày vài bài cho
quen tay. Làm được chừng 50 bài mà vẫn thấy mông lung phần nào thì mới cần người kèm — lúc đó
dùng buổi học thử free 60 phút để hỏi đúng chỗ mình hổng. Đừng học 5 ngôn ngữ một lúc; chọn một
thứ (Python hoặc JavaScript) rồi đi hết nhánh của nó. Bí chỗ nào thì hỏi ở kênh `câu-hỏi`.
Bắt đầu ở đây: https://www.youtube.com/@Dev8Sync · Luyện: https://coding.8syncdev.com

## Kênh YouTube và video học

keywords: youtube, kênh youtube, video, xem video, playlist, khoá học video, live, shorts, xem ở đâu, có video không, quay video, kênh của mình

Kênh là nơi mình để phần lớn công sức: **313 video**, có tab Khoá học, Shorts và Video phát trực
tiếp, hiện **2.490 người đăng ký** (số đếm ngày 02/08/2026). Nội dung bám đúng thứ đang dạy ở đây
— C/C++, Python, Java, SQL, kỹ thuật lập trình, cấu trúc dữ liệu và giải thuật, cơ sở dữ liệu.
Bài nào trên news hay đề nào trên coding mà bạn thấy khó nuốt thì thường có một video làm tay từ
đầu cho đúng chỗ đó; tìm trong tab Khoá học trước, nhanh hơn lướt tab Video.
Kênh: https://www.youtube.com/@Dev8Sync

## Nhờ sửa lỗi code

keywords: sửa lỗi, sửa giúp, debug, code không chạy, hỏi bài, bí bài, giúp mình với, báo lỗi code, chạy không ra

Đăng vào kênh `sửa-lỗi-lập-trình` kèm đủ 4 thứ thì gần như chắc chắn có người gỡ được: đoạn code
đặt trong khối ``` (đừng chụp màn hình chữ), nguyên văn thông báo lỗi, bạn mong nó chạy ra gì, và
bạn đã thử cách nào rồi. Lỗi khi deploy hay dựng server thì sang kênh `sửa-lỗi-deployment` cho
đúng chỗ. Hỏi kiểu "code em lỗi giúp với" mà không có ba dòng trên thì không ai đoán được đâu.
Video giải thích lỗi hay gặp: https://www.youtube.com/@Dev8Sync

## Đóng góp bài tập hoặc nội dung

keywords: đóng góp, góp đề, gửi đề, thêm bài tập, contribute, viết bài cho, muốn góp

Rất hoan nghênh, và cần đủ ba phần: đề bài viết bằng tiếng Việt, một lời giải mẫu chạy được, và
tối thiểu 5 test case trong đó có ca biên. Gửi vào kênh `bài-tập-lập-trình` hoặc email
atus@8syncdev.com; đề đạt sẽ được đưa lên coding.8syncdev.com. Góp bài viết kỹ thuật thì gửi bản
nháp cùng nguồn tham khảo, đừng gửi bài do AI viết nguyên khối.
Kênh video: https://www.youtube.com/@Dev8Sync · Xem đề đang có: https://coding.8syncdev.com

## Xin việc, CV và phỏng vấn

keywords: xin việc, tìm việc, việc làm, cv, phỏng vấn, tuyển dụng, review cv, đi làm, junior thất nghiệp

8 Sync Dev không phải sàn tuyển dụng, nên đừng chờ ở đây có tin tuyển. Phần chuẩn bị thì có thật:
nhóm đề **Phỏng vấn** nằm trong 1.000 bài trên coding, danh mục `career` trên news bàn chuyện
nghề, và gói 24 buổi có đồ án được mentor review — thứ để đưa vào CV. Muốn ai đó ngó qua CV thì
đăng vào kênh `câu-hỏi`, nhớ che số điện thoại và email trước khi đăng.
Video về nghề và phỏng vấn: https://www.youtube.com/@Dev8Sync · Luyện đề phỏng vấn: https://coding.8syncdev.com

## Thực tập và tham gia team

keywords: thực tập, intern, thực tập sinh, tuyển thực tập, làm cùng team, tham gia dự án

Hiện chưa có chương trình thực tập nào được công bố, nói thẳng vậy để bạn khỏi chờ. Team nhận
người qua việc làm thật: đóng góp đề cho coding, sửa lỗi trong repo công khai trên
github.com/8syncdev, hoặc viết bài kỹ thuật tử tế. Có sản phẩm rồi thì gửi mail atus@8syncdev.com
kèm link GitHub, ngắn gọn, đừng gửi CV mẫu.
Kênh video: https://www.youtube.com/@Dev8Sync · Repo công khai: https://github.com/8syncdev

## Tài khoản dùng chung cả hệ sinh thái

keywords: tài khoản, đăng ký, tạo tài khoản, account, đăng nhập, có phải trả tiền không

Một tài khoản 8syncdev mở được cả hệ sinh thái: luyện code, đọc tin, vào khoá học, dùng ZUS —
không phải đăng ký lại từng nơi. Tạo tài khoản free ở app.8syncdev.com, phần luyện code và đọc
tin vẫn free sau khi có tài khoản. Chỉ khoá 1-kèm-1 mới mất phí.
Kênh video: https://www.youtube.com/@Dev8Sync · Tạo tài khoản: https://app.8syncdev.com

## Tài liệu tự học miễn phí

keywords: tài liệu, nguồn tự học, tự học, học free, học miễn phí, sách, tài liệu ở đâu

Ba nguồn free dùng được ngay: 313 video trên kênh YouTube (có playlist theo chủ đề, thêm Shorts
và các buổi live), 1.000 bài luyện trên coding.8syncdev.com, và tin công nghệ tóm tắt tiếng Việt
trên news.8syncdev.com. Trong server thì kênh `nguồn-tự-học` ghim thêm tài liệu theo chủ đề. Học
free được tới đâu là tuỳ bạn có làm bài đều hay không, chứ không thiếu tài liệu.
Video: https://www.youtube.com/@Dev8Sync · Luyện: https://coding.8syncdev.com

## Spam và scam trong server

keywords: spam, scam, lừa đảo, bán tài khoản, kèo, usdt, telegram, báo cáo bài, tin nhắn lạ

Không ai của 8 Sync Dev nhắn riêng để mời mua tài khoản, mời kèo USDT, hay dẫn bạn sang nhóm
Telegram — gặp mấy thứ đó thì là lừa đảo, chặn luôn. Đừng bấm link, đừng gửi mã OTP, đừng chuyển
khoản cho bất kỳ ai kể cả người dùng tên giống admin. Chụp màn hình rồi đăng vào kênh `câu-hỏi`
để mod xoá và ban. Mọi thông báo chính thức chỉ nằm ở kênh `thông-báo-mới`.
