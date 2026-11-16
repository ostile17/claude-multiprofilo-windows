# Portare in un profilo progetti e personalizzazioni del Claude principale

Lo script crea profili **vuoti**. Se vuoi spostare in un profilo il lavoro che hai già nel Claude Code principale (istruzioni, skill, mod, memorie dei progetti, conversazioni, routine), devi farlo a mano.

Questa pagina raccoglie cosa ha funzionato e cosa no in una migrazione reale. La prova è di novembre 2026, con Claude Desktop 5.11492 dal Microsoft Store e Claude Code 2.1.325, spostando una ventina di progetti in un profilo con account Pro. **Non è una procedura supportata da Anthropic**: le strutture interne dell'app possono cambiare a ogni aggiornamento.

Nella pagina:
- `<profilo>` è la cartella del profilo, per esempio `%USERPROFILE%\ClaudeProfili\lavoro`;
- `<config>` è la sua configurazione Claude Code, cioè `<profilo>\claude-config`, dalla 0.3.0.

## Regole d'oro

1. **Backup prima di tutto.** Salva `settings.json` e `.claude.json` di entrambi e le cartelle `memory` dei progetti.
2. **Il profilo deve essere chiuso**, dal menu della sua finestra: ≡ → File → Esci. Per sicurezza aspetta che nel suo `logs\main.log` compaia `willQuit: handler is ready for quit, so quitting`. Con l'app aperta, le schede delle conversazioni e il registro delle routine vengono riletti e riscritti dall'app.
3. **Negli script PowerShell non usare nomi di variabile che differiscono solo per maiuscole** (`$A` e `$a`): sono la stessa variabile. In questa migrazione un errore del genere ha copiato i file delle routine in una cartella sbagliata. Dopo ogni copia verifica i percorsi **assoluti** di destinazione.
4. **Mai scrivere in `<profilo>\claude-code`.** È la cartella dove l'app tiene le versioni di Claude Code, e a ogni avvio cancella tutto il resto che ci trova. La configurazione va in `<config>`.
5. **Non chiudere a forza il Claude principale.** Se usi Claude Code dentro l'app, la sessione da cui lavori gira lì.
6. **Leggi `.claude.json` del principale come hashtable** (`ConvertFrom-Json -AsHashtable`): contiene chiavi che differiscono solo per maiuscole o separatori di percorso.

## Cosa funziona e come

| Cosa | Dove sta nel principale | Come portarlo | Esito |
|---|---|---|---|
| Istruzioni personali | `~\.claude\CLAUDE.md` | Copia in `<config>\CLAUDE.md`. Lascia `claudeMdExcludes`, che lo script imposta, così il file non viene letto due volte | ✅ |
| Impostazioni | `~\.claude\settings.json` | **Unisci**, non sovrascrivere. Tema, plugin abilitati, marketplace e hook si portano. Il modello può non esistere sul piano dell'altro account. Gli hook con percorsi assoluti possono puntare allo stesso script | ✅ |
| Skill | `~\.claude\skills\` | Crea in `<config>\skills\` dei collegamenti (junction) verso la stessa sorgente: si modificano una volta sola. Salta `skills\synced`, che è gestita dall'app | ✅ |
| Plugin e mod | `~\.claude\plugins\` | **Reinstallali** con la riga di comando di Claude Code del profilo e `CLAUDE_CONFIG_DIR=<config>`: `claude plugin marketplace add …` poi `claude plugin install nome@marketplace`. Non copiare la cartella `plugins`: i percorsi di installazione puntano al principale | ✅ |
| Server MCP | `~\.claude.json`, chiave `mcpServers` | Copia le voci che ti servono nel `.claude.json` del profilo. Le intestazioni possono contenere chiavi API | ✅ |
| Memorie dei progetti | `~\.claude\projects\<nome>\memory\` | Copia in `<config>\projects\<nome>\memory\`. `<nome>` è il percorso del progetto con ogni carattere non alfanumerico sostituito da `-` | ✅ |
| Impostazioni dei progetti | `.claude.json`, chiave `projects["<percorso>"]` | Porta `hasTrustDialogAccepted`, `allowedTools`, `enabledMcpjsonServers`, `disabledMcpjsonServers` e `mcpServers`. Il resto è cache o statistiche | ✅ |
| Chiavi SSH | `%USERPROFILE%\.ssh` | Nessuna azione: sono dell'utente Windows e valgono per tutte le istanze | ✅ |
| File di progetto | `CLAUDE.md`, `.claude\`, `.mcp.json` nella cartella del progetto | Nessuna azione: stanno nel progetto e valgono per tutte le istanze | ✅ |
| Conversazioni della scheda Code | Vedi sotto | Vedi sotto | ✅ con avvisi |
| Routine pianificate | Vedi sotto | Vedi sotto | ✅ con avvisi |
| Claude in Chrome | Estensione nel profilo Chrome principale | Secondo profilo di Chrome, vedi sotto | ✅ |

### Plugin: due dettagli

- `claude plugin marketplace add` rifiuta un marketplace se la sorgente non è **scritta esattamente** come in `extraKnownMarketplaces` del `settings.json`. Per GitHub usa l'URL completo, per esempio `https://github.com/<owner>/<repo>.git`, e non la forma breve `owner/repo`.
- Un marketplace di tipo `directory` (per esempio le tue mod) può puntare alla stessa cartella del principale. Ogni istanza però installa una **sua copia**: quando modifichi una mod, aggiornala in tutte e due.

### Conversazioni della scheda Code

Ogni conversazione è fatta di due parti:
- **la scheda della barra laterale:** `<profilo>\claude-code-sessions\<account>\<organizzazione>\local_<id>.json`. Nel principale è sotto `%LOCALAPPDATA%\Claude-Data\…\claude-code-sessions\…`;
- **la trascrizione:** `<config>\projects\<nome>\<id>.jsonl`, più l'eventuale cartella `<id>\`. Gli `<id>` sono `cliSessionId` e `lastAssistantCliSessionId` della scheda.

Copiando entrambe, a profilo chiuso, la conversazione compare nella barra laterale e si riprende da dove era rimasta. Dalla scheda togli i campi legati all'account d'origine:
- `enabledMcpTools`, `remoteMcpServersConfig`, `cliMcpAppServerNames`;
- `envScopeId`, `startedFromEnvironmentId`;
- `toolSurfaceSnapshot`, `promptAppendSnapshot`, `spawnSeed`.

Gli avvisi:
- **Il "thinking" non passa.** Riprendendo una conversazione compare *"Claude can't use thinking from another organization"*. Il testo c'è tutto, ma i ragionamenti interni salvati appartengono all'organizzazione d'origine: la prima risposta rilegge la conversazione ed è più lenta.
- **Lo stato archiviato si conserva** (`isArchived`).
- **Alcune schede non hanno più la trascrizione**, di solito esecuzioni vecchie di routine: non c'è niente da copiare.
- **Le conversazioni ancora aperte vanno escluse.** Per esempio quella da cui stai facendo la migrazione.
- **Dimensioni:** le trascrizioni possono pesare centinaia di MB l'una.

### Routine pianificate

Anche una routine ha due parti:
- **il testo:** `<config>\scheduled-tasks\<id>\SKILL.md`;
- **orario e stato:** il registro `<profilo>\claude-code-sessions\<account>\<organizzazione>\scheduled-tasks.json`, nell'array `scheduledTasks`.

Copia la voce dal registro del principale e cambia `filePath` con il nuovo percorso **assoluto** del `SKILL.md`. Nella prova l'app cercava comunque il file in `<config>\scheduled-tasks\<id>\SKILL.md`, ma è meglio che il registro sia coerente. Togli `notifySessionId`, che punta a una sessione dell'altra istanza. I permessi già approvati (`approvedPermissions`) si possono tenere. Mantieni il formato delle date: in PowerShell 7 usa `ConvertFrom-Json -DateKind String`.

Poi togli la routine dal principale con l'app, o con lo strumento `delete_scheduled_task`: il `SKILL.md` resta sul disco e lo puoi spostare in un backup.

Gli avvisi:
- **Le routine una tantum già eseguite** non compaiono nell'elenco dell'app, nemmeno con tutti i filtri su "Tutto". Restano nel registro, però, e se le riprogrammi con una data futura ricompaiono.
- **Se il `SKILL.md` manca,** l'app scrive nel log `task file not found` e salta la routine, ma nell'elenco la routine compare lo stesso, senza descrizione. Se vedi routine senza descrizione, controlla i file.
- **Le routine girano solo con l'istanza aperta.** Se il profilo è chiuso all'ora prevista, la routine parte alla prima apertura.
- **Una routine che usa Claude in Chrome** ha bisogno del browser abbinato all'account del profilo, come spiegato qui sotto.

### Claude in Chrome per un profilo

L'estensione Chrome si abbina a **un solo account claude.ai**. Per usarla anche da un profilo con un altro account:
1. In Chrome crea un nuovo profilo **senza sincronizzazione**: Aggiungi → *Continua senza account*. Chrome non permette di sincronizzare lo stesso account Google in due profili, ma puoi **accedere ai siti** con quell'account anche dal profilo nuovo, per esempio a Search Console.
2. In quel profilo di Chrome entra in claude.ai con l'account del profilo Claude e installa l'estensione da `https://claude.ai/chrome`.

Risultato verificato: ogni istanza vede il **suo** browser, le schede si aprono nel profilo Chrome giusto, e l'istanza principale continua a vedere il Chrome di sempre.

## Ripulire il principale dopo la migrazione

- **Le sessioni:** eliminale o archiviale dall'app, o con gli strumenti di gestione delle sessioni di Claude Code (`archive_session`, `delete_session`). `delete_session` chiede conferma per gruppi di 25. È più sicuro che toccare i file con l'app aperta.
- **Le memorie dei progetti spostati:** toglile dal principale solo dopo aver verificato che ogni file sia identico, per contenuto, nel profilo e nel backup.
- **Le trascrizioni rimaste su disco,** per esempio vecchie sessioni da riga di comando: spostale in un backup invece di cancellarle.
- **Il `.claude.json` del principale:** le sue voci di progetto si possono lasciare. Sono innocue, e il file viene riscritto di continuo dalle sessioni aperte.
