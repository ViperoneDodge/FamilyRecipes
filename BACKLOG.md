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
