param([string]$Output = (Join-Path $PSScriptRoot "artifacts"))
$ErrorActionPreference = "Stop"
$publish = Join-Path $Output "Luna-Windows-x64"
dotnet publish "$PSScriptRoot/src/Luna.App/Luna.App.csproj" -c Release -r win-x64 --self-contained true -o $publish
if ($LASTEXITCODE -ne 0) { throw "Publish failed" }
$vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
if (!(Test-Path $vswhere)) { throw "Visual Studio C++ tools are required to locate redistributable runtime DLLs" }
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$runtime = Get-ChildItem "$vs/VC/Redist/MSVC/*/x64/Microsoft.VC*.CRT" -Directory | Sort-Object FullName -Descending | Select-Object -First 1
if (!$runtime) { throw "Visual C++ runtime not found" }
Copy-Item "$($runtime.FullName)/*.dll" $publish
foreach ($dll in @("msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll")) {
    if (!(Test-Path (Join-Path $publish $dll))) { throw "Missing $dll" }
}
Copy-Item "$PSScriptRoot/README.md" $publish
$zip = Join-Path $Output "Luna-Windows-x64.zip"
Compress-Archive -Path "$publish/*" -DestinationPath $zip -Force
Write-Output $zip
