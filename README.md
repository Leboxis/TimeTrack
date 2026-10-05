# Wellbeing — journal personnel iOS

Application native **SwiftUI**, en français, pour iPhone et iPad sous **iOS 17 ou version ultérieure**. Suivi neutre du bien-être, sans programme sexuel ni objectif de performance.

## Fonctionnalités

- Chronomètre avec pause, reprise et restauration après fermeture de l’application (limite : 24 h).
- Saisie manuelle, modification et suppression des séances.
- Date, durée, ressenti de 1 à 5 et notes personnelles.
- Journal avec recherche et calendrier de filtrage.
- Graphiques des durées et du ressenti sur 7 jours, 30 jours ou toute la période.
- Graphiques interactifs : toucher ou glisser pour sélectionner une séance, repères synchronisés, fiche détaillée et modification directe. Navigation précédente/suivante pour parcourir tous les points, y compris les séances à la même heure.
- Export CSV compatible avec les tableurs et suppression complète sur confirmation.
- Suivi des jours sans porno : série, record et taux de jours propres, calculés depuis les séances cochées « avec porno » dans l'éditeur.
- Stockage local, protection de fichier iOS et écran masqué lorsque l’app est inactive.
- Interface adaptative, mode sombre système et contrôles SwiftUI accessibles.

Les notes ne sont jamais envoyées à GitHub. Aucun compte ni service de suivi. Le flux RSS charge du contenu public depuis Reddit, avec ta session Reddit si tu l’as connectée dans les Réglages. Les sauvegardes système de l’appareil peuvent inclure les données. L’écran masqué n’est pas un verrou biométrique. Le chronomètre utilise l’heure système ; la modifier pendant une séance peut affecter sa durée.

## Télécharger l’IPA

1. Ouvrir l’onglet **Actions** du dépôt.
2. Choisir une exécution réussie du workflow **Build iOS IPA**.
3. Télécharger l’artefact **Wellbeing-IPA** en bas de la page (connexion GitHub nécessaire).
4. Décompresser le ZIP pour obtenir **Wellbeing.ipa** et sa somme SHA-256.

Une compilation démarre à chaque push sur `main`. On peut aussi la lancer depuis **Actions → Build iOS IPA → Run workflow**. Les artefacts expirent après 30 jours ; relancer le workflow permet d’en générer un nouveau.

### LiveContainer

Dans LiveContainer déjà installé et configuré, utiliser **+**, puis importer `Wellbeing.ipa`. L’IPA contient un exécutable arm64 non chiffré, sans extensions ni groupes d’applications. La compatibilité réelle dépend de la version d’iOS et de la configuration de LiveContainer ; une compilation réussie ne remplace pas un essai sur appareil.

Documentation officielle : https://github.com/LiveContainer/LiveContainer

### SideStore

Dans SideStore déjà configuré, importer `Wellbeing.ipa` depuis **My Apps → +**. SideStore doit signer l’app pour l’appareil avec le compte Apple configuré. Le fichier fourni par Actions n’a **pas** de signature de distribution Apple et ne s’installe pas directement par simple ouverture dans Fichiers. Aucun certificat ni mot de passe Apple n’est nécessaire dans GitHub Actions.

Les limites du compte Apple et les renouvellements de signature s’appliquent. Conserver le même identifiant d’app pour les mises à jour et exporter les données avant une désinstallation.

Documentation officielle : https://docs.sidestore.io/

## Développer sur Mac

Prérequis : Xcode 16.4, Python 3 et [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
python3 scripts/make_icon.py
xcodegen generate
open Wellbeing.xcodeproj
```

Choisir une équipe de signature dans Xcode pour une installation directe sur appareil. Le projet Xcode, le plist et l’icône sont générés à partir des sources suivies dans Git.

```sh
swift test
```

Les tests couvrent la sérialisation du journal, les données invalides, les doublons, l’échappement CSV, la neutralisation des formules et la pause/reprise du chronomètre. La CI compile ensuite l’app pour iOS et vérifie la structure de l’IPA. Le dépôt ne contient aucune donnée utilisateur.

## Vérification sur appareil

- Démarrer, mettre en pause, reprendre, fermer puis rouvrir l’app.
- Enregistrer une séance, la modifier, filtrer le journal et contrôler les graphiques.
- Toucher et parcourir les points des deux graphiques ; vérifier la fiche, les flèches, la remise à zéro de la sélection lors d’un changement de période et l’édition directe. Tester avec une seule séance et avec plusieurs séances à la même heure.
- Exporter un CSV avec accents, guillemets et plusieurs lignes de notes.
- Tester le mode sombre, les grandes tailles de texte et la rotation sur iPad.
- Tester séparément l’import LiveContainer et la signature SideStore.
