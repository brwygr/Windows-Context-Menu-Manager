# Read-only provenance discovery. This file never writes registry values.
function Get-AttributionValue($Root,[string]$Path,[string]$Name='') {
 try{$key=$Root.OpenSubKey($Path)}catch{Add-MenuScanWarning '识别来源' $Path $_.Exception.Message;return ''}
 if(-not $key){return ''}
 try{[string]$key.GetValue($Name,'',[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}finally{$key.Dispose()}
}
function Resolve-MenuFile([string]$Raw,$Root) {
 if(-not $Raw){return ''}
 $text=[Environment]::ExpandEnvironmentVariables($Raw.Trim())
 if($text.StartsWith('@{')){return ''}
 if($text.StartsWith('@')){$text=$text.Substring(1)}
 if($text.StartsWith('\\?\') -and $text.Substring(4) -match '^[A-Za-z]:\\'){$text=$text.Substring(4)}
 if($text -match '(?i)\brundll32(?:\.exe)?"?\s+"?(.+?\.(?:dll|cpl))(?:"|,|\s|$)'){$text=$Matches[1]}
 $candidate=''
 if($text -match '^"([^"]+)"'){$candidate=$Matches[1]}
 elseif($text -match '(?i)^([A-Z]:\\.+?\.(?:exe|dll|cpl|ocx|scr))(?=,|\s|$)'){$candidate=$Matches[1]}
 elseif($text -match '(?i)^([^\s",]+\.(?:exe|dll|cpl|ocx|scr))(?=,|\s|$)'){$candidate=$Matches[1]}
 if(-not $candidate -and $text -match '^(?i)(explorer|control|notepad|rundll32|powershell|cmd|mmc)(?:\s|$)'){$candidate=$Matches[1]+'.exe'}
 if($candidate -match '^\\\\\?\\[A-Za-z]:\\'){$candidate=$candidate.Substring(4)}
 if(-not $candidate -or $candidate -match '%[0-9*LlVv]' -or $candidate.StartsWith('\\')){return ''}
 if([IO.Path]::IsPathRooted($candidate)){return $candidate}
 # Resolve only fixed local Windows locations and App Paths, never execute a command.
 foreach($hive in @('CurrentUser','LocalMachine')){
  $base=Open-Base $hive
  try{$app=Get-AttributionValue $base ("Software\Microsoft\Windows\CurrentVersion\App Paths\"+$candidate)}finally{$base.Dispose()}
  if($app){$expanded=[Environment]::ExpandEnvironmentVariables($app.Trim('"'));if($expanded -match '^[A-Za-z]:\\' -and [IO.File]::Exists($expanded)){return $expanded}}
 }
 $dirs=@("$env:WINDIR\System32","$env:WINDIR","$env:WINDIR\System32\WindowsPowerShell\v1.0","$env:ProgramFiles\Internet Explorer",([Environment]::GetFolderPath('ProgramFilesX86')+'\Internet Explorer'))
 foreach($dir in $dirs){$file=Join-Path $dir $candidate;if([IO.File]::Exists($file)){return $file}}
 ''
}
function Get-MenuFileInfo([string]$Path) {
 if($script:AttributionFileCache.ContainsKey($Path)){return $script:AttributionFileCache[$Path]}
 $info=[pscustomobject]@{Path=$Path;Name='';Evidence='';State='仍需确认';Target=''}
 if(-not [IO.File]::Exists($Path)){
  $info.Name=[IO.Path]::GetFileNameWithoutExtension($Path)+'（登记路径未找到）'
  $info.State='目标未找到';$info.Target='未找到文件或不可访问';$info.Evidence="注册信息指向 $Path；本次未找到文件，不代表软件已卸载。"
 }else{
  $info.Target='文件存在'
  try{
   $v=[Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
   $product=([string]$v.ProductName).Trim()
   $description=([string]$v.FileDescription).Trim()
   $company=([string]$v.CompanyName).Trim()
   if($product){
    $info.Name=$product;$info.State='已识别'
    if($product -match 'Windows.*Operating System|Windows.*操作系统'){$info.Name='Windows 系统组件'}
    $info.Evidence="目标文件：$Path；产品：$product；描述：$description；公司字段：$company（文件内自报，非签名验证）。"
   }else{
    $info.Name=if($description){$description}else{[IO.Path]::GetFileName($Path)}
    $info.State='部分识别';$info.Evidence="已定位文件：$Path；产品字段为空。"
   }
   # Metadata is sometimes blank (shell extensions) or left over from Electron.
   if(-not $product -or $company -eq 'GitHub, Inc.' -or $company -eq 'GitHub Inc.'){
    $signature=Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction SilentlyContinue
    if($signature -and $signature.Status -eq 'Valid' -and $signature.SignerCertificate){
     $subject=$signature.SignerCertificate.Subject
     $info.Evidence+=" 有效数字签名：$subject。"
     if($Path -match '\\Quark\\quarkshellext_' -and $subject -match 'ALIBABA'){$info.Name='夸克扩展';$info.State='已识别'}
     elseif($Path -match '\\doubao_ext\\' -and $subject -match '春田知韵'){$info.Name='豆包扩展';$info.State='已识别'}
     elseif([IO.Path]::GetFileName($Path) -eq 'Docker Desktop.exe' -and $subject -match 'CN=Docker Inc'){$info.Name='Docker Desktop';$info.State='已识别'}
     elseif([IO.Path]::GetFileName($Path) -eq 'MuMuNxMain.exe' -and $subject -match 'NetEase'){$info.Name='MuMu 模拟器';$info.State='已识别'}
     elseif([IO.Path]::GetFileName($Path) -eq 'PixPin.exe' -and $subject -match 'Shenzhen Shendu Tujing'){$info.Name='PixPin';$info.State='已识别'}
    }elseif(-not $product){$info.Evidence+=' 未取得有效签名归属，保留待核对。'}
   }
  }catch{$info.Name=[IO.Path]::GetFileName($Path);$info.State='部分识别';$info.Evidence="文件存在，但产品信息读取失败：$($_.Exception.Message)"}
 }
 $script:AttributionFileCache[$Path]=$info
 $info
}
function Get-ComCandidates($Root,[string]$Clsid) {
 if($Clsid -notmatch '^\{[0-9A-Fa-f-]{36}\}$'){return}
 foreach($sub in @('InprocServer32','LocalServer32')){
  $value=Get-AttributionValue $Root "CLSID\$Clsid\$sub"
  if($value){[pscustomobject]@{Raw=$value;Via="COM $Clsid\$sub"}}
 }
}
function Get-RegistrationCandidates($Root,[string]$Registration) {
 $dropClsid=Get-AttributionValue $Root ($Registration+'\DropTarget') 'CLSID'
 if($dropClsid){Get-ComCandidates $Root $dropClsid}
 foreach($where in @($Registration,($Registration+'\command'))){
  foreach($name in @('DelegateExecute','ExplorerCommandHandler')){
   $clsid=Get-AttributionValue $Root $where $name
   if($clsid){Get-ComCandidates $Root $clsid}
  }
 }
 $scope=$Registration -replace '\\shell\\[^\\]+$',''
 $resourcePairs=@([pscustomobject]@{Path=$Registration;Name='MUIVerb'},[pscustomobject]@{Path=$Registration;Name=''},[pscustomobject]@{Path=$Registration;Name='Icon'},[pscustomobject]@{Path=($scope+'\DefaultIcon');Name=''})
 foreach($pair in $resourcePairs){
  $value=Get-AttributionValue $Root $pair.Path $pair.Name
  if($value -and ($value.StartsWith('@') -or $pair.Name -eq 'Icon' -or $pair.Path.EndsWith('\DefaultIcon'))){[pscustomobject]@{Raw=$value;Via="资源引用 $($pair.Path)"}}
 }
 $submenus=$Root.OpenSubKey($Registration+'\shell')
 if($submenus){
  try{foreach($child in $submenus.GetSubKeyNames()){
   $value=Get-AttributionValue $Root ($Registration+'\shell\'+$child+'\command')
   if($value){[pscustomobject]@{Raw=$value;Via='子菜单命令'}}
  }}finally{$submenus.Dispose()}
 }
}
function Get-MenuPackageIdentity($Root,[string]$Registration) {
 $scope=$Registration -replace '\\shell\\[^\\]+$',''
 $package=Get-AttributionValue $Root $Registration 'PackageId'
 $model=Get-AttributionValue $Root ($scope+'\Application') 'AppUserModelID'
 if(-not $model){$model=Get-AttributionValue $Root $Registration 'AppUserModelID'}
 if(-not $package -and -not $model){return}
 $id=if($package){($package -split '_')[0]}else{($model -split '_|!')[0]}
 $names=@{'Microsoft.ZuneMusic'='Windows 媒体播放器';'Microsoft.ZuneVideo'='电影和电视';'Microsoft.Windows.Photos'='微软照片';'Microsoft.ScreenSketch'='Windows 截图工具';'Microsoft.WindowsNotepad'='Windows 记事本';'Microsoft.DesktopAppInstaller'='Windows 应用安装程序';'Microsoft.WindowsTerminal'='Windows 终端'}
 $label=if($names.ContainsKey($id)){$names[$id]}else{$id+'（应用包）'}
 [pscustomobject]@{Name=$label;Evidence="应用注册 PackageId=$package；AppUserModelID=$model。"}
}
function Update-MenuAttribution($Rows) {
 $script:AttributionFileCache=@{}
 $cr=Open-Base 'ClassesRoot'
 try {
  foreach($row in $Rows){
   try {
   $known=$row.Software -ne '系统 / 未确认'
   $row | Add-Member -NotePropertyName Attribution -NotePropertyValue '仍需确认' -Force
   $row | Add-Member -NotePropertyName Evidence -NotePropertyValue '' -Force
   $row | Add-Member -NotePropertyName TargetState -NotePropertyValue '' -Force
   if($known){
    $row.Attribution='已识别';$row.Evidence='已登记的软件入口标识。'
    if($row.Source){$file=Resolve-MenuFile $row.Source $cr;if($file){$meta=Get-MenuFileInfo $file;$row.TargetState=$meta.Target;if($meta.State -eq '目标未找到'){$row.Attribution='目标未找到'};$row.Evidence+=' '+$meta.Evidence}}
    continue
   }
   $registration=[string]$row.Registrations[0]
   $package=if($row.Type -eq 'verb'){Get-MenuPackageIdentity $cr $registration}else{$null}
   if($package){
    $row.Software=$package.Name;$row.Attribution='已识别';$row.Evidence=$package.Evidence;$row.TargetState='应用包注册';$row.Reason='已找到应用归属；文件关联入口，只读保护。'
    continue
   }
   if($row.Type -eq 'verb' -and $row.Source -match '^\s*"?%[1lL]"?(?:\s|$)' -and $registration -match '^(batfile|cmdfile|comfile|exefile|piffile|scrfile)\\shell\\'){
    $row.Software='Windows 文件执行关联';$row.Attribution='已识别';$row.TargetState='按所选文件执行';$row.Evidence='该文件类型的命令运行所选文件（%1），不指向固定安装程序。';$row.Reason='系统文件关联，只读保护。';continue
   }
   $candidates=New-Object 'System.Collections.Generic.List[object]'
   if($row.Source){$candidates.Add([pscustomobject]@{Raw=$row.Source;Via='命令 / 扩展文件'})}
   if($row.Type -eq 'com' -and $row.Id.StartsWith('com|{')){
    foreach($c in @(Get-ComCandidates $cr $row.Id.Substring(4))){$candidates.Add($c)}
   }
   foreach($c in @(Get-RegistrationCandidates $cr $registration)){$candidates.Add($c)}
   $chosen=$null;$chosenVia=''
   foreach($candidate in @($candidates | Sort-Object @{Expression={if($_.Via -eq '命令 / 扩展文件'){0}elseif($_.Via.StartsWith('COM ')){1}elseif($_.Via -eq '子菜单命令'){2}else{3}}})){
    $file=Resolve-MenuFile $candidate.Raw $cr
    if(-not $file){continue}
    $meta=Get-MenuFileInfo $file
    if(-not $chosen){$chosen=$meta;$chosenVia=$candidate.Via}
    # The primary executable/DLL is authoritative, even when missing.
    # An unrelated icon must not mask a missing actual target.
    if($candidate.Via -eq '命令 / 扩展文件' -or $candidate.Via.StartsWith('COM ') -or $meta.State -eq '已识别'){$chosen=$meta;$chosenVia=$candidate.Via;break}
   }
   if($chosen){
    $row.Software=$chosen.Name;$row.Attribution=$chosen.State;$row.TargetState=$chosen.Target
    $row.Evidence="$chosenVia；$($chosen.Evidence)"
    if($chosenVia.StartsWith('资源引用') -and $row.Attribution -eq '已识别'){$row.Attribution='部分识别';$row.TargetState='仅资源文件存在；执行入口待确认';$row.Evidence+=' 目前只确认资源文件归属，具体执行入口仍需核对。'}
    $row.Reason=if($row.Attribution -eq '已识别'){'已找到来源；文件关联、系统功能或未开放管理的扩展，只读保护。'}else{'来源仍待核对；保持只读。'}
   }elseif($row.Type -eq 'verb' -and $row.Source -match '^\s*"?%[1lL]"?\s*(%\*)?\s*$' -and $registration -match '^(batfile|cmdfile|comfile|exefile|piffile)\\shell\\'){
    $row.Software='Windows 文件执行关联';$row.Attribution='已识别';$row.TargetState='按所选文件执行';$row.Evidence='该文件类型的执行命令使用所选文件占位符，不对应固定安装程序。';$row.Reason='系统文件关联，只读保护。'
   }else{
    $row.Software='来源仍待确认';$row.Reason='现有注册信息不足，只读保护。'
    if($row.Type -eq 'com' -and $row.Id.StartsWith('com|{')){
     $row.Evidence="扩展引用 $($row.Id.Substring(4))；未找到可解析的 64 位 COM 服务文件，不能仅按登记名称认定归属。"
     $row.TargetState='COM 实现未定位'
     continue
    }
    $key=$cr.OpenSubKey($registration)
    if($key){try{
     if($key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0){$row.Evidence='注册项为空：没有值或子项；不能据此确定原软件或认定应删除。';$row.TargetState='空注册项'}
     else{$row.Evidence='未找到可验证的固定程序路径、应用包或资源引用；也可能由系统动态处理。';$row.TargetState='调用方式待确认'}
    }finally{$key.Dispose()}}
   }
   }catch{
    $row.CanEdit=$false;$row.Reason='来源读取失败，只读保护。'
    $row | Add-Member -NotePropertyName Attribution -NotePropertyValue '仍需确认' -Force
    $row | Add-Member -NotePropertyName Evidence -NotePropertyValue $_.Exception.Message -Force
    $row | Add-Member -NotePropertyName TargetState -NotePropertyValue '读取失败' -Force
    Add-MenuScanWarning '识别来源' $row.Id $_.Exception.Message
   }
  }
 }finally{$cr.Dispose()}
}
