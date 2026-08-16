<#
  uia.ps1 — điều khiển & đọc UI của app Tauri trên Windows qua UI Automation.

  Vì sao không dùng cách khác:
    - Trình duyệt + dev server (:1420): mở được trang NHƯNG `__TAURI_INTERNALS__`
      không tồn tại ⇒ mọi nút gọi IPC báo "Không có bridge Tauri". Chỉ hợp để
      xem bố cục, KHÔNG kiểm chứng được nút.
    - `--remote-debugging-port` / WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS: đã thử,
      cổng CDP không mở trên bản debug của app này.
    - Giả lập chuột (`mouse_event` + `SetForegroundWindow`): thất bại âm thầm
      (Windows chặn đổi foreground, cửa sổ tự di chuyển làm lệch toạ độ) và có
      lần click trúng nút Close làm app thoát giữa chừng.
  ⇒ UI Automation đọc thẳng cây accessibility của WebView2, không cần toạ độ.

  Dùng:
    powershell -NoProfile -ExecutionPolicy Bypass -File uia.ps1 -Action dump
    powershell ... -File uia.ps1 -Action click -Name "Quét lại danh sách"
    powershell ... -File uia.ps1 -Action wait  -Text "Đang bật..." -TimeoutMs 60000

  Tên tiếng Việt có dấu: truyền qua -Name/-Text thường hỏng mã khi đi qua
  Git Bash. Dùng -NameFile <đường dẫn file UTF-8> để chắc chắn.
#>
[CmdletBinding()]
param(
  [ValidateSet('dump', 'click', 'wait', 'exists')]
  [string]$Action = 'dump',

  [string]$Name = '',
  [string]$NameFile = '',
  [string]$Text = '',
  [int]$Index = 0,
  [int]$TimeoutMs = 8000,
  [string]$Process = 'eightic',
  [string]$Out = ''
)

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

function Get-AppRoot {
  param([string]$ProcName)
  $p = Get-Process $ProcName -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if (-not $p) { throw "KHONG_THAY_APP: không có tiến trình '$ProcName' nào có cửa sổ" }
  [System.Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
}

function Get-All {
  param($Root)
  $Root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.Condition]::TrueCondition)
}

# Tên nút đọc từ file UTF-8 khi có: tránh hỏng dấu tiếng Việt qua dòng lệnh.
if ($NameFile -ne '') {
  $Name = [System.IO.File]::ReadAllText($NameFile, [System.Text.Encoding]::UTF8).Trim()
}

$root = Get-AppRoot -ProcName $Process

switch ($Action) {

  'dump' {
    $all = Get-All -Root $root
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($e in $all) {
      $n = $e.Current.Name
      if ($n -and $n.Length -gt 1) {
        $t = $e.Current.ControlType.ProgrammaticName.Replace('ControlType.', '')
        $lines.Add("${t}: $n")
      }
    }
    if ($Out -ne '') {
      # WriteAllLines + UTF8: `Write-Output` qua pipe của Git Bash mất sạch chữ.
      [System.IO.File]::WriteAllLines($Out, $lines, [System.Text.Encoding]::UTF8)
      Write-Host "DUMP_OK=$($lines.Count) -> $Out"
    } else {
      $lines | ForEach-Object { Write-Host $_ }
    }
  }

  'click' {
    if ($Name -eq '') { throw "click cần -Name hoặc -NameFile" }
    $cond = New-Object System.Windows.Automation.PropertyCondition(
      [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
      [System.Windows.Automation.ControlType]::Button)
    $btns = @($root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond) |
      Where-Object { $_.Current.Name -eq $Name })
    if ($btns.Count -eq 0) {
      $btns = @($root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond) |
        Where-Object { $_.Current.Name -like "*$Name*" })
    }
    if ($btns.Count -eq 0) { Write-Host "KHONG_THAY_NUT: $Name"; exit 1 }
    if ($Index -ge $btns.Count) { Write-Host "INDEX_QUA_LON: có $($btns.Count) nút"; exit 1 }
    $b = $btns[$Index]
    $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Write-Host "CLICK_OK: '$($b.Current.Name)' (khớp $($btns.Count))"
  }

  'exists' {
    $all = Get-All -Root $root
    $hit = @($all | Where-Object { $_.Current.Name -like "*$Text*" })
    Write-Host "EXISTS=$($hit.Count)"
    if ($hit.Count -eq 0) { exit 1 }
  }

  'wait' {
    # Đợi một chuỗi XUẤT HIỆN. Nhãn phản hồi kiểu "Đã lưu" chỉ sống ~2s nên
    # phải hỏi liên tục, đọc trễ một nhịp là tưởng nút chết.
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
      $all = Get-All -Root $root
      $hit = @($all | Where-Object { $_.Current.Name -like "*$Text*" })
      if ($hit.Count -gt 0) {
        Write-Host "THAY: '$($hit[0].Current.Name)'"
        exit 0
      }
      Start-Sleep -Milliseconds 300
    }
    Write-Host "HET_GIO sau ${TimeoutMs}ms, không thấy: $Text"
    exit 1
  }
}
