param(
    [Parameter(Mandatory)][string]$Out,
    [Parameter(Mandatory)][int]$ProcId,
    [int]$Cmd = 0,
    [int]$Pad = 110,
    [string]$Wallpaper = "C:\Windows\Web\Wallpaper\Windows\img19.jpg"
)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class Cmp {
    public delegate bool EnumProc(IntPtr hwnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hwnd, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out RECT rect, int size);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L; public int T; public int R; public int B; }
}
"@
[Cmp]::SetProcessDPIAware() | Out-Null

$target = [IntPtr]::Zero
foreach ($i in 1..40) {
    $cb = [Cmp+EnumProc]{
        param($hwnd, $lp)
        $wpid = [uint32]0
        [Cmp]::GetWindowThreadProcessId($hwnd, [ref]$wpid) | Out-Null
        if ($wpid -eq $script:ProcId -and [Cmp]::IsWindowVisible($hwnd)) {
            $c = New-Object System.Text.StringBuilder 256
            [Cmp]::GetClassName($hwnd, $c, 256) | Out-Null
            if ($c.ToString() -eq "AutoHotkeyGUI") { $script:target = $hwnd; return $false }
        }
        return $true
    }
    [Cmp]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
    if ($target -ne [IntPtr]::Zero) { break }
    Start-Sleep -Milliseconds 250
}
if ($target -eq [IntPtr]::Zero) { Write-Error "no visible AutoHotkeyGUI window for pid $ProcId"; exit 1 }

if ($Cmd -ne 0) {
    [Cmp]::PostMessage($target, 0x111, [IntPtr]$Cmd, [IntPtr]::Zero) | Out-Null
    Start-Sleep -Milliseconds 800
}

$wr = New-Object Cmp+RECT
[Cmp]::GetWindowRect($target, [ref]$wr) | Out-Null
$dr = New-Object Cmp+RECT
[Cmp]::DwmGetWindowAttribute($target, 9, [ref]$dr, 16) | Out-Null

$fullW = $wr.R - $wr.L
$fullH = $wr.B - $wr.T
$full = New-Object System.Drawing.Bitmap($fullW, $fullH)
$gf = [System.Drawing.Graphics]::FromImage($full)
$hdc = $gf.GetHdc()
[Cmp]::PrintWindow($target, $hdc, 2) | Out-Null
$gf.ReleaseHdc($hdc)
$gf.Dispose()

$cropX = $dr.L - $wr.L
$cropY = $dr.T - $wr.T
$winW = $dr.R - $dr.L
$winH = $dr.B - $dr.T
$win = $full.Clone([System.Drawing.Rectangle]::new($cropX, $cropY, $winW, $winH), $full.PixelFormat)
$full.Dispose()

$outW = $winW + 2 * $Pad
$outH = $winH + 2 * $Pad
$outBmp = New-Object System.Drawing.Bitmap($outW, $outH)
$g = [System.Drawing.Graphics]::FromImage($outBmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

$wall = [System.Drawing.Image]::FromFile($Wallpaper)
$srcW = [Math]::Min($wall.Width, [int]($wall.Width * $outW / 2560.0))
$srcH = [Math]::Min($wall.Height, [int]($wall.Height * $outH / 1600.0))
$srcX = [int](($wall.Width - $srcW) / 2)
$srcY = [int](($wall.Height - $srcH) / 2)
$g.DrawImage($wall, [System.Drawing.Rectangle]::new(0, 0, $outW, $outH),
    [System.Drawing.Rectangle]::new($srcX, $srcY, $srcW, $srcH), [System.Drawing.GraphicsUnit]::Pixel)
$wall.Dispose()

function RoundedPath([int]$x, [int]$y, [int]$w, [int]$h, [int]$rad) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $rad * 2
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

foreach ($i in 20..1) {
    $alpha = [int](36 / $i)
    if ($alpha -lt 1) { $alpha = 1 }
    $sb = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($alpha, 0, 0, 0))
    $sp = RoundedPath ($Pad - $i) ($Pad - $i + 8) ($winW + 2 * $i) ($winH + 2 * $i) (12 + $i)
    $g.FillPath($sb, $sp)
    $sp.Dispose(); $sb.Dispose()
}

$clip = RoundedPath $Pad $Pad $winW $winH 12
$g.SetClip($clip)
$g.DrawImage($win, $Pad, $Pad, $winW, $winH)
$g.ResetClip()
$clip.Dispose()

$outBmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $outBmp.Dispose(); $win.Dispose()
Write-Output "saved $Out ($outW x $outH)"
