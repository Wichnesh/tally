; Windows installer for Tally (Inno Setup 6).
; Built by .github/workflows/windows.yml after "flutter build windows".
; Installs for the current user (no administrator needed) into
; %LOCALAPPDATA%\Programs\Tally, with a Start menu entry and a desktop icon.
; The app's data (%APPDATA%\com.gheetally\Tally) and backups
; (Documents\Tally Backups) are never touched by installing, updating or
; uninstalling.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
; Never change AppId: Windows uses it to recognise updates of the same app
AppId={{4429FA4B-26A3-4061-97B4-5811A43AA603}
AppName=Tally
AppVersion={#AppVersion}
AppVerName=Tally {#AppVersion}
AppPublisher=Amutham
DefaultDirName={autopf}\Tally
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
OutputDir=..\dist
OutputBaseFilename=Tally-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Tally.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Tally"; Filename: "{app}\Tally.exe"
Name: "{autodesktop}\Tally"; Filename: "{app}\Tally.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Tally.exe"; Description: "{cm:LaunchProgram,Tally}"; Flags: nowait postinstall skipifsilent
