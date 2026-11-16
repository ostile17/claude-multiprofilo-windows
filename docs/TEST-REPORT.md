# Report di test

**Ambiente:**
- Windows 11 Home con Desktop reindirizzato su OneDrive.
- Claude Desktop dal Microsoft Store (MSIX), versioni 5.1231.2 e 5.11492.0: l'app si è aggiornata durante i test.
- PowerShell 7.7 e Windows PowerShell 5.1.

**Data:** novembre 2026, versione dello strumento 0.1.0.

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
| D9 | Scheda Code del profilo isolata da `~/.claude` | ✅ con un limite | Con account Pro: `CLAUDE_CONFIG_DIR` corretto nella sessione; progetti, sessioni e cronologia scritti nel profilo; nessun progetto nuovo nel `~/.claude` principale. **Limite:** un progetto dentro la cartella utente eredita `C:\Users\<tu>\.claude\CLAUDE.md` come istruzione di una cartella superiore (verificato: progetto in `C:\Users\…\prova` sì, in `D:\prova` no) |
| D9b | Accesso alla scheda Code dopo il passaggio a Pro | ⚠️ Nuovo accesso | Il server ha rifiutato l'accesso iniziale come troppo vecchio (`session_stale_relogin`) e le sessioni Code non partivano finché non è stato rifatto. Il link `claude://` è arrivato ancora al principale, che è rimasto sul suo account |
| D10 | Claude in Chrome con più istanze | ❓ Non testato | Ogni istanza, all'avvio, registra lo stesso host dell'estensione (`HKCU\...\NativeMessagingHosts\com.anthropic.claude_browser_extension`) |
| D11 | Cowork con più istanze | ❓ Non testato | Servizio unico del pacchetto (`CoworkVMService`) |
| D12 | Aggiornamento di Claude con un profilo aperto | ⚠️ Limite | L'aggiornamento MSIX chiude tutte le istanze ("Windows session ending (close-app)") e riapre solo il principale. Il profilo resta chiuso finché non lo riapri |

## 2. Test dello script (`tests/run-tests.ps1`)

La suite lavora in una cartella temporanea, con un percorso che contiene spazi e "è", e crea i collegamenti in una cartella finta.

| Area | Casi | PS 7.7 | PS 5.1 |
|---|---|---|---|
| Validazione nomi | maiuscole, `../x`, spazi, `claude`, `claude-x`, `con`, `-x`, 41 caratteri | ✅ | ✅ |
| `add` | marcatore, cartella `claude-code`, avviatore UTF-16 con BOM, icona, 2 collegamenti con destinazione, argomenti e icona corretti, istruzioni di accesso | ✅ | ✅ |
| `add` duplicato | rifiutato | ✅ | ✅ |
| `list` | stato chiuso/aperto, scheda Code, gestito | ✅ | ✅ |
| `repair` | cambio nome visualizzato (vecchi collegamenti rimossi), `createdAt` conservato, adozione di una cartella creata a mano, opzioni conservate | ✅ | ✅ |
| `-SharedClaudeCode`, `-StartWithWindows`, `-NoDesktopShortcut` | file flag, collegamenti giusti | ✅ | ✅ |
| `remove` | collegamenti rimossi e dati conservati; `-DeleteData` cancella; rifiuta cartelle senza marcatore e le lascia intatte | ✅ | ✅ |
| Avvio reale (`-Launch`) | Claude avviato con la cartella giusta, `list` lo vede aperto, `remove` rifiutato mentre è aperto, chiusura dei soli processi di test | ✅ | — |

Durante tutti i test, il Claude principale e il profilo reale sono rimasti aperti e intatti.

## 3. Bug trovati durante lo sviluppo

| Bug | Correzione |
|---|---|
| L'icona del collegamento puntava alla cartella versionata di Claude in `WindowsApps` e si rompeva all'aggiornamento | L'icona viene copiata nella cartella dei profili |
| La scheda Code di un profilo usava `~/.claude` dell'account principale | L'avviatore imposta `CLAUDE_CONFIG_DIR` per profilo |
| Con il Desktop reindirizzato su OneDrive, `%USERPROFILE%\Desktop` non esiste | Percorsi ricavati con `[Environment]::GetFolderPath()` |
| `list` scriveva direttamente sullo schermo e non si poteva filtrare | Restituisce oggetti PowerShell |
| Il rilevamento dei processi interpretava male i percorsi tra virgolette con spazi | Espressione regolare separata per percorsi tra virgolette e senza |

## 4. Da verificare

- Escludere il `CLAUDE.md` della cartella utente con l'impostazione `claudeMdExcludes` nel `settings.json` del profilo, per i progetti dentro la cartella utente.
- D10, D11: Claude in Chrome e Cowork con più istanze aperte.
- Installazione classica da claude.ai/download (Squirrel, `%LOCALAPPDATA%\AnthropicClaude`).
- Windows 10.

## Note per chi testa

- **Non chiudere a forza il Claude principale:** se usi Claude Code dentro Claude Desktop, la sessione vive lì.
- **Per chiudere solo un profilo,** filtra i processi per riga di comando con `Get-CimInstance Win32_Process` e un `CommandLine` che contiene la cartella del profilo.
