; Felix CLI - Windows GUI Installer
; Requires Inno Setup 6.x (https://jrsoftware.org/isinfo.php)
;
; Built automatically by scripts\package-release.ps1 when iscc.exe is in PATH.
;
; Manual build (from repo root):
;   iscc /DVersion=0.9.0 /DSourceDir=.release\win-x64 /DOutputDir=.release scripts\felix-installer.iss
;
; Output: .release\felix-{Version}-setup.exe

; Allow Version / SourceDir / OutputDir to be passed via /D on the command line.
#ifndef Version
  #define Version "0.9.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\.release\win-x64"
#endif
#ifndef OutputDir
  #define OutputDir "..\.release"
#endif

#define AppName   "Felix CLI"
#define Publisher "Felix AI"
#define AppURL    "https://www.felix.ai"
#define ExeName   "felix.exe"
#define OutFile   "felix-" + Version + "-setup"

; ─── Setup ───────────────────────────────────────────────────────────────────
[Setup]
AppName={#AppName}
AppVersion={#Version}
AppPublisher={#Publisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}
; Install per-user by default (no UAC prompt); user can elevate via dialog.
DefaultDirName={localappdata}\Programs\Felix
DisableProgramGroupPage=yes
AllowNoIcons=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutFile}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
UninstallDisplayIcon={app}\{#ExeName}
; Uncomment when you have a code-signing certificate:
; SignTool=signtool sign /td sha256 /fd sha256 /tr http://timestamp.digicert.com /a $f

; ─── Languages ───────────────────────────────────────────────────────────────
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

; ─── Tasks ───────────────────────────────────────────────────────────────────
[Tasks]
Name: "modifypath"; Description: "Add Felix to &PATH (recommended)"; Flags: checkedonce

; ─── Files ───────────────────────────────────────────────────────────────────
[Files]
Source: "{#SourceDir}\{#ExeName}"; DestDir: "{app}"; Flags: ignoreversion

; ─── Icons ───────────────────────────────────────────────────────────────────
[Icons]
Name: "{group}\Felix CLI";            Filename: "{app}\{#ExeName}"
Name: "{group}\Uninstall Felix CLI";  Filename: "{uninstallexe}"

; ─── Post-install step ───────────────────────────────────────────────────────
[Run]
; Run 'felix install' silently to extract embedded engine scripts.
Filename: "{app}\{#ExeName}"; Parameters: "install"; \
  StatusMsg: "Running initial setup..."; \
  Flags: nowait postinstall runhidden skipifsilent

; ─── Pascal code: PATH management ────────────────────────────────────────────
[Code]

procedure AddToUserPath(const Dir: string);
var
  OldPath: string;
begin
  if not RegQueryStringValue(HKEY_CURRENT_USER, 'Environment', 'Path', OldPath) then
    OldPath := '';
  if Pos(LowerCase(Dir), LowerCase(OldPath)) = 0 then
  begin
    if OldPath = '' then
      RegWriteStringValue(HKEY_CURRENT_USER, 'Environment', 'Path', Dir)
    else
      RegWriteStringValue(HKEY_CURRENT_USER, 'Environment', 'Path', OldPath + ';' + Dir);
  end;
end;

procedure RemoveFromUserPath(const Dir: string);
var
  OldPath, NewPath: string;
begin
  if RegQueryStringValue(HKEY_CURRENT_USER, 'Environment', 'Path', OldPath) then
  begin
    NewPath := OldPath;
    StringChangeEx(NewPath, Dir + ';', '', True);
    StringChangeEx(NewPath, ';' + Dir, '', True);
    StringChangeEx(NewPath, Dir,       '', True);
    RegWriteStringValue(HKEY_CURRENT_USER, 'Environment', 'Path', NewPath);
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssPostInstall) and IsTaskSelected('modifypath') then
    AddToUserPath(ExpandConstant('{app}'));
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
    RemoveFromUserPath(ExpandConstant('{app}'));
end;
