# Suite di test di ClaudeProfile.ps1. Lavora in -Base (cartella temporanea) e non tocca Desktop, menu Start o profili reali.
# Uso: powershell -ExecutionPolicy Bypass -File .\tests\run-tests.ps1 -Script .\ClaudeProfile.ps1 -Base $env:TEMP\cmp-test [-Launch]
param([string]$Script, [string]$Base, [switch]$Launch)
$ErrorActionPreference = 'Continue'
$root = Join-Path $Base 'radice test è'; $sc = Join-Path $Base 'collegamenti'
if (Test-Path -LiteralPath $Base) { Remove-Item -LiteralPath $Base -Recurse -Force }
New-Item -ItemType Directory -Force $root, $sc | Out-Null
$script:fail = 0
function Check($label, [bool]$cond) { if ($cond) { "PASS  $label" } else { "FAIL  $label"; $script:fail++ } }
function Run { $cmd = "& '$Script' $($args -join ' ') -Root '$root' -ShortcutDir '$sc'"; try { (Invoke-Expression $cmd *>&1 | Out-String) -join "`n" } catch { "ERRORE: " + $_.Exception.Message } }
$wsh = New-Object -ComObject WScript.Shell

"== PowerShell $($PSVersionTable.PSVersion)"
# 1 nomi non validi
foreach ($bad in @('Lavoro', '../x', 'a b', 'claude', 'claude-x', 'con', '-x', ('a' * 41))) {
  $o = Run add "'$bad'" -Force; Check "nome rifiutato: '$bad'" ($o -match 'non valido|riservato')
}
# 2 add
$o = Run add test1 -Force
$d = Join-Path $root 'test1'
Check 'add: marcatore creato' (Test-Path -LiteralPath "$d\profilo.json")
Check 'add: cartella claude-code' (Test-Path -LiteralPath "$d\claude-code")
Check 'add: avviatore creato' (Test-Path -LiteralPath "$root\avvia-profilo.vbs")
$bom = [IO.File]::ReadAllBytes("$root\avvia-profilo.vbs")[0..1]
Check 'add: avviatore in UTF-16 con BOM' ($bom[0] -eq 0xFF -and $bom[1] -eq 0xFE)
Check 'add: icona copiata' ((Get-Item -LiteralPath "$root\claude.ico").Length -gt 1000)
$links = Get-ChildItem -LiteralPath $sc -Filter '*.lnk'
Check 'add: 2 collegamenti (menu + desktop)' ($links.Count -eq 2)
$s = $wsh.CreateShortcut($links[0].FullName)
Check 'add: collegamento -> wscript' ($s.TargetPath -like '*wscript.exe')
Check 'add: argomenti con avviatore e nome' ($s.Arguments -eq "`"$root\avvia-profilo.vbs`" test1")
Check 'add: icona del collegamento esiste' (Test-Path -LiteralPath (($s.IconLocation -split ',')[0]))
Check 'add: istruzioni di accesso stampate' ($o -match 'incognito')
# 3 duplicato
Check 'add duplicato rifiutato' ((Run add test1 -Force) -match 'esiste già')
# 4 list
$o = Run list; Check 'list mostra test1 chiuso e gestito' ($o -match 'test1' -and $o -match 'chiuso' -and $o -match 'separata')
# 5 repair con nuovo nome visualizzato
$o = Run repair test1 -DisplayName "'Prova Uno'" -Force
$names = (Get-ChildItem -LiteralPath $sc -Filter '*.lnk').Name
Check 'repair: vecchi collegamenti rimossi' (-not ($names -match '\(test1\)'))
Check 'repair: nuovi collegamenti con nome' (@($names -match 'Prova Uno').Count -eq 2)
$m = Get-Content -LiteralPath "$d\profilo.json" -Raw | ConvertFrom-Json
Check 'repair: createdAt conservato, displayName aggiornato' ($m.createdAt -and $m.displayName -eq 'Prova Uno')
# 6 adozione di una cartella fatta a mano
$man = Join-Path $root 'manuale'; New-Item -ItemType Directory $man | Out-Null; Set-Content -LiteralPath "$man\Preferences" 'x'
$o = Run repair manuale -Force
Check 'repair: adotta cartella manuale' ((Test-Path -LiteralPath "$man\profilo.json") -and (Test-Path -LiteralPath "$man\Preferences"))
# 7 scheda Code condivisa + avvio automatico
$o = Run add condiviso -SharedClaudeCode -StartWithWindows -NoDesktopShortcut -Force
Check 'shared: file flag presente' (Test-Path -LiteralPath "$root\condiviso\claude-code-condiviso")
Check 'shared: nessuna cartella claude-code' (-not (Test-Path -LiteralPath "$root\condiviso\claude-code"))
$cn = (Get-ChildItem -LiteralPath $sc -Filter '*condiviso*').Name
Check 'shared: menu + avvio, niente desktop' ($cn.Count -eq 2 -and ($cn -match '^avvio-') -and -not ($cn -match '^desktop-'))
$o = Run repair condiviso -Force
Check 'repair conserva le opzioni (shared, avvio)' ((Test-Path -LiteralPath "$root\condiviso\claude-code-condiviso") -and @((Get-ChildItem -LiteralPath $sc -Filter '*condiviso*')).Count -eq 2)
# 8 remove
$o = Run remove test1 -Force
Check 'remove: collegamenti rimossi' (-not (Get-ChildItem -LiteralPath $sc -Filter '*Prova Uno*'))
Check 'remove: dati conservati senza -DeleteData' (Test-Path -LiteralPath "$d\profilo.json")
$o = Run remove test1 -DeleteData -Force
Check 'remove -DeleteData: cartella cancellata' (-not (Test-Path -LiteralPath $d))
# 9 remove di cartella non gestita
New-Item -ItemType Directory (Join-Path $root 'estranea') | Out-Null
Check 'remove: rifiuta cartella senza marcatore' ((Run remove estranea -DeleteData -Force) -match 'non tocco')
Check 'remove: cartella estranea intatta' (Test-Path -LiteralPath (Join-Path $root 'estranea'))
# 10 avvio reale (solo con -Launch)
if ($Launch) {
  $o = Run add avvio -Force
  $o = Run start avvio; Start-Sleep 12
  $pd = Join-Path $root 'avvio'
  $p = Get-CimInstance Win32_Process -Filter "Name='claude.exe'" | Where-Object { $_.CommandLine -like "*radice test*" }
  Check 'start: Claude avviato con la cartella del profilo' (@($p | Where-Object { $_.CommandLine -notmatch '--type=' }).Count -eq 1)
  Check 'start: Claude ha creato i suoi file' (Test-Path -LiteralPath "$pd\Local State")
  $o = Run list; Check 'list: profilo aperto rilevato' ($o -match 'aperto')
  $o = Run remove avvio -Force; Check 'remove rifiutato se il profilo è aperto' ($o -match 'aperto')
  $p | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Start-Sleep 3
  Check 'processi di test chiusi' (-not (Get-CimInstance Win32_Process -Filter "Name='claude.exe'" | Where-Object { $_.CommandLine -like "*radice test*" }))
}
"== risultato: $script:fail falliti"
