# Suite di test di ClaudeProfile.ps1. Lavora in -Base (cartella temporanea) e non tocca Desktop, menu Start o profili reali.
# Uso: powershell -ExecutionPolicy Bypass -File .\tests\run-tests.ps1 -Script .\ClaudeProfile.ps1 -Base $env:TEMP\cmp-test [-Launch]
param([string]$Script, [string]$Base, [switch]$Launch)
$ErrorActionPreference = 'Continue'
$root = Join-Path $Base 'radice test è'; $sc = Join-Path $Base 'collegamenti'
if (Test-Path -LiteralPath $Base) { Remove-Item -LiteralPath $Base -Recurse -Force }
New-Item -ItemType Directory -Force $root, $sc | Out-Null
$script:fail = 0
function Check($label, [bool]$cond) { if ($cond) { "PASS  $label" } else { "FAIL  $label"; $script:fail++ } }
function Run { $cmd = "& '$Script' $($args -join ' ') -Root '$root' -ShortcutDir '$sc'"; try { (Invoke-Expression $cmd *>&1 | Out-String -Width 4096) -join "`n" } catch { "ERRORE: " + $_.Exception.Message } }
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
Check 'add: cartella claude-config' (Test-Path -LiteralPath "$d\claude-config")
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
Check 'shared: nessuna cartella claude-config' (-not (Test-Path -LiteralPath "$root\condiviso\claude-config"))
$cn = (Get-ChildItem -LiteralPath $sc -Filter '*condiviso*').Name
Check 'shared: menu + avvio, niente desktop' ($cn.Count -eq 2 -and ($cn -match '^avvio-') -and -not ($cn -match '^desktop-'))
$o = Run repair condiviso -Force
Check 'repair conserva le opzioni (shared, avvio)' ((Test-Path -LiteralPath "$root\condiviso\claude-code-condiviso") -and @((Get-ChildItem -LiteralPath $sc -Filter '*condiviso*')).Count -eq 2)
# 7b esclusione delle istruzioni personali (claudeMdExcludes)
$mainMd = (Join-Path $env:USERPROFILE '.claude\CLAUDE.md') -replace '\\', '/'
$sj = Join-Path $d 'claude-config\settings.json'
Check 'excludes: settings.json creato' (Test-Path -LiteralPath $sj)
$sb = [IO.File]::ReadAllBytes($sj)
Check 'excludes: settings.json senza BOM' (-not ($sb[0] -eq 0xEF -and $sb[1] -eq 0xBB))
Check 'excludes: contiene il CLAUDE.md principale' (@((Get-Content -LiteralPath $sj -Raw | ConvertFrom-Json).claudeMdExcludes) -contains $mainMd)
Check 'shared: nessun settings.json' (-not (Test-Path -LiteralPath (Join-Path $root 'condiviso\claude-config\settings.json')))
$mg = Join-Path $root 'unione'; New-Item -ItemType Directory -Force (Join-Path $mg 'claude-code') | Out-Null
[IO.File]::WriteAllText((Join-Path $mg 'claude-code\settings.json'), '{"model":"modello-test","claudeMdExcludes":["D:/altro/CLAUDE.md"]}')
New-Item -ItemType Directory -Force (Join-Path $mg 'claude-code\2.1.325') | Out-Null; [IO.File]::WriteAllText((Join-Path $mg 'claude-code\2.1.325\claude.exe'), 'bin')
$o = Run repair unione -Force
$mj = Get-Content -LiteralPath (Join-Path $mg 'claude-config\settings.json') -Raw | ConvertFrom-Json
Check 'excludes: altre impostazioni conservate' ($mj.model -eq 'modello-test')
Check 'excludes: esclusioni esistenti conservate e unite' ((@($mj.claudeMdExcludes) -contains 'D:/altro/CLAUDE.md') -and (@($mj.claudeMdExcludes) -contains $mainMd))
$o = Run repair unione -Force
Check 'excludes: nessun duplicato dopo un secondo repair' (@((Get-Content -LiteralPath (Join-Path $mg 'claude-config\settings.json') -Raw | ConvertFrom-Json).claudeMdExcludes | Where-Object { $_ -ceq $mainMd }).Count -eq 1)
# 7c spostamento da claude-code (0.2.0) a claude-config (0.3.0)
Check 'legacy: settings.json spostato in claude-config' ((Test-Path -LiteralPath (Join-Path $mg 'claude-config\settings.json')) -and -not (Test-Path -LiteralPath (Join-Path $mg 'claude-code\settings.json')))
Check 'legacy: cartella versione dell''app lasciata in claude-code' (Test-Path -LiteralPath (Join-Path $mg 'claude-code\2.1.325\claude.exe'))
Check 'legacy: nessuna versione dell''app copiata in claude-config' (-not (Test-Path -LiteralPath (Join-Path $mg 'claude-config\2.1.325')))
Check 'avviatore: usa claude-config' ([IO.File]::ReadAllText("$root\avvia-profilo.vbs") -match '\\claude-config"')
$bk = Join-Path $root 'rotto'; New-Item -ItemType Directory -Force (Join-Path $bk 'claude-code') | Out-Null
[IO.File]::WriteAllText((Join-Path $bk 'claude-code\settings.json'), '{ non json')
$o = Run repair rotto -Force
Check 'excludes: JSON illeggibile lasciato intatto' (([IO.File]::ReadAllText((Join-Path $bk 'claude-config\settings.json'))) -eq '{ non json')
Check 'excludes: avviso per JSON illeggibile' ($o -match 'non è un JSON valido')
# 7d GitHub e identità git del profilo (0.4.0)
$o = Run add githubtest -GitHubUser 'utente-di-prova' -GitName "'Nome Prova'" -GitEmail 'prova@example.com' -Force
$gd = Join-Path $root 'githubtest'
Check 'github: hosts.yml creato con l''account' ((Test-Path -LiteralPath "$gd\gh\hosts.yml") -and ([IO.File]::ReadAllText("$gd\gh\hosts.yml") -match 'user: utente-di-prova'))
Check 'github: hosts.yml non contiene token' (-not ([IO.File]::ReadAllText("$gd\gh\hosts.yml") -match '(?i)oauth_token|gho_|ghp_'))
$gc = [IO.File]::ReadAllText("$gd\gitconfig")
Check 'git: gitconfig include quello globale' ($gc -match [regex]::Escape(((Join-Path $env:USERPROFILE '.gitconfig') -replace '\\','/')))
Check 'git: identità del profilo' ($gc -match 'name = Nome Prova' -and $gc -match 'email = prova@example.com')
Check 'git: identità letta da git' ((& git config --file "$gd\gitconfig" user.email) -eq 'prova@example.com')
$m7 = Get-Content -LiteralPath "$gd\profilo.json" -Raw | ConvertFrom-Json
Check 'github: opzioni salvate nel marcatore' ($m7.githubUser -eq 'utente-di-prova' -and $m7.gitEmail -eq 'prova@example.com')
Remove-Item -LiteralPath "$gd\gitconfig" -Force
$o = Run repair githubtest -Force
Check 'repair: ricrea gitconfig dalle opzioni salvate' (Test-Path -LiteralPath "$gd\gitconfig")
$vb = [IO.File]::ReadAllText("$root\avvia-profilo.vbs")
Check 'avviatore: imposta GH_CONFIG_DIR e GIT_CONFIG_GLOBAL' ($vb -match 'GH_CONFIG_DIR' -and $vb -match 'GIT_CONFIG_GLOBAL')
Check 'git: email non valida rifiutata' ((Run add gitrotto -GitName 'X' -GitEmail "'non-una-email'" -Force) -match 'non validi')
Check 'git: nome senza email rifiutato' ((Run add gitmezzo -GitName 'X' -Force) -match 'servono sia')
Check 'github: utente non valido rifiutato' ((Run add ghrotto -GitHubUser "'a b'" -Force) -match 'non valido')
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
