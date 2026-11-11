#requires -version 5.1
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'app\MenuCore.ps1')
$script:TestCount=0
function Assert-Test([bool]$Condition,[string]$Name) {if(-not $Condition){throw "FAILED: $Name"};$script:TestCount++;Write-Output "PASS: $Name"}
function Expect-Failure([scriptblock]$Action,[string]$Name){$didThrow=$false;try{& $Action | Out-Null}catch{$didThrow=$true};Assert-Test $didThrow $Name}
$off=[pscustomobject]@{Exists=$false;Kind='String';Value=$null}
$on=[pscustomobject]@{Exists=$true;Kind='String';Value=''}
$pathA='Software\Classes\Directory\shell\WorkBuddy'
$pathB='Software\Classes\Directory\Background\shell\WorkBuddy'
function Make-Row($StateA,$StateB,[bool]$Hide,[bool]$Edit=$true) {
 [pscustomobject]@{Label='Test WorkBuddy';CanEdit=$Edit;Hide=$Hide;Targets=@(
 [pscustomobject]@{Path=$pathA;Name='LegacyDisable';State=$StateA;External=$false},
 [pscustomobject]@{Path=$pathB;Name='LegacyDisable';State=$StateB;External=$false})}
}
Assert-Test (@(Get-ChangePlan @((Make-Row $off $off $false))).Count -eq 0) 'unchanged produces no writes'
Assert-Test (@(Get-ChangePlan @((Make-Row $off $off $true))).Count -eq 2) 'hide includes all locations'
Assert-Test (@(Get-ChangePlan @((Make-Row $on $on $false))).Count -eq 2) 'enable removes only markers'
Assert-Test (@(Get-ChangePlan @((Make-Row $off $off $true $false))).Count -eq 0) 'protected rows cannot change'
Assert-Test (@(Get-ChangePlan @((Make-Row $on $off $false))).Count -eq 0) 'mixed states stay unchanged'
Assert-Test (@(Get-ChangePlan @((Make-Row $on $off $true))).Count -eq 1) 'mixed states hide only missing location'
Expect-Failure {Assert-AllowedValue 'Software\Classes\exefile\shell\open' 'LegacyDisable'} 'system verbs rejected'
Expect-Failure {Assert-AllowedValue $pathA '(default)'} 'command values rejected'
Expect-Failure {Assert-AllowedValue 'Software\OutsideTool' 'LegacyDisable'} 'outside paths rejected'
Assert-Test (-not (Equal-State $off $on)) 'missing and empty value distinguished'
Assert-Test (Equal-State $on ([pscustomobject]@{Exists=$true;Kind='String';Value=''})) 'empty value preserved'

# Parse every shipped PowerShell source under the actual Windows PowerShell engine.
$repoRoot=Split-Path $PSScriptRoot -Parent
foreach($folder in @('app','scripts','tests')){
 foreach($sourceFile in Get-ChildItem -LiteralPath (Join-Path $repoRoot $folder) -Filter '*.ps1'){
  $tokens=$null;$parseErrors=$null
  [void][Management.Automation.Language.Parser]::ParseFile($sourceFile.FullName,[ref]$tokens,[ref]$parseErrors)
  Assert-Test (-not $parseErrors.Count) ("PowerShell source parses: "+$sourceFile.Name)
 }
}
. (Join-Path $repoRoot 'app\MenuAttribution.ps1')
$registry=Open-Base 'ClassesRoot'
try{
 $examples=@(
  @('"C:\Example App\tool.exe" "%1"','C:\Example App\tool.exe'),
  @('C:\Example App\tool.exe "%1"','C:\Example App\tool.exe'),
  @('\\?\C:\Example App\tool.exe "%1"','C:\Example App\tool.exe'),
  @('"\\?\C:\Example App\tool.exe" "%1"','C:\Example App\tool.exe'),
  @('rundll32.exe shell32.dll,OpenAs_RunDLL "%1"',(Join-Path $env:WINDIR 'System32\shell32.dll')),
  @('explorer ms-settings:storagesense',(Join-Path $env:WINDIR 'explorer.exe')),
  @('\\example.invalid\share\tool.exe "%1"',''),
  @('"\\?\UNC\example.invalid\share\tool.exe" "%1"',''))
 foreach($example in $examples){Assert-Test ((Resolve-MenuFile $example[0] $registry) -eq $example[1]) ("Portable command parsing: "+$example[0])}
}finally{$registry.Dispose()}

# All transaction tests below replace the registry adapter with an in-memory fake.
# No function in this test process can write to the Windows registry.
$script:Fake=@{}
$script:FailPath=''
function Get-ValueState([string]$Path,[string]$Name,[string]$Hive='CurrentUser'){
 $id="$Hive|$Path|$Name";if($script:Fake.ContainsKey($id)){$script:Fake[$id]}else{$off}
}
function Set-ValueState([string]$Path,[string]$Name,$State) {
 Assert-AllowedValue $Path $Name
 if($Path -eq $script:FailPath){throw 'injected write failure'}
 $script:Fake["CurrentUser|$Path|$Name"]=$State
}
function Get-UserSid {'SIMULATED-USER-NOT-A-REAL-BACKUP'}
$folder=Join-Path (Split-Path $PSScriptRoot -Parent) ('.test-results\'+[guid]::NewGuid().ToString('N'))
$ops=@(Get-ChangePlan @((Make-Row $off $off $true)))
$file=Invoke-ChangeTransaction $ops $folder
Assert-Test ((Equal-State (Get-ValueState $pathA 'LegacyDisable') $on) -and (Equal-State (Get-ValueState $pathB 'LegacyDisable') $on)) 'transaction applied in memory'
$record=Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Test ($record.Status -eq 'applied' -and $record.Operations.Count -eq 2) 'journal contains complete changes'
$undo=@(Get-RestorePlan $file)
Assert-Test ($undo.Count -eq 2) 'restore builds reverse plan'
$undoFile=Invoke-ChangeTransaction $undo $folder 'restore'
Assert-Test ((Equal-State (Get-ValueState $pathA 'LegacyDisable') $off) -and (Equal-State (Get-ValueState $pathB 'LegacyDisable') $off)) 'restore recovers absent values'
Assert-Test (@(Get-RestorePlan $file).Count -eq 0) 'repeated restore is no-op'
$script:Fake=@{};$script:FailPath=$pathB
Expect-Failure {Invoke-ChangeTransaction $ops $folder} 'write failure detected'
Assert-Test (Equal-State (Get-ValueState $pathA 'LegacyDisable') $off) 'partial writes rolled back'
$script:FailPath=''
$script:Fake["CurrentUser|$pathA|LegacyDisable"]=$on
Expect-Failure {Invoke-ChangeTransaction $ops $folder} 'stale scan refuses overwrite'
$script:Fake=@{}
$file=Invoke-ChangeTransaction $ops $folder
$script:Fake["CurrentUser|$pathA|LegacyDisable"]=[pscustomobject]@{Exists=$true;Kind='String';Value='another-program'}
Expect-Failure {Get-RestorePlan $file} 'restore refuses outside changes'
$script:Fake=@{}
$odd=[pscustomobject]@{Exists=$true;Kind='String';Value='preserve-this'}
$script:Fake["CurrentUser|$pathA|LegacyDisable"]=$odd
$op=[pscustomobject]@{Path=$pathA;Name='LegacyDisable';Before=$odd;After=$off;Label='existing value';Action='show'}
$file=Invoke-ChangeTransaction @($op) $folder
[void](Invoke-ChangeTransaction @(Get-RestorePlan $file) $folder 'restore')
Assert-Test (Equal-State (Get-ValueState $pathA 'LegacyDisable') $odd) 'restore retains original nonempty value'

$comList=@(
'{0D8B46EA-7D35-4921-B88C-7E2B1E2D80F0}',
'{AF1D7D2F-6AE8-4BAA-ABFA-738201F4871C}',
'{67F4D210-BFC2-4ADD-9A2A-C9B9E1F42C4F}',
'{AA147FFB-0B1F-4BB1-9B1E-8D062B35C146}',
'{99D4E39A-EA7F-453E-9488-58C56BBF7B98}',
'{A5AF131F-FAE4-48FD-95A2-D0CE5B91DEC2}')
foreach($clsid in $comList){
 Assert-AllowedValue $script:BlockedPath $clsid
 $mockrow=[pscustomobject]@{Label=$clsid;CanEdit=$true;Hide=$true;Targets=@([pscustomobject]@{Path=$script:BlockedPath;Name=$clsid;State=$off;External=$false})}
 $change=@(Get-ChangePlan @($mockrow))
 Assert-Test ($change.Count -eq 1 -and $change[0].Path -eq $script:BlockedPath -and $change[0].Name -eq $clsid) "new third-party extension supported: $clsid"
 $journal=Invoke-ChangeTransaction $change $folder
 $restore=@(Get-RestorePlan $journal)
 [void](Invoke-ChangeTransaction $restore $folder 'restore')
 Assert-Test (Equal-State (Get-ValueState $script:BlockedPath $clsid) $off) "new extension restore exact: $clsid"
}
Expect-Failure {Assert-AllowedValue $script:BlockedPath '{F3D06E7C-1E45-4A26-847E-F9FCDEE59BE0}'} 'system CopyAsPath remains protected'
Expect-Failure {Assert-AllowedValue $script:BlockedPath '{E2529821-0B54-4D5A-9268-C6AD72C6E1D0}'} 'unresolved old Quark extension stays protected'
Expect-Failure {Assert-AllowedValue 'Software\Classes\WPS.docx.6\shell\open' 'LegacyDisable'} 'WPS default opening remains protected'

Expect-Failure {Assert-AllowedValue $script:BlockedPath '{1984DD45-52CF-49CD-AB77-18F378FEA264}'} 'Fences remains protected in backend'

# Portability: no installed applications or readable menu registrations required.
& {
 $script:EmptyRegistry=[pscustomobject]@{}
 $script:EmptyRegistry | Add-Member ScriptMethod GetSubKeyNames { @() }
 $script:EmptyRegistry | Add-Member ScriptMethod OpenSubKey { param($Path) $null }
 $script:EmptyRegistry | Add-Member ScriptMethod Dispose {}
 function Open-Base([string]$Hive){ $script:EmptyRegistry }
 $empty=@(Get-MenuInventory)
 Assert-Test ($empty.Count -eq 0) 'empty registry scans successfully'
 Assert-Test (@(Get-ChangePlan $empty).Count -eq 0) 'empty scan creates no changes'
}
& {
 $script:DeniedRegistry=[pscustomobject]@{}
 $script:DeniedRegistry | Add-Member ScriptMethod GetSubKeyNames { throw [UnauthorizedAccessException]::new('fixture denied') }
 $script:DeniedRegistry | Add-Member ScriptMethod Dispose {}
 $script:RootRegistry=[pscustomobject]@{}
 $script:RootRegistry | Add-Member ScriptMethod GetSubKeyNames { @() }
 $script:RootRegistry | Add-Member ScriptMethod OpenSubKey { param($Path) if($Path -eq 'SystemFileAssociations'){ $script:DeniedRegistry } }
 $script:RootRegistry | Add-Member ScriptMethod Dispose {}
 function Open-Base([string]$Hive){ $script:RootRegistry }
 [void]@(Get-MenuInventory)
 Assert-Test (@(Get-MenuScanWarnings).Count -gt 0) 'enumeration denial produces warning'
}
$foreign=Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
$foreign.UserSid='ANOTHER-SIMULATED-USER'
$foreignPath=Join-Path $folder 'foreign-user-fixture.json'
Save-JsonAtomic $foreign $foreignPath
Expect-Failure {Get-RestorePlan $foreignPath} 'foreign-user backup is refused'

Write-Output "ALL $script:TestCount TESTS PASSED. Registry writes: 0 (in-memory adapter)."
