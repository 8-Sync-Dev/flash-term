# Markdown đẹp trong terminal — "bí kíp" render của project này

> **Vì sao ghi lại:** guide `8sync gsd guide` trông đẹp là nhờ một layered renderer chain, không phải magic. File này chép đủ công thức để tái dùng cho bất kỳ command nào trong repo muốn show markdown tiếng Việt đẹp, không mojibake.

---

## 🎨 Công thức đang dùng

**Tầng 1 — Viết markdown có emoji + bảng + blockquote + code fence** (thứ terminal renderer xử lý tốt):

- `#`, `##`, `###` cho heading → renderer tô màu theo cấp.
- `|` bảng → `glow` render đường kẻ Unicode đẹp.
- `> ...` blockquote → nhấn câu quan trọng.
- ` ```powershell / ```yaml ` fence có language hint → syntax highlight.
- Emoji ⭐ 🚀 🧠 🪜 🚨 🧯 ⚡ 📡 → nhìn lướt ra section ngay.
- List `-` và numbered `1.` → đều ok, renderer tự indent.
- Dùng **bảng 2 cột** (Lỗi ↔ Fix, Feature ↔ Công dụng) thay vì đoạn văn dài — user scan nhanh hơn 10x.

**Tầng 2 — PowerShell renderer chain** (`Show-GsdGuide` trong `modules/gsd/20-interactive.ps1`):

```powershell
# Thứ tự ưu tiên: glow → bat → mdcat → fallback PowerShell colorised
foreach ($cmd in @('glow', 'bat', 'mdcat')) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) { $renderer = $cmd; break }
}

switch ($renderer) {
    'glow'  { & glow -p $guidePath }                               # đẹp nhất, có pager
    'bat'   { & bat --style=plain --paging=always --language=markdown $guidePath }
    'mdcat' { & mdcat $guidePath }
    default {
        # Fallback: tự tô màu theo regex (không cần cài gì)
        Get-Content $guidePath -Encoding UTF8 | ForEach-Object {
            $line = $_
            if     ($line -match '^# ')        { Write-Host $line -ForegroundColor Magenta }
            elseif ($line -match '^## ')       { Write-Host $line -ForegroundColor Cyan }
            elseif ($line -match '^### ')      { Write-Host $line -ForegroundColor Yellow }
            elseif ($line -match '^\s*\| ')    { Write-Host $line -ForegroundColor Gray }
            elseif ($line -match '^\s*```')    { Write-Host $line -ForegroundColor DarkGray }
            elseif ($line -match '^\s*>')      { Write-Host $line -ForegroundColor DarkCyan }
            elseif ($line -match '^\s*[-*] ')  { Write-Host $line -ForegroundColor White }
            elseif ($line -match '^\s*\d+\. ') { Write-Host $line -ForegroundColor White }
            else                               { Write-Host $line -ForegroundColor Gray }
        }
    }
}
```

**Tầng 3 — Nội dung tiếng Việt**:

- File save **UTF-8 không BOM**. PowerShell 7+ tự detect tốt; không cần ép encoding.
- `Get-Content -Encoding UTF8` là dòng mấu chốt chống mojibake tiếng Việt.
- WezTerm cần font có glyph Unicode rộng (Nerd Font, JetBrains Mono Nerd, Cascadia Code) để emoji + bảng kẻ không bị vỡ.

---

## 📦 Cài renderer xịn (tùy chọn, fallback vẫn đẹp)

```powershell
scoop install glow        # khuyên dùng — https://github.com/charmbracelet/glow
scoop install bat         # backup — có syntax highlight code fence
scoop install mdcat       # alternative Rust
```

Không cài gì vẫn ok — fallback PowerShell colorised vẫn nhìn ra heading/code/list rõ ràng.

---

## 🧩 Pattern tái sử dụng cho command khác

Muốn thêm command `8sync xxx guide` hiển thị doc cho module xxx? Copy snippet này:

```powershell
function Show-XxxGuide {
    $guidePath = Join-Path $PSScriptRoot 'docs/xxx-vi.md'
    if (-not (Test-Path $guidePath)) {
        Write-Host "  [xxx] Guide not found: $guidePath" -ForegroundColor Red
        return
    }

    $renderer = $null
    foreach ($cmd in @('glow', 'bat', 'mdcat')) {
        if (Get-Command $cmd -ErrorAction SilentlyContinue) { $renderer = $cmd; break }
    }

    switch ($renderer) {
        'glow'  { & glow -p $guidePath }
        'bat'   { & bat --style=plain --paging=always --language=markdown $guidePath }
        'mdcat' { & mdcat $guidePath }
        default {
            # Fallback colorised — copy khối ForEach-Object ở trên
            Get-Content $guidePath -Encoding UTF8 | ForEach-Object { <# ... #> }
        }
    }
}
```

Dispatch từ wrapper:
```powershell
'guide' { Show-XxxGuide }
```

---

## ✍️ Checklist viết guide đẹp

- [ ] Heading emoji (🚀 ⭐ ⚡ 🏗 🧭 🆘) để scan lướt.
- [ ] Bảng 2-3 cột cho so sánh / troubleshoot.
- [ ] Code fence có language hint (`powershell`, `yaml`, `bash`).
- [ ] Blockquote `>` cho câu "nhắc cuối".
- [ ] Copy-paste commands thực tế (không pseudo-code).
- [ ] Link chính thức cuối file.
- [ ] Mở bằng: `8sync <module> guide` — nhớ thêm hint cài `glow` ở cuối.
- [ ] Save UTF-8 (không BOM). Kiểm tra bằng `Get-Content -Encoding UTF8` render không lỗi dấu.

---

## 🔗 Ví dụ sống

- `modules/gsd/docs/gsd-pi-vi.md` — guide gsd-pi v2.76 (reference implementation).
- `modules/gsd/20-interactive.ps1` → `Show-GsdGuide` — renderer chain.
- `modules/gsd/50-command.ps1` → dispatch `'guide'`.

Gõ ngay:
```powershell
8sync gsd guide
```

> **Kết luận ngắn:** "đẹp" = markdown clean + glow render + UTF-8 đúng + fallback có màu. Không cần framework, không cần CSS. Terminal thuần PowerShell + 1 binary 10MB (glow) là đủ.
