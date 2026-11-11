#requires -version 5.1
[CmdletBinding()]
param([string]$Package)
$ErrorActionPreference='Stop'
$repoRoot=Split-Path $PSScriptRoot -Parent
$version=(Get-Content -LiteralPath (Join-Path $repoRoot 'VERSION') -Raw).Trim()
if(-not $Package){$Package=Join-Path $repoRoot "dist\WindowsContextMenuManager-$version-win-x64.zip"}
$actual=(Get-FileHash -LiteralPath $Package -Algorithm SHA256).Hash.ToLowerInvariant()
$record=(Get-Content -LiteralPath ($Package+'.sha256') -Raw).Trim()
if(($record -split '\s+')[0] -ne $actual){throw 'Package checksum mismatch.'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::OpenRead($Package)
try{
 $allowed=@('Launch.ps1','Manager.ps1','MenuCore.ps1','MenuAttribution.ps1','Start.cmd','MenuManager.exe.config','README.md','LICENSE','CHANGELOG.md','MenuManager.exe','build-info.json')
 $found=@()
 foreach($entry in $archive.Entries){
  if(-not $entry.Name){continue}
  $path=$entry.FullName.Replace('\','/')
  if($path -notmatch '^[^/]+/[^/]+$' -or $entry.Name -notin $allowed){throw "Unexpected file in public package: $path"}
  $found+=$entry.Name
  if($entry.Name -ne 'MenuManager.exe'){
   $reader=New-Object IO.StreamReader($entry.Open())
   try{$text=$reader.ReadToEnd()}finally{$reader.Dispose()}
   if($text -match '(?i)[A-Z]:\\Users\\[^\\\s''"]+' -or $text -match '(?i)ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}'){
    throw "Possible private machine path or token in $path"
   }
  }
 }
 if($found.Count -ne $allowed.Count -or @($allowed | Where-Object {$_ -notin $found}).Count){throw 'Portable package is incomplete.'}
 Write-Output "PACKAGE CHECK: $($found.Count) expected files; checksum valid; no runtime data included."
}finally{$archive.Dispose()}
