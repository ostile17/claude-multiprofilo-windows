<#
.SYNOPSIS
  Più account di Claude Desktop aperti insieme su Windows, ognuno nel suo profilo.

.DESCRIPTION
  Ogni profilo ha una cartella dati separata (accesso, chat, impostazioni,
  connettori) e, se non diversamente indicato, una propria configurazione di
  Claude Code per la scheda Code. Claude viene avviato con --user-data-dir
  tramite un piccolo avviatore VBScript, senza finestre di console.

.EXAMPLE
  .\ClaudeProfile.ps1 add lavoro
  .\ClaudeProfile.ps1 add cliente-rossi -DisplayName "Cliente Rossi" -StartWithWindows
  .\ClaudeProfile.ps1 list
  .\ClaudeProfile.ps1 start lavoro
  .\ClaudeProfile.ps1 repair lavoro
  .\ClaudeProfile.ps1 remove lavoro
  .\ClaudeProfile.ps1 remove lavoro -DeleteData
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('add', 'list', 'start', 'repair', 'remove', 'help')]
    [string]$Command = 'help',

    [Parameter(Position = 1)]
    [string]$Name,

    # Cartella che contiene tutti i profili.
    [string]$Root = (Join-Path $env:USERPROFILE 'ClaudeProfili'),

    # Nome mostrato nei collegamenti: "Claude (<DisplayName>)". Predefinito: il nome del profilo.
    [string]$DisplayName,

    [switch]$NoDesktopShortcut,
    [switch]$StartWithWindows,

    # Non separare la scheda Code: le sessioni Claude Code del profilo useranno ~/.claude.
    [switch]$SharedClaudeCode,

    # Account GitHub del profilo: gh (e quindi git push/pull su github.com, che usa gh
    # per le credenziali) userà solo questo account. Deve essere già entrato in gh.
    [string]$GitHubUser,

    # Identità dei commit del profilo (user.name e user.email).
    [string]$GitName,
    [string]$GitEmail,

    # Con 'remove': cancella anche la cartella dati del profilo (chat, accesso, impostazioni).
    [switch]$DeleteData,

    # Salta le conferme interattive (uso da script). Non salta mai il controllo
    # "profilo aperto" né quello sul file marcatore.
    [switch]$Force,

    # Solo per i test: crea tutti i collegamenti in questa cartella invece che
    # su Desktop, menu Start ed Esecuzione automatica.
    [string]$ShortcutDir
)

Set-StrictMode -Version 3
$ErrorActionPreference = 'Stop'
$ScriptBound = $PSBoundParameters

$ToolId = 'claude-multiprofilo-windows'
$ToolVersion = '0.4.0'
# Configurazione Claude Code del profilo (CLAUDE_CONFIG_DIR). NON usare "claude-code":
# l'app tiene in <profilo>\claude-code le sue versioni di Claude Code e a ogni avvio
# cancella come "versione vecchia" ogni altra cartella che trova lì dentro.
$CodeDirName = 'claude-config'
$LegacyCodeDirName = 'claude-code'
$MarkerName = 'profilo.json'
$SharedCodeFlag = 'claude-code-condiviso'
$LauncherName = 'avvia-profilo.vbs'
$IconName = 'claude.ico'
$ReservedNames = @('claude', 'default', 'predefinito', 'con', 'prn', 'aux', 'nul',
    'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
    'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9')

# ---------------------------------------------------------------- utilità

function Write-Ok($msg)   { Write-Host "  [ok] $msg" -ForegroundColor Green }
function Write-Info($msg) { Write-Host "  $msg" }
function Write-Warn($msg) { Write-Host "  [!] $msg" -ForegroundColor Yellow }

function Confirm-Action([string]$Question) {
    if ($Force) { return $true }
    $a = Read-Host "$Question [s/N]"
    return $a -match '^(s|si|sì|y|yes)$'
}

function Assert-ProfileName([string]$n) {
    if (-not $n) { throw "Specifica il nome del profilo, per esempio: .\ClaudeProfile.ps1 $Command lavoro" }
    if ($n -cnotmatch '^[a-z0-9][a-z0-9-]{0,39}$') {
        throw "Nome non valido: '$n'. Usa solo lettere minuscole, cifre e trattini (max 40), iniziando con una lettera o una cifra."
    }
    if ($ReservedNames -contains $n -or $n.StartsWith('claude-')) {
        throw "Il nome '$n' è riservato. Scegline un altro."
    }
}

function Get-ProfileDir([string]$n) { Join-Path $Root $n }

function Read-Marker([string]$dir) {
    $f = Join-Path $dir $MarkerName
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try { $m = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
    if ($m.tool -ne $ToolId) { return $null }
    return $m
}

function Write-Marker([string]$dir, $data) {
    $data | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $dir $MarkerName) -Encoding UTF8
}

# Dove trovare Claude Desktop. L'alias del pacchetto Microsoft Store è stabile tra
# le versioni; l'installazione classica (Squirrel) usa un avviatore in LOCALAPPDATA.
function Find-ClaudeExe {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\claude-desktop.exe'),
        (Join-Path $env:LOCALAPPDATA 'AnthropicClaude\claude.exe')
    )
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $c } }
    throw "Claude Desktop non trovato. Installalo dal Microsoft Store o da claude.ai/download e riprova."
}

# Icona copiata accanto ai profili: il percorso del pacchetto cambia a ogni
# aggiornamento, quindi un collegamento che punta lì perderebbe l'icona.
function Install-Icon {
    $dest = Join-Path $Root $IconName
    $sources = @()
    $pkg = Get-AppxPackage -Name 'Claude' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkg) {
        $sources += Get-ChildItem -LiteralPath (Join-Path $pkg.InstallLocation 'app\resources') -Filter '*.ico' -ErrorAction SilentlyContinue |
            Sort-Object Name | Select-Object -ExpandProperty FullName
    }
    $squirrel = Join-Path $env:LOCALAPPDATA 'AnthropicClaude'
    if (Test-Path -LiteralPath $squirrel) {
        $sources += Get-ChildItem -LiteralPath $squirrel -Filter '*.ico' -Recurse -Depth 3 -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName
    }
    $src = $sources | Where-Object { $_ -notmatch 'Dark' } | Select-Object -First 1
    if (-not $src) { $src = $sources | Select-Object -First 1 }
    if ($src) {
        Copy-Item -LiteralPath $src -Destination $dest -Force
        return $dest
    }
    Write-Warn "Icona di Claude non trovata: i collegamenti useranno l'icona predefinita."
    return $null
}

function Install-Launcher {
    $vbs = @'
' claude-multiprofilo-windows: avviatore di un profilo di Claude Desktop.
' Uso: wscript.exe avvia-profilo.vbs <nome-profilo>
' Generato da ClaudeProfile.ps1: le modifiche manuali vengono sovrascritte da "repair".
Option Explicit
Dim sh, fso, re, root, nome, dataDir, codeDir, exe, candidates, c

Sub Fail(msg)
  MsgBox msg, vbExclamation, "Claude multiprofilo"
  WScript.Quit 1
End Sub

Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

If WScript.Arguments.Count < 1 Then Fail "Manca il nome del profilo."
nome = WScript.Arguments(0)
Set re = New RegExp
re.Pattern = "^[a-z0-9][a-z0-9-]{0,39}$"
If Not re.Test(nome) Then Fail "Nome del profilo non valido: " & nome

root = fso.GetParentFolderName(WScript.ScriptFullName)
dataDir = root & "\" & nome
If Not fso.FileExists(dataDir & "\profilo.json") Then
  Fail "Profilo non trovato: " & dataDir & vbCrLf & vbCrLf & "Crealo o riparalo con: ClaudeProfile.ps1 repair " & nome
End If

' La scheda Code del profilo usa la sua configurazione di Claude Code, non ~/.claude.
If Not fso.FileExists(dataDir & "\claude-code-condiviso") Then
  codeDir = dataDir & "\claude-config"
  If Not fso.FolderExists(codeDir) Then fso.CreateFolder codeDir
  sh.Environment("Process")("CLAUDE_CONFIG_DIR") = codeDir
End If

' GitHub e git del profilo: configurazione gh propria e identità dei commit propria.
If fso.FolderExists(dataDir & "\gh") Then sh.Environment("Process")("GH_CONFIG_DIR") = dataDir & "\gh"
If fso.FileExists(dataDir & "\gitconfig") Then sh.Environment("Process")("GIT_CONFIG_GLOBAL") = dataDir & "\gitconfig"

exe = ""
candidates = Array( _
  sh.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Microsoft\WindowsApps\claude-desktop.exe", _
  sh.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\AnthropicClaude\claude.exe")
For Each c In candidates
  If exe = "" Then
    If fso.FileExists(c) Then exe = c
  End If
Next
If exe = "" Then Fail "Claude Desktop non trovato. Reinstallalo e riprova."

sh.Run """" & exe & """ --user-data-dir=""" & dataDir & """", 1, False
'@
    $dest = Join-Path $Root $LauncherName
    # UTF-16 con BOM: il formato Unicode che wscript legge correttamente anche con percorsi accentati.
    Set-Content -LiteralPath $dest -Value $vbs -Encoding Unicode
    return $dest
}

# Claude Code legge anche i CLAUDE.md delle cartelle superiori al progetto. Per un
# progetto dentro la cartella utente, una di queste è %USERPROFILE%, e il suo
# .claude\CLAUDE.md sono le istruzioni personali del Claude Code principale. Le
# escludo nelle impostazioni utente del profilo (claudeMdExcludes), unendole a
# quelle già presenti. Un settings.json illeggibile non viene toccato.
function Set-ClaudeMdExclude([string]$codeDir) {
    $settings = Join-Path $codeDir 'settings.json'
    $main = (Join-Path $env:USERPROFILE '.claude\CLAUDE.md') -replace '\\', '/'
    $patterns = @($main, ($main.Substring(0, 1).ToLowerInvariant() + $main.Substring(1)),
        ($main.Substring(0, 1).ToUpperInvariant() + $main.Substring(1))) | Select-Object -Unique

    $obj = [pscustomobject]@{}
    if (Test-Path -LiteralPath $settings) {
        try {
            $raw = [IO.File]::ReadAllText($settings)
            if ($raw.Trim()) { $obj = $raw | ConvertFrom-Json }
        } catch {
            Write-Warn "$settings non è un JSON valido: non lo modifico. Le istruzioni personali potrebbero essere lette dai progetti dentro la cartella utente."
            return $false
        }
    }
    $current = @()
    $prop = $obj.PSObject.Properties['claudeMdExcludes']
    if ($prop) { $current = @($prop.Value) }
    $merged = @($current + $patterns | Where-Object { $_ } | Select-Object -Unique)
    $obj | Add-Member -NotePropertyName 'claudeMdExcludes' -NotePropertyValue $merged -Force
    # UTF-8 senza BOM: Claude Code legge il file come JSON puro.
    [IO.File]::WriteAllText($settings, ($obj | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
    return $true
}

function Get-ShortcutTargets([string]$display, [bool]$desktop, [bool]$startup) {
    $file = "Claude ($display).lnk"
    if ($ShortcutDir) {
        $t = @(Join-Path $ShortcutDir "menu-$file")
        if ($desktop) { $t += Join-Path $ShortcutDir "desktop-$file" }
        if ($startup) { $t += Join-Path $ShortcutDir "avvio-$file" }
        return $t
    }
    $t = @(Join-Path ([Environment]::GetFolderPath('Programs')) $file)
    # Il Desktop può essere reindirizzato (OneDrive): chiedo il percorso a Windows.
    if ($desktop) { $t += Join-Path ([Environment]::GetFolderPath('Desktop')) $file }
    if ($startup) { $t += Join-Path ([Environment]::GetFolderPath('Startup')) $file }
    return $t
}

function New-ProfileShortcut([string]$path, [string]$n, [string]$launcher, [string]$icon, [string]$display) {
    $sh = New-Object -ComObject WScript.Shell
    $s = $sh.CreateShortcut($path)
    $s.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
    $s.Arguments = "`"$launcher`" $n"
    $s.WorkingDirectory = $Root
    if ($icon) { $s.IconLocation = "$icon,0" }
    $s.Description = "Claude Desktop - profilo $display"
    $s.Save()
}

function Get-ProfileProcesses([string]$dir) {
    $needle = $dir.TrimEnd('\').ToLowerInvariant()
    Get-CimInstance Win32_Process -Filter "Name='claude.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $cl = $_.CommandLine
        $cl -and $cl -match '--user-data-dir=(?:"([^"]+)"|(\S+))' -and
            ($(if ($Matches[1]) { $Matches[1] } else { $Matches[2] })).TrimEnd('\').ToLowerInvariant() -eq $needle
    }
}

# Fino alla 0.2.0 la configurazione stava in <profilo>\claude-code, la cartella dove
# l'app tiene le versioni di Claude Code: a ogni avvio l'app cancella lì dentro le
# cartelle che non sono una versione (projects, plugins, skills...). Sposto in
# claude-config tutto ciò che non è una versione, senza sovrascrivere nulla.
function Move-LegacyCodeConfig([string]$dir) {
    $legacy = Join-Path $dir $LegacyCodeDirName
    if (-not (Test-Path -LiteralPath $legacy)) { return }
    $items = @(Get-ChildItem -LiteralPath $legacy -Force | Where-Object { $_.Name -notmatch '^\d+\.\d+\.\d+$' })
    if (-not $items.Count) { return }
    if (@(Get-ProfileProcesses $dir).Count) {
        throw "Il profilo è aperto: chiudilo dal menu della sua finestra (File > Esci) per spostare la sua configurazione Claude Code in $CodeDirName\."
    }
    $new = Join-Path $dir $CodeDirName
    New-Item -ItemType Directory -Force -Path $new | Out-Null
    foreach ($i in $items) {
        $dest = Join-Path $new $i.Name
        if (Test-Path -LiteralPath $dest) { Write-Warn "$dest esiste già: lascio $($i.FullName) dov'è."; continue }
        Move-Item -LiteralPath $i.FullName -Destination $dest
    }
    Write-Ok "Configurazione Claude Code spostata da $LegacyCodeDirName\ a $CodeDirName\ (l'app svuota $LegacyCodeDirName\ a ogni avvio)."
}

function Get-MarkerValue($marker, [string]$key) {
    if (-not $marker) { return $null }
    $p = $marker.PSObject.Properties[$key]
    if ($p) { return $p.Value } else { return $null }
}

# Configurazione gh del profilo: indica solo quale account usare. Il token resta dove gh
# l'ha salvato (Gestore credenziali di Windows), quindi l'account deve aver già fatto
# "gh auth login" almeno una volta su questo PC. Non sovrascrive un hosts.yml non nostro.
function Set-ProfileGitHub([string]$dir, [string]$user) {
    if ($user -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$') { throw "Nome utente GitHub non valido: '$user'." }
    $ghDir = Join-Path $dir 'gh'
    $hosts = Join-Path $ghDir 'hosts.yml'
    $mark = "# $ToolId"
    if ((Test-Path -LiteralPath $hosts) -and -not ((Get-Content -LiteralPath $hosts -TotalCount 1) -eq $mark)) {
        Write-Warn "$hosts esiste e non è stato creato da questo strumento: non lo modifico."
        return
    }
    New-Item -ItemType Directory -Force -Path $ghDir | Out-Null
    $yml = @($mark, 'github.com:', '    users:', "        ${user}:", '    git_protocol: https', "    user: $user") -join "`n"
    [IO.File]::WriteAllText($hosts, $yml + "`n", [Text.UTF8Encoding]::new($false))
    # Controllo di sola lettura: guardo solo se nel Gestore credenziali esiste la voce
    # di gh per quell'account. Non lancio gh, che potrebbe creare o copiare voci.
    $known = @(cmdkey /list 2>$null | Where-Object { $_ -match "target=gh:github\.com:$([regex]::Escape($user))\s*$" }).Count -gt 0
    if ($known) { Write-Ok "GitHub del profilo: $user (credenziali di gh già presenti su questo PC)." }
    else { Write-Warn "GitHub del profilo: $user non ha ancora fatto l'accesso a gh su questo PC. Esegui una volta: `$env:GH_CONFIG_DIR='$ghDir'; gh auth login --hostname github.com --web" }
}

# Identità dei commit del profilo: un gitconfig che include quello globale dell'utente
# (credenziali, alias, impostazioni) e cambia solo [user].
function Set-ProfileGitConfig([string]$dir, [string]$name, [string]$email) {
    if ($name -match '[\r\n"\\\[\]]' -or $email -notmatch '^[^\s@"<>\[\]\\]+@[^\s@"<>\[\]\\]+$') { throw 'Nome o email per git non validi.' }
    $global = (Join-Path $env:USERPROFILE '.gitconfig') -replace '\\', '/'
    $lines = @("# ${ToolId}: configurazione git del profilo", '[include]', "`tpath = $global", '[user]')
    if ($name) { $lines += "`tname = $name" }
    if ($email) { $lines += "`temail = $email" }
    [IO.File]::WriteAllText((Join-Path $dir 'gitconfig'), ($lines -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
    Write-Ok "Commit del profilo firmati come: $name <$email>"
}

function Install-Profile([string]$n, $marker) {
    $dir = Get-ProfileDir $n
    $display = if ($DisplayName) { $DisplayName } elseif ($marker -and $marker.displayName) { $marker.displayName } else { $n }
    $desktop = if ($ScriptBound.ContainsKey('NoDesktopShortcut') -or -not $marker) { -not $NoDesktopShortcut } else { [bool]$marker.desktopShortcut }
    $startup = if ($StartWithWindows -or -not $marker) { [bool]$StartWithWindows } else { [bool]$marker.startWithWindows }
    $shared  = if ($SharedClaudeCode -or -not $marker) { [bool]$SharedClaudeCode } else { [bool]$marker.sharedClaudeCode }

    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    if ($shared) {
        New-Item -ItemType File -Force -Path (Join-Path $dir $SharedCodeFlag) | Out-Null
    } else {
        Remove-Item -LiteralPath (Join-Path $dir $SharedCodeFlag) -Force -ErrorAction SilentlyContinue
        Move-LegacyCodeConfig $dir
        $codeDir = Join-Path $dir $CodeDirName
        New-Item -ItemType Directory -Force -Path $codeDir | Out-Null
        $null = Set-ClaudeMdExclude $codeDir
    }

    $ghUser   = if ($GitHubUser) { $GitHubUser } else { Get-MarkerValue $marker 'githubUser' }
    $gitName  = if ($GitName) { $GitName } else { Get-MarkerValue $marker 'gitName' }
    $gitEmail = if ($GitEmail) { $GitEmail } else { Get-MarkerValue $marker 'gitEmail' }
    if ($ghUser) { Set-ProfileGitHub $dir $ghUser }
    if ($gitName -or $gitEmail) {
        if (-not ($gitName -and $gitEmail)) { throw 'Per l''identità dei commit servono sia -GitName sia -GitEmail.' }
        Set-ProfileGitConfig $dir $gitName $gitEmail
    }

    $launcher = Install-Launcher
    $icon = Install-Icon

    # Rimuove i collegamenti registrati in precedenza (per esempio con un altro nome visualizzato).
    if ($marker -and $marker.shortcuts) {
        foreach ($old in $marker.shortcuts) { Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue }
    }
    $links = @(Get-ShortcutTargets $display $desktop $startup)
    foreach ($l in $links) { New-ProfileShortcut $l $n $launcher $icon $display }

    Write-Marker $dir ([ordered]@{
        tool             = $ToolId
        version          = $ToolVersion
        name             = $n
        displayName      = $display
        createdAt        = if ($marker -and $marker.createdAt) { $marker.createdAt } else { (Get-Date).ToString('o') }
        updatedAt        = (Get-Date).ToString('o')
        desktopShortcut  = $desktop
        startWithWindows = $startup
        sharedClaudeCode = $shared
        githubUser       = $ghUser
        gitName          = $gitName
        gitEmail         = $gitEmail
        shortcuts        = $links
    })
    return [pscustomobject]@{ Dir = $dir; Links = $links; Display = $display; Shared = $shared }
}

# ---------------------------------------------------------------- comandi

function Invoke-Add {
    Assert-ProfileName $Name
    $null = Find-ClaudeExe
    $dir = Get-ProfileDir $Name
    $marker = Read-Marker $dir
    if ($marker) { throw "Il profilo '$Name' esiste già. Usa 'repair' per ricreare collegamenti e avviatore." }
    if ((Test-Path -LiteralPath $dir) -and (Get-ChildItem -LiteralPath $dir -Force | Select-Object -First 1)) {
        Write-Warn "La cartella $dir esiste già e non è stata creata da questo strumento."
        if (-not (Confirm-Action "Usarla come cartella dati del profilo '$Name'?")) { Write-Info 'Annullato.'; return }
    }
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    $r = Install-Profile $Name $null
    Write-Ok "Profilo '$Name' creato in $($r.Dir)"
    foreach ($l in $r.Links) { Write-Ok "Collegamento: $l" }
    if (-not $r.Shared) { Write-Ok 'Scheda Code separata: configurazione in claude-config\ dentro il profilo, istruzioni personali del Claude principale escluse.' }
    Write-Host ''
    Write-Host '  Primo accesso (importante):' -ForegroundColor Cyan
    Write-Info "1. Apri 'Claude ($($r.Display))' e scegli 'Continua con email'."
    Write-Info '2. NON cliccare il link nella mail: copialo e aprilo in una finestra in incognito.'
    Write-Info "3. Se il browser chiede di aprire Claude, scegli 'Annulla'."
    Write-Info '4. Scrivi nel profilo il codice di verifica mostrato dalla pagina.'
    Write-Info "   Evita 'Accedi con Google': il ritorno all'app finirebbe nel Claude principale."
}

function Invoke-List {
    if (-not (Test-Path -LiteralPath $Root)) { Write-Info "Nessun profilo ($Root non esiste)."; return }
    $rows = foreach ($d in Get-ChildItem -LiteralPath $Root -Directory) {
        $m = Read-Marker $d.FullName
        [pscustomobject]@{
            Profilo   = $d.Name
            Nome      = if ($m) { $m.displayName } else { '-' }
            Stato     = if (@(Get-ProfileProcesses $d.FullName).Count) { 'aperto' } else { 'chiuso' }
            SchedaCode =if (-not $m) { '-' } elseif ($m.sharedClaudeCode) { 'condivisa' } else { 'separata' }
            Gestito   = if ($m) { 'sì' } else { 'no (usa repair)' }
        }
    }
    if ($rows) { $rows } else { Write-Info 'Nessun profilo.' }
}

function Invoke-Start {
    Assert-ProfileName $Name
    $dir = Get-ProfileDir $Name
    if (-not (Read-Marker $dir)) { throw "Profilo '$Name' non trovato in $Root." }
    Start-Process (Join-Path $env:WINDIR 'System32\wscript.exe') -ArgumentList "`"$(Join-Path $Root $LauncherName)`" $Name"
    Write-Ok "Avvio di '$Name' richiesto."
}

function Invoke-Repair {
    Assert-ProfileName $Name
    $null = Find-ClaudeExe
    $dir = Get-ProfileDir $Name
    if (-not (Test-Path -LiteralPath $dir)) { throw "La cartella $dir non esiste. Per crearla usa 'add'." }
    $marker = Read-Marker $dir
    if (-not $marker) {
        Write-Warn "$dir non è ancora gestita da questo strumento (per esempio un profilo creato a mano)."
        if (-not (Confirm-Action "Adottarla come profilo '$Name'?")) { Write-Info 'Annullato.'; return }
    }
    $r = Install-Profile $Name $marker
    Write-Ok "Profilo '$Name' riparato: avviatore, icona e collegamenti ricreati."
    foreach ($l in $r.Links) { Write-Ok "Collegamento: $l" }
}

function Invoke-Remove {
    Assert-ProfileName $Name
    $dir = Get-ProfileDir $Name
    $marker = Read-Marker $dir
    if (-not $marker) { throw "Nessun profilo gestito '$Name' in $Root. Per sicurezza non tocco cartelle senza $MarkerName." }
    if (@(Get-ProfileProcesses $dir).Count) {
        throw "Il profilo '$Name' è aperto. Chiudilo dal menu della sua finestra (File > Esci) e riprova."
    }
    if (-not (Confirm-Action "Rimuovere i collegamenti del profilo '$Name'?")) { Write-Info 'Annullato.'; return }
    foreach ($l in @($marker.shortcuts)) {
        if ($l -and (Test-Path -LiteralPath $l)) { Remove-Item -LiteralPath $l -Force; Write-Ok "Rimosso $l" }
    }
    if ($DeleteData) {
        $full = [IO.Path]::GetFullPath($dir).TrimEnd('\')
        $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
        if (-not $full.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Percorso inatteso, cancellazione rifiutata: $full" }
        Write-Warn "Stai per cancellare DEFINITIVAMENTE $full (accesso, chat locali, impostazioni, configurazione Claude Code)."
        $ok = $Force
        if (-not $ok) { $ok = (Read-Host "Per confermare scrivi il nome del profilo ($Name)") -ceq $Name }
        if ($ok) { Remove-Item -LiteralPath $full -Recurse -Force; Write-Ok "Cartella dati cancellata." }
        else { Write-Info 'Cartella dati conservata.' }
    } else {
        Write-Info "Cartella dati conservata: $dir (aggiungi -DeleteData per cancellarla)."
    }
}

function Show-Help {
    Get-Help $PSCommandPath -Detailed | Out-Host
}

switch ($Command) {
    'add'    { Invoke-Add }
    'list'   { Invoke-List }
    'start'  { Invoke-Start }
    'repair' { Invoke-Repair }
    'remove' { Invoke-Remove }
    default  { Show-Help }
}
