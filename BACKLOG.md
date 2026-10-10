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

## Versione 1.2.0

Pubblicata il 9 ottobre 2026:

- [x] **Linguette leggibili in modalità scura**: colori più profondi e testo chiaro (prima quasi invisibili).
- [x] **Nuova scheda "Cosa mangio stasera?"** (in basso, "Stasera"), con tre modi:
  - *Ricettario*: si scelgono le portate (categorie) e qualche filtro (tempo massimo, solo facili,
    da quale ricettario); l'app pesca una ricetta a caso per ogni portata, con "Un'altra" per cambiarla.
  - *Ingredienti*: fino a 3 ingredienti (con suggerimenti da quelli già nel ricettario); ricette del
    ricettario che li usano tutti o in parte, e ricerca anche su internet.
  - *Internet*: una ricetta a sorpresa da TheMealDB (gratuito, in inglese); si legge e si può salvare
    nel ricettario passando dall'editor, con la foto. Ingredienti italiani comuni tradotti in inglese
    per la ricerca. Privacy aggiornata.
- [x] Scheda rinominata **"Suggerimento dello chef"** (su due righe nella barra in basso); il titolo della
  pagina è "Cosa mangio oggi?".
- [x] **Ricette da internet tradotte** nella lingua dell'app, sul telefono, con Google ML Kit Translation
  (gratuito, senza chiavi; la prima volta scarica il pacchetto della lingua, ~30 MB, poi funziona offline).
  Si traducono titolo, categoria, cucina, ingredienti, dosi (abbreviazioni inglesi espanse prima) e
  passaggi; c'è "Mostra originale". **La fonte è sempre in fondo** (TheMealDB, link alla ricetta
  originale, "Tradotta automaticamente dall'inglese") e, salvando, finisce nei consigli della ricetta.
- [x] **Linguette senza numeri**: tolto il conteggio delle ricette da ogni linguetta (in alto e a destra);
  le categorie vuote restano più chiare.

## Versione 1.3.0

- [x] **Nuova ricetta letta da foto o PDF**: *Nuova ricetta* chiede se scriverla a mano, fotografarla
  (anche più pagine, una dopo l'altra), sceglierla dalla galleria o aprire un PDF (prime 6 pagine).
  - Testo letto **sul telefono** con Google ML Kit Text Recognition: niente invio a server, funziona
    offline. I PDF vengono trasformati in immagini pagina per pagina; testo su due colonne riordinato.
  - Riconosciuti titolo, ingredienti con dose (g, kg, ml, cucchiai, pizzico, q.b., frazioni…),
    passaggi (numerati o dopo "Preparazione"/"Procedimento"), dosi, tempi, difficoltà, consigli;
    categoria proposta dalle parole chiave.
  - Si apre l'editor già compilato con un avviso "controlla e correggi" prima di salvare.
- [x] **36 lingue** come MyFleetManager: frasi in comune riprese dall'altra app, frasi nuove (ricette,
  categorie, linguette, suggerimento dello chef, lettura da foto) tradotte in tutte le lingue; menu
  Lingua con tutte le 36 lingue; nel PDF font per cinese, giapponese, coreano, hindi e thai (il font
  a mano dei titoli resta per le lingue con alfabeto latino). Test automatico: ogni lingua ha tutte le
  frasi e gli stessi segnaposto.

## Versione 1.4.0

- [x] **Importazione ricette da file** (per caricare il primo ricettario):
  - Modulo web condiviso **"Ricettario da compilare"** (pagina su claude.ai): si scrivono le ricette anche
    in più persone (categoria, titolo, presentazione, difficoltà, costo, tempi, dosi, ingredienti con dose,
    passaggi, consigli, autore, foto del piatto rimpicciolita); incollando un elenco di ingredienti o un
    testo a paragrafi si divide da solo in righe e passaggi. Con *Scarica il file per l'app* si ottiene
    un `.json` con tutte le ricette e le foto.
  - Nell'app: *Nuova ricetta → Importa un file di ricette* (o Impostazioni → *Importa ricette*): si sceglie
    il file e il ricettario di destinazione (Le mie o un gruppo dove si può modificare); anteprima con le
    ricette trovate, quelle già presenti (stesso titolo e categoria) deselezionate; salvataggio normale
    (foto ridimensionate, sincronizzazione, avvisi al gruppo). Le ricette restano dell'account di chi
    importa, con "Scritta da" il nome indicato nel modulo.
  - Il file accetta anche valori in italiano ("Primi", "Media"…) e un elenco semplice, così si può
    preparare a mano o da OneNote.

## Prossima release

- [ ] Esportare un ricettario nello stesso formato `.json` (per passarlo ad altri o farne una copia di
  sicurezza).

- [ ] **Lettura da foto o PDF, migliorie**: se il PDF contiene già il testo usarlo direttamente
  (più preciso della lettura dall'immagine); proporre la foto letta come foto del piatto; lettura
  della scrittura a mano (ora riconosce bene soprattutto il testo stampato).
