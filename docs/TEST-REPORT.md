# Report di test

**Ambiente:**
- Windows 11 Home con Desktop reindirizzato su OneDrive.
- Claude Desktop dal Microsoft Store (MSIX), versioni 5.1231.2 e 5.11492.0: l'app si è aggiornata durante i test.
- PowerShell 7.7 e Windows PowerShell 5.1.

**Data:** novembre 2026, versioni dello strumento 0.1.0, 0.2.0 e 0.3.0.

---

## 1. Comportamento di Claude Desktop con più profili

Prove su un'installazione reale, con il Claude principale e un profilo aggiuntivo aperti insieme e due account con abbonamenti diversi.

| # | Prova | Esito | Verifica |
|---|---|---|---|
| D1 | Seconda istanza aperta insieme al principale | ✅ | Processi e log: due istanze con cartelle dati diverse |
| D2 | Account e abbonamenti separati | ✅ | Nei log le due istanze usano organizzazioni diverse; il principale resta sul suo piano |
| D3 | La cartella del principale non viene toccata | ✅ | Data di ultima modifica invariata all'avvio del profilo |
| D4 | Secondo clic sul collegamento di un profilo aperto | ✅ | Nessun processo nuovo; la finestra esistente torna in primo piano (`second-instance` nel log del profilo, nulla nel principale) |
| D5 | Percorsi con spazi e lettere accentate | ✅ | Profilo `test profilo è` avviato, chiuso e cancellato |
| D6 | `CLAUDE_CONFIG_DIR` arriva all'app attraverso l'alias MSIX | ✅ | Letto dall'ambiente del processo Claude in esecuzione |
| D7 | Chiusura completa e riapertura: l'accesso resta | ✅ | Prova manuale e log: stessa organizzazione dopo la riapertura |
| D8 | Accesso di un nuovo account al profilo | ✅ con procedura | Funziona con il codice di verifica letto in incognito. Il link `claude://` è arrivato al principale (log: `claudeURLHandler: login`), che per fortuna non ha cambiato account |
| D9 | Scheda Code del profilo isolata da `~/.claude` | ✅ | Con account Pro: `CLAUDE_CONFIG_DIR` corretto nella sessione; progetti, sessioni e cronologia scritti nel profilo; nessun progetto nuovo nel `~/.claude` principale |
| D9c | Progetto dentro la cartella utente | ✅ dalla 0.2.0 | Senza correzioni, un progetto in `C:\Users\…\prova` ereditava `C:\Users\<tu>\.claude\CLAUDE.md` come istruzione di una cartella superiore (in `D:\prova` no). Con `claudeMdExcludes` nel `settings.json` del profilo, la sessione nella stessa cartella non lo vede più |
| D9b | Accesso alla scheda Code dopo il passaggio a Pro | ⚠️ Nuovo accesso | Il server ha rifiutato l'accesso iniziale come troppo vecchio (`session_stale_relogin`) e le sessioni Code non partivano finché non è stato rifatto. Il link `claude://` è arrivato ancora al principale, che è rimasto sul suo account |
| D10b | Claude in Chrome per un profilo tramite un secondo profilo di Chrome | ✅ | Profilo Chrome senza sincronizzazione, con l'estensione abbinata all'account del profilo. Il profilo Claude vede il suo browser e ci apre le schede. L'istanza principale vede ancora il suo Chrome, con lo stesso identificativo di dispositivo di prima |
| D15 | Migrazione manuale dal principale a un profilo | ✅ con avvisi | Istruzioni, impostazioni, skill (junction), plugin e mod reinstallati, server MCP, memorie e impostazioni di 24 progetti, 61 conversazioni e 4 routine. Dettagli e trappole in [MIGRAZIONE.md](MIGRAZIONE.md) |
| D10 | Claude in Chrome con più istanze | ⚠️ Solo un account | Ogni istanza, all'avvio, riscrive lo stesso host dell'estensione (`HKCU\...\NativeMessagingHosts\com.anthropic.claude_browser_extension`) e c'è un solo canale locale (`\\.\pipe\claude-mcp-browser-bridge-<utente>`). Con l'estensione entrata con l'account del principale: il principale vede il browser anche dopo l'avvio del profilo; il profilo risponde "nessun browser collegato". Nessuna interferenza |
| D11 | Cowork (attività locali dalla chat) con più istanze | ✅ | Da settembre 2026 Cowork è integrato nella chat: nessun pulsante dedicato, né nel principale né nel profilo. Due chat avviate a circa 30 secondi di distanza, una per istanza, hanno creato ciascuna il proprio file in `D:\prova-cowork`. Ogni istanza ha salvato la sessione nella propria cartella `local-agent-mode-sessions\<account>` senza riferimenti all'altra. Servizio `CoworkVMService` unico e sempre attivo. Al primo uso il profilo ha scaricato la propria macchina virtuale: circa 9 GB in `vm_bundles` e 350 MB in `claude-code-vm`, come il principale |
| D14 | Configurazione in `<profilo>\claude-code` (0.1 e 0.2) | ❌ Bug, corretto nella 0.3.0 | All'avvio l'app registra `[CCD] Removing old version: plugins / projects / skills` e cancella tutte le cartelle che non sono una versione di Claude Code, cioè memorie, collegamenti delle skill e plugin del profilo. Restano solo i file singoli (`CLAUDE.md`, `settings.json`, `.claude.json`). Le sorgenti dei collegamenti non vengono toccate. Dalla 0.3.0 la configurazione sta in `claude-config`: dopo l'avvio memorie, skill e plugin restano tutti, e nel log non ci sono più cancellazioni |
| D13 | Riavvio deciso dall'app (per esempio dopo lo scarico della macchina virtuale) | ✅ | Il profilo si è riavviato da solo con `--user-data-dir` e `--restarted-by-app`; `CLAUDE_CONFIG_DIR` era ancora presente nel nuovo processo |
| D12 | Aggiornamento di Claude con un profilo aperto | ⚠️ Limite | L'aggiornamento MSIX chiude tutte le istanze ("Windows session ending (close-app)") e riapre solo il principale. Il profilo resta chiuso finché non lo riapri |

## 2. Test dello script (`tests/run-tests.ps1`)

La suite lavora in una cartella temporanea, con un percorso che contiene spazi e "è", e crea i collegamenti in una cartella finta.

| Area | Casi | PS 7.7 | PS 5.1 |
|---|---|---|---|
| Validazione nomi | maiuscole, `../x`, spazi, `claude`, `claude-x`, `con`, `-x`, 41 caratteri | ✅ | ✅ |
| `add` | marcatore, cartella `claude-config`, avviatore UTF-16 con BOM, icona, 2 collegamenti con destinazione, argomenti e icona corretti, istruzioni di accesso | ✅ | ✅ |
| `add` duplicato | rifiutato | ✅ | ✅ |
| `list` | stato chiuso/aperto, scheda Code, gestito | ✅ | ✅ |
| `repair` | cambio nome visualizzato (vecchi collegamenti rimossi), `createdAt` conservato, adozione di una cartella creata a mano, opzioni conservate | ✅ | ✅ |
| `-SharedClaudeCode`, `-StartWithWindows`, `-NoDesktopShortcut` | file flag, collegamenti giusti | ✅ | ✅ |
| Spostamento da `claude-code` a `claude-config` (0.3.0) | file e cartelle di configurazione spostati; cartelle versione dell'app (`2.1.325`) lasciate in `claude-code`; avviatore aggiornato; rifiuto se il profilo è aperto | ✅ | ✅ |
| `claudeMdExcludes` (0.2.0) | `settings.json` creato senza BOM con il CLAUDE.md principale; altre impostazioni ed esclusioni esistenti conservate; nessun duplicato dopo più `repair`; JSON illeggibile lasciato intatto con avviso; niente con `-SharedClaudeCode` | ✅ | ✅ |
| `remove` | collegamenti rimossi e dati conservati; `-DeleteData` cancella; rifiuta cartelle senza marcatore e le lascia intatte | ✅ | ✅ |
| Avvio reale (`-Launch`) | Claude avviato con la cartella giusta, `list` lo vede aperto, `remove` rifiutato mentre è aperto, chiusura dei soli processi di test | ✅ | — |

Durante tutti i test, il Claude principale e il profilo reale sono rimasti aperti e intatti.

## 3. Bug trovati durante lo sviluppo

| Bug | Correzione |
|---|---|
| La configurazione Claude Code del profilo stava in `<profilo>\claude-code`, la cartella delle versioni dell'app, che la svuotava a ogni avvio (D14) | Dalla 0.3.0 sta in `claude-config`; `repair` sposta i profili esistenti |
| L'icona del collegamento puntava alla cartella versionata di Claude in `WindowsApps` e si rompeva all'aggiornamento | L'icona viene copiata nella cartella dei profili |
| La scheda Code di un profilo usava `~/.claude` dell'account principale | L'avviatore imposta `CLAUDE_CONFIG_DIR` per profilo |
| Con il Desktop reindirizzato su OneDrive, `%USERPROFILE%\Desktop` non esiste | Percorsi ricavati con `[Environment]::GetFolderPath()` |
| `list` scriveva direttamente sullo schermo e non si poteva filtrare | Restituisce oggetti PowerShell |
| Il rilevamento dei processi interpretava male i percorsi tra virgolette con spazi | Espressione regolare separata per percorsi tra virgolette e senza |

## 4. Da verificare

- Attività locali lunghe che usano davvero la macchina virtuale in entrambe le istanze nello stesso momento (nei test i file sono stati creati prima che la macchina virtuale del profilo finisse di scaricarsi).
- Installazione classica da claude.ai/download (Squirrel, `%LOCALAPPDATA%\AnthropicClaude`).
- Windows 10.

## Note per chi testa

- **Non chiudere a forza il Claude principale:** se usi Claude Code dentro Claude Desktop, la sessione vive lì.
- **Per chiudere solo un profilo,** filtra i processi per riga di comando con `Get-CimInstance Win32_Process` e un `CommandLine` che contiene la cartella del profilo.
