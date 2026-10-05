# Suivi des jours sans porno — design

Date : 2026-10-05 · Statut : à relire

## Intention

Suivre les jours sans porno, à partir des séances déjà enregistrées, sans ajouter
d'écran ni de fichier de données. L'utilisateur suit des séances (journal existant) et
veut maintenant savoir combien de jours sont passés sans porno, et ce qu'a donné le mois
dernier. Le suivi doit être **bien intégré** à l'app : il prolonge le journal existant,
il ne vit pas à côté.

Hors périmètre, et pour cause : le blocage d'autres apps ou de Safari. iOS n'accorde
l'entitlement « Family Controls » qu'aux apps distribuées via l'App Store ; l'app est
signée et installée en IPA non chiffré (LiveContainer, SideStore). Aucun code de cette
app ne peut donc fermer une app tierce. Le suivi repose sur l'enregistrement, pas sur
une barrière technique.

## Modèle de données

Un seul champ ajouté, dans `Sources/WellbeingCore/Session.swift` :

```swift
public var hasPorn: Bool
```

- Défaut `false` dans `init`, et `decodeIfPresent(Bool.self) ?? false` dans
  `init(from:)`, exactement comme `orgasm`, `mental` et `ejaculation` le font déjà. Un
  `journal.json` écrit avant ce changement continue de décoder, et ses séances comptent
  comme « sans porno » — le défaut est le cas favorable, et le dire dans la spec évite
  qu'on se retrouve avec un compteur qui Ment sur l'historique.
- Pas de nouveau fichier, pas de migration, pas de nouveau type dans le package. Le CSV
  gagne une colonne `avec_porno` (`1`/`0`) après `type_ejaculation`, parce que
  `Journal.csv` énumère les champs à la main et sans elle l'export perdrait l'information.
- `isValid` n'a pas besoin de la toucher : un `Bool` ne peut pas être hors plage.

## Calcul — une valeur, testée dans WellbeingCore

Nouveau fichier `Sources/WellbeingCore/Abstinence.swift`, sans SwiftUI, comme
`RatingBand` et `nearestSession`:

```swift
public struct Abstinence: Equatable {
    public let days: Int          // série en cours, 0 si aujourd'hui ou hier est « sale »
    public let longest: Int       // plus longue série de l'historique
    public let relapses: Int      // nombre de jours avec au moins une séance porno
    public let cleanRate: Double  // 0...1, jours propres / jours couverts
    public let lastRelapse: Date? // date de la dernière journée marquée
}

public func abstinence(sessions: [Session], now: Date = Date(), calendar: Calendar = .current) -> Abstinence
```

Règles, qui sont tout le contrat :

1. **Borné par les données, pas par le calendrier.** Le compteur commence au premier jour
   où le journal existe. Sans borne basse explicite, un journal créé aujourd'hui
   afficherait « 0 jour sans porno » au lieu de « 1 », et surtout afficherait 1 après
   avoir enregistré une seule séance porno il y a dix minutes — parce qu'on compterait
   dix jours dont personne n'a rien noté. On compte donc les jours entre la date de la
   plus ancienne séance et aujourd'hui, inclus.
2. **Un jour avec une séance porno casse la série, même si d'autres séances ce jour-là
   sont propres.** Le jour est sale ou propre, pas la séance.
3. **Un jour sans aucune séance compte comme propre.** C'est le choix qui rend le
   suivi utilisable : l'utilisateur n'a pas à déclarer chaque journée sobre.
4. **La série en cours vaut 0 si la journée d'aujourd'hui est déjà sale** — sinon il
   faut attendre minuit pour voir bouger le compteur, ce qui donne l'impression que
   rien n'est compté.
5. `relapses` compte les **jours** marqués, pas les séances : trois séances porno le
   même jour sont un échec, pas trois.
6. `cleanRate` porte sur les jours couverts par le journal, jamais sur une durée
   calendaire. Un jour vide avant la première séance ne doit pas dégrader le taux.

## Écrans

**`SessionEditor.swift`** — une `Toggle("Séance avec porno", isOn: $session.hasPorn)`
dans la section « Séance », après la durée. Libellé explicite plutôt que « porno » seul :
la case décrit le contenu de la séance, pas la valeur de l'utilisateur.

**`TrendsView.swift`** — une carte abstinence au-dessus du `Picker` de période, donc
visible même quand le journal est vide. Contenu :

- Deux métriques : « Jours sans porno » (série en cours) et « Record », en réutilisant
  `metric(_:_:symbol:)` qui existe déjà et fait le même format.
- Une bande de 30 jours : une case par jour, teintée si le jour est propre, avec la
 Accessibility que le Chart n'apporte pas ici.
- Une ligne de contexte : « 24 rechutes sur 87 jours · 72 % de jours propres ».
- Si `sessions.isEmpty`, la carte affiche « Les jours sans porno apparaîtront après
  votre première séance. » et rien d'autre.

La carte ignore le `Picker` de période : une série se lit en absolu, pas sur une fenêtre
glissante. `store.loadFailed` reste prioritaire — on n'affiche pas de compteur sur un
journal illisible, ce qui est déjà la règle du fichier.

**`JournalView.swift`** — un `chip` supplémentaire sur les lignes cochées, dans le
palette existante, pour que l'information soit visible sans ouvrir la séance. Et
`accessibilitySummary` annonce « avec porno » / « sans porno », sinon VoiceOver ne dit
rien de plus qu'avant.

## Ce qui ne change pas

Pas de nouvel onglet. Pas de nouvelle destination de navigation. Pas de réseau, pas de
dépendance. Pas de fichier de données supplémentaire. Le README garde sa liste de
fonctionnalités ; une ligne « Suivi des jours sans porno » est ajoutée.

## Tests

`Tests/WellbeingCoreTests/AbstinenceTests.swift`, avec un `Calendar` fixé
(`gregorian`, `UTC`) pour que les tests ne cassent pas au passage de fuseau :

- Journal vide → tous les compteurs à zéro, `lastRelapse` nil.
- Une séance porno aujourd'hui → `days == 0`.
- Une séance propre aujourd'hui → `days == 1`.
- Cinq jours sans rien puis une séance porno aujourd'hui → `days == 0`, `longest == 5`.
- Une séance porno il y a 3 jours, rien depuis → `days == 3`.
- Deux séances porno le même jour → `relapses == 1`.
- Journal qui commence il y a 10 jours, 1 jour porno aujourd'hui → `cleanRate == 9/10`,
  pas `9/11` ni `10/11`.
- Une séance porno et une séance propre le même jour → le jour compte sale.
- `hasPorn` absent du JSON (journal 1.4.0) → décode en `false`, la série n'explose pas.

## Risques

- **Un compteur flatteur par défaut.** Un historique sans la case se lit « 100 % propre ».
  Le libellé de la carte le dit explicitement (« selon les séances cochées ») plutôt que
  de laisser croire à une mesure.
- **Course à minuit.** Une série calculée sur `Date()` peut changer entre deux
  evaluations de vue. Le calcul est recalculé à chaque `body`, ce qui suffit ici : la
  valeur est vraie à l'instant où elle est lue.
- **Le champ ne dit pas la quantité.** « Séance avec porno » est binaire. Un suivi de
  volume est explicitement hors périmètre.