---
name: product-handoff
description: >
  Đóng gói / giao / bán sản phẩm CRM-bot này (agentic-cloudgo) cho khách hoặc team
  dev, và deploy lên site dev/staging/prod. Chọn mô hình phân phối (SaaS giữ lõi ·
  Docker self-host + license ký số · Hybrid), license + expiration + gia hạn + revoke
  + track (tái dùng hệ access-key SẴN CÓ), và runbook deploy thật (Encore apps
  kufi/chatbot-ma9i, `encore build docker`→ghcr, FE Vercel + ENCORE_BASE_URL). Dùng
  khi nghe: "đóng gói", "ship / giao cho khách / cho dev", "self-host", "bản quyền /
  license / hết hạn / gia hạn", "site dev", "lên dev/staging/prod", "build docker".
---

# product-handoff — ship & license sản phẩm CRM-bot

## Sự thật DRM (nói thẳng, không hứa hão)
Cái gì **chạy trên máy người khác** thì đủ kiên nhẫn đều reverse/patch được — đây là
giới hạn vật lý. Crypto (ký số) **bất khả xâm phạm**, nhưng *enforcement* (đoạn code
check license) thì **patch bỏ được**. Binary chỉ **nâng rào**, không phải tường thành.
→ Muốn "không giải được tuyệt đối" thì **lõi phải nằm ở server của mình**.

## Giá trị nằm ở đâu (quyết định mọi thứ)
Project này 100% **config/DB-driven**: kernel/prompt/guardrail/seed/model nằm trong
`be/*/migrations/*.up.sql` (DB), KHÔNG nằm trong code Go. → **Crown jewels = DB**, không
phải binary. **Không ship DB là đã giữ được 90% giá trị.**

## 3 phương án (chắc → tiện)

### 1. SaaS — giữ lõi ở infra mình  ⭐ KHUYẾN NGHỊ cho case này
Khách gọi API của mình bằng key; DB/prompt không rời server → **không giải được gì**.
**Đã có sẵn hệ license đúng kiểu này** — chỉ cần mở rộng:
- `/domain/register` phát `ak_live_*` (one-time) + `ws_*` webhook secret — `be/gateway/router.go` `routeDomain` → `be/iam`.
- `enforce_access_key` bật/tắt per-domain — `be/iam/domains_api.go` `SetEnforcement` (`POST /iam/domains/:id/enforcement`); guard `accessKeyAllowed` (gateway) chặn khi bật.
- Cấp/thu key — `IssueAccessKey` / `SetKeyStatus` (`/iam/domains/:id/keys`, `/iam/keys/:keyID/status` revoke).
- **Thêm exp + gia hạn + track** (việc cần làm): migration thêm cột `expires_at` vào bảng access-key (coreDB/iam) → guard check hết hạn → endpoint `renew` đổi `expires_at` → log mỗi request (track ai đang chạy). Hết hạn = chặn; gia hạn = đổi exp; revoke = `status`.

### 2. Self-host bắt buộc — Docker (ghcr) + license ký số
- `encore build docker IMAGE` → image chuẩn (binary Go đã biên dịch, **không phải source**); `-ldflags "-s -w"` strip symbol; tùy chọn `garble` để obfuscate.
- Push `ghcr.io/<org>/<img>` → khách tự `docker run`.
- License = **Ed25519/JWT** chứa `exp` + `customer_id`; binary nhúng **public key**, verify **offline** (không có private key của mình thì KHÔNG forge nổi).
- Gia hạn + track + revoke: binary **phone-home** về license-server lúc start + định kỳ.
- Điểm yếu duy nhất (không tránh được): patch bỏ đoạn check → qua. Chấp nhận "không tuyệt đối".

### 3. Hybrid — vỏ self-host + lõi gọi về
Ship engine Go binary cho khách tự host, nhưng **lõi giá trị** (prompt/kernel/model/RAG)
gọi API về server mình kèm key. Không có key còn hạn → vỏ vô dụng. Cân bằng tốt giữa 1 và 2.

**Kết luận:** "không giải được + exp + gia hạn + track" đúng nghĩa → **PA1 hoặc PA3** (lõi ở mình).
PA2 cho track/gia hạn/revoke + crypto unbreakable nhưng *không tuyệt đối*. CRM-bot này giá trị
ở DB/prompt → **PA1 (SaaS, tái dùng access-key + thêm expiration)** rẻ nhất & kín nhất.

## Runbook deploy (repo này) — "cách chuyển dễ nhất"
**2 Encore apps** (khác account):
- **kufi** (= **DEV**) = `agentic-cloudgo-v1-kufi`, env `prod-dev` (`https://prod-dev-agentic-cloudgo-v1-kufi.encr.app`), deploy nhánh `go-kit` (`git push encore-kufi go-kit:go-kit`, auth `tuan8165`) — backend của **FE dev** `cloudgo-ai-agent` (`cloudgo-agent.8syncdev.com`); cũng là env CRM-widget thật (crm5in1.cloudgo.vn) + QA real-chat (`tools/qa/qa.mjs`). **Test/verify ở đây.**
- **chatbot-ma9i** (= **PROD**) = env `staging`+`prod` (`https://{staging,prod}-chatbot-ma9i.encr.app`), deploy nhánh `main` — backend của **FE prod** `agentic-cloudgo-dashboard` (`agentic-cloudgo-dashboard.vercel.app`), phục vụ khách thật (`pms.cloudgo.vn`). Account riêng → cần **auth key**. **KHÔNG test ở đây, chỉ trace log.**

**BE deploy:**
- chatbot-ma9i **deploy từ nhánh `main`** (KHÔNG phải go-kit): `git push encore go-kit:main` (FF) → deploy cả staging+prod. Cần auth: `encore auth login --auth-key=ena_…` (back up rồi restore `~/.config/encore/.auth_token` = tuan8165). `git remote` `encore` = `encore://chatbot-ma9i`.
- ⚠️ Working-tree `be/encore.app` có thể bị leftover `kufi` — KHÔNG commit nó khi target chatbot-ma9i (committed phải = `chatbot-ma9i`).
- Compile gate local (env encore lỗi): `cd be && GOROOT=~/.encore/encore-go GOTOOLCHAIN=local ~/.encore/encore-go/bin/go build ./...` — chỉ lỗi `router.go:22 errs.HTTPStatus` là chấp nhận (resolve trên cloud).
- Migration auto-apply lúc deploy (thêm `{N}_name.up.sql`, không sửa file đã apply).

**FE deploy (Vercel) — chốt 2026-06-29:**
- **DEV `cloudgo-ai-agent` (→kufi) ĐÃ Connect Git → `git push origin go-kit` AUTO-BUILD** (alias `…-git-go-kit-…`, ~52s server-side). **PROD `agentic-cloudgo-dashboard` (→ma9i) CHƯA Connect Git** (verify `vercel project inspect`: không có mục git; push KHÔNG tạo build prod) → deploy tay `cd fe/web && vercel link --yes --project agentic-cloudgo-dashboard && vercel --prod --yes` (rootDir=fe/web, upload ~330KB). KHÔNG `--archive`/upload nguyên repo (account chỉ 1 build-slot concurrent → build tay treo sẽ queue cả build dev). Muốn prod auto: Connect Git ở Vercel (production branch=`go-kit`).
- FE→BE qua per-project env `ENCORE_BASE_URL` (ma9i `https://prod-chatbot-ma9i.encr.app` · kufi `https://prod-dev-agentic-cloudgo-v1-kufi.encr.app`); FE đọc qua BFF `lib/api.ts`. Đổi link = sửa env rồi `vercel --prod` lại (env chỉ áp khi redeploy).

**VERIFY (bắt buộc):** xác nhận deploy bằng **đổi behavior thật** (vd PUT 1 field rồi GET lại), KHÔNG chỉ `engine.builtins=200` — pod cũ cũng trả 200. Chờ build+rollout ~3–4 phút; kernel-cache ~5 phút sau migration.

## Cite
- License primitives: `be/iam/domains_api.go`, `be/iam/auth_api.go`, `be/gateway/router.go` (routeDomain), `be/iam/compat_router.go`.
- Deploy gotchas: `agents/KNOWLEDGE.md` ("chatbot-ma9i deploys from MAIN"), `agents/skills/encore-migrations`.
