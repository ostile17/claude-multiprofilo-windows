# Claude multiprofilo per Windows

Più account di **Claude Desktop** aperti **insieme** su Windows, ognuno con il suo accesso, abbonamento, chat, impostazioni e connettori. Per esempio, un account personale e uno di lavoro, senza uscire da uno per entrare nell'altro.

Un solo script PowerShell, senza installazioni e senza dipendenze. Non modifica l'app di Claude e non tocca il profilo che usi già.

> Progetto indipendente, non affiliato ad Anthropic. Si appoggia a un'opzione standard di Electron (`--user-data-dir`): un aggiornamento futuro di Claude Desktop potrebbe cambiarne il comportamento.

---

## Come funziona

Claude Desktop tiene tutto (accesso, chat, impostazioni, connettori) in una cartella dati. Lo script crea per ogni profilo una cartella separata e un collegamento che avvia Claude con quella cartella. Due cartelle diverse danno due istanze indipendenti, che possono restare aperte insieme.

```
%USERPROFILE%\ClaudeProfili\
├── avvia-profilo.vbs       avviatore (nessuna finestra di console)
├── claude.ico              icona copiata dall'app
├── lavoro\                 cartella dati del profilo "lavoro"
│   ├── profilo.json        marcatore: lo script tocca solo cartelle che lo contengono
│   ├── claude-config\      configurazione di Claude Code per la scheda Code del profilo
│   └── claude-code\        versioni di Claude Code scaricate dall'app (gestita dall'app, non toccare)
└── cliente-rossi\
```

Il Claude che usi già resta com'è e continua ad aprirsi dalla sua icona di sempre.

## Requisiti

- Windows 10 o 11.
- Claude Desktop installato. È testato con la versione del **Microsoft Store**; quella scaricata da claude.ai/download dovrebbe funzionare ma non è ancora testata (vedi [Limiti](#limiti)).
- PowerShell 5.1, già presente in Windows, oppure PowerShell 7.

## Installazione

1. Scarica la repo (pulsante **Code → Download ZIP**) ed estraila dove vuoi.
2. Apri PowerShell nella cartella estratta e sblocca lo script, che Windows marca come scaricato da Internet:

   ```powershell
   Unblock-File .\ClaudeProfile.ps1
   ```
3. Crea il primo profilo aggiuntivo:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\ClaudeProfile.ps1 add lavoro
   ```

Sul Desktop e nel menu Start compare **Claude (lavoro)**.

## Primo accesso: leggi prima di entrare

Windows consegna sempre i link `claude://` al Claude principale. Per entrare nel nuovo profilo **non** usare i metodi che passano dal browser:

1. Apri **Claude (lavoro)** e scegli **Continua con email**.
2. **Non cliccare** il link che ricevi per email. Fai clic destro sul pulsante → **Copia indirizzo link**.
3. Apri una finestra **in incognito** (Ctrl+Maiusc+N), incolla il link e premi Invio.
4. Se il browser chiede di aprire Claude, scegli **Annulla**.
5. La pagina mostra un **codice di verifica**: scrivilo nella finestra del profilo e conferma.

Evita **Accedi con Google**: il ritorno all'app finirebbe nel Claude principale. Il codice via email funziona anche con gli account Google.

Dopo il primo accesso, il profilo resta collegato anche dopo la chiusura e il riavvio del PC.

## Comandi

```powershell
.\ClaudeProfile.ps1 add <nome>        # crea un profilo
.\ClaudeProfile.ps1 list              # elenca i profili e dice quali sono aperti
.\ClaudeProfile.ps1 start <nome>      # apre un profilo
.\ClaudeProfile.ps1 repair <nome>     # ricrea avviatore, icona e collegamenti; adotta cartelle create a mano
.\ClaudeProfile.ps1 remove <nome>     # toglie i collegamenti, conserva i dati
.\ClaudeProfile.ps1 remove <nome> -DeleteData   # cancella anche i dati (chiede di scrivere il nome per conferma)
```

| Opzione | Effetto |
|---|---|
| `-DisplayName "Cliente Rossi"` | Nome nei collegamenti: "Claude (Cliente Rossi)" |
| `-NoDesktopShortcut` | Solo menu Start, niente icona sul Desktop |
| `-StartWithWindows` | Apre il profilo all'accensione del PC |
| `-GitHubUser <login>` | `gh`, e quindi anche `git push` e `pull` su github.com, usa solo questo account GitHub nel profilo. Vedi [GitHub e git per profilo](#github-e-git-per-profilo) |
| `-GitName "Nome" -GitEmail email` | Identità dei commit fatti dal profilo |
| `-SharedClaudeCode` | La scheda Code del profilo usa la configurazione Claude Code principale (`~/.claude`) invece di una propria |
| `-Root <cartella>` | Dove tenere i profili (predefinito `%USERPROFILE%\ClaudeProfili`) |
| `-Force` | Nessuna domanda di conferma (per script) |

Nomi dei profili: lettere minuscole, cifre e trattini, fino a 40 caratteri.

## Uso quotidiano

- **Apri ogni profilo dal suo collegamento.** Un secondo clic sul collegamento di un profilo già aperto riporta in primo piano la sua finestra.
- **Per chiudere un profilo usa il menu della sua finestra: ≡ → File → Esci.** Le icone accanto all'orologio sono tutte uguali, e rischieresti di chiudere il Claude principale.
- **Dopo un aggiornamento di Claude**, riapri i profili dai loro collegamenti (vedi sotto).

## Limiti

| Limite | Cosa comporta |
|---|---|
| **Gli aggiornamenti chiudono tutti i profili** | Windows chiude ogni istanza del pacchetto per installare l'aggiornamento e riapre solo il Claude principale. I profili vanno riaperti a mano; le loro sessioni in corso vengono interrotte. I riavvii decisi dall'app stessa, invece, mantengono il profilo e la separazione della scheda Code. |
| **I link `claude://` vanno al Claude principale** | Per questo l'accesso si fa con il codice (vedi sopra). Vale anche per altri link che aprono l'app dal browser. |
| **Le finestre non si distinguono** | Si chiamano tutte "Claude" e hanno la stessa icona. Puoi fissare i collegamenti dei profili sulla barra delle applicazioni. |
| **Claude in Chrome** | L'estensione si abbina a un solo account claude.ai, quello con cui è entrata in Chrome. Per usarla anche da un profilo, crea un **secondo profilo di Chrome senza sincronizzazione** con l'estensione abbinata all'account del profilo. Testato: ogni istanza vede il suo browser e le schede si aprono nel profilo Chrome giusto. Dettagli in [docs/MIGRAZIONE.md](docs/MIGRAZIONE.md#claude-in-chrome-per-un-profilo). |
| **Cowork** | Da settembre 2026 Cowork è integrato nella chat: non c'è più un pulsante dedicato. Nei test, due chat avviate quasi insieme hanno creato ciascuna il proprio file sul disco, e ogni istanza ha salvato la sessione nella propria cartella. Il servizio di sistema (`CoworkVMService`) è uno solo per tutte le istanze. |
| **Spazio su disco** | Ogni profilo scarica la propria macchina virtuale per le attività locali (circa 9 GB in `vm_bundles`) e i propri file di Claude Code. Conta circa 10 GB per ogni profilo che usa queste funzioni. |
| **Isolamento per cartelle, non sandbox** | Ogni programma che gira con il tuo utente Windows può leggere le cartelle di tutti i profili. |
| **Installazione da claude.ai/download** | Supportata nel codice (`%LOCALAPPDATA%\AnthropicClaude\claude.exe`) ma non ancora testata. |

## Scheda Code

`--user-data-dir` separa solo i dati di Claude Desktop. Le sessioni della scheda **Code** leggerebbero comunque la configurazione principale di Claude Code (`~/.claude`: CLAUDE.md, impostazioni, skill, memoria). Per evitarlo, l'avviatore imposta `CLAUDE_CONFIG_DIR` sulla cartella `claude-config` del profilo.

> **Aggiorna se hai la 0.1 o la 0.2.** Fino alla 0.2.0 la configurazione stava in `<profilo>\claude-code`. Quella cartella però è dell'app: ci tiene le versioni di Claude Code e a ogni avvio cancella tutto il resto che trova lì dentro, compresi memorie, skill e plugin del profilo. Dalla 0.3.0 la configurazione sta in `claude-config`. Con `.\ClaudeProfile.ps1 repair <nome>`, a profilo chiuso, lo script la sposta e lascia all'app le sue versioni.

È verificato con un account Pro: sessioni, cronologia, progetti e memoria della scheda Code finiscono nella cartella del profilo, e la configurazione principale non viene toccata.

**Progetti dentro la cartella utente.** Claude Code legge anche i `CLAUDE.md` e i `.claude\CLAUDE.md` di tutte le cartelle superiori al progetto. Per un progetto dentro `C:\Users\<tu>\`, una di queste è la cartella utente, il cui `.claude\CLAUDE.md` contiene le istruzioni personali del Claude Code principale. Senza correzioni il profilo le leggerebbe come istruzione di progetto.

Per questo lo script scrive nel `settings.json` del profilo l'impostazione `claudeMdExcludes`, che esclude solo quel file:
- le altre impostazioni e le esclusioni già presenti restano;
- un `settings.json` illeggibile non viene toccato;
- i CLAUDE.md dei progetti continuano a essere letti normalmente.

Verificato con un progetto in `C:\Users\<tu>\prova`: senza l'impostazione vedeva le istruzioni personali, con l'impostazione no. Con `-SharedClaudeCode` l'impostazione non viene scritta.

Altre due note sulla scheda Code nei profili:
- **Primo accesso alla scheda Code:** la prima volta può chiedere di nuovo l'accesso all'account, perché il server considera troppo vecchio quello iniziale (`session_stale_relogin` nei log). Rifallo con il codice da browser in incognito, come al primo accesso.
- **Spazio su disco:** l'app scarica i file di Claude Code nella cartella `claude-code` del profilo, che gestisce da sola.

Se vuoi che un profilo condivida la configurazione principale, crealo con `-SharedClaudeCode`.

## GitHub e git per profilo

Senza opzioni, tutte le istanze condividono la stessa identità GitHub:
- `gh` ha **un solo account attivo** per l'utente Windows;
- git usa `gh`, o il gestore credenziali, per accedere a github.com;
- l'identità dei commit è quella globale di git.

Se ogni account Claude lavora con un account GitHub diverso, il profilo può averne uno suo:

```powershell
.\ClaudeProfile.ps1 repair lavoro -GitHubUser mio-utente -GitName "Mio Nome" -GitEmail me@example.com
```

**Cosa fa:**
- crea `<profilo>\gh\hosts.yml`, che dice a `gh` quale account usare nel profilo. **Non contiene token**: il token resta nel Gestore credenziali di Windows, dove `gh` lo ha salvato;
- crea `<profilo>\gitconfig`, che riprende la tua configurazione git globale (credenziali, alias, impostazioni) e cambia solo l'identità dei commit;
- fa impostare all'avviatore `GH_CONFIG_DIR` e `GIT_CONFIG_GLOBAL`, che valgono per le sessioni Code del profilo. Valgono dal prossimo avvio del profilo.

**Prerequisito:** l'account deve aver fatto almeno una volta l'accesso a `gh` su questo PC. Se non l'ha fatto:

```powershell
$env:GH_CONFIG_DIR = "$env:USERPROFILE\ClaudeProfili\lavoro\gh"; gh auth login --hostname github.com --web
```

Se il browser predefinito è entrato su GitHub con un altro account, **non premere Invio** quando `gh` mostra il codice. Apri `https://github.com/login/device` nel profilo Chrome dove sei entrato con l'account giusto e inserisci lì il codice.

**Verificato:** con l'ambiente del profilo `gh` risponde con il suo account e un `git push --dry-run` su una repo di quell'account è autorizzato. Con l'ambiente principale lo stesso push è negato.

## Portare in un profilo il lavoro che hai già

Lo script crea profili vuoti. Se vuoi spostare in un profilo istruzioni, skill, mod, memorie dei progetti, conversazioni e routine del Claude principale, devi farlo a mano. La guida [docs/MIGRAZIONE.md](docs/MIGRAZIONE.md) racconta una migrazione reale: cosa ha funzionato, cosa no e quali trappole evitare.

## Disinstallazione

```powershell
.\ClaudeProfile.ps1 remove lavoro -DeleteData
```

Ripeti per ogni profilo, poi cancella la cartella `%USERPROFILE%\ClaudeProfili`. Il Claude principale non viene toccato.

## Sicurezza

Lo script:
- non usa la rete;
- non richiede privilegi di amministratore;
- non legge credenziali;
- non modifica il registro di sistema.

Scrive solo:
- dentro la cartella dei profili;
- nei collegamenti su Desktop, menu Start ed Esecuzione automatica.

Cancella soltanto:
- collegamenti che ha creato lui;
- cartelle che contengono il suo `profilo.json`, e solo con `-DeleteData` più la conferma scritta.

Dettagli in [SECURITY.md](SECURITY.md).

## Test

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\run-tests.ps1 -Script .\ClaudeProfile.ps1 -Base $env:TEMP\cmp-test
```

La suite usa una cartella temporanea e collegamenti finti, quindi non tocca Desktop né profili reali. Con `-Launch` apre e richiude anche un'istanza di prova di Claude. Report completo in [docs/TEST-REPORT.md](docs/TEST-REPORT.md).

## Crediti

Idea ispirata a [claude-multiprofile](https://github.com/jmdarre-v/claude-multiprofile), che fa la stessa cosa su macOS. Questo progetto è una reimplementazione indipendente per Windows.

## Licenza

MIT, vedi [LICENSE](LICENSE).
