; Inno Setup fragment — .kdbx file association for dgvault (Windows).
; Include from your installer script's [Registry] section. This makes dgvault
; the default handler and gives .kdbx files the dgvault document icon.
;
; Assumes the app is installed as {app}\dgvault.exe and the document icon is
; shipped alongside it as {app}\kdbx_document.ico (copy it in your [Files]
; section from windows\runner\resources\kdbx_document.ico).

[Registry]
; ProgID that describes "a dgvault vault".
Root: HKA; Subkey: "Software\Classes\dgvault.kdbx"; ValueType: string; ValueData: "KeePass Database"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\dgvault.kdbx\DefaultIcon"; ValueType: string; ValueData: "{app}\kdbx_document.ico"
Root: HKA; Subkey: "Software\Classes\dgvault.kdbx\shell\open\command"; ValueType: string; ValueData: """{app}\dgvault.exe"" ""%1"""

; Point the .kdbx extension at that ProgID and register under OpenWithProgids.
Root: HKA; Subkey: "Software\Classes\.kdbx"; ValueType: string; ValueData: "dgvault.kdbx"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.kdbx\OpenWithProgids"; ValueType: string; ValueName: "dgvault.kdbx"; ValueData: ""; Flags: uninsdeletevalue

; After install, refresh Explorer so the new icon shows immediately, e.g. run
;   ie4uinit.exe -show
; from a [Run] entry, or call SHChangeNotify(SHCNE_ASSOCCHANGED, ...) from [Code].
