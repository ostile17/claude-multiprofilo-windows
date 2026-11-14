# Sicurezza

## Cosa fa lo script, e cosa no

| | |
|---|---|
| **Rete** | Nessuna. Lo script e l'avviatore non contattano nessun server. |
| **Privilegi** | Gira con il tuo utente, senza diritti di amministratore. |
| **Credenziali** | Non legge né copia accessi, token o il Portachiavi/Gestione credenziali di Windows. Ogni profilo fa il proprio accesso. |
| **Registro di Windows** | Non lo modifica. |
| **Scritture** | Solo nella cartella dei profili (predefinita `%USERPROFILE%\ClaudeProfili`) e nei collegamenti `Claude (<nome>).lnk` su Desktop, menu Start ed Esecuzione automatica. |
| **Cancellazioni** | Solo i collegamenti elencati nel `profilo.json` del profilo. La cartella dati solo con `remove -DeleteData`, solo se contiene `profilo.json` creato da questo strumento, solo se è dentro la cartella dei profili e solo dopo aver scritto il nome del profilo per conferma. |
| **Profilo aperto** | `remove` rifiuta di agire su un profilo in esecuzione. |
| **App di Claude** | Non viene modificata. Lo script avvia l'app installata con l'opzione `--user-data-dir`. |

## Input e quoting

- I nomi dei profili sono limitati a `[a-z0-9-]`, al massimo 40 caratteri, senza nomi riservati di Windows (`con`, `nul`, `com1`…) né il prefisso `claude-`. Nessun nome può uscire dalla cartella dei profili.
- L'avviatore VBScript ricontrolla il nome con la stessa regola prima di usarlo e avvia Claude solo dai due percorsi noti:
  - `%LOCALAPPDATA%\Microsoft\WindowsApps\claude-desktop.exe` (alias del Microsoft Store);
  - `%LOCALAPPDATA%\AnthropicClaude\claude.exe` (installazione classica).

## Isolamento: cosa aspettarsi

I profili sono separati per **cartelle**, non da un sandbox. Qualsiasi programma che gira con il tuo utente può leggere le cartelle di tutti i profili, come può già leggere quella del Claude principale.

Rischi noti, descritti nel README:
- i link `claude://` vengono consegnati al Claude principale;
- Claude in Chrome e Cowork usano componenti condivisi tra le istanze.

## Segnalare un problema

Per un problema di sicurezza (per esempio un profilo che vede i dati di un altro, o lo script che scrive fuori dai percorsi indicati) usa **Security → Report a vulnerability** su GitHub invece di aprire una issue pubblica.

Le vulnerabilità di Claude Desktop vanno segnalate ad Anthropic: https://www.anthropic.com/responsible-disclosure-policy
