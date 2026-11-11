#requires -version 5.1
param([switch]$InventoryOnly,[switch]$SmokeTest)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'MenuCore.ps1')
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
if(-not [Environment]::Is64BitProcess){throw '请使用 64 位 Windows PowerShell 启动。'}
$script:DataDir=Join-Path $PSScriptRoot 'data'
$script:BackupDir=Join-Path $script:DataDir 'Backups'
$script:Rows=@()
function Export-Inventory {
 $folder=Join-Path $script:DataDir 'exports'
 [void][IO.Directory]::CreateDirectory($folder)
 $path=Join-Path $folder '菜单清单.csv'
 @($script:Rows | Select-Object @{n='菜单名称';e={$_.Label}},@{n='所属软件';e={$_.Software}},@{n='出现位置';e={$_.Locations}},@{n='当前设置';e={$_.Current}},@{n='可修改';e={$_.CanEdit}},@{n='说明';e={($_.Note+' '+$_.Reason).Trim()}},@{n='注册位置';e={$_.Registrations -join ' | '}},@{n='程序路径';e={$_.Source}},@{n='来源识别';e={$_.Attribution}},@{n='来源依据';e={$_.Evidence}},@{n='目标状态';e={$_.TargetState}}) | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8
 $path
}
if($InventoryOnly){
 $script:Rows=@(Get-MenuInventory)
 $file=Export-Inventory
 [pscustomobject]@{Total=$script:Rows.Count;Editable=@($script:Rows|Where-Object CanEdit).Count;File=$file;Items=@($script:Rows|Where-Object {$_.Software -ne '系统 / 未确认'}|Select-Object Label,Software,Locations,CanEdit,Current)} | ConvertTo-Json -Depth 5
 exit 0
}
[xml]$xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="右键菜单管理 · 通用便携版" Width="1240" Height="790" MinWidth="1060" MinHeight="650" WindowStartupLocation="CenterScreen"
 Background="#F3F5F9" FontFamily="Microsoft YaHei UI" FontSize="14">
 <Window.Resources>
  <Style TargetType="Button"><Setter Property="Padding" Value="16,9"/><Setter Property="Margin" Value="0,0,10,0"/><Setter Property="Background" Value="White"/><Setter Property="BorderBrush" Value="#D2D9E3"/><Setter Property="Cursor" Value="Hand"/></Style>
  <Style TargetType="DataGridCell"><Setter Property="Padding" Value="8,9"/><Setter Property="BorderThickness" Value="0"/><Setter Property="VerticalContentAlignment" Value="Center"/></Style>
  <Style TargetType="DataGridColumnHeader"><Setter Property="Padding" Value="8,10"/><Setter Property="Background" Value="#EAF0F7"/><Setter Property="FontWeight" Value="SemiBold"/></Style>
 </Window.Resources>
 <Grid Margin="26,22">
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="125"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <StackPanel Grid.Row="0">
   <TextBlock Text="把右键菜单，留给常用功能" FontSize="26" FontWeight="SemiBold" Foreground="#16263C"/>
   <TextBlock Text="先看清单，再决定隐藏什么。所有选择都要点击“预览并应用”才会生效。" Margin="0,8,0,0" Foreground="#526279"/>
  </StackPanel>
  <Border Grid.Row="1" Background="#E5EEFC" CornerRadius="8" Padding="14,10" Margin="0,16,0,14">
   <TextBlock TextWrapping="Wrap" Foreground="#254D82" Text="勾选「隐藏」＝隐藏该入口；取消勾选＝恢复显示。软件本身不会卸载。同一扩展可能影响多个位置；系统和来源未确认的项目为只读。"/>
  </Border>
  <Grid Grid.Row="2" Margin="0,0,0,12">
   <Grid.ColumnDefinitions><ColumnDefinition Width="230"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
   <ComboBox Name="Filter" SelectedIndex="0" Padding="8,6" Margin="0,0,12,0">
    <ComboBoxItem Content="可管理的第三方入口"/><ComboBoxItem Content="全部注册项（含只读）"/><ComboBoxItem Content="当前已设为隐藏"/><ComboBoxItem Content="已识别的其他入口（只读）"/><ComboBoxItem Content="来源仍需核对"/><ComboBoxItem Content="登记目标未找到"/>
   </ComboBox>
   <TextBox Grid.Column="1" Name="Search" Padding="9,6" ToolTip="搜索菜单名称、软件或出现位置" VerticalContentAlignment="Center"/>
   <Button Grid.Column="2" Name="Refresh" Content="重新扫描" Margin="12,0,0,0"/>
   <TextBlock Grid.Column="1" Name="SearchHint" Text="搜索名称、软件或位置…" Foreground="#8290A0" Margin="11,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
  </Grid>
  <DataGrid Grid.Row="3" Name="MenuGrid" AutoGenerateColumns="False" CanUserAddRows="False" CanUserDeleteRows="False" CanUserResizeRows="False" HeadersVisibility="Column" GridLinesVisibility="Horizontal"
   HorizontalGridLinesBrush="#EBEFF4" Background="White" BorderBrush="#DAE1EB" RowHeaderWidth="0" AlternatingRowBackground="#F8FAFD" SelectionMode="Single" SelectionUnit="FullRow" EnableRowVirtualization="True">
   <DataGrid.Columns>
    <DataGridTemplateColumn Header="隐藏" Width="58" CanUserSort="False">
     <DataGridTemplateColumn.CellTemplate><DataTemplate><CheckBox IsChecked="{Binding Hide, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}" IsEnabled="{Binding CanEdit}" HorizontalAlignment="Center" VerticalAlignment="Center" ToolTip="勾选隐藏，取消恢复；应用前不修改系统"/></DataTemplate></DataGridTemplateColumn.CellTemplate>
    </DataGridTemplateColumn>
    <DataGridTextColumn Header="菜单名称" Binding="{Binding Label}" Width="195" IsReadOnly="True"/>
    <DataGridTextColumn Header="所属软件" Binding="{Binding Software}" Width="170" IsReadOnly="True"/><DataGridTextColumn Header="来源识别" Binding="{Binding Attribution}" Width="100" IsReadOnly="True"/>
    <DataGridTextColumn Header="出现位置" Binding="{Binding Locations}" Width="*" MinWidth="220" IsReadOnly="True"/>
    <DataGridTextColumn Header="当前设置" Binding="{Binding Current}" Width="165" IsReadOnly="True"/>
   </DataGrid.Columns>
  </DataGrid>
  <Border Grid.Row="4" Background="White" BorderBrush="#DAE1EB" BorderThickness="1" CornerRadius="6" Padding="12,8" Margin="0,12,0,12">
   <TextBox Name="Details" IsReadOnly="True" BorderThickness="0" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Background="Transparent" Foreground="#526279" FontSize="12"
    Text="点选一行，查看它出现在哪里。&#10;这里列出注册表中可发现的传统菜单入口；部分软件会按文件类型、选中数量等条件临时生成菜单。&#10;基本的复制、删除、属性等功能由 Windows 提供，不会被此工具更改。"/>
  </Border>
  <StackPanel Grid.Row="5" Orientation="Horizontal">
   <Button Name="Apply" Content="预览并应用" Background="#265EAF" Foreground="White" BorderBrush="#265EAF"/>
   <Button Name="Reset" Content="撤销未应用的选择"/>
   <Button Name="Restore" Content="从备份还原"/>
   <Button Name="Export" Content="导出完整清单"/>
  </StackPanel>
  <TextBlock Grid.Row="6" Name="Status" Foreground="#526279" Margin="0,12,0,0" TextWrapping="Wrap"/>
 </Grid>
</Window>
'@
$reader=New-Object Xml.XmlNodeReader $xaml
$script:Window=[Windows.Markup.XamlReader]::Load($reader)
foreach($name in @('Filter','Search','SearchHint','Refresh','MenuGrid','Details','Apply','Reset','Restore','Export','Status')){Set-Variable -Name $name -Value $script:Window.FindName($name) -Scope Script}
function Show-Notice([string]$Text,[string]$Title='右键菜单管理') {
 [void][Windows.MessageBox]::Show($script:Window,$Text,$Title,'OK','Information')
}
$script:ScanJob=$null
$script:SmokeFailure=''
$script:ScanWarnings=@()
$script:ScanTimer=New-Object Windows.Threading.DispatcherTimer -ArgumentList ([Windows.Threading.DispatcherPriority]::Background),$script:Window.Dispatcher
$script:ScanTimer.Interval=[TimeSpan]::FromMilliseconds(200)
function Start-MenuScan {
 if($script:ScanJob){return}
 $script:Status.Text='正在扫描本机右键菜单，请稍候…'
 foreach($control in @($script:Refresh,$script:Apply,$script:Restore,$script:Export,$script:MenuGrid)){$control.IsEnabled=$false}
 $worker=[PowerShell]::Create()
 [void]$worker.AddScript({
  param($corePath)
  $ErrorActionPreference='Stop'
  . $corePath
  $inventory=@(Get-MenuInventory)
  [pscustomobject]@{Rows=$inventory;Warnings=@(Get-MenuScanWarnings)}
 }).AddArgument((Join-Path $PSScriptRoot 'MenuCore.ps1'))
 try {
  $handle=$worker.BeginInvoke()
  $script:ScanJob=[pscustomobject]@{Worker=$worker;Handle=$handle}
  $script:ScanTimer.Start()
 }catch{
  $worker.Dispose()
  foreach($control in @($script:Refresh,$script:Apply,$script:Restore,$script:Export,$script:MenuGrid)){$control.IsEnabled=$true}
  throw
 }
}
function Complete-MenuScan {
 if(-not $script:ScanJob -or -not $script:ScanJob.Handle.IsCompleted){return}
 $script:ScanTimer.Stop()
 $job=$script:ScanJob
 try{
  $output=@($job.Worker.EndInvoke($job.Handle))
  if($job.Worker.HadErrors){throw (($job.Worker.Streams.Error | ForEach-Object {$_.ToString()}) -join [Environment]::NewLine)}
  if($output.Count -ne 1){throw '扫描没有返回预期的结果。'}
  $script:Rows=@($output[0].Rows)
  $script:ScanWarnings=@($output[0].Warnings)
  $script:ScanJob=$null
  Update-View
  if($script:ScanWarnings.Count){
   $script:Details.Text="有 $($script:ScanWarnings.Count) 项未完整读取，其余结果仍可查看。"+[Environment]::NewLine+(($script:ScanWarnings|Select-Object -First 15|ForEach-Object {"$($_.Stage)：$($_.Path) — $($_.Message)"})-join [Environment]::NewLine)
  }
 }catch{
  $script:Status.Text='扫描未完成，可点击“重新扫描”重试。'
  if($SmokeTest){$script:SmokeFailure=$_.Exception.Message}else{Show-Notice $_.Exception.Message '扫描未完成'}
 }finally{
  $script:ScanJob=$null
  $job.Worker.Dispose()
  foreach($control in @($script:Refresh,$script:Apply,$script:Restore,$script:Export,$script:MenuGrid)){$control.IsEnabled=$true}
 }
}
$script:ScanTimer.Add_Tick({Complete-MenuScan})
function Update-Status {
 if($script:ScanJob){$script:Status.Text='正在扫描本机右键菜单，请稍候…';return}
 $changes=@(Get-ChangePlan $script:Rows)
 $count=@($changes | Select-Object -ExpandProperty Label -Unique).Count
 $script:Status.Text="已扫描 $($script:Rows.Count) 组注册项，其中 $(@($script:Rows | Where-Object CanEdit).Count) 组可管理。待应用：$count 项。读取提醒：$($script:ScanWarnings.Count) 项。备份保存在 data\Backups 文件夹。"
}
function Update-View {
 $q=$script:Search.Text.Trim()
 $script:SearchHint.Visibility=if($q){'Collapsed'}else{'Visible'}
 $items=@($script:Rows | Where-Object {
  ($script:Filter.SelectedIndex -ne 0 -or $_.CanEdit) -and
  ($script:Filter.SelectedIndex -ne 2 -or $_.Current.StartsWith('已设为隐藏') -or $_.Current.StartsWith('部分位置隐藏')) -and
  ($script:Filter.SelectedIndex -ne 3 -or ($_.Attribution -eq '已识别' -and -not $_.CanEdit)) -and
  ($script:Filter.SelectedIndex -ne 4 -or $_.Attribution -in @('仍需确认','部分识别')) -and
  ($script:Filter.SelectedIndex -ne 5 -or $_.Attribution -eq '目标未找到') -and
  (-not $q -or ($_.Label+' '+$_.Software+' '+$_.Locations).IndexOf($q,[StringComparison]::OrdinalIgnoreCase) -ge 0)
 })
 $script:MenuGrid.ItemsSource=$items
 Update-Status
}
function Reload-Rows {
 Start-MenuScan
}
function Confirm-Plan($Operations,[string]$Title) {
 [xml]$px=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Width="760" Height="510" MinWidth="650" MinHeight="400" WindowStartupLocation="CenterOwner" FontFamily="Microsoft YaHei UI" FontSize="14" Background="#F3F5F9">
 <Grid Margin="22"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
 <TextBlock Name="Heading" FontSize="21" FontWeight="SemiBold" Margin="0,0,0,14"/>
 <TextBox Name="Plan" Grid.Row="1" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Padding="12" Background="White"/>
 <TextBlock Grid.Row="2" Margin="0,14" TextWrapping="Wrap" Text="确认后才会修改当前用户的菜单设置，并自动保存逐项备份。不会卸载软件、重启电脑或关闭资源管理器。"/>
 <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right"><Button Name="Cancel" Content="返回，不修改" Padding="18,9" Margin="0,0,12,0" IsCancel="True"/><Button Name="Confirm" Content="确认应用" Padding="18,9" Background="#265EAF" Foreground="White" IsDefault="False"/></StackPanel>
 </Grid>
</Window>
'@
 $r=New-Object Xml.XmlNodeReader $px;$dialog=[Windows.Markup.XamlReader]::Load($r)
 $dialog.Owner=$script:Window;$dialog.Title=$Title
 $dialog.FindName('Heading').Text=$Title
 $lines=@($Operations | Group-Object Label,Action | ForEach-Object {
  $op=$_.Group[0]
  "$($op.Action)：$($op.Label)`r`n涉及 $($_.Count) 项设置"
 })
 $dialog.FindName('Plan').Text=$lines -join "`r`n`r`n"
 $dialog.FindName('Confirm').Add_Click({[Windows.Window]::GetWindow($this).DialogResult=$true})
 return $dialog.ShowDialog() -eq $true
}
$script:Filter.Add_SelectionChanged({Update-View})
$script:Search.Add_TextChanged({Update-View})
$script:MenuGrid.Add_SelectionChanged({
 $r=$script:MenuGrid.SelectedItem
 if($r){
  $script:Details.Text="菜单：$($r.Label)    软件：$($r.Software)`r`n出现位置：$($r.Locations)`r`n$($r.Note) $($r.Reason)`r`n来源识别：$($r.Attribution)；$($r.Evidence)`r`n程序：$($r.Source)`r`n注册位置：$($r.Registrations -join ' | ')"
 }
})
$script:MenuGrid.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent,[Windows.RoutedEventHandler]{param($sender,$e) if($e.OriginalSource -is [Windows.Controls.CheckBox]){Update-Status}})
$script:Refresh.Add_Click({
 try{
  if(@(Get-ChangePlan $script:Rows).Count -and [Windows.MessageBox]::Show($script:Window,'重新扫描会放弃未应用的选择，继续吗？','重新扫描','YesNo','Question','No') -ne 'Yes'){return}
  Reload-Rows
 }catch{Show-Notice $_.Exception.Message '扫描失败'}
})
$script:Reset.Add_Click({foreach($r in $script:Rows){$r.Hide=$r.Targets.Count -gt 0 -and @($r.Targets|Where-Object {$_.State.Exists -or $_.External}).Count -eq $r.Targets.Count};Update-View})
$script:Export.Add_Click({try{$p=Export-Inventory;Show-Notice "完整清单已保存：`r`n$p"}catch{Show-Notice $_.Exception.Message '导出失败'}})
$script:Apply.Add_Click({
 try{
  [void]$script:MenuGrid.CommitEdit()
  $ops=@(Get-ChangePlan $script:Rows)
  if(-not $ops.Count){Show-Notice '还没有选择需要修改的项目。请勾选要隐藏的入口，再预览。';return}
  if(-not (Confirm-Plan $ops '请核对本次修改')){return}
  $backup=Invoke-ChangeTransaction $ops $script:BackupDir
  Reload-Rows
  Show-Notice "设置已保存。关闭右键菜单后重新打开查看。`r`n`r`n部分扩展会缓存状态，需要你方便时手动注销并重新登录 Windows 才能完整生效。工具不会自动注销或重启。`r`n`r`n备份：$backup"
 }catch{Show-Notice $_.Exception.Message '未完成修改'}
})
$script:Restore.Add_Click({
 try{
  if(@(Get-ChangePlan $script:Rows).Count){Show-Notice '请先应用或撤销当前未应用的选择，再还原备份。';return}
  if(-not [IO.Directory]::Exists($script:BackupDir)){Show-Notice '尚未创建备份。第一次应用修改时会自动备份。';return}
  $pick=New-Object Microsoft.Win32.OpenFileDialog
  $pick.Title='选择本工具创建的备份';$pick.Filter='菜单备份 (*.json)|*.json';$pick.InitialDirectory=$script:BackupDir
  if($pick.ShowDialog($script:Window) -ne $true){return}
  $ops=@(Get-RestorePlan $pick.FileName)
  if(-not $ops.Count){Show-Notice '设置已经与该备份中的原状态一致。';return}
  if(-not (Confirm-Plan $ops '请核对备份还原')){return}
  $backup=Invoke-ChangeTransaction $ops $script:BackupDir 'restore'
  Reload-Rows
  Show-Notice "还原完成，并保存了还原前的状态：`r`n$backup`r`n`r`n部分扩展需要手动注销再登录才会刷新。"
 }catch{Show-Notice $_.Exception.Message '未完成还原'}
})
$script:Window.Add_Closing({
 param($sender,$e)
 if(@(Get-ChangePlan $script:Rows).Count -and [Windows.MessageBox]::Show($script:Window,'还有未应用的选择。直接关闭并放弃这些选择吗？','关闭工具','YesNo','Question','No') -ne 'Yes'){$e.Cancel=$true}
})
Update-View
if($SmokeTest){
 try{
  Start-MenuScan
  $watch=[Diagnostics.Stopwatch]::StartNew()
  while($script:ScanJob){
   if($watch.Elapsed.TotalMinutes -gt 3){throw 'Background scan timeout.'}
   [void][Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background)
   Start-Sleep -Milliseconds 50
  }
  if($script:SmokeFailure){throw $script:SmokeFailure}
  [pscustomobject]@{WindowLoaded=$true;BackgroundScan=$true;Rows=$script:Rows.Count;Editable=@($script:Rows|Where-Object CanEdit).Count;Warnings=$script:ScanWarnings.Count}|ConvertTo-Json -Compress
 }finally{
  $script:ScanTimer.Stop()
  if($script:ScanJob){$script:ScanJob.Worker.Stop();$script:ScanJob.Worker.Dispose();$script:ScanJob=$null}
 }
 return
}
$script:Window.Add_ContentRendered({try{Start-MenuScan}catch{Show-Notice $_.Exception.Message '扫描失败'}})
try{[void]$script:Window.ShowDialog()}finally{
 $script:ScanTimer.Stop()
 if($script:ScanJob){$script:ScanJob.Worker.Stop();$script:ScanJob.Worker.Dispose();$script:ScanJob=$null}
}
