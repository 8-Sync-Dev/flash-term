---
name: site-ux-audit
description: Audit UI/UX của các site 8 Sync Dev (monorepo + AcoLeads + product) đang chạy production — phát hiện lỗi layout/đè, widget nhúng (webchat AcoLeads) sai theme/ngữ cảnh, rồi xuất bug report tách theo role (Quốc Hưng=FE / Anh Tú=fullstack BE·AI). Dùng khi user nói "soi/check site", "chatbox lỗi", "UI đè", "audit web 8syncdev", "bắt lỗi UX các site". Nguồn site = references/products-registry.json (đừng đoán URL).
---

# site-ux-audit — soi UI/UX site 8 Sync Dev → bug report tách role

**Mục tiêu:** ra lệnh cơ bản ("soi các site 8syncdev") → agent tự lấy danh sách site, mở từng site bằng `browser` (omp), bắt lỗi layout + widget nhúng, screenshot, rồi ghi bug tách theo role vào `briefs/dev-team-tasks.md` (+ optional Lark).

## 0. Nguồn site — KHÔNG đoán URL
Đọc **`references/products-registry.json`** (verify lại: `vercel project ls`, account `kilopfds-projects`). Field: `url`, `repo`, `owner_fe`, `scope`, `webchat`. Ưu tiên `scope:"core"` (funnel lập trình) trừ khi user chỉ định khác.

## 1. Vai trò → tách bug cho đúng người (founder xác nhận 2026-07-23)
- **Quốc Hưng = FE** → lỗi layout/CSS/z-index/đè/copy/responsive; phần *nhúng* widget trên monorepo `8syncdev-pro-v2`.
- **Anh Tú = fullstack (BE·AI·product)** → backend/AI/model/knowledge-base; sản phẩm AcoLeads (SDK webchat, theme config, persona, KB, model).
- Ranh giới webchat: *chỗ nhúng + z-index + theme token host* = FE; *nội dung bot + KB + model + white-label SDK* = Anh Tú.

## 2. Quy trình mỗi site (dùng tool `browser`, model có vision đọc screenshot)
1. `open` tab với `viewport:{width:1440,height:900}`, `wait_until:"networkidle2"`.
2. Chờ preloader tắt (nhiều site có `.preloader-overlay`), rồi `screenshot` top.
3. Scroll bottom + `screenshot` để soi footer + copy sai scope (vd tagline còn "IELTS/Cloud").
4. **Probe widget nhúng + đè** (paste snippet §3) — bắt fixed/absolute góc phải-dưới, z-index bất thường (webchat AcoLeads z=2147483000), launcher `.launch` trong **shadow DOM**.
5. Nếu có webchat: click launcher → screenshot panel → đánh giá **theme match** (panel vs theme site) + **greeting/ngữ cảnh**. Test 1 câu hỏi sản phẩm (vd giá khóa học) → xem bot có **grounded** không (biết số public?) + lỗi ngôn ngữ (leak CJK) + hành vi (xin SĐT kiểu Messenger?).
6. Ghi nhận: theme mismatch · overlap/z-index · widget nhúng đúng tập site? · copy sai scope · bot không grounded/leak/persona sai.

## 3. Probe snippet (paste vào `browser` run — bắt launcher qua shadow DOM)
```js
const info = await page.evaluate(()=>{
  function* walk(root){for(const el of root.querySelectorAll('*')){yield el; if(el.shadowRoot) yield* walk(el.shadowRoot);}}
  const vw=innerWidth,vh=innerHeight,out=[]; let launcher=null;
  for(const el of walk(document)){
    const cs=getComputedStyle(el); if(cs.position!=='fixed'&&cs.position!=='absolute')continue;
    const r=el.getBoundingClientRect(); if(r.width<28||r.height<28||r.width>220)continue;
    if(r.right>vw*0.6&&r.bottom>vh*0.55){
      const host=el.getRootNode&&el.getRootNode().host;
      const rec={tag:el.tagName,cls:(el.className||'').toString().slice(0,40),x:Math.round(r.x+r.width/2),y:Math.round(r.y+r.height/2),w:Math.round(r.width),z:cs.zIndex,shadow:!!host};
      if(el.classList&&el.classList.contains('launch'))launcher=rec; else out.push(rec);
    }
  }
  const sdk=[...document.querySelectorAll('script[src]')].map(s=>s.src).find(s=>/acolead|webchat|chat|crisp|tawk|intercom/i.test(s))||null;
  return {url:location.href,acoleadsSDK:sdk,launcher,nativeFixedBR:out.slice(0,10)};
});
```
Đè = `launcher` và `nativeFixedBR` có toạ độ center gần nhau (< ~60px) → chồng tap-target. Webchat input/panel nằm trong `shadowRoot` → tìm host bằng `walk(document)` rồi `.shadowRoot.querySelector('textarea,input')`.

## 4. Viewport ↔ screenshot scale (GOTCHA)
Screenshot PNG downscale ~1.25× so với CSS viewport (vw≈1440 → shot 1800). Click theo **CSS coord từ `getBoundingClientRect`** (`page.mouse.click(cx,cy)`), KHÔNG theo pixel screenshot.

## 5. Xuất bug report
- Ghi vào **`8syncdev-org-skills/briefs/dev-team-tasks.md`** theo format DEV-NN: Người nhận · Ưu tiên · Trạng thái · Brief · Triệu chứng (screenshot path) · Cách fix (checklist) · Acceptance (test được).
- Screenshot lưu `briefs/audit-<topic>-<date>/`.
- Optional Lark: cần profile browser (`browser-profile-control` open `linkedin` → CDP :9222) + recipe addRecord của skill `lark-base-ops`. Table: FE→`8syncdev Monorepo`/`ZUS IDE`; AcoLeads→`AcoLeads`. Lark LIVE fragile → founder xác nhận trước khi ghi.

## 6. Precedent
Audit đầu tiên: 2026-07-23 (`briefs/audit-webchat-2026-07-23/`) → DEV-05 (FE nhúng/đè/theme) + DEV-06 (Anh Tú KB/model/persona). Phát hiện: webchat AcoLeads nhúng coding/news/course, z=max đè control coding, panel light-theme trên site dark, bot không grounded + leak chữ Trung (glm-4.5-flash) + persona lead-gen Messenger.
