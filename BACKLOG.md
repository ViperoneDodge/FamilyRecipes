# Backlog

Cose da sistemare nelle prossime release.

## Prossima release

- [ ] **Schermata di avvio impaginata male** (segnalato su 1.0.2, Android): lo sfondo sfumato
  e il contenuto occupano solo la parte sinistra dello schermo (circa 3/4); a destra resta il
  colore pieno. Causa: in `lib/screens/intro_screen.dart` il `Container` con la sfumatura non ha
  larghezza, quindi prende quella della `Column` (il testo più largo) invece di tutto lo schermo.
  Correzione: dare al `Container` `width: double.infinity` (o `SizedBox.expand`) e alla `Column`
  `crossAxisAlignment: CrossAxisAlignment.center` su tutta la larghezza. Da ricontrollare anche
  il contrasto di titolo e sottotitolo e la visibilità del vapore sopra la pentola.

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
