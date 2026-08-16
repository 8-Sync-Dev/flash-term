<#
  winprobe.ps1 — đếm/đóng cửa sổ NGOÀI app: File Explorer và dialog hệ thống.

  Vì sao cần: nhãn nút đổi màu không chứng minh được gì. Bằng chứng một nút chạy
  thật là hiệu ứng quan sát được bên ngoài webview — cửa sổ Explorer mở ra, hộp
  thoại Save hiện lên, file xuất hiện trên đĩa.

  Cạm bẫy đã gặp:
    - `Shell.Application.Windows()` và `MainWindowTitle` đều trả RỖNG cho cửa sổ
      Explorer trong phiên automation ⇒ tưởng nút hỏng. Phải lọc theo CLASS
      cửa sổ: `CabinetWClass` / `ExploreWClass`.
    - Hộp thoại Save As là cửa sổ top-level class `#32770`, KHÔNG nằm trong cây
      UIA của app; tìm bằng `FindFirst(Name='Save As')` từ app sẽ chỉ thấy một
      phần tử Text trùng tên, không có ô nhập nào.
    - `explorer.exe <path>` chạy rồi thoát ngay (HasExited=True) và giao việc cho
      shell — đừng lấy tiến trình làm bằng chứng, hãy lấy CỬA SỔ.

  Dùng:
    powershell ... -File winprobe.ps1 -Action count-explorer
    powershell ... -File winprobe.ps1 -Action close-explorer
    powershell ... -File winprobe.ps1 -Action count-dialog
#>
[CmdletBinding()]
param(
  [ValidateSet('count-explorer', 'close-explorer', 'count-dialog', 'close-dialog')]
  [string]$Action = 'count-explorer'
)

Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class WinProbe {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
}
'@

$explorerClasses = @('CabinetWClass', 'ExploreWClass')
$dialogClass = '#32770'
$wantClasses = if ($Action -like '*explorer*') { $explorerClasses } else { @($dialogClass) }
$doClose = $Action -like 'close-*'

$hits = New-Object System.Collections.Generic.List[string]
$cb = [WinProbe+EnumProc]{
  param($h, $l)
  if (-not [WinProbe]::IsWindowVisible($h)) { return $true }
  $c = New-Object System.Text.StringBuilder 256
  [void][WinProbe]::GetClassName($h, $c, 256)
  if ($wantClasses -contains $c.ToString()) {
    $t = New-Object System.Text.StringBuilder 512
    [void][WinProbe]::GetWindowText($h, $t, 512)
    $hits.Add("$($c.ToString())|$($t.ToString())")
    if ($doClose) { [void][WinProbe]::PostMessage($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) }  # WM_CLOSE
  }
  return $true
}
[void][WinProbe]::EnumWindows($cb, [IntPtr]::Zero)

Write-Host "COUNT=$($hits.Count)"
foreach ($h in $hits) { Write-Host "  $h" }
