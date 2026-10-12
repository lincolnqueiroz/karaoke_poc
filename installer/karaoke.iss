#ifndef PackageRoot
  #error PackageRoot must point to the complete Windows package.
#endif

[Setup]
AppId={{297CFA39-91D7-4B94-891B-5992EBC1A50D}
AppName=Karaoke PoC
AppVersion=0.1
AppPublisher=Karaoke PoC
AppPublisherURL=https://github.com/lincolnqueiroz/karaoke_poc/
DefaultDirName={localappdata}\Programs\KaraokePoC
DefaultGroupName=Karaoke PoC
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=..\dist\releases\v0.1\installer
OutputBaseFilename=KaraokePoC-0.1-Setup
Compression=lzma2/normal
SolidCompression=no
DiskSpanning=yes
DiskSliceSize=1500000000
WizardStyle=modern
UninstallDisplayIcon={app}\Karaoke.exe
CloseApplications=yes
SetupLogging=yes

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#PackageRoot}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Karaoke PoC"; Filename: "{app}\Karaoke.exe"; WorkingDir: "{app}"
Name: "{group}\Uninstall Karaoke PoC"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Karaoke PoC"; Filename: "{app}\Karaoke.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\Karaoke.exe"; Description: "Launch Karaoke PoC"; Flags: nowait postinstall skipifsilent
