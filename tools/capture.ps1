param(
    [Parameter(Mandatory)][string]$Out,
    [Parameter(Mandatory)][int]$ProcId,
    [int]$Cmd = 0
)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class Cap {
    public delegate bool EnumProc(IntPtr hwnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hwnd, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out RECT rect, int size);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L; public int T; public int R; public int B; }
}
"@
[Cap]::SetProcessDPIAware() | Out-Null

$target = [IntPtr]::Zero
foreach ($i in 1..40) {
    $cb = [Cap+EnumProc]{
        param($hwnd, $lp)
        $wpid = [uint32]0
        [Cap]::GetWindowThreadProcessId($hwnd, [ref]$wpid) | Out-Null
        if ($wpid -eq $script:ProcId -and [Cap]::IsWindowVisible($hwnd)) {
            $c = New-Object System.Text.StringBuilder 256
            [Cap]::GetClassName($hwnd, $c, 256) | Out-Null
            if ($c.ToString() -eq "AutoHotkeyGUI") { $script:target = $hwnd; return $false }
        }
        return $true
    }
    [Cap]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
    if ($target -ne [IntPtr]::Zero) { break }
    Start-Sleep -Milliseconds 250
}
if ($target -eq [IntPtr]::Zero) { Write-Error "no visible AutoHotkeyGUI window for pid $ProcId"; exit 1 }

[Cap]::SetForegroundWindow($target) | Out-Null
Start-Sleep -Milliseconds 500

if ($Cmd -ne 0) {
    [Cap]::PostMessage($target, 0x111, [IntPtr]$Cmd, [IntPtr]::Zero) | Out-Null
    Start-Sleep -Milliseconds 800
}

$r = New-Object Cap+RECT
[Cap]::DwmGetWindowAttribute($target, 9, [ref]$r, 16) | Out-Null
$w = $r.R - $r.L
$h = $r.B - $r.T
if ($w -le 0 -or $h -le 0) { Write-Error "bad bounds $w x $h"; exit 1 }

$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$bmp.Dispose()
Write-Output "saved $Out ($w x $h)"
