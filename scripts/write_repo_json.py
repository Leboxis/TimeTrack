"""Regenerate repo.json so SideStore and LiveContainer can install and update the app."""
import json
import os
from datetime import datetime, timezone
from pathlib import Path

repository = os.environ["GITHUB_REPOSITORY"]
tag = os.environ["RELEASE_TAG"]
release = "https://github.com/{0}/releases/download/{1}".format(repository, tag)
raw = "https://raw.githubusercontent.com/{0}/main/repo.json".format(repository)
subtitle = "Chronomètre, journal et tendances, entièrement sur l’appareil."
icon = release + "/icon.png"

manifest = {
    "name": "Wellbeing",
    "identifier": "com.leboxis.wellbeing.source",
    "sourceURL": raw,
    "iconURL": icon,
    "website": "https://github.com/" + repository,
    "subtitle": subtitle,
    "apps": [
        {
            "name": "Wellbeing",
            "bundleIdentifier": "com.leboxis.wellbeingtracker",
            "developerName": "Leboxis",
            "subtitle": subtitle,
            "localizedDescription": (
                "Journal personnel de suivi des séances : chronomètre, saisie, "
                "recherche, graphiques et export CSV. Stockage local, sans compte "
                "ni serveur."
            ),
            "iconURL": icon,
            "versions": [
                {
                    "version": os.environ["GITHUB_RUN_NUMBER"],
                    "date": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "downloadURL": release + "/Wellbeing.ipa",
                    "size": Path("Wellbeing.ipa").stat().st_size,
                }
            ],
        }
    ],
}

Path("repo.json").write_text(
    json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
)
print("Wrote repo.json for build " + os.environ["GITHUB_RUN_NUMBER"])
