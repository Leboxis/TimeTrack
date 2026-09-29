# Flux RSS et lecteur média plein écran

Date : 2026-09-29 · Statut : à valider · Version cible : 1.6.0

Référence : `C:\Users\KEDI-ADMIN\Documents\Project\Redditmediapocket` (portage partiel,
allégé, iOS 17). Sous-projet 2 sur 4. Sous-projet 1 (champs de séance) livré en 1.4.0,
méthode Coach Sarah en 1.5.0.

## Contexte

L'onglet Méthode affiche aujourd'hui la liste des méthodes. L'utilisateur veut, en
haut de cet écran, trois boutons : Flux (opérationnel), Médias (contenu fourni plus
tard) et Galeries (images fournies plus tard, mécanisme de swipe construit
maintenant).

## Objectif

Un lecteur plein écran vertical, identique dans son usage à celui de RedditMediaPocket :
on fait défiler les posts du subreddit choisi, chaque média (image, vidéo Reddit,
Redgifs, carrousel) visible directement, autoplay à l'apparition. Aucun téléchargement,
aucun compte, aucune sauvegarde.

## Boutons de l'onglet Méthode

`App/MethodListView` gagne en tête une rangée de trois `NavigationLink` stylés
boutons : Flux, Médias, Galeries. La liste des méthodes suit en dessous, inchangée.

## Réseau et parsing du flux

`Sources/WellbeingCore/Feed.swift` (nouveau, logique pure et testée — la référence
sépare `MediaCore` de `App`, ce projet sépare déjà `WellbeingCore` de `App`) :

| Pièce | Origine | Adaptation |
|---|---|---|
| `Post` (id, title, html, publishedAt, link) | `Feed.swift:6-15`, verbatim | aucune |
| `Media` (direct, redditVideo, redgifs) | `Feed.swift:17-26`, verbatim | aucune |
| Erreurs (`invalidFeed`, `invalidSubreddit`) | `Feed.swift:28-39`, messages français repris | sans le helper `L`, chaînes en dur |
| `FeedParser` (XMLParser, guard `isFeed`) | `Feed.swift:139-177`, verbatim | aucune |
| Construction d'URL | `Feed.swift:108-136`, branche subreddit seule | tri fixé à `new`, `limit=25`, pas de `after` |
| Validation du nom | `Feed.swift:70-76`, verbatim (`^[A-Za-z0-9_]{2,21}$`) | aucune |
| `MediaExtractor.extract` + `previewImage` | `Feed.swift:215-256`, verbatim, allowlists inchangées | aucune |
| `GalleryFeed` (linked, commentsJSONURL, parse) | `GalleryFeed.swift`, verbatim | aucune |
| `QualityPolicy.originalImageURL` + `redgifsCandidates` | `QualityPolicy.swift`, verbatim | aucune |
| `RedgifsAPI.gifURL` + `headers` | `RedgifsAPI.swift:8-22`, verbatim | aucune |

`App/FeedModel.swift` (`@MainActor @Observable`, non testé comme le reste de `App/`) :
`subreddit` persisté en `UserDefaults`, `posts`, `loading`, `errorMessage`, `load()`.
L'appel réseau vit là : `GET https://www.reddit.com/r/<sub>/new.rss?limit=25` avec
`User-Agent: Wellbeing/1.6 (iOS; RSS reader)` sur `URLSession.shared`, seuil 200-299
sinon `invalidFeed`, puis `FeedParser.parse`. Token Redgifs anonyme mis en cache 30
min dans le modèle. Pas de cache applicatif, pas de retry, pas de rate-limit.

## Lecteur plein écran

`App/FeedView.swift` + `App/FeedCard.swift` + `App/AutoPlayVideo.swift`, portés de
`SavedPostsView.swift:321-350` et `:492-548` :

- Conteneur : `ScrollView(.vertical)` + `LazyVStack(spacing: 0)` + cartes en
  `containerRelativeFrame(.vertical)` + `scrollTargetLayout()` +
  `scrollTargetBehavior(.paging)` + `scrollPosition(id:)`. Tout est iOS 17, aucun
  remplacement nécessaire. La décoration `scrollTransition` est reprise, elle est
  iOS 17 aussi.
- `visibleID` est la seule source de vérité pour l'autoplay.
- Carte : fond noir, média redimensionné, titre et date en surimpression basse,
  `ProgressView` pendant le chargement, état d'erreur avec bouton Réessayer.
- États : chargement initial, liste, erreur réseau avec réessai, pull-to-refresh.
- Posts sans média exploitable : ignorés, comme la référence. Toucher un post ne fait
  rien : le média est déjà visible.

Comportement par type de média, résolu depuis `Post.html` avec `MediaExtractor.extract`
(`Feed.swift:233-256`, verbatim, allowlists inchangées) :

| Type | Affichage |
|---|---|
| Image directe (`i.redd.it`, `i.imgur.com` + extension) | streaming via `URLSession`, `CGImageSource` plafonné comme la référence, pas de fichier temporaire |
| Vidéo Reddit (`v.redd.it/<id>`) | streaming HLS direct `https://v.redd.it/<id>/HLSPlaylist.m3u8` dans `AVPlayer`. **Hypothèse non vérifiée sans appareil** : si une vidéo ne démarre pas, le repli est le portage complet du pipeline DASH (`DASHParser` + téléchargement + fusion `AVAssetExportSession`) |
| Redgifs (`redgifs.com/watch/<id>`) | token anonyme `GET https://api.redgifs.com/v2/auth/temporary` (sans clé, cache 30 min), puis `GET https://api.redgifs.com/v2/gifs/<id>?views=yes`, lecture hd sinon sd en streaming |
| Carrousel (lien `/gallery/`) | résolu via `GET https://www.reddit.com/comments/<id>.json?raw_json=1&limit=1` (`GalleryFeed`, verbatim), pager horizontal dans la carte |
| Miniature d'attente | `previewImage` (`Feed.swift:215-225`, verbatim) affichée pendant la résolution |

`AutoPlayVideo` (`AVPlayerViewController`, `showsPlaybackControls`, boucle par
`actionAtItemEnd = .none` + seek, `play`/`pause` sur `isActive`, démontage avec
`replaceCurrentItem(nil)`) est repris verbatim. Son normal, contrôles natifs,
aucune gestion de session audio.

Abandonné de la référence : `FeedPreloadStore.prefetchNext` (préchargement agressif),
`FeedTempBin` (fichiers temporaires), `DASHParser` + fusion (remplacés par HLS),
téléchargements, collections, KDrive, login, cookies, `RatePolicy`, partage, zoom.

Un cache mémoire simple des URL média résolues par `entry.id` évite de re-résoudre en
faisant défiler en arrière.

## Menu des niveaux

`App/FeedLevel.swift` :

```swift
enum FeedLevel: Int, CaseIterable {
    case zero, one, two, three, four
    var title: String { "Niveau \(rawValue)" }
    var subreddits: [String] { … }
}
```

- Niveau 0 : BBWFeet, MommyMilfs, PublicFeetPics, feet, feetgooned, vagina
- Niveau 1 : burstingout, OnOff
- Niveau 2 : milfspanties, classyboners
- Niveau 3 : ClothedForPrejac
- Niveau 4 : CensoredFeet

`App/FeedModel.swift` (`@MainActor @Observable`) : `subreddit: String` persisté en
`UserDefaults` (`wellbeing.feed.subreddit`, défaut `feet`), `posts`, `loading`,
`errorMessage`, `load()`. La barre du flux porte un `Menu("r/\(subreddit)")` avec un
sous-menu par niveau, coche sur le courant. Changer de subreddit recharge.

## Galeries et Médias (contenu ultérieur)

- `App/GalleryCatalog.swift` : `Gallery` (id, title, imageNames) + `GalleryCatalog.all`
  **vide**, sur le modèle de `MethodCatalog`. `App/GalleryPickerView.swift` liste les
  galeries ou affiche « Aucune galerie ». `App/GalleryViewer.swift` : `TabView`
  paginé d'images bundlées, swipe gauche/droite, indicateur de page. Fonctionnel dès
  maintenant, contenu branché plus tard sans toucher aux vues.
- `App/MediaCatalog.swift` : `MediaItem` (id, title) + `MediaCatalog.all` **vide**.
  `App/MediaLibraryView.swift` affiche « Contenu à venir ». Le lecteur audio/vidéo
  sera construit quand le contenu sera fourni.

## Confidentialité

L'utilisateur a demandé la suppression des promesses « sans réseau » :

- `App/SettingsView`, section Confidentialité : le `Label` devient « Journal local,
  sans compte ni suivi » et le texte devient « Le journal reste dans son espace local
  et peut être inclus dans les sauvegardes de votre appareil. Exportez-le avant de
  désinstaller l'app ou son conteneur. Seul le flux RSS contacte Reddit pour afficher
  son contenu public. »
- `README.md:17` : « Aucun compte, serveur, service de suivi ou dépendance applicative
  tierce. » est remplacé par « Aucun compte ni service de suivi. Le flux RSS charge du
  contenu public depuis Reddit. » Le reste du README est inchangé.

## Hors périmètre

- Tri autre que `new`, pagination « charger plus », recherche.
- Zoom dans le flux vertical (n'existe pas dans la référence non plus).
- Partage, sauvegarde, mode hors-ligne, notifications.
- Lecture audio seule (attend le contenu médias).
- Sous-projets 3 et 4 au-delà des écrans vides décrits ci-dessus.

## Tests

`Tests/WellbeingCoreTests/FeedTests.swift` (nouveau, tout le parsing étant dans
`WellbeingCore`) :

1. Construction d'URL : `r/feet` en `new` donne
   `https://www.reddit.com/r/feet/new.rss?limit=25`, tri inconnu retombe sur `new`.
2. Validation : `vagina` accepté, `a` / 22 caractères / `r/feet!` rejetés.
3. Parsing XML sur un flux Atom figé : deux `entry` donnent deux `Post` avec id, titre,
   lien et date ; un document sans racine `feed` lève `invalidFeed`.
4. Extraction média : `v.redd.it`, `redgifs.com/watch`, `i.redd.it/*.jpg` reconnus,
   hôte inconnu ignoré, doublons dédupliqués.
5. `QualityPolicy.originalImageURL` : suffixe imgur retiré.
6. `GalleryFeed` : URL `comments.json` bien formée, `linked` détecté.

`App/` (modèle, vues, lecteur) reste vérifié par compilation iOS + essai sur appareil :
25 posts du niveau 0, swipe vertical avec autoplay, Redgifs qui démarre, carrousel qui
swipe, changement de niveau qui recharge, mode avion qui affiche l'erreur avec réessai.

## Notes de livraison

- `MARKETING_VERSION` 1.5.0 → 1.6.0.
- Le point HLS est le seul risque technique ouvert, avec repli défini.
