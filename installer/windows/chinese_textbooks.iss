; 无界课本 —— Windows 安装包（Inno Setup）
;
; 打包对象是 `flutter build windows --release` 的**整个产物目录**：
; exe 旁边还有 flutter_windows.dll、pdfium.dll、各插件 dll，以及装着 AOT 快照与
; 资源的 data\ 子目录。少任何一个文件应用都起不来，所以这里是整目录安装，
; 不做任何挑选。
;
; 编译：
;   本地   flutter build windows --release
;          iscc installer\windows\chinese_textbooks.iss
;   CI     由 .github/workflows/release.yml 调用，并用 /DAppVersion=x.y.z 传入版本号
;
; 需要**自带中文语言文件**的 Inno Setup（7.x 有，见下面的 [Languages]）。
; 语言文件取编译器自带的 `compiler:` 那一份，而不是往仓库里塞一份抄本：
; 抄本会跟着编译器版本漂移，编译器加了新消息就编译不过，而且报错很难懂。

#define AppName "无界课本"
#define AppExeName "chinese_textbooks.exe"

; 版本号，两个：
;   AppVersion     展示用，可以是 1.0.1-beta 这种带后缀的（CI 传 tag）
;   NumericVersion [Setup] 的 AppVersion 只吃纯数字，格式不对会**编译失败**，
;                  而这一步失败等于整个发布挂掉，所以单独留一个纯数字的。
; 本地直接编译时用兜底值，CI 会覆盖。
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef NumericVersion
  #define NumericVersion "0.0.0"
#endif

; 安装界面的语言文件。CI 会先看编译器带不带中文，不带就传英文那份进来。
#ifndef MessagesFile
  #define MessagesFile "compiler:Languages\ChineseSimplified.isl"
#endif

; Flutter 的 Windows 产物目录。相对本文件，可用 /DBuildDir=... 覆盖。
;
; 注意**不要**把它叫成 SourceDir：[Setup] 里有个同名指令会改变所有相对路径的
; 基准，连 OutputDir 都会被它带跑。这里只是个预处理变量。
#ifndef BuildDir
  #define BuildDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
; AppId 是这个应用在 Windows 上的**身份**，一旦发布就不能再改：
; 改了会被当成另一个软件，覆盖安装、升级、卸载都会各自为政。
; （这里是随机生成的，与别的应用撞车的概率可以忽略。）
AppId={{E5D3E484-7C6F-48B5-8372-8B6F78913879}
AppName={#AppName}
AppVersion={#NumericVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppName}

; {autopf} 在 64 位系统上解析为 Program Files。
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; 只出 64 位安装包；Flutter 的 Windows 桌面端本来也只有 x64 产物。
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Flutter 的 Windows 端要求 Windows 10 起（WebView2 也在 7/8 上装不了）。
; 不写这一条的话，安装程序会在 Win7 上照装不误，然后应用一启动就崩。
MinVersion=10.0

; 产物落在 build\ 下面，那里已经在 .gitignore 里，不会被误提交。
OutputDir=..\..\build\installer
; 文件名保持 ASCII，而且**不带版本号**：这样
;   /releases/latest/download/wujie-textbook-windows-x64-setup.exe
; 永远指向最新版，产品页与「去下载」都能写死这个链接。
; 版本号在 Release 标题和 exe 的属性里，不在文件名里。
; （中文名在 AppName 上；中文文件名进 URL 会被百分号编码成一长串。）
OutputBaseFilename=wujie-textbook-windows-x64-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}

Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

; 应用把教材、进度、登录态都放在 %APPDATA%，不在安装目录里，
; 因此卸载**不需要**额外删数据——用户重装后书架原样还在。

[Languages]
Name: "chinesesimplified"; MessagesFile: "{#MessagesFile}"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; 递归装整个产物目录。ignoreversion 是因为这里全是随之一起发布的文件，
; 版本号比较没有意义，只会拖慢安装。
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
