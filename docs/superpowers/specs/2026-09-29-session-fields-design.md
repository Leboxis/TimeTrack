# Champs de séance : spasme orgasmique, ressenti mental, type d'éjaculation

Date : 2026-09-29 · Statut : à valider · Version cible : 1.4.0

## Contexte

Wellbeing suit des séances (chronomètre, journal, tendances). Deux échelles de
ressenti 1-5 existent déjà : `feeling` (global). L'utilisateur veut y ajouter le
ressenti de l'orgasme, le ressenti mental, et le type d'éjaculation. Le sous-projet
RSS et le sous-projet galerie sont hors de ce document.

## Objectif

Trois mesures supplémentaires par séance, visibles dans l'éditeur, le journal et les
tendances, sans jamais rendre un `journal.json` existant illisible.

## Modèle de données

`Sources/WellbeingCore/Session.swift` :

```swift
public enum Ejaculation: String, Codable, CaseIterable {
    case aucune, baveuse, jet
}
```

Nouveaux champs sur `Session`, à la suite de `feeling` :

| Champ | Type | Défaut | Bornes |
|---|---|---|---|
| `orgasm` | `Int` | 3 | 1...5 |
| `mental` | `Int` | 3 | 1...5 |
| `ejaculation` | `Ejaculation` | `.aucune` | énumération fermée |

`Session` gagne un `init` membre explicite, avec valeurs par défaut, pour que les
tests et l'appelant existente restent simples.

## Compatibilité ascendante — exigence bloquante

Les fichiers `journal.json` déjà écrits ne contiennent pas ces clés. Avec le
`Codable` synthétisé, `Journal.decode` lèverait une erreur et `Journal.decodeRecovering`
rejeterait les vraies séances comme « illisibles » : perte de données, précisément le
défaut corrigé en 1.2.0.

`Session` reçoit donc un `init(from:)` manuel qui utilise `decodeIfPresent` pour les
trois nouveaux champs. `encode(to:)` reste synthétisé et écrit les six champs.

Conséquence : **aucun code de migration, aucune réécriture du fichier existant.**
C'est un ajout de schéma ; les nouvelles clés apparaissent au prochain enregistrement.
Les séances existantes se chargent avec `3 / 3 / aucune`, ce qui rend leurs valeurs
indistinguables d'une saisie réelle.

Cette information doit être visible dans l'app, pas seulement dans le README, qui ne
doit pas être modifié. `App/RatingRow.swift` porte sous chaque échelle une mention
« Valeur par défaut pour les séances enregistrées avant cette version » uniquement
quand la valeur provient d'un défaut, ce qui suppose que `Session` distingue une
valeur saisie d'une valeur par défaut. On ne sur-complexifie pas : la mention est
statique, affichée une fois dans l'écran Réglages.

## Validation

`Session.isValid` gagne `(1...5).contains(orgasm)` et `(1...5).contains(mental)`.
`Ejaculation` est valide par construction.

## Éditeur de séance

`App/RatingRow.swift` (nouveau) : une ligne de 5 boutons pour une échelle 1-5, avec
étiquettes. Réutilisée trois fois dans `SessionEditor` :

- `Ressenti` — étiquettes existantes (`1 · Difficile` … `5 · Très bien`)
- `Orgasme` — `1 · Difficile` … `5 · Excellent`
- `Mental` — `1 · Anxieux` … `5 · Serein`

`SessionEditor` gagne aussi un `Picker` 3 états pour le type d'éjaculation.

## Journal

`App/JournalView` : la ligne de séance affiche, en plus de la date et de la durée, une
rangée compacte de pastilles (Ressenti, Orgasme, Mental) et le type d'éjaculation.
Une ligne de plus qu'aujourd'hui au maximum.

## Tendances

`App/TrendsView` :

- `ChartMetric` gagne `.orgasm` et `.mental`, domain 1...5, une courbe chacune, à côté
  de la courbe de ressenti existante.
- Nouveau graphique en barres pour le type d'éjaculation : répartition du nombre de
  séances par type, sur la période sélectionnée.

## Hors périmètre

- **Colonnes CSV** : l'export reste `date_utc, duree_secondes, ressenti_sur_5, notes`.
  Les trois nouvelles mesures n'y figurent pas. Décision de l'utilisateur, à revoir.
- Sous-projet RSS (flux subreddit) et sous-projet galerie d'images.
- Pas de migration du format de fichier, pas de numéro de version de schéma.

## Tests

`Tests/WellbeingCoreTests/JournalTests.swift` :

1. Décodage d'un `journal.json` ancien sans `orgasm` / `mental` / `ejaculation` :
   les trois champs prennent leurs défauts, la séance n'est pas rejetée.
2. `isValid` refuse `orgasm` hors 1-5.
3. `isValid` refuse `mental` hors 1-5.
4. Aller-retour encode/decode avec les trois champs renseignés.
5. `Journal.csv` produit exactement l'en-tête et les colonnes actuels.
6. `decodeRecovering` ne rejette aucune séance d'un fichier ancien valide.

## Notes de livraison

- Version `MARKETING_VERSION` 1.3.0 → 1.4.0.
- CI : `swift test` puis build iOS. Le test 1 est la vraie protection contre la
  régression de compatibilité.
