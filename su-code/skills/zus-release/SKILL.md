---
name: zus-release
description: ZUS 2-Stage Automated CI/CD Release & Security/Performance Audit Flow. Use when asked to cut a release, release a new version, test the 100% FREE CI/CD pipeline, audit native Rust security/speed, or verify release feed integrity.
---

# ZUS Release & CI/CD Pipeline Skill

Skill này quy định quy trình cắt phát hành (release), kiểm tra an ninh (security audit), tối ưu hiệu năng (performance gate) và tự động hoá 100% CI/CD cho dự án **ZUS** của **8 Sync Dev** (tiền thân **8SyncX**).

---

## 🏗️ 1. Kiến trúc Pipeline 2 Chặng & Bảng chi phí ($0.00 / ~$0.004)

Pipeline phát hành của ZUS được thiết kế theo ranh giới **NIỀM TIN** thay vì chi phí:

| Chặng | Repository | Quyền hạn & Bảo mật | Chi phí thực tế |
|---|---|---|---|
| **Chặng 1: Build 3 OS** | Repo Public `8syncdev/zus-releases` (`release.yml`) | Source Private được checkout tạm qua Deploy Key Read-Only. Biên dịch Linux, macOS, Windows bằng **Khoá RÁC**. | **$0.00 / 100% FREE** (GitHub Actions miễn phí cho repo Public) |
| **Chặng 2: Ký & Publish** | Repo Private `8syncdev/zus` (`sign.yml`) | Tải artifact draft → xoá chữ ký rác → Ký lại bằng **Khoá THẬT** (`TAURI_SIGNING_PRIVATE_KEY`) → Dựng & ký `latest.json` → Verify → Publish. | **~$0.004 / lần** (Chỉ tốn ~30-45s Ubuntu, giảm 99.8% từ $2.61/lần cũ) |
| **Local Pre-push Gate** | Máy Dev (`scripts/gate.sh all`) | Rà soát test Bun FE, test Rust workspace, audit dependency, và Vite production bundle. | **$0.00** |

---

## 🔒 2. Phase 1: Native Rust Security & Hardening Audit

Trước khi kích hoạt pipeline release, AI Agent bắt buộc phải xác nhận 5 tiêu chí bảo mật native:

1. **Deny Unsafe Code**:
   `Cargo.toml` root phải duy trì:
   ```toml
   [workspace.lints.rust]
   unsafe_code = "deny"
   ```
2. **Dependency Vulnerabilities**:
   Chạy `cargo audit` local — không được có lỗ hổng mức `critical` hoặc `high`.
3. **Fail-closed Updater Signature**:
   Trường `plugins.updater.pubkey` trong `src-tauri/tauri.conf.json` và module `crates/zus-update` sử dụng chữ ký Minisign trên thuật toán `ED` (Ed25519 trên Blake2b-512 prehash). Manifest thiếu chữ ký hoặc lệch key ID bắt buộc phải **fail-closed** (từ chối cập nhật).
4. **Throwaway Key Isolation**:
   Khoá ký thật (`TAURI_SIGNING_PRIVATE_KEY`) **TUYỆT ĐỐI KHÔNG** được copy sang repo public `zus-releases`. Chặng 1 chỉ dùng khoá rác sinh tạm trong CI.
5. **No Secret Leakage**:
   Đảm bảo không rò rỉ token, API key hoặc private key trong git history và build artifacts (kiểm tra qua `gitleaks` pre-commit hook).

---

## ⚡ 3. Phase 2: Performance & Optimization Gate

1. **Rust Release Profile**:
   Kiểm tra profile release trong `Cargo.toml` root:
   ```toml
   [profile.release]
   opt-level = 3
   lto = "thin"
   codegen-units = 1
   strip = true
   panic = "abort"
   ```
2. **Vite Bundle Production Optimization**:
   Chạy `bash scripts/gate.sh build` — đảm bảo bundle Vite thành công ở local để nổ lỗi (nếu có) trước khi code lên repo public (tránh rò code frame qua log build public).
3. **In-process SIMD Prefilter**:
   Quét codebase trong `zus-memory` và `zus-index` sử dụng SIMD byte search (`memchr` / `grep-regex`) với thời gian xử lý <1ms cho mỗi file scan.

---

## 🚨 4. Phase 3: AI Agent Mandatory CI/CD Protocol (Quy tắc BẤT BIẾN)

> **CẤM TỰ Ý DỪNG HOẶC TUYÊN BỐ THÀNH CÔNG NẾU CHƯA VERIFY CI/CD PASS 100%**

Khi được yêu cầu cắt release hoặc test CI/CD pipeline, AI Agent phải thực hiện đúng 4 bước:

### Bước 3.1: Chạy Thử Kế Hoạch (Dry-run)
```bash
bash scripts/release.sh X.Y.Z --dry-run
```
Xác nhận version `X.Y.Z`, các file sẽ bump (`package.json`, `tauri.conf.json`, `src-tauri/Cargo.toml`, `Cargo.lock`), và mục `Unreleased` trong `CHANGELOG.md`.

### Bước 3.2: Kích Hoạt Pipeline Tự Động 100%
```bash
bash scripts/release.sh X.Y.Z --auto
```
Script se tự động:
1. Bump version & roll CHANGELOG.
2. Chạy `scripts/gate.sh all` + `scripts/gate.sh build`.
3. Commit `release: vX.Y.Z` & push tag `vX.Y.Z` lên `main`.
4. Trigger Chặng 1 (`release.yml` trên `8syncdev/zus-releases`).
5. Theo dõi `watch_and_verify` Chặng 1 tới khi xong.
6. Trigger Chặng 2 (`sign.yml` trên `8syncdev/zus`).
7. Theo dõi `watch_and_verify` Chặng 2 tới khi xong.
8. Verify chữ ký live public feed `latest.json`.
9. Dựng sẵn 3 file manifest Winget trong `dist/winget/X.Y.Z/`.

### Bước 3.3: Job-level Verification (AI Agent Vibe Check)
AI Agent phải tự kiểm tra log của `watch_and_verify`:
- **Chặng 1 (`zus-releases`)**: Assert 100% jobs (Linux `.deb/.rpm/.AppImage`, macOS `.dmg`, Windows `.exe`) đạt `conclusion == "success"`.
- **Chặng 2 (`zus`)**: Assert job `sign` đạt `conclusion == "success"`.

### Bước 3.4: Live Feed Integrity Verification
AI Agent kiểm tra lệnh verify feed public xuất ra ở cuối script:
```
✓ feed public OK: X.Y.Z (5 platforms)
🎉 RELEASE vX.Y.Z THÀNH CÔNG RỰC RỠ!
```

---

## 🪟 5. Phase 4: Submit Winget & Distribution Check

1. **Winget Manifest Auto-generation**:
   Script `release.sh` đã tự gọi `bash scripts/release-winget.sh X.Y.Z` để đọc SHA256 thật từ release vừa publish và sinh sẵn 3 file YAML tại `dist/winget/X.Y.Z/`.
2. **Submit PR Winget (Nếu cần publish lên Microsoft Winget)**:
   ```bash
   gh repo sync 8syncdev/winget-pkgs --source microsoft/winget-pkgs --branch master
   # Copy dist/winget/X.Y.Z/*.yaml vào manifests/8/8syncdev/ZUS/X.Y.Z/ trong fork
   gh pr create --repo microsoft/winget-pkgs --title "New version: 8syncdev.ZUS version X.Y.Z" --body "Automated manifest for ZUS X.Y.Z."
   ```
3. **Scoop Bucket Verification**:
   Xác nhận `8syncdev/scoop-zus` tự động cập nhật qua pattern `checkver` trỏ `zus-releases/releases/latest`.

---

## 📋 Summary Checklist cho AI Agent

- [ ] Run `bash scripts/release.sh X.Y.Z --dry-run` check diff.
- [ ] Run `bash scripts/release.sh X.Y.Z --auto`.
- [ ] Confirm Chặng 1 (`zus-releases`) 3/3 OS PASS (`success`).
- [ ] Confirm Chặng 2 (`zus`) Sign & Publish PASS (`success`).
- [ ] Confirm Live Public Feed Signature verification PASS (`verify-manifest-sig.mjs`).
- [ ] Confirm Winget manifests generated at `dist/winget/X.Y.Z/`.
