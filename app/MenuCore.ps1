#requires -version 5.1
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$script:MenuScanWarnings=@()
function Add-MenuScanWarning([string]$Stage,[string]$Path,[string]$Message) {
 $script:MenuScanWarnings += [pscustomobject]@{Stage=$Stage;Path=$Path;Message=$Message}
}
function Get-MenuScanWarnings { @($script:MenuScanWarnings) }

$script:BlockedPath = 'Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'
$script:KnownCom = @{
'{0D8B46EA-7D35-4921-B88C-7E2B1E2D80F0}' = @('WPS 桌面／文件夹扩展','WPS Office')
'{AF1D7D2F-6AE8-4BAA-ABFA-738201F4871C}' = @('WPS 文件操作扩展','WPS Office')
'{67F4D210-BFC2-4ADD-9A2A-C9B9E1F42C4F}' = @('WPS 云文档扩展','WPS Office')
'{AA147FFB-0B1F-4BB1-9B1E-8D062B35C146}' = @('WPS 云文档扩展菜单','WPS Office')
'{99D4E39A-EA7F-453E-9488-58C56BBF7B98}' = @('夸克 AI 右键扩展','夸克')
'{A5AF131F-FAE4-48FD-95A2-D0CE5B91DEC2}' = @('豆包右键扩展','豆包')

'{85212CFD-77ED-4ADD-8E24-A0A39E3DBFC3}' = @('搜狗输入法扩展','搜狗输入法')
'{7BCE96FA-77AF-4288-9E16-2388A50EC807}' = @('搜狗输入法扩展（空白处）','搜狗输入法')
'{6D85624F-305A-491D-8848-C1927AA0D790}' = @('百度网盘扩展','百度网盘')
'{23170F69-40C1-278A-1000-000100020000}' = @('7-Zip 压缩菜单','7-Zip')
'{18A3E590-F219-4105-9079-93DAFA51B9D6}' = @('火绒扫描','火绒安全')
'{9F012318-CAA5-402C-9BF6-28EB36F61496}' = @('火绒文件粉碎','火绒安全')
'{1984DD45-52CF-49CD-AB77-18F378FEA264}' = @('Fences 桌面整理','Fences')
'{F2E8B4A1-9C7D-4F6E-B3A5-8D2C1F4E9B7A}' = @('NVIDIA 桌面菜单','NVIDIA')
'{A929C4CE-FD36-4270-B4F5-34ECAC5BD63C}' = @('NVIDIA 程序菜单','NVIDIA')
'{E97DEC16-A50D-49BB-AE24-CF682282E08D}' = @('NVIDIA 图形选项','NVIDIA')
}
function Open-Base([string]$Hive) {
 [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::$Hive,[Microsoft.Win32.RegistryView]::Registry64)
}
function Get-ValueState([string]$Path,[string]$Name,[string]$Hive='CurrentUser') {
 $b=Open-Base $Hive; $k=$null
 try {
  $k=$b.OpenSubKey($Path)
  $exists=$null -ne $k -and $k.GetValueNames() -contains $Name
  $kind='String'; $value=$null
  if($exists) {$kind=$k.GetValueKind($Name).ToString();$value=$k.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}
  [pscustomobject]@{Exists=[bool]$exists;Kind=$kind;Value=$value}
 } finally {if($k){$k.Dispose()};$b.Dispose()}
}
function Equal-State($A,$B) {
 if([bool]$A.Exists -ne [bool]$B.Exists){return $false}
 if(-not $A.Exists){return $true}
 return ($A.Kind -eq $B.Kind -and (ConvertTo-Json -InputObject $A.Value -Compress -Depth 8) -ceq (ConvertTo-Json -InputObject $B.Value -Compress -Depth 8))
}
function Assert-AllowedValue([string]$Path,[string]$Name) {
 if($Path -eq $script:BlockedPath -and ($script:KnownCom.ContainsKey($Name) -and $Name -ne '{1984DD45-52CF-49CD-AB77-18F378FEA264}')){return}
 if($Name -eq 'LegacyDisable' -and $Path -match '^Software\\Classes\\(.+)\\shell\\([^\\]+)$'){
  $scope=$Matches[1];$verb=$Matches[2]
  if($scope -in @('*','Directory','Directory\Background','Drive','Folder','DesktopBackground','AllFilesystemObjects','lnkfile','exefile') -and
   $verb -in @('Open with IntelliJ IDEA','Open with PyCharm','IntelliJ IDEA','PyCharm','VSCode','git_gui','git_shell','WorkBuddy','WeTypeFileTransfer','OpenProjectInCodex','YunShellExplorerCommand')) {return}
 }
 throw "拒绝修改管理范围之外的设置：$Path / $Name"
}
function Set-ValueState([string]$Path,[string]$Name,$State) {
 Assert-AllowedValue $Path $Name
 $b=Open-Base 'CurrentUser';$k=$null
 try {
  if($State.Exists){
   $k=$b.CreateSubKey($Path)
   $kind=[enum]::Parse([Microsoft.Win32.RegistryValueKind],[string]$State.Kind)
   $val=$State.Value
   switch($State.Kind){ 'DWord' {$val=[int]$val}; 'QWord' {$val=[long]$val}; 'Binary' {$val=[byte[]]$val}; 'MultiString' {$val=[string[]]$val}; default {$val=[string]$val} }
   $k.SetValue($Name,$val,$kind)
  } else {
   $k=$b.OpenSubKey($Path,$true)
   if($k){$k.DeleteValue($Name,$false)}
  }
 } finally {if($k){$k.Dispose()};$b.Dispose()}
 # Empty overlay keys are harmless; never remove unrelated values or subkeys.
}
function Get-LocationLabel([string]$Scope) {
 switch($Scope){
 '*' {'所有文件'}; 'AllFilesystemObjects' {'文件和文件夹'}; 'Directory' {'文件夹'};
 'Directory\Background' {'文件夹 / 桌面空白处'}; 'DesktopBackground' {'桌面空白处'};
 'Drive' {'磁盘'}; 'Folder' {'文件夹（含特殊文件夹）'}; 'lnkfile' {'快捷方式'}; 'exefile' {'应用程序'};
 default {if($Scope.StartsWith('SystemFileAssociations\')){"文件类型：$($Scope.Substring(23))"}else{"文件类型：$Scope"}}
 }
}
function Get-StaticIdentity([string]$Verb) {
 switch -Exact ($Verb) {
 'Open with IntelliJ IDEA' {@('用 IDEA 编辑','IntelliJ IDEA')}
 'IntelliJ IDEA' {@('用 IDEA 打开','IntelliJ IDEA')}
 'Open with PyCharm' {@('用 PyCharm 编辑','PyCharm')}
 'PyCharm' {@('用 PyCharm 打开','PyCharm')}
 'VSCode' {@('通过 Code 打开','Visual Studio Code')}
 'git_gui' {@('Git GUI Here','Git')}
 'git_shell' {@('Git Bash Here','Git')}
 'WorkBuddy' {@('用 WorkBuddy 打开','WorkBuddy')}
 'WeTypeFileTransfer' {@('使用微信输入法隔空传送','微信输入法')}
 'OpenProjectInCodex' {@('Open project in ChatGPT','Codex')}
 'YunShellExplorerCommand' {@('百度网盘入口','百度网盘')}
 default {@()}
 }
}
function Get-MenuInventory {
 $script:MenuScanWarnings=@()
 $cr=Open-Base 'ClassesRoot'
 $rows=New-Object 'System.Collections.Generic.List[object]'
 $groups=@{}
 $scopes=New-Object 'System.Collections.Generic.List[string]'
 try {
  foreach($s in $cr.GetSubKeyNames()){
   if($s -notin @('CLSID','Interface','TypeLib','AppID','Wow6432Node','ActivatableClasses','Local Settings')){$scopes.Add($s)}
  }
  $scopes.Add('Directory\Background')
  $sf=$null;try{$sf=$cr.OpenSubKey('SystemFileAssociations')}catch{Add-MenuScanWarning '扫描' 'SystemFileAssociations' $_.Exception.Message}
  if($sf){try{foreach($s in $sf.GetSubKeyNames()){$scopes.Add("SystemFileAssociations\$s")}}catch{Add-MenuScanWarning '枚举文件关联' 'SystemFileAssociations' $_.Exception.Message}finally{$sf.Dispose()}}
  foreach($scope in ($scopes | Select-Object -Unique)){
   foreach($type in @('verb','com')){
    $base=if($type -eq 'verb'){"$scope\shell"}else{"$scope\shellex\ContextMenuHandlers"}
    try{$parent=$cr.OpenSubKey($base)}catch{Add-MenuScanWarning '扫描' $base $_.Exception.Message;continue}
    if(-not $parent){continue}
    try {
     foreach($leaf in $parent.GetSubKeyNames()){
      $path="$base\$leaf";try{$key=$cr.OpenSubKey($path)}catch{Add-MenuScanWarning '扫描' $path $_.Exception.Message;continue}
      if(-not $key){continue}
      try {
       $raw=[string]$key.GetValue('');$label=$raw;$source='';$software='系统 / 未确认';$can=$false;$reason='系统或来源未确认，只读保护'
       $id="$type|$path";$targets=@();$external=$false;$note=''
       if($type -eq 'verb'){
        $title=[string]$key.GetValue('MUIVerb');if($title){$label=$title}
        if(-not $label -or $label.StartsWith('@')){$label=$leaf}
        $ck=$key.OpenSubKey('command');if($ck){try{$source=[string]$ck.GetValue('')}finally{$ck.Dispose()}}
        $identity=@(Get-StaticIdentity $leaf)
        if($identity.Count -eq 2 -and $scope -in @('*','Directory','Directory\Background','Drive','Folder','DesktopBackground','AllFilesystemObjects','lnkfile','exefile')){
         $label=$identity[0];$software=$identity[1];$can=$true;$reason='';$id="verb|$leaf"
        }
        $targetPath="Software\Classes\$path"
        $state=Get-ValueState $targetPath 'LegacyDisable'
        $machine=Get-ValueState $targetPath 'LegacyDisable' 'LocalMachine'
        $external=$machine.Exists -or $key.GetValueNames() -contains 'ProgrammaticAccessOnly'
        if($key.GetValueNames() -contains 'Extended'){$note='按住 Shift 时显示'}
        $targets=@([pscustomobject]@{Path=$targetPath;Name='LegacyDisable';State=$state;External=$external})
       } else {
        $clsid=$raw.Trim().ToUpperInvariant()
        if($clsid -notmatch '^\{[0-9A-F-]{36}\}$' -and $leaf -match '^\{[0-9A-Fa-f-]{36}\}$'){$clsid=$leaf.ToUpperInvariant()}
        if($clsid -match '^\{[0-9A-F-]{36}\}$'){
         $id="com|$clsid"
         $dll=$cr.OpenSubKey("CLSID\$clsid\InprocServer32")
         if($dll){try{$source=[string]$dll.GetValue('')}finally{$dll.Dispose()}}
         if($script:KnownCom.ContainsKey($clsid)){
          $label=$script:KnownCom[$clsid][0];$software=$script:KnownCom[$clsid][1];$can=$true;$reason=''
         }else{$label=$leaf}
         $state=Get-ValueState $script:BlockedPath $clsid
         $machine=Get-ValueState $script:BlockedPath $clsid 'LocalMachine'
         $external=$machine.Exists
         $targets=@([pscustomobject]@{Path=$script:BlockedPath;Name=$clsid;State=$state;External=$external})
         $note='扩展菜单：同一扩展的所有位置一起隐藏'
        }else{$label=$leaf;$note='扩展标识为空或无法识别'}
       }
       if($external){$can=$false;$reason='其他设置已隐藏此项，只读保护'}
       if($software -eq 'Fences'){$can=$false;$reason='关联桌面整理功能，只读保护'}
       if(-not $groups.ContainsKey($id)){
        $obj=[pscustomobject]@{Id=$id;Label=$label;Software=$software;Locations='';Current='';Hide=$false;CanEdit=$can;Reason=$reason;Note=$note;Source=$source;Type=$type;ScopeList=(New-Object 'System.Collections.Generic.List[string]');Registrations=(New-Object 'System.Collections.Generic.List[string]');Targets=(New-Object 'System.Collections.Generic.List[object]')}
        $groups[$id]=$obj;$rows.Add($obj)
       }
       $obj=$groups[$id];$obj.ScopeList.Add((Get-LocationLabel $scope));$obj.Registrations.Add($path)
       if(-not $can){$obj.CanEdit=$false;if($reason){$obj.Reason=$reason}}
       foreach($target in $targets){if(-not @($obj.Targets | Where-Object {$_.Path -eq $target.Path -and $_.Name -eq $target.Name}).Count){$obj.Targets.Add($target)}}
      } catch {Add-MenuScanWarning '读取菜单' $path $_.Exception.Message} finally {$key.Dispose()}
     }
    } catch {Add-MenuScanWarning '枚举菜单' $base $_.Exception.Message} finally {$parent.Dispose()}
   }
  }
 } finally {$cr.Dispose()}
 . (Join-Path $PSScriptRoot 'MenuAttribution.ps1')
 Update-MenuAttribution $rows
 foreach($row in $rows){
  $row.Locations=($row.ScopeList | Select-Object -Unique) -join '、'
  $hidden=@($row.Targets | Where-Object {$_.State.Exists -or $_.External}).Count
  $row.Hide=$row.Targets.Count -gt 0 -and $hidden -eq $row.Targets.Count
  $row.Current=if($row.Hide){'已设为隐藏'}elseif($hidden -gt 0){'部分位置隐藏'}else{'未设为隐藏'}
  if(-not $row.CanEdit){$row.Current+=' · 只读'}
 }
 @($rows | Sort-Object @{Expression='CanEdit';Descending=$true},Software,Label)
}
function Get-ChangePlan($Rows) {
 foreach($row in $Rows){
  if(-not $row.CanEdit){continue}
  # Mixed states remain untouched unless the checkbox is changed.
  $originalAll=$row.Targets.Count -gt 0 -and @($row.Targets | Where-Object {$_.State.Exists}).Count -eq $row.Targets.Count
  if([bool]$row.Hide -eq $originalAll){continue}
  foreach($target in $row.Targets){
   $after=[pscustomobject]@{Exists=[bool]$row.Hide;Kind='String';Value=if($row.Hide){''}else{$null}}
   if([bool]$target.State.Exists -eq [bool]$after.Exists){continue}
   Assert-AllowedValue $target.Path $target.Name
   [pscustomobject]@{Path=$target.Path;Name=$target.Name;Before=$target.State;After=$after;Label=$row.Label;Action=if($row.Hide){'隐藏'}else{'恢复显示'}}
  }
 }
}
function Save-JsonAtomic($Object,[string]$Path) {
 $temp="$Path.tmp";$text=ConvertTo-Json -InputObject $Object -Depth 16
 [IO.File]::WriteAllText($temp,$text,(New-Object Text.UTF8Encoding($true)))
 Move-Item -LiteralPath $temp -Destination $Path -Force
}
function Get-UserSid { [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
function Invoke-ChangeTransaction($Operations,[string]$Folder,[string]$Kind='apply') {
 $ops=@($Operations);if(-not $ops.Count){throw '没有待应用的变化'}
 foreach($op in $ops){
  Assert-AllowedValue $op.Path $op.Name
  if(-not (Equal-State (Get-ValueState $op.Path $op.Name) $op.Before)){throw "设置已被其他程序改变，请重新扫描：$($op.Label)"}
 }
 [void][IO.Directory]::CreateDirectory($Folder)
 $file=Join-Path $Folder ("{0}-{1}-{2}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'),$Kind,([guid]::NewGuid().ToString('N').Substring(0,8)))
 $record=[pscustomobject]@{Schema=1;UserSid=(Get-UserSid);Computer=$env:COMPUTERNAME;Created=(Get-Date).ToString('o');Kind=$Kind;Status='prepared';Operations=$ops;Error=''}
 Save-JsonAtomic $record $file
 $completed=New-Object 'System.Collections.Generic.List[object]'
 try {
  foreach($op in $ops){
   # Recheck immediately before writing, including during restore.
   if(-not (Equal-State (Get-ValueState $op.Path $op.Name) $op.Before)){throw "检测到并发修改：$($op.Label)"}
   $completed.Add($op)
   Set-ValueState $op.Path $op.Name $op.After
   if(-not (Equal-State (Get-ValueState $op.Path $op.Name) $op.After)){throw "写入校验失败：$($op.Label)"}
  }
  $record.Status='applied';Save-JsonAtomic $record $file
 } catch {
  $problem=$_.Exception.Message;$failed=@()
  for($i=$completed.Count-1;$i -ge 0;$i--){
   $op=$completed[$i]
   try {
    $now=Get-ValueState $op.Path $op.Name
    if(Equal-State $now $op.After){Set-ValueState $op.Path $op.Name $op.Before}
    elseif(-not (Equal-State $now $op.Before)){throw '外部设置冲突'}
   }catch{$failed+=$op.Label}
  }
  $record.Status=if($failed.Count){'rollback-incomplete'}else{'rolled-back'};$record.Error=$problem
  Save-JsonAtomic $record $file
  throw "应用未完成：$problem。备份：$file；状态：$($record.Status)"
 }
 $file
}
function Get-RestorePlan([string]$File) {
 $record=Get-Content -LiteralPath $File -Raw -Encoding UTF8 | ConvertFrom-Json
 if($record.Schema -ne 1 -or $record.UserSid -ne (Get-UserSid) -or $record.Computer -ne $env:COMPUTERNAME){throw '备份不属于当前电脑和用户'}
 if($record.Status -notin @('applied','prepared','rollback-incomplete')){throw "该记录无需还原（$($record.Status)）"}
 $ops=@($record.Operations)
 for($i=$ops.Count-1;$i -ge 0;$i--){
  $op=$ops[$i];Assert-AllowedValue $op.Path $op.Name
  $now=Get-ValueState $op.Path $op.Name
  if(Equal-State $now $op.Before){continue}
  if(-not (Equal-State $now $op.After)){throw "此项后来又被修改过，暂不覆盖：$($op.Label)"}
  [pscustomobject]@{Path=$op.Path;Name=$op.Name;Before=$now;After=$op.Before;Label=$op.Label;Action='还原备份'}
 }
}
