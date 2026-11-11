#requires -version 5.1
[CmdletBinding()]
param([string]$Version)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
$repoRoot=Split-Path $PSScriptRoot -Parent
if(-not $Version){$Version=(Get-Content -LiteralPath (Join-Path $repoRoot 'VERSION') -Raw).Trim()}
if($Version -notmatch '^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$'){throw 'Invalid release version.'}
if($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess){
 throw 'Build with 64-bit Windows PowerShell 5.1 (powershell.exe), not PowerShell 7.'
}
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(-not (Test-Path -LiteralPath $compiler)){throw 'The .NET Framework C# compiler was not found.'}
$packageName="WindowsContextMenuManager-$Version-win-x64"
$buildDir=Join-Path $repoRoot ('.build\'+[guid]::NewGuid().ToString('N'))
$stage=Join-Path $buildDir $packageName
$dist=Join-Path $repoRoot 'dist'
[void][IO.Directory]::CreateDirectory($stage)
[void][IO.Directory]::CreateDirectory($dist)
$source=Join-Path $repoRoot 'app'
$payload=@('Launch.ps1','Manager.ps1','MenuCore.ps1','MenuAttribution.ps1','Start.cmd','MenuManager.exe.config')
foreach($file in $payload){Copy-Item -LiteralPath (Join-Path $source $file) -Destination (Join-Path $stage $file)}
foreach($file in @('README.md','LICENSE','CHANGELOG.md')){Copy-Item -LiteralPath (Join-Path $repoRoot $file) -Destination (Join-Path $stage $file)}
$assembly=[System.Management.Automation.PowerShell].Assembly.Location
$numericVersion=($Version -split '-')[0]+'.0'
$versionSource=Join-Path $buildDir 'AssemblyInfo.cs'
$attributes=@"
using System.Reflection;
[assembly: AssemblyTitle("Windows Context Menu Manager")]
[assembly: AssemblyDescription("Portable Windows context menu inventory and management")]
[assembly: AssemblyCompany("brwygr")]
[assembly: AssemblyProduct("Windows Context Menu Manager")]
[assembly: AssemblyVersion("$numericVersion")]
[assembly: AssemblyFileVersion("$numericVersion")]
"@
[IO.File]::WriteAllText($versionSource,$attributes,[Text.Encoding]::UTF8)
& $compiler /nologo /target:winexe /platform:x64 "/out:$(Join-Path $stage 'MenuManager.exe')" "/reference:$assembly" /reference:System.Windows.Forms.dll "/win32manifest:$(Join-Path $source 'app.manifest')" (Join-Path $source 'MenuManager.cs') $versionSource
if($LASTEXITCODE -ne 0){throw "Compilation failed: $LASTEXITCODE"}
$commit=[string]$env:GITHUB_SHA
if($commit -notmatch '^[0-9a-f]{40}$'){
 $headPath=Join-Path $repoRoot '.git\HEAD'
 if(Test-Path -LiteralPath $headPath){
  $head=(Get-Content -LiteralPath $headPath -Raw).Trim()
  if($head -match '^ref: (refs/[A-Za-z0-9/_-]+)$'){
   $refPath=Join-Path (Join-Path $repoRoot '.git') $Matches[1]
   if(Test-Path -LiteralPath $refPath){$commit=(Get-Content -LiteralPath $refPath -Raw).Trim()}
  }elseif($head -match '^[0-9a-f]{40}$'){$commit=$head}
 }
}
if($commit -notmatch '^[0-9a-f]{40}$'){$commit='source archive'}
[pscustomobject]@{Version=$Version;Source='https://github.com/brwygr/Windows-Context-Menu-Manager';Commit=$commit;Architecture='x64';Runtime='Windows PowerShell 5.1 / .NET Framework 4.8'} |
 ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stage 'build-info.json') -Encoding UTF8
$zip=Join-Path $dist ($packageName+'.zip')
Compress-Archive -LiteralPath $stage -DestinationPath $zip -CompressionLevel Optimal -Force
$hash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText(($zip+'.sha256'),("$hash  "+[IO.Path]::GetFileName($zip)+[Environment]::NewLine),[Text.Encoding]::ASCII)
Write-Output "Built: $zip"
Write-Output "SHA256: $hash"
