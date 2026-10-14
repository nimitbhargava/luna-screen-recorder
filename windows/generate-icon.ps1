# Regenerate luna.ico from the unchanged repository mascot on Windows.
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class LunaIconHandle {
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr handle);
}
'@
$source = [System.Drawing.Bitmap]::new((Join-Path $PSScriptRoot "../assets/luna_mascot.png"))
$bitmap = [System.Drawing.Bitmap]::new($source, [System.Drawing.Size]::new(256, 256))
$handle = $bitmap.GetHicon()
$icon = [System.Drawing.Icon]::FromHandle($handle)
$output = [System.IO.File]::Create((Join-Path $PSScriptRoot "src/Luna.App/luna.ico"))
try { $icon.Save($output) }
finally { $output.Dispose(); $icon.Dispose(); [LunaIconHandle]::DestroyIcon($handle) | Out-Null; $bitmap.Dispose(); $source.Dispose() }
