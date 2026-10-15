# Press a key (letter or digit) in the Dota 2 game window.
# Usage: powershell -File tools/key.ps1 S
param([string]$Key)
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class GtdKey {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint type);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
  public static IntPtr Find(uint target, string title) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => { uint pid; GetWindowThreadProcessId(h, out pid); var sb = new StringBuilder(256); GetWindowText(h, sb, 256); if (pid == target && sb.ToString() == title) { found = h; } return true; }, IntPtr.Zero);
    return found;
  }
}
"@
$p = Get-Process -Name dota2 -ErrorAction Stop
$h = [GtdKey]::Find([uint32]$p.Id, "Dota 2")
[GtdKey]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 300
$named = @{ "ENTER" = 0x0D; "ESC" = 0x1B; "DELETE" = 0x2E }
if ($named.ContainsKey($Key.ToUpper())) { $vk = [byte]$named[$Key.ToUpper()] } else { $vk = [byte][char]$Key.ToUpper() }
$scan = [byte][GtdKey]::MapVirtualKey($vk, 0)
[GtdKey]::keybd_event($vk, $scan, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 60
[GtdKey]::keybd_event($vk, $scan, 2, [IntPtr]::Zero)
"pressed $Key"
