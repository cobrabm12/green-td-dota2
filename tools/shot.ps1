# Bring the Dota 2 game window to the front, take a screenshot through the console and convert it to PNG.
# Usage: powershell -File tools/shot.ps1 <out.png>
param([string]$Out = "_work/shot.png")
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class GtdWin {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  public static IntPtr Find(uint target, string title) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => { uint pid; GetWindowThreadProcessId(h, out pid); var sb = new StringBuilder(256); GetWindowText(h, sb, 256); if (pid == target && sb.ToString() == title) { found = h; } return true; }, IntPtr.Zero);
    return found;
  }
}
"@
$p = Get-Process -Name dota2 -ErrorAction Stop
$h = [GtdWin]::Find([uint32]$p.Id, "Dota 2")
if ($h -ne [IntPtr]::Zero) { [GtdWin]::ShowWindow($h, 9) | Out-Null; [GtdWin]::SetForegroundWindow($h) | Out-Null }
Start-Sleep -Milliseconds 1500
$root = Split-Path -Parent $PSScriptRoot
python -I "$root/tools/netcon.py" --wait 2 "screenshot" | Out-Null
$dir = "C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta\game\dota\screenshots"
$tga = Get-ChildItem $dir -Filter *.tga | Sort-Object LastWriteTime -Descending | Select-Object -First 1
python -I "$root/tools/tga2png.py" $tga.FullName $Out
