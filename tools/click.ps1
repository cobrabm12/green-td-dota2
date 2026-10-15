# Click inside the Dota 2 game window. Coordinates are in the 1280x720 client area.
# Usage: powershell -File tools/click.ps1 <x> <y> [left|right]
param([int]$X, [int]$Y, [string]$Button = "left")
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class GtdClick {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
  public static IntPtr Find(uint target, string title) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => { uint pid; GetWindowThreadProcessId(h, out pid); var sb = new StringBuilder(256); GetWindowText(h, sb, 256); if (pid == target && sb.ToString() == title) { found = h; } return true; }, IntPtr.Zero);
    return found;
  }
}
"@
$p = Get-Process -Name dota2 -ErrorAction Stop
$h = [GtdClick]::Find([uint32]$p.Id, "Dota 2")
[GtdClick]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 300
$pt = New-Object GtdClick+POINT
$pt.X = $X; $pt.Y = $Y
[GtdClick]::ClientToScreen($h, [ref]$pt) | Out-Null
[GtdClick]::SetCursorPos($pt.X, $pt.Y) | Out-Null
Start-Sleep -Milliseconds 200
if ($Button -eq "right") { $down = 0x0008; $up = 0x0010 } else { $down = 0x0002; $up = 0x0004 }
[GtdClick]::mouse_event($down, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 80
[GtdClick]::mouse_event($up, 0, 0, 0, [IntPtr]::Zero)
"clicked $Button at client ($X,$Y) -> screen ($($pt.X),$($pt.Y))"
