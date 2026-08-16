# 20 AI Loop Design Patterns — distilled + ZUS mapping

> Nguồn (owner gửi 2026-07-07, "luôn lưu cái này"): <https://youmind.com/landing/x-viral-articles/ai-loop-design-patterns-guide>
> (@sairahul1, X post 2072258045460226373, 2026-07-01). Đối chiếu với doctrine cũ
> Prompt/Context/Harness/Loop (dailydoseofds — SKILL.md gốc, ADR-0009).

**Thesis bài mới:** agent = worker; **loop = thứ làm worker giỏi lên sau lần thử đầu**.
Mọi pattern chung 1 xương: `Act → Observe → Evaluate → Adjust`. Output lần đầu là điểm
xuất phát, không phải kết quả.

## Đối chiếu với doctrine cũ (4 tầng lồng nhau)

- Doctrine cũ trả lời **"đầu tư VÀO ĐÂU"** (Prompt ⊂ Context ⊂ Harness ⊂ Loop — body > brain).
- Bài 20 patterns trả lời **"tầng Loop THIẾT KẾ THẾ NÀO"** — 20 patterns là catalog cụ thể
  cho tầng LOOP (cat 1/3/4/5) + tầng CONTEXT-qua-thời-gian (cat 2 Memory).
- Hai bài KHÔNG mâu thuẫn: dùng doctrine cũ để định vị tầng, dùng catalog này để chọn
  hình dạng loop trong tầng đó. Gap ARCH-plch-2026 ("loop thiếu self-verify + done-contract")
  chính là patterns #2/#15 — đã đóng bằng engine_verify gate từ round 13.

## Catalog + trạng thái ZUS (✅ đang chạy · 🟡 một phần · ⬜ chưa)

### Cat 1 — Quality (output tốt hơn trước khi rời hệ thống)
1. **Generate→Critique→Rewrite** — ✅ reviewer subagent mỗi round (P0/P1 fix trước commit — round 13/14/17/18 đều bắt bug thật); generator ≠ judge.
2. **Score-and-Retry** — ✅ `engine_verify` gate (lint/test/build đo được, retry với fix KHÁC, 3 fail = BLOCK).
3. **Multi-Critic** — ✅ round-22: `default_critics()` (Correctness+Ponytail) chấm **CÓ ĐIỂM** (`Verdict.score` 0..1 = coze-loop `EvalOutput`), chạy trong `run_agent_verified` khi autopilot; reviewer subagent vẫn cho release gate.
4. **Adversarial Critique** — 🟡 reviewer được lệnh "tìm P0" (phá, không khen); chưa systematic cho reply chat.
5. **Judge Ensemble** — ⬜ single reviewer; cân nhắc khi stakes cao (release gate).
### Cat 2 — Memory (học từ việc đã xảy ra)
6. **Reflexion** — ✅ KNOWLEDGE `failure:` đọc đầu phiên trước khi sửa vùng liên quan (contract 8sync).
7. **Memory Update** — ✅ STATE rewrite mỗi phase-boundary + retain memory (Mnemopi).
8. **Error Library** — ✅ KNOWLEDGE `failure:` chính là nó (search trước khi đụng listener/sync — bài round 18).
9. **Success Pattern** — ✅ PLAYBOOKS `validated:` runbook (index theo When:).
10. **Memory Compression** — ✅ compactHistory LSA/TextRank 2 tầng (thế hệ 85% + big-compact) + KNOWLEDGE distill; đúng lời bài: "nhiều memory cụ thể → ít abstraction cấp cao".
### Cat 3 — Planning (kế hoạch đổi khi thực tế đổi)
11. **Plan→Execute→Replan** — ✅ engine_plan replace được giữa chừng (interjection hôm nay là ví dụ sống).
12. **Dynamic Workflow** — 🟡 `zus_agent::runner::run_workflow` có on_success/on_error edge gating (P3 builder); pipeline chính vẫn tĩnh.
13. **Goal Decomposition** — ✅ engine slices→tasks smallest-first; native `run_workflow` graph.
14. **Progress Evaluation** — ✅ no-progress/doom-loop guard (2 identical fail warn, 3 block) + `noteRepeat` connBridge (backend, TOOL LOOP DETECTED).
15. **Constraint Satisfaction** — ✅ verify commands = business rules (eslint+tsc+test+grep gate); guardrails eino (no-source-no-claim, read-before-write NEED_READ_FIRST).
### Cat 4 — Exploration (nhiều đường, chọn tốt nhất)
16. **Branch-and-Explore** — ⬜ (dùng ad-hoc khi debug nhiều giả thuyết; chưa là cơ chế)
17. **Tree Search** — ⬜ đắt; chỉ khi single-pass bí.
18. **Debate** — ⬜ cân nhắc cho quyết định kiến trúc lớn.
### Cat 5 — System Optimization (loop cải thiện loop)
19. **Prompt Optimization** — 🟡 round-22: chưa có offline test-set A/B (coze-loop tầng platform), NHƯNG có vòng self-learning ONLINE: critic issue → `lesson` (salience cân theo `1-score`) → `fold_learned_lessons` đẩy bài học tái diễn vào system prompt lượt sau (khép #6 Reflexion với #19).
20. **Workflow Optimization** — 🟡 8sync bench đo loop (`8sync harness bench`); chưa tự-sửa-workflow.

## Ưu tiên khi lấp gap (ponytail — chỉ làm khi có cầu thật)

1. **#3 Multi-Critic** — ✅ ĐÃ LÀM round-22 (scored critic runtime; reviewer subagent cho release gate vẫn giữ). Source-grounded: `su-code/design-refs/RESEARCH-coze-vs-eino.md` §5.
2. **#19 Prompt Optimization** — 🟡 ONLINE self-learning done round-22 (scored-salience lesson → fold vào prompt). Offline eval-set A/B = owner-gated (chỉ khi có cầu).
3. #5/#16/#17/#18: chưa có cầu — ghi nhận, không build trước.
