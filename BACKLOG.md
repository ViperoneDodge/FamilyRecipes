# Backlog

Cose da sistemare nelle prossime release.

## Versione 1.1.0

Pubblicata l'8 ottobre 2026:

- [x] Tolta la scheda **Indice** (doppione di "Le mie"): restano "Le mie" e "Gruppi".
- [x] **Linguette per categoria in stile rubrica**, su due righe, in cima alle ricette (anche nel
  ricettario dei gruppi), con il numero di ricette per categoria.
- [x] **Nuova icona dell'app** (pentola con la famiglia) e **nuova schermata di avvio** su fondo crema
  con il logo; icona delle notifiche e splash Android aggiornati.
- [x] **Logo corretto**: "recipes" al posto di "recips" (stesse lettere del disegno). Il logo sorgente è
  `tool/branding/logo_source.png`; icone e logo si rigenerano con `python3 tool/make_icons.py tool/branding/logo_source.png .`
- [x] **Impostazione linguette** (Impostazioni → Aspetto → Linguette delle categorie): *In alto* (due
  righe), *A destra* (verticali sul bordo del foglio, testo ruotato: comodo su tablet e schermi larghi)
  oppure *Nessuna* (la categoria si sceglie da un menu sopra l'elenco).
- [x] **Rotazione bloccata sui telefoni**: su schermi con lato corto sotto i 600 dp l'app resta sempre
  verticale; tablet e pieghevoli aperti continuano a ruotare (si ricontrolla quando il pieghevole si
  apre o si chiude).

- [x] **Schermata di avvio impaginata male** (segnalato su 1.0.2, Android): lo sfondo sfumato
  e il contenuto occupano solo la parte sinistra dello schermo (circa 3/4); a destra resta il
  colore pieno. Causa: in `lib/screens/intro_screen.dart` il `Container` con la sfumatura non ha
  larghezza, quindi prende quella della `Column` (il testo più largo) invece di tutto lo schermo.
  Correzione: dare al `Container` `width: double.infinity` (o `SizedBox.expand`) e alla `Column`
  `crossAxisAlignment: CrossAxisAlignment.center` su tutta la larghezza. Da ricontrollare anche
  il contrasto di titolo e sottotitolo e la visibilità del vapore sopra la pentola.
  → Risolto con la nuova schermata di avvio a tutto schermo.

## Prossima release

- [ ] **Importazione ricette da file** (per caricare il primo ricettario, ad esempio da OneNote):
  - Impostazioni → *Importa ricette*: si sceglie un file (`.json` o `.zip`) e la destinazione
    (Le mie ricette o un gruppo dove si può modificare); anteprima con l'elenco delle ricette
    trovate e conferma prima di salvare.
  - Formato del file: un elenco di ricette con gli stessi campi dell'app (categoria, titolo,
    presentazione, difficoltà, costo, tempi, dosi, ingredienti con dose, passaggi, consigli) e le
    foto in base64 o come file nello `.zip`; valori mancanti → valori predefiniti modificabili.
  - Le ricette vengono create con l'account di chi importa (nessuna chiave Firebase da condividere)
    e passano per il normale salvataggio: foto ridimensionate, sincronizzazione, avvisi al gruppo.
  - Evitare doppioni: se esiste già una ricetta con lo stesso titolo e categoria nella destinazione,
    chiedere se saltarla o importarla comunque.
  - Conversione da OneNote: esportare le sezioni in Word (.docx) o PDF; Claude trasforma le pagine
    nel file di importazione (una pagina = una ricetta). In seguito si può valutare l'importazione
    diretta di un `.docx` dall'app.
  - Utile anche dopo: esportare un ricettario nello stesso formato per passarlo ad altri o farne
    una copia di sicurezza.

- [ ] **Importare una ricetta da foto o PDF** (lettura automatica, come la lettura del libretto in
  MyFleetManager):
  - Da *Nuova ricetta* → *Leggi da foto o PDF*: si scatta o si sceglie una foto (anche più pagine, per
    esempio il quaderno della nonna o una pagina di libro) oppure un PDF.
  - Lettura del testo **sul telefono** con Google ML Kit Text Recognition (come `registration_reader.dart`
    di MyFleetManager): niente invio a server, funziona anche offline. I PDF vengono prima trasformati in
    immagini pagina per pagina; se il PDF ha già il testo si usa direttamente quello.
  - Riconoscimento delle parti della ricetta: titolo (prima riga in evidenza), ingredienti (righe con
    quantità e unità: g, kg, ml, l, cucchiai, cucchiaini, bicchieri, pizzico, q.b., numeri e frazioni),
    passaggi (righe numerate o paragrafi dopo "Preparazione"/"Procedimento"), tempi e dosi ("per 4
    persone", "cottura 30 minuti"), consigli; categoria proposta dalle parole chiave.
  - Si apre l'editor della ricetta già compilato, da controllare e correggere prima di salvare; la foto
    usata può diventare la foto del piatto o di un passaggio.
  - Funziona insieme all'importazione da file (stessa logica di riconoscimento per i testi da OneNote).
