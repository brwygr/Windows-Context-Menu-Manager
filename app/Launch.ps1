#requires -version 5.1
$ErrorActionPreference='Stop'
try {
 if($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess){
  throw '请使用 64 位 Windows PowerShell 5.1 或便携包内的 MenuManager.exe。'
 }
 & (Join-Path $PSScriptRoot 'Manager.ps1')
}catch{
 $message=$_.Exception.Message
 try{
  $logDir=Join-Path $PSScriptRoot 'data\logs'
  [void][IO.Directory]::CreateDirectory($logDir)
  [IO.File]::WriteAllText((Join-Path $logDir 'startup-error.log'),($_ | Out-String),(New-Object Text.UTF8Encoding($true)))
 }catch{}
 Add-Type -AssemblyName PresentationFramework
 [void][Windows.MessageBox]::Show("启动失败：$message"+[Environment]::NewLine+'请先完整解压文件，并确认 Windows PowerShell 5.1 与 .NET Framework 4.8 可用。','右键菜单管理','OK','Error')
}
