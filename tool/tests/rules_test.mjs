// Tester cattivo — regole Firestore di FamilyRecipes sull'EMULATORE (progetto demo-…), mai sulla produzione.
// Adattato da MyFleetManager (sec_rules_test.mjs, rules_test.mjs, t24x_rules_test.mjs, thack_rules_test.mjs).
//
// Lancio (serve una cartella con @firebase/rules-unit-testing, firebase e firebase-tools in node_modules):
//   cp tool/tests/rules_test.mjs <cartella>/ && cd <cartella>
//   npx firebase emulators:exec --only firestore --project demo-fr "node rules_test.mjs /home/user/FamilyRecipes/firestore.rules"
// Con la correzione proposta:
//   ... "node rules_test.mjs /home/user/FamilyRecipes/tool/tests/firestore_proposta.rules"
//
// «ok»      = flusso vero dell'app (payload presi da lib/services/sync_service.dart): se non riesce è ROTTO.
// «vietato» = attacco: se riesce è un BUCO.
// «limite»  = l'attacco riesce e le regole da sole non bastano (o è una scelta di progetto): segnato, non conta.
import fs from 'fs';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, getDocs, collection, collectionGroup, query, where,
  arrayUnion, arrayRemove, deleteField,
} from 'firebase/firestore';

const rulesPath = process.argv[2] || 'firestore.rules';
const env = await initializeTestEnvironment({
  projectId: 'demo-fr',
  firestore: { rules: fs.readFileSync(rulesPath, 'utf8'), host: '127.0.0.1', port: 8080 },
});

const EMAIL = (u) => `${u}@example.com`;
const db = (uid, extra = {}) => env.authenticatedContext(uid, { email: EMAIL(uid), email_verified: true, ...extra }).firestore();
const anon = env.unauthenticatedContext().firestore();
const asAdmin = (fn) => env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));

const O = 'uidProprietario'; // crea il gruppo G
const AD = 'uidAdmin2';      // admin (non proprietario) di G
const E = 'uidEditor';       // modifica in G
const V = 'uidViewer';       // sola lettura in G
const V2 = 'uidViewer2';     // un altro in sola lettura (vittima della promozione forzata)
const X = 'uidAttaccante';   // utente qualsiasi con il codice invito
const X2 = 'uidComplice';    // secondo account dell'attaccante
const B = 'uidVittimaB';     // utente qualsiasi con il suo ricettario personale
const N = 'uidNuovo';        // account appena creato
const G = 'ABCDEFGH23';      // gruppo «Famiglia» (id come newId(10))
const G2 = 'GRUPPO2345';     // altro gruppo
const ADMIN_APP = 'appmyfleetmanager@gmail.com';

const now = () => Date.now();
// Copia di Recipe.toJson() senza bookId, come SyncService.push (sync_service.dart:293-296).
const recipe = (id, by, over = {}) => ({
  id, category: 'primi', title: 'Lasagne', intro: '', cover: null, difficulty: 'easy', cost: 'low', prep: 10, cook: 20,
  servings: 4, ingredients: [{ name: 'farina', amount: '200 g' }], steps: [{ id: 'S1', text: 'impasta', photos: [] }],
  tips: '', courses: [], updatedAt: now(), updatedBy: by, updatedByUid: by, createdBy: by, createdByName: by,
  createdAt: now(), deleted: false, ...over,
});
const photo = (recipeId, b64 = 'QUJD') => ({ b64, recipeId, createdAt: now() });
// Come SyncService.createGroup / ensurePersonal / joinGroup / leaveGroup / removeMember / setRole.
const groupDoc = (owner, name = 'Famiglia') => ({
  personal: false, name, ownerUid: owner, members: [owner], memberEmails: { [owner]: EMAIL(owner) },
  admins: [owner], viewers: [], createdAt: now(),
});
const personalDoc = (uid) => ({
  personal: true, name: 'Le mie ricette', ownerUid: uid, members: [uid], memberEmails: { [uid]: EMAIL(uid) }, createdAt: now(),
});
const join = (uid) => ({ members: arrayUnion(uid), [`memberEmails.${uid}`]: EMAIL(uid), viewers: arrayUnion(uid) });
const leave = (uid) => ({ members: arrayRemove(uid), [`memberEmails.${uid}`]: deleteField(), viewers: arrayRemove(uid), admins: arrayRemove(uid) });
const remove = (uid) => ({ members: arrayRemove(uid), [`memberEmails.${uid}`]: deleteField(), viewers: arrayRemove(uid) });
const role = (uid, r) => ({
  admins: r === 'admin' ? arrayUnion(uid) : arrayRemove(uid),
  viewers: r === 'viewer' ? arrayUnion(uid) : arrayRemove(uid),
});

const res = { ok: 0, rotto: [], buco: [], limite: [] };
async function ok(name, p) {
  try { await assertSucceeds(p); res.ok++; console.log('ok      ', name); } catch (e) { res.rotto.push(name); console.log('ROTTO   ', name, '-', String(e.message).split('\n')[0]); }
}
async function vietato(name, p) {
  try { await assertFails(p); res.ok++; console.log('ok      ', '(vietato)', name); } catch (e) { res.buco.push(name); console.log('BUCO    ', name); }
}
async function limite(name, p) {
  try { await p; res.limite.push(name); console.log('LIMITE  ', name, '(riesce)'); } catch (e) { res.ok++; console.log('ok      ', '(limite respinto)', name); }
}

async function seed() {
  await env.clearFirestore();
  await asAdmin(async (a) => {
    await setDoc(doc(a, `books/${G}`), {
      ...groupDoc(O), members: [O, AD, E, V, V2],
      memberEmails: { [O]: EMAIL(O), [AD]: EMAIL(AD), [E]: EMAIL(E), [V]: EMAIL(V), [V2]: EMAIL(V2) },
      admins: [O, AD], viewers: [V, V2],
    });
    await setDoc(doc(a, `books/${G}/recipes/R1`), recipe('R1', O));
    await setDoc(doc(a, `books/${G}/photos/P1`), photo('R1'));
    await setDoc(doc(a, `books/${B}`), personalDoc(B));
    await setDoc(doc(a, `books/${B}/recipes/RB`), recipe('RB', B, { title: 'Ricetta segreta di B' }));
    await setDoc(doc(a, `books/${B}/photos/PB`), photo('RB'));
    await setDoc(doc(a, `users/${B}`), { name: 'B', email: EMAIL(B), seenAt: now() });
    await setDoc(doc(a, `books/${G2}`), groupDoc(B, 'Altro gruppo'));
  });
}

// ---------------------------------------------------------------- T-HACK-10: i flussi veri dell'app
await seed();
console.log('\n== T-HACK-10 flussi dell\'app (devono funzionare) ==');
await ok('nuovo account legge il proprio libro personale che non esiste ancora', getDoc(doc(db(N), `books/${N}`)));
await ok('nuovo account crea il libro personale (ensurePersonal)', setDoc(doc(db(N), `books/${N}`), personalDoc(N)));
await ok('salva il profilo (saveProfile, merge)', setDoc(doc(db(N), `users/${N}`), { name: 'N', email: EMAIL(N), seenAt: now() }, { merge: true }));
await ok('scrive e legge una ricetta nel proprio libro', setDoc(doc(db(N), `books/${N}/recipes/RN`), recipe('RN', N)));
await ok('carica una foto nel proprio libro', setDoc(doc(db(N), `books/${N}/photos/PN`), photo('RN', 'A'.repeat(900000))));
await ok('elenco dei propri ricettari (where members array-contains)', getDocs(query(collection(db(N), 'books'), where('members', 'array-contains', N))));
await ok('crea un gruppo (createGroup)', setDoc(doc(db(N), 'books/NUOVOGRP12'), groupDoc(N)));
await ok('X legge il gruppo con il codice prima di entrare (joinGroup)', getDoc(doc(db(X), `books/${G}`)));
await ok('X entra con il codice come sola lettura (joinGroup)', updateDoc(doc(db(X), `books/${G}`), join(X)));
await ok('X (sola lettura) legge le ricette e le foto', getDocs(collection(db(X), `books/${G}/recipes`)));
await ok('l\'admin AD rende X «modifica» (setRole editor)', updateDoc(doc(db(AD), `books/${G}`), role(X, 'editor')));
await ok('X (modifica) scrive una ricetta', setDoc(doc(db(X), `books/${G}/recipes/RX`), recipe('RX', X)));
await ok('X (modifica) carica una foto', setDoc(doc(db(X), `books/${G}/photos/PX`), photo('RX')));
await ok('X (modifica) elimina la foto', deleteDoc(doc(db(X), `books/${G}/photos/PX`)));
await ok('il proprietario rende X admin (setRole admin)', updateDoc(doc(db(O), `books/${G}`), role(X, 'admin')));
await ok('X (admin) rinomina il gruppo (renameGroup)', updateDoc(doc(db(X), `books/${G}`), { name: 'Famiglia Rossi' }));
await ok('X (admin) rimette V2 in «modifica»', updateDoc(doc(db(X), `books/${G}`), role(V2, 'editor')));
await ok('X (admin) esce dal gruppo (leaveGroup)', updateDoc(doc(db(X), `books/${G}`), leave(X)));
await ok('l\'editor E esce dal gruppo', updateDoc(doc(db(E), `books/${G}`), leave(E)));
await ok('l\'admin AD toglie V dal gruppo (removeMember)', updateDoc(doc(db(AD), `books/${G}`), remove(V)));
await ok('il proprietario elimina ricette, foto e poi il gruppo (deleteGroup)', (async () => {
  const o = db(O);
  for (const c of ['recipes', 'photos']) for (const d of (await getDocs(collection(o, `books/${G}/${c}`))).docs) await deleteDoc(d.ref);
  await deleteDoc(doc(o, `books/${G}`));
})());
await ok('eliminazione account: svuota il libro personale, lo elimina, elimina il profilo (deleteAllData)', (async () => {
  const n = db(N);
  for (const c of ['recipes', 'photos']) for (const d of (await getDocs(collection(n, `books/${N}/${c}`))).docs) await deleteDoc(d.ref);
  await deleteDoc(doc(n, `books/${N}`));
  await deleteDoc(doc(n, `users/${N}`));
})());
await seed();
await ok('amministratore dell\'app: legge tutte le ricette (collectionGroup)', getDocs(collectionGroup(db('uidAdminApp', { email: ADMIN_APP }), 'recipes')));
await ok('amministratore dell\'app: sposta una ricetta nel personale di B (reassignRecipe)',
  setDoc(doc(db('uidAdminApp', { email: ADMIN_APP }), `books/${B}/recipes/NUOVA`), recipe('NUOVA', B)));

// ---------------------------------------------------------------- T-HACK-01/07/09: dati di un altro account
await seed();
console.log('\n== T-HACK-01/07 dati di un altro account ==');
await vietato('non autenticato legge un gruppo', getDoc(doc(anon, `books/${G}`)));
await vietato('non autenticato crea il proprio libro', setDoc(doc(anon, `books/${X}`), personalDoc(X)));
await vietato('X legge il libro personale di B', getDoc(doc(db(X), `books/${B}`)));
await vietato('X legge le ricette personali di B', getDocs(collection(db(X), `books/${B}/recipes`)));
await vietato('X legge una ricetta personale di B per id', getDoc(doc(db(X), `books/${B}/recipes/RB`)));
await vietato('X legge una foto personale di B', getDoc(doc(db(X), `books/${B}/photos/PB`)));
await vietato('X scrive nel libro personale di B', setDoc(doc(db(X), `books/${B}/recipes/RX`), recipe('RX', X)));
await vietato('X elenca tutti i ricettari', getDocs(collection(db(X), 'books')));
await vietato('X cerca i ricettari di B (array-contains B)', getDocs(query(collection(db(X), 'books'), where('members', 'array-contains', B))));
await vietato('X legge tutte le ricette (collectionGroup recipes)', getDocs(collectionGroup(db(X), 'recipes')));
await vietato('X legge tutte le foto (collectionGroup photos)', getDocs(collectionGroup(db(X), 'photos')));
await vietato('X legge il profilo di B', getDoc(doc(db(X), `users/${B}`)));
await vietato('X scrive il profilo di B', setDoc(doc(db(X), `users/${B}`), { name: 'falso' }, { merge: true }));
await vietato('X elenca i profili', getDocs(collection(db(X), 'users')));
await vietato('X (non membro) legge le ricette di G', getDocs(collection(db(X), `books/${G}/recipes`)));
await vietato('X (non membro) scrive una ricetta in G', setDoc(doc(db(X), `books/${G}/recipes/RX`), recipe('RX', X)));
await vietato('X elimina il gruppo G', deleteDoc(doc(db(X), `books/${G}`)));
await vietato('X elimina il libro personale di B', deleteDoc(doc(db(X), `books/${B}`)));
await vietato('admin finto: email dell\'admin NON verificata', getDocs(collectionGroup(db('uidFinto', { email: ADMIN_APP, email_verified: false }), 'recipes')));
await vietato('admin finto: email dell\'admin in maiuscolo', getDocs(collectionGroup(db('uidFinto', { email: ADMIN_APP.toUpperCase() }), 'recipes')));
await limite('X con il codice invito vede nomi ed email di tutti i membri di G prima di entrare (T-HACK-07)', getDoc(doc(db(X), `books/${G}`)));
await limite('X scopre se B ha un libro personale (get negato = esiste, get permesso = non esiste)', getDoc(doc(db(X), `books/${N}`)));

// ---------------------------------------------------------------- T-HACK-02/03: identità e ruoli
console.log('\n== T-HACK-02/03 prendere identità e salire di ruolo ==');
await seed();
await vietato('X crea un gruppo a nome di B (ownerUid = B)', setDoc(doc(db(X), 'books/FALSO12345'), { ...groupDoc(B), members: [B] }));
await vietato('X crea un gruppo con B già tra i membri', setDoc(doc(db(X), 'books/FALSO12345'), { ...groupDoc(X), members: [X, B] }));
await vietato('X occupa il libro personale di B', setDoc(doc(db(X), `books/uidFuturo`), { ...personalDoc(X) }));
await vietato('X crea un «gruppo» con l\'id di un uid (28 caratteri)', setDoc(doc(db(X), 'books/abcdefghijklmnopqrstuvwxyz12'), groupDoc(X)));
await vietato('X entra in G direttamente come «modifica» (senza viewers)', updateDoc(doc(db(X), `books/${G}`), { members: arrayUnion(X), [`memberEmails.${X}`]: EMAIL(X) }));
await vietato('X entra in G come admin', updateDoc(doc(db(X), `books/${G}`), { ...join(X), admins: arrayUnion(X) }));
await vietato('X entra in G e porta con sé il complice', updateDoc(doc(db(X), `books/${G}`), { members: arrayUnion(X, X2), [`memberEmails.${X}`]: 'x', viewers: arrayUnion(X, X2) }));
await vietato('X entra in G e cambia nome al gruppo', updateDoc(doc(db(X), `books/${G}`), { ...join(X), name: 'Mio' }));
await vietato('X entra in G e falsifica l\'email del proprietario', updateDoc(doc(db(X), `books/${G}`), { ...join(X), [`memberEmails.${O}`]: 'falso' }));
await vietato('X entra nel libro personale di B con il suo uid come codice', updateDoc(doc(db(X), `books/${B}`), join(X)));
await vietato('il viewer V si promuove admin', updateDoc(doc(db(V), `books/${G}`), { admins: arrayUnion(V) }));
await vietato('il viewer V si toglie da viewers (diventa «modifica»)', updateDoc(doc(db(V), `books/${G}`), { viewers: arrayRemove(V) }));
await vietato('il viewer V scrive una ricetta', setDoc(doc(db(V), `books/${G}/recipes/RV`), recipe('RV', V)));
await vietato('il viewer V elimina una ricetta', deleteDoc(doc(db(V), `books/${G}/recipes/R1`)));
await vietato('il viewer V carica una foto', setDoc(doc(db(V), `books/${G}/photos/PV`), photo('RV')));
await vietato('il viewer V elimina una foto', deleteDoc(doc(db(V), `books/${G}/photos/P1`)));
await vietato('l\'editor E si promuove admin', updateDoc(doc(db(E), `books/${G}`), { admins: arrayUnion(E) }));
await vietato('l\'editor E toglie il viewer V', updateDoc(doc(db(E), `books/${G}`), remove(V)));
await vietato('l\'editor E rinomina il gruppo', updateDoc(doc(db(E), `books/${G}`), { name: 'Mio' }));
await vietato('l\'editor E diventa proprietario', updateDoc(doc(db(E), `books/${G}`), { ownerUid: E }));
await vietato('l\'admin AD diventa proprietario', updateDoc(doc(db(AD), `books/${G}`), { ownerUid: AD }));
await vietato('l\'admin AD toglie il proprietario', updateDoc(doc(db(AD), `books/${G}`), remove(O)));
await vietato('l\'admin AD rende personale il gruppo', updateDoc(doc(db(AD), `books/${G}`), { personal: true }));
await vietato('l\'admin AD elimina il gruppo', deleteDoc(doc(db(AD), `books/${G}`)));
await vietato('il proprietario toglie l\'admin AD (gli admin non si tolgono)', updateDoc(doc(db(O), `books/${G}`), remove(AD)));
await vietato('il membro E «esce» ma resta tra i membri', updateDoc(doc(db(E), `books/${G}`), { [`memberEmails.${E}`]: deleteField() }));
await vietato('il proprietario «esce» lasciando il gruppo senza proprietario', updateDoc(doc(db(O), `books/${G}`), leave(O)));

console.log('\n== T-HACK-03 trucchi con «esci» ed «entra» (2 passi) ==');
await seed();
await vietato('BUCO A: il viewer V esce aggiungendosi agli admin (passo 1 di 2)',
  updateDoc(doc(db(V), `books/${G}`), { ...leave(V), admins: arrayUnion(V) }));
// Passo 2, solo se il passo 1 è riuscito: rientra con il codice come «sola lettura» ma è admin.
const rientrato = await updateDoc(doc(db(V), `books/${G}`), join(V)).then(() => true, () => false);
if (rientrato) {
  await vietato('BUCO A: …poi rientra con il codice e scrive ricette come admin',
    setDoc(doc(db(V), `books/${G}/recipes/RV`), recipe('RV', V)));
  await vietato('BUCO A: …e toglie dal gruppo l\'editor E', updateDoc(doc(db(V), `books/${G}`), remove(E)));
}
await seed();
await vietato('BUCO B: l\'editor E esce e lascia il complice X2 come membro admin',
  updateDoc(doc(db(E), `books/${G}`), {
    members: [O, AD, V, V2, X2], [`memberEmails.${E}`]: deleteField(), admins: [O, AD, X2], viewers: [V, V2],
  }));
const compliceDentro = await getDoc(doc(db(X2), `books/${G}/recipes/R1`)).then(() => true, () => false);
if (compliceDentro) await vietato('BUCO B: …il complice (mai invitato) elimina le ricette', deleteDoc(doc(db(X2), `books/${G}/recipes/R1`)));
await seed();
await vietato('BUCO C: X entra con il codice e toglie V2 da viewers (V2 diventa «modifica» senza permesso)',
  updateDoc(doc(db(X), `books/${G}`), { ...join(X), viewers: [X] }));
await seed();
await vietato('BUCO C: il viewer V esce e toglie anche V2 da viewers',
  updateDoc(doc(db(V), `books/${G}`), { ...leave(V), viewers: [] }));

// ---------------------------------------------------------------- T-HACK-05/06: avvelenamento e risorse
console.log('\n== T-HACK-05/06 avvelenamento e risorse ==');
await seed();
await vietato('foto di 1.000.000 di caratteri esatti (limite < 1.000.000)', setDoc(doc(db(E), `books/${G}/photos/PBIG`), photo('R1', 'A'.repeat(1000000))));
await ok('foto di 999.999 caratteri', setDoc(doc(db(E), `books/${G}/photos/POK`), photo('R1', 'A'.repeat(999999))));
await vietato('foto senza b64', setDoc(doc(db(E), `books/${G}/photos/PNO`), { recipeId: 'R1' }));
await vietato('foto con b64 numerico', setDoc(doc(db(E), `books/${G}/photos/PNUM`), { b64: 12345, recipeId: 'R1' }));
await limite('l\'editor scrive una ricetta con «updatedAt» nel 2286 (gli altri membri non vedranno più modifiche né eliminazione)',
  setDoc(doc(db(E), `books/${G}/recipes/R1`), recipe('R1', E, { updatedAt: 9999999999999 })));
await limite('l\'editor scrive una ricetta con tipi sbagliati (title: 123): sparisce dagli altri telefoni',
  setDoc(doc(db(E), `books/${G}/recipes/RT`), recipe('RT', E, { title: 123, steps: 'x' })));
await limite('l\'editor scrive una ricetta SENZA «id»: ogni telefono la duplica a ogni aggiornamento',
  setDoc(doc(db(E), `books/${G}/recipes/RNOID`), (({ id, ...r }) => r)(recipe('RNOID', E))));
await limite('l\'editor firma una ricetta con l\'uid del proprietario (updatedByUid falso: niente avviso per lui)',
  setDoc(doc(db(E), `books/${G}/recipes/RF`), recipe('RF', O)));
// BUCO D: campi del tipo sbagliato nel documento del gruppo. FamilyGroup.fromDoc (models.dart:283) lancia e il
// listener dei gruppi di OGNI membro si ferma prima di onGroups (tool/tests/bug_gruppi_test.dart).
await vietato('BUCO D: l\'admin rinomina il gruppo con un numero', updateDoc(doc(db(AD), `books/${G}`), { name: 123 }));
await vietato('BUCO D: l\'admin trasforma «viewers» in un testo', updateDoc(doc(db(AD), `books/${G}`), { viewers: 'tutti' }));
await vietato('BUCO D: l\'admin trasforma «memberEmails» in un testo', updateDoc(doc(db(AD), `books/${G}`), { memberEmails: 'tutti' }));
await vietato('BUCO D: X crea un gruppo «avvelenato» (nome numerico) e ne diffonde il codice',
  setDoc(doc(db(X), 'books/VELENO1234'), { ...groupDoc(X), name: 123 }));
await limite('l\'admin aggiunge a G un utente che non ha mai accettato (B)',
  updateDoc(doc(db(AD), `books/${G}`), { members: arrayUnion(B) }));
await limite('l\'admin cambia l\'email mostrata di un altro membro', updateDoc(doc(db(AD), `books/${G}`), { [`memberEmails.${E}`]: 'truffa@example.com' }));
await seed();
await limite('il proprietario elimina il gruppo lasciando ricette e foto orfane (nessuno potrà più cancellarle)',
  deleteDoc(doc(db(O), `books/${G}`)));
await vietato('dopo l\'eliminazione: le ricette orfane non sono leggibili da nessun ex membro', getDoc(doc(db(E), `books/${G}/recipes/R1`)));

console.log(`\n${res.ok} ok · ${res.buco.length} BUCHI · ${res.rotto.length} ROTTI · ${res.limite.length} limiti`);
for (const b of res.buco) console.log('  BUCO  ', b);
for (const r of res.rotto) console.log('  ROTTO ', r);
await env.cleanup();
process.exit(res.buco.length || res.rotto.length ? 1 : 0);
