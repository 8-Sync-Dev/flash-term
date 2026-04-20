# 🚀 gsd-pi (GSD-2) — Hướng dẫn nhanh tiếng Việt

> **Phiên bản tham chiếu:** `gsd-pi` v2.x (dòng GSD-2, phát hành trên npm)
> GSD-2 là CLI độc lập xây trên Pi SDK — không còn là prompt framework như v1.

---

## 🧠 GSD-2 là gì?

**GSD = Get Shit Done.** Hệ spec-driven development cho AI coding agent:

- Viết spec → roadmap → milestone → slice → task → verify — tất cả commit vào git dưới `.gsd/`.
- Agent có **context window mới 200k token cho mỗi task** — không tích rác, không "tôi sẽ ngắn gọn lại".
- Dispatch tự chèn sẵn plan, summary, decision, roadmap — agent bắt tay vào code ngay.
- **Một lệnh. Đi uống cafe. Về có dự án chạy được + git history sạch.**

---

## ⚙️ Cài đặt

```bash
# Yêu cầu: Node.js >= 22 (20.6+ tạm được, 22+ khuyến nghị)
npm install -g gsd-pi

# Vá Anthropic OAuth + routing stack cho dự án lớn
8sync gsd setup --auto
8sync gsd fix
```

Nếu lỗi `experimental-strip-types` → nâng Node lên 22+.
Nếu `gsd` bị alias bởi oh-my-zsh (`git svn dcommit`) → `unalias gsd`.

---

## 🎯 Vòng đời một milestone (dùng hàng ngày)

```
/gsd new-milestone    # tạo M00x từ spec
/gsd auto             # chạy toàn bộ M00x không cần can thiệp
/gsd next             # chạy 1 unit rồi dừng (an toàn)
/gsd query            # snapshot JSON trạng thái (~50ms, không gọi LLM)
```

**Step mode** (mặc định): state machine như auto nhưng dừng giữa các unit, có wizard "đã xong gì / sắp làm gì".
**Auto mode**: chạy cả milestone. Escape để pause bất cứ lúc nào — conversation được giữ, gõ `/gsd auto` resume từ disk.

---

## 🧱 Cấu trúc hierarchy

```
Milestone (M001)
 └─ Slice (S01)               — vertical cut có thể demo
     └─ Task (T01..Tnn)       — đơn vị dispatch thực sự
         └─ Verification      — lint/test/typecheck tự chạy
```

Mỗi tầng đều có `PLAN.md` + `SUMMARY.md` — survive mọi `/new` và context reset.

---

## 🔁 Tính năng killer cho **dự án lớn**

| Feature | Công dụng |
|---|---|
| **Fresh session per unit** | Mỗi task một context 200k sạch — không còn agent "mệt mỏi" sau 3 giờ. |
| **Context pre-loading** | Dispatch đã inline plan/summary/deps → agent không tốn tool call đọc file. |
| **Git isolation** | `git.isolation = worktree\|branch` → mỗi milestone một branch `milestone/<MID>`. |
| **Verification enforcement** | Chạy `npm run lint/test` sau mỗi task; fail → auto-fix retry; pre-existing errors chỉ log warning. |
| **Validate-milestone gate** | Sau khi xong hết slice, so sánh success criteria với kết quả thực tế trước khi "seal". |
| **Headless mode** | `gsd headless --timeout 600000` cho CI/cron; exit code 0 done / 1 error / 2 blocked; auto-restart exponential backoff. |
| **Multi-session** | File-based IPC trong `.gsd/parallel/` — nhiều worker cùng chạy nhiều milestone. |
| **Remote questions** | Route quyết định sang Slack/Discord khi cần human input. |
| **RTK output compression** | Nén stdout của `bash`, `bg_shell`, verification — tiết kiệm context. |
| **Stuck-loop detection** | Tự phát hiện loop → break → escalate. |
| **Crash recovery** | Restart từ disk state, không mất task đã xong. |
| **Migrate từ GSD v1** | `/gsd migrate` parse `.planning/` cũ → `.gsd/` mới, giữ completion state. |

---

## 🪜 Workflow cho team / dự án lớn

1. **Khởi động:** `gsd config` → set `ANTHROPIC_API_KEY` (hoặc provider khác).
2. **Spec trước, code sau:** viết `spec.md`, rồi `gsd headless new-milestone --context spec.md --auto`.
3. **Terminal 1** chạy `/gsd auto`; **terminal 2** dùng để review/chỉnh roadmap — quyết định terminal 2 được pick up ở phase boundary kế tiếp.
4. **Verify chặt:** set `verification_commands`, `verification_auto_fix`, `verification_max_retries` trong preferences.
5. **CI integration:** `gsd headless query` trả JSON → dashboard tiến độ không cần spawn LLM.
6. **Branch-per-milestone:** git isolation giữ main luôn xanh; reviewer chỉ merge milestone branch khi gate pass.
7. **Pause/resume:** Escape → inspect → `/gsd auto`. An toàn để handoff giữa ca hoặc giữa dev.

---

## 🧰 Lệnh `8sync gsd` (wrapper trên config này)

```
8sync gsd setup --auto          # Auto-detect provider tốt nhất + apply
8sync gsd setup --model codex   # Preset stack theo brand
8sync gsd setup --pick          # fzf picker có status
8sync gsd fix                   # Repair nhanh ~/.gsd/agent
8sync gsd fix --refresh         # Refresh runtime local (không đụng global)
8sync gsd status                # Auth + key + routing hiện tại
8sync gsd keys                  # List provider + trạng thái
8sync gsd model add <id>        # Thêm model mới không cần upgrade gsd-pi
8sync gsd guide                 # Mở hướng dẫn này (tiếng Việt)
8sync gsd local                 # Inspect .gsd/vendor/gsd-pi local
```

---

## 🔒 Pro tips để trở thành "chuyên gia GSD"

1. **Luôn dùng `--auto` setup đầu project** → tự pick OAuth/API key hợp lệ nhất.
2. **Bật git isolation** ngay milestone đầu — tránh drama merge sau này.
3. **Viết spec kỹ, slice mỏng** — slice càng vertical càng dễ demo, càng dễ rollback.
4. **Đừng tắt verification** — auto-fix retry rẻ hơn debug thủ công rất nhiều.
5. **Commit `.gsd/`** — đó là bộ nhớ dài hạn của agent; mất nó = agent amnesia.
6. **Dùng `gsd headless query`** trong script CI thay vì parse markdown.
7. **Model routing nhiều tier:** planning dùng model mạnh (Opus/GPT-5), exec dùng model rẻ (Sonnet/Haiku) — tiết kiệm 60–80% cost.
8. **`.gsd/STATE.md` là single source of truth** — khi rối, đọc file này trước, đừng hỏi agent.

---

## 🔗 Tham khảo

- npm: <https://www.npmjs.com/package/gsd-pi>
- GitHub: <https://github.com/gsd-build/gsd-2>
- Docs: <https://github.com/gsd-build/gsd-2/tree/main/docs/user-docs>

> Bản dịch/tóm tắt này nằm trong repo cấu hình WezTerm của bạn. Mở lại bằng:
> ```
> 8sync gsd guide
> ```
