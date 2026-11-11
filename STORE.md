# Pubblicazione su Google Play e App Store

Guida per la prima uscita sugli store. Le immagini sono in `store/` (rigenerabili con
`tool/make_store_assets.py`), le build arrivano da GitHub Actions.

- **Android**: workflow *Compila APK Android* (a ogni push su `main`). Con la chiave di caricamento nei
  Secrets crea anche il file `.aab` per Google Play, allegato alla Release.
- **iPhone**: workflow *Compila app iPhone* (si avvia a mano da GitHub → Actions). Senza chiavi controlla
  che l'app compili; con le chiavi di App Store Connect la firma e la carica su TestFlight. Non serve un Mac.

Identificativo dell'app su entrambi gli store: **`it.familyrecipes.familyrecipes`** (non si può più cambiare
dopo la pubblicazione).

---

## 1. Google Play

### Una volta sola
1. **Account sviluppatore** su <https://play.google.com/console> (25 $ una tantum, verifica dell'identità).
   Con un account *personale* creato dopo novembre 2023, Google chiede un **test chiuso con almeno
   12 tester per 14 giorni di fila** prima di poter pubblicare in produzione: la famiglia va benissimo.
2. **Chiave di caricamento** (sul tuo PC, con Java installato):
   ```
   keytool -genkeypair -v -keystore upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
   ```
   Conserva `upload.jks` e le password in un posto sicuro (se le perdi si chiede a Google un reset).
3. **Secrets su GitHub** (repository → Settings → Secrets and variables → Actions → New repository secret):
   - `UPLOAD_KEYSTORE_B64` = il file in base64 (`base64 -w0 upload.jks` su Linux,
     `certutil -encode upload.jks out.txt` su Windows e poi il contenuto senza le righe BEGIN/END)
   - `UPLOAD_STORE_PASSWORD`, `UPLOAD_KEY_PASSWORD` = le password scelte
   - `UPLOAD_KEY_ALIAS` = `upload`

   Da lì ogni build su `main` produce anche `FamilyRecipes-vX.Y.Z.aab` nella Release.
4. **Crea l'app** nella Play Console: nome *FamilyRecipes – Ricettario*, lingua predefinita italiano,
   app gratuita. *Firma dell'app di Google Play* resta attiva (consigliato).
5. **Accesso con Google dall'app scaricata dal Play Store**: dopo il primo caricamento vai in
   *Test e rilascio → Integrità dell'app → Firma dell'app* e copia lo **SHA-1** della *chiave di firma
   dell'app* e della *chiave di caricamento*. Aggiungili in Firebase → Impostazioni progetto → app Android →
   *Aggiungi impronta digitale*, poi riscarica `google-services.json` e mandamelo. Senza questo passo
   l'accesso con Google non funziona nell'app del Play Store (funziona invece nell'APK di prova).
6. **Scheda dello store** (*Crescita → Presenza nello store → Scheda principale*): testi qui sotto,
   icona `store/icon-512.png`, grafica `store/feature-graphic.png`, screenshot `store/android/it/` (e `en/`).
7. **Contenuti dell'app** (*Monitora e migliora → Norme → Contenuti dell'app*): risposte qui sotto.

### Ogni versione
1. Push su `main` (lo faccio io) → scarica il file `.aab` dalla Release su GitHub.
2. Play Console → *Test → Test chiuso* (o *Produzione*) → *Crea nuova release* → carica l'`.aab` → note di
   rilascio → *Revisiona e avvia*.

> L'APK firmato con la chiave di prova (quello che usate ora) e l'app del Play Store hanno firme diverse:
> per passare al Play Store bisogna disinstallare l'APK. Le ricette online restano nell'account.

---

## 2. App Store (iPhone)

### Una volta sola
1. **Apple Developer Program** su <https://developer.apple.com/programs/> (99 € all'anno).
2. **Identificativo dell'app**: developer.apple.com → *Certificates, Identifiers & Profiles → Identifiers*
   → **+** → *App IDs* → *App* → Bundle ID esplicito `it.familyrecipes.familyrecipes`, e spunta
   **Push Notifications** e **Sign In with Apple**.
3. **Firebase**:
   - Impostazioni progetto → *Aggiungi app* → **iOS**, bundle ID `it.familyrecipes.familyrecipes`.
     Dal file `GoogleService-Info.plist` mandami **GOOGLE_APP_ID** e **CLIENT_ID** (li metto io in
     `lib/firebase_config.dart`: servono a Firebase e all'accesso con Google su iPhone).
   - Authentication → *Sign-in method* → **Apple** → Abilita (per l'app iPhone non serve altro).
   - Notifiche: developer.apple.com → *Keys* → **+** → spunta *Apple Push Notifications service (APNs)* →
     scarica il file `.p8`; poi Firebase → Impostazioni progetto → *Cloud Messaging* → app iOS →
     *Chiave di autenticazione APNs* → carica il `.p8` con Key ID e Team ID.
4. **Chiave per GitHub** (firma e caricamento automatici, senza Mac): App Store Connect → *Utenti e accessi →
   Integrazioni → App Store Connect API* → *Chiavi del team* → **+**, ruolo **Admin** → scarica il `.p8`
   (si scarica una volta sola). Secrets su GitHub:
   - `APPSTORE_KEY_ID` = ID chiave, `APPSTORE_ISSUER_ID` = Issuer ID (in cima alla pagina)
   - `APPSTORE_KEY_P8` = tutto il contenuto del file `.p8` (righe BEGIN/END comprese)
   - `APPLE_TEAM_ID` = Team ID (developer.apple.com → *Membership*)
5. **Crea l'app** in App Store Connect → *App* → **+** → *Nuova app*: iOS, nome *FamilyRecipes – Ricettario*,
   lingua principale italiano, bundle ID `it.familyrecipes.familyrecipes`, SKU `familyrecipes`.
6. **Scheda**: testi qui sotto, screenshot `store/ios/it/` (iPhone 6,9"/6,7"; vanno bene 1290×2796),
   categoria *Cibi e bevande*, URL privacy e assistenza qui sotto, *Privacy dell'app* con le risposte qui sotto.

### Ogni versione
1. GitHub → *Actions → Compila app iPhone → Run workflow* (o chiedimelo). Dopo 20–30 minuti la build
   compare in App Store Connect → TestFlight.
2. TestFlight: aggiungi i familiari come tester (fino a 100 interni, o esterni con link).
3. Per l'App Store: nella versione scegli la build, compila le *Note per la revisione* (sotto) e *Invia per
   la revisione*.

---

## 3. Testi delle schede

**URL informativa privacy**: <https://viperonedodge.github.io/FamilyRecipes/privacy.html>
**URL cancellazione account (Google Play)**: <https://viperonedodge.github.io/FamilyRecipes/privacy.html#delete>
**URL assistenza (App Store)**: <https://viperonedodge.github.io/FamilyRecipes/privacy.html>
**Email di contatto**: appmyfleetmanager@gmail.com
**Categoria**: Cibi e bevande / Food & Drink · **Prezzo**: gratuita · **Pubblicità**: no

### Italiano
- **Nome** (max 30): FamilyRecipes – Ricettario
- **Sottotitolo App Store** (max 30): Le ricette di casa, insieme
- **Descrizione breve Google Play** (max 80): Il ricettario di famiglia: scrivi, fotografa e condividi le ricette di casa.
- **Parole chiave App Store** (max 100): ricette,ricettario,cucina,famiglia,quaderno,ingredienti,dosi,menù,dolci,preferiti,gruppi,PDF
- **Testo promozionale App Store** (max 170): Le ricette della nonna, al sicuro e condivise con tutta la famiglia. Leggile da foto, PDF o link e sfogliale come un vero quaderno.
- **Descrizione**:

```
FamilyRecipes è il ricettario di famiglia: un quaderno degli appunti in cui raccogliere le ricette di casa,
da scrivere e sfogliare insieme.

SCRIVI LE TUE RICETTE
• Scheda completa: foto del piatto, presentazione, difficoltà, costo, tempi, dosi per persona
• Ingredienti con le quantità e passaggi numerati, ognuno con le sue foto
• Categorie: aperitivi, antipasti, primi, secondi, contorni, dolci, liquori, conserve e menù completi
• Dosi ricalcolate per il numero di persone che vuoi

NON RISCRIVERE NIENTE
• Fotografa una ricetta dal quaderno o da un libro, o apri un PDF: l'app legge il testo e la compila per te
• Incolla il link di un sito di ricette, inquadra un QR o usa «Condividi» dal browser: la ricetta arriva
  con ingredienti, passaggi e foto, senza pubblicità
• Importa un intero ricettario da file

IN FAMIGLIA
• Crea un gruppo e invita parenti e amici con un codice o un QR
• Ruoli: amministratore, può modificare, solo lettura
• Un avviso quando qualcuno aggiunge o modifica una ricetta

E POI
• Preferiti come pagina iniziale
• Sfoglia le ricette con un gesto, come le pagine di un quaderno
• Schermo sempre acceso mentre cucini
• «Suggerimento dello chef»: un'idea dal tuo ricettario, con quello che hai in frigo o da internet
• PDF di una ricetta o di tutto il ricettario, con indice
• Funziona anche senza internet: tutto è salvato sul telefono e si sincronizza quando torna la rete
• 36 lingue, tema chiaro e scuro, colori e fogli a scelta

Nessuna pubblicità, nessuna profilazione.
```

### English
- **Name**: FamilyRecipes – Recipe Book
- **App Store subtitle**: Your family recipes, together
- **Google Play short description**: Your family recipe book: write, photograph and share the recipes you love.
- **App Store keywords**: recipes,cookbook,recipe book,family,cooking,ingredients,meal,menu,dessert,favourites,groups,PDF
- **App Store promotional text**: Grandma's recipes, safe and shared with the whole family. Import them from photos, PDFs or links and flip through them like a real notebook.
- **Description**:

```
FamilyRecipes is your family recipe book: a notebook to collect the recipes you grew up with,
written and browsed together.

WRITE YOUR RECIPES
• Full recipe card: dish photo, introduction, difficulty, cost, times, servings
• Ingredients with quantities and numbered steps, each with its own photos
• Categories: aperitifs, starters, first courses, main courses, sides, desserts, liqueurs, preserves
  and full menus
• Quantities recalculated for any number of people

NO RETYPING
• Photograph a recipe from a notebook or book, or open a PDF: the app reads the text and fills it in
• Paste a recipe website link, scan a QR code or use Share from the browser: the recipe arrives with
  ingredients, steps and photos, without ads
• Import a whole recipe book from a file

WITH YOUR FAMILY
• Create a group and invite relatives and friends with a code or QR
• Roles: admin, can edit, read only
• A notification when someone adds or edits a recipe

AND MORE
• Favourites as your start page
• Flip through recipes with a swipe, like the pages of a notebook
• Screen stays on while you cook
• Chef's suggestion: an idea from your recipe book, from what's in the fridge or from the web
• PDF of a recipe or the whole recipe book, with an index
• Works offline: everything is saved on your phone and syncs when you're back online
• 36 languages, light and dark theme, your choice of colours and paper

No ads, no tracking.
```

### Note di rilascio della prima versione
- IT: Prima versione sugli store: ricettario di famiglia con gruppi, preferiti, lettura da foto, PDF e link.
- EN: First store release: family recipe book with groups, favourites and import from photos, PDFs and links.

---

## 4. Questionari

### Google Play – Sicurezza dei dati
- **Dati raccolti** (tutti per *Funzionalità dell'app* e *Gestione dell'account*, nessuno per pubblicità o
  statistiche; nessuno condiviso con terze parti):
  - Informazioni personali → **Indirizzo email**, **Nome** (obbligatori per l'account online)
  - Foto e video → **Foto** (facoltative: foto delle ricette)
  - Attività nelle app → **Altri contenuti generati dagli utenti** (le ricette)
  - ID dispositivo o altri ID → **ID dispositivo** (token per le notifiche)
- **Crittografia in transito**: sì · **Richiesta di eliminazione**: sì (in app e URL qui sopra)
- I dati dell'account *Solo telefono* non lasciano il telefono.

### Google Play – Altri contenuti
- **Pubblicità**: no · **App per bambini**: no · **Pubblico di destinazione**: 18+ (ci sono ricette di liquori)
- **Accesso all'app**: alcune funzioni richiedono l'accesso → fornisci un **account di prova** (email e
  password di un account online creato apposta, con un gruppo e qualche ricetta).
- **Classificazione dei contenuti** (questionario IARC): categoria *Riferimento, notizie o istruzione* o
  *Altro*; nessuna violenza o contenuto sessuale; **riferimenti all'alcol: sì** (ricette di liquori);
  gli utenti **possono condividere contenuti** solo con i gruppi in cui sono invitati; nessuna posizione
  condivisa, nessun acquisto.
- **App governative / finanziarie / salute**: no.

### App Store – Privacy dell'app
- **Raccolta dati: sì**. Per ognuno: *Funzionalità dell'app*, **collegato all'identità**, **non usato per
  il tracciamento**:
  - Informazioni di contatto → **Nome**, **Indirizzo email**
  - Contenuto utente → **Foto o video**, **Altri contenuti dell'utente**
  - Identificativi → **ID dispositivo** (notifiche)
- **Classificazione per età**: rispondi *Raro/lieve* a *Alcol, tabacco o droghe* (ricette di liquori);
  tutto il resto *Nessuno*.
- **Note per la revisione** (in inglese): account di prova, poi:
  `Sign in with Apple and Google are on the login screen ("Online account"). Account deletion: Settings →
  Support and privacy → Delete account and online data. Groups are private: a group is joined only with
  its invite code or QR.`

---

## 5. Cosa manca su iPhone (rispetto ad Android)
- **Avvisi dei gruppi ad app chiusa**: su Android l'app controlla ogni 15 minuti da sola; iOS non lo
  permette, quindi su iPhone gli avvisi arrivano solo ad app aperta (servirebbe un piccolo servizio su
  Firebase che invii le notifiche push).
- **Condividi → FamilyRecipes** da Safari e il **piano B** per i siti protetti (lettura dal browser
  invisibile) sono solo su Android per ora; su iPhone si incolla il link o si inquadra il QR.
- L'app è solo per **iPhone** (niente iPad, così servono meno schermate): si può aggiungere dopo.
