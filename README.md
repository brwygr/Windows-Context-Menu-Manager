# Windows Context Menu Manager · 右键菜单管理

一个中文界面的 Windows 右键菜单扫描与管理工具。下载便携包、解压、双击后，自动读取**当前电脑、当前用户**的菜单注册信息。

[下载最新便携版](https://github.com/brwygr/Windows-Context-Menu-Manager/releases/latest) · [反馈问题](https://github.com/brwygr/Windows-Context-Menu-Manager/issues)

## 开始使用

1. 在 Releases 下载名称包含 **win-x64.zip** 的便携包，不要把 GitHub 自动生成的 Source code ZIP 当成编译版。
2. 完整解压到你有写入权限的文件夹，保留包内所有文件。
3. 双击 **MenuManager.exe**。启动后自动扫描，无需手工指定注册表路径或预先生成菜单清单。
4. 在“可管理的第三方入口”里勾选想隐藏的项目，再点击“预览并应用”，核对后确认。
5. 恢复时取消勾选并应用，或使用“从备份还原”。

首次扫描不会自动清理菜单。列表数量取决于电脑上实际安装的软件；数千条文件关联不意味着右键菜单会同时显示数千项。

## 系统与支持范围

- 面向 **Windows 10 / Windows 11，x64** 桌面系统。
- 需要 **Windows PowerShell 5.1、.NET Framework 4.8 和 WPF**。常见的 Windows 10/11 安装通常已具备；精简系统或企业策略可能移除/禁用相关组件。
- 不支持 macOS、Linux、32 位 Windows；Windows ARM64 尚未验证。
- 不要求安装 Python、Node.js 或 Docker。
- 使用当前用户权限；不用以管理员身份运行。仅修改当前用户的已知菜单隐藏标记。
- 初版面向早期使用者。CI 构建和扫描检查不等于已覆盖所有 Windows 桌面版本及第三方软件组合。

## 可以做什么

- 自动扫描 64 位资源管理器的传统菜单注册项，涵盖文件、文件夹、空白处、磁盘、快捷方式及文件类型关联。
- 根据程序文件、COM 注册、应用包、产品信息和部分签名证据显示来源。
- 搜索菜单名称、软件、出现位置；区分已识别、部分识别、目标未找到和仍需确认。
- 对已收录的附加菜单逐项隐藏/恢复，例如百度网盘、WPS、夸克 AI、豆包、搜狗、7-Zip、Git 和常见编辑器入口。只显示本机实际存在的注册项，数量不是固定的。
- 确认后先备份原值，再应用修改；遇到写入失败尝试回滚。还原时会检测设置是否又被其他程序更改。
- 导出本机菜单清单用于自己查看。

## 哪些项目保持只读

系统基础功能、来源不明的项目、Fences 桌面整理相关项，以及多数 open/edit/print/new 等文件关联保持只读。“已识别软件”不等于“适合隐藏”。

传统 COM 扩展通常是一组菜单入口；关闭一个扩展可能影响其多个位置或子菜单，不能保证只隐藏其中某个按钮。Windows 11 的现代菜单、UWP 打包扩展、软件临时生成的菜单及 32 位程序内菜单不在完整管理范围内。

没有定位到程序文件可能意味着软件升级、路径变化、访问受限或残留注册，工具不会据此自动删除项目。

## 数据、备份与隐私

运行数据保存在便携程序旁的 **data** 文件夹：

- data/Backups：每次确认修改前的逐项备份；
- data/exports：主动导出的清单；
- data/logs：启动或运行错误日志。

数据可能包含本机安装路径、Windows 用户名和账户标识。不要把整份清单、日志或备份直接发到公开 Issue。分享问题前请先遮盖私人内容。

程序没有菜单清单上传、遥测或自动更新功能。数字签名验证由 Windows 提供，系统可能依据自己的证书策略进行证书相关联网检查。公开仓库和发行包不包含作者电脑的清单、备份或日志。

工具不会卸载软件、强制结束资源管理器、注销或重启电脑。部分扩展有缓存，关闭菜单后重开仍未变化时，可在自己方便时手动注销并登录。

## 常见问题

**下载后打不开？**

确认已解压全部文件，使用 x64 Windows，并且 PowerShell 5.1 / .NET Framework 4.8 可用。企业策略可能禁止本地脚本或相关组件。当前发行版没有购买代码签名证书，Windows 可能显示发布者未验证提示；也可审查源码后自行构建。

**软件在电脑上装了，为什么还没有可管理入口？**

只有收录并核对过的菜单标识才开放管理，其他项目会显示为只读。可以在 Issue 中提供软件名称、版本和去除私人路径后的注册项名称。

**其他清理工具停用了菜单，能直接恢复吗？**

不保证。当前工具主要还原自己记录的隐藏标记，不会自动恢复其他工具移动、重命名或删除的注册项。

**能保证不会有问题吗？**

任何修改注册表的工具都不能保证覆盖所有系统状态。请核对预览并保留备份；本项目按 MIT 许可证提供，不附带担保。

## 从源码构建

在 Windows 上使用 **64 位 Windows PowerShell 5.1**：

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Core.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\app\Manager.ps1 -SmokeTest
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build.ps1
~~~

构建使用 Windows 自带 .NET Framework C# 编译器，不下载 NuGet 包。输出位于 dist，包含便携 ZIP 和 SHA-256 校验文件。执行策略参数仅作用于本次进程，不修改系统的持久执行策略。

测试中的注册表写入使用内存模拟；SmokeTest 在本机执行只读扫描和 WPF 加载，不应用菜单修改。GitHub Actions 在干净 Windows runner 上运行相同检查。

## 项目结构

- app/：界面、扫描与备份还原逻辑、轻量 .NET 启动器。
- tests/：模拟事务及兼容性检查。
- scripts/Build.ps1：便携包构建。
- .github/workflows/：自动测试与构建。

## 许可证

[MIT](LICENSE)。第三方软件名称仅用于识别对应菜单，本项目与这些厂商无关联。
