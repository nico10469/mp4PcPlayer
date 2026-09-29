; Installer Windows di mp4Player (Inno Setup 6).
; Lo compila la GitHub Action "Installer"; a mano:  iscc /DAppVersion=1.0.0 installer\windows\mp4player.iss
; Si aspetta l'app in app\build\windows\x64\runner\Release e il server in dist\mp4player-server.exe.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#define AppName "mp4Player"
#define ServerPort "8000"
#define Root "..\.."

[Setup]
AppId={{7C4E2A51-3B8D-4F0E-9A61-2D5C8B7E4F10}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=nico10469
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir={#Root}\dist
OutputBaseFilename=mp4Player-{#AppVersion}-windows-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Serve l'amministratore per installare in Programmi e aprire la porta del server nel firewall.
PrivilegesRequired=admin
UninstallDisplayIcon={app}\mp4player.exe

[Languages]
Name: "italian"; MessagesFile: "compiler:Languages\Italian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Types]
Name: "full"; Description: "App e server di download (consigliato)"
Name: "app"; Description: "Solo l'app (uso un server su un altro computer)"

[Components]
Name: "app"; Description: "App mp4Player"; Types: full app; Flags: fixed
Name: "server"; Description: "Server di download (yt-dlp): serve per scaricare i brani anche dal telefono"; Types: full

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "serverautostart"; Description: "Avvia il server di download all'accensione del PC"; Components: server; Flags: unchecked

[Files]
Source: "{#Root}\app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Components: app; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#Root}\dist\mp4player-server.exe"; DestDir: "{app}\server"; Components: server; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\mp4player.exe"
Name: "{group}\{#AppName} Server"; Filename: "{app}\server\mp4player-server.exe"; Components: server
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\mp4player.exe"; Tasks: desktopicon
Name: "{commonstartup}\{#AppName} Server"; Filename: "{app}\server\mp4player-server.exe"; Parameters: ""; Flags: runminimized; Tasks: serverautostart

[Run]
; Apre la porta del server solo sulle reti private (casa), così il telefono lo raggiunge.
; Prima cancella la regola, così reinstallando non si duplica.
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""{#AppName} Server"""; Flags: runhidden; Components: server
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""{#AppName} Server"" dir=in action=allow protocol=TCP localport={#ServerPort} profile=private"; Flags: runhidden; Components: server
Filename: "{app}\server\mp4player-server.exe"; Description: "Avvia il server di download"; Flags: nowait postinstall skipifsilent runasoriginaluser; Components: server
Filename: "{app}\mp4player.exe"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent runasoriginaluser

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM mp4player-server.exe"; Flags: runhidden; RunOnceId: "StopServer"
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""{#AppName} Server"""; Flags: runhidden; RunOnceId: "FirewallRule"
