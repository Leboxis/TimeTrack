struct PracticeMethod: Identifiable {
    let id: String
    let title: String
    let summary: String
    let steps: [String]
    let cadence: String?
}

/// Adding a method means adding one entry here. No view changes required.
enum MethodCatalog {
    static let all: [PracticeMethod] = [
        PracticeMethod(
            id: "orgasme-rapide",
            title: "Orgasme rapide",
            summary: "Réduire progressivement la stimulation, d'abord physique puis visuelle, pour que la stimulation complète devienne plus intense. Chronométrer chaque séance sert à mesurer la progression.",
            steps: [
                "Chronométrer chaque séance et consigner le temps, du premier geste jusqu'à l'orgasme inévitable.",
                "Un seul doigt, avec du lubrifiant, sur le frein du pénis. Jamais de masturbation habituelle.",
                "Uniquement des femmes habillées comme stimulus visuel, jamais de nudité.",
                "À chaque progrès, réduire la stimulation : vêtements entre la main et le corps, zones moins sensibles, puis plus de mains.",
                "Méthode du déclencheur : juste avant l'orgasme, remplacer l'image par une image banale et la fixer au moment de l'orgasme. À utiliser avec prudence.",
                "Objectif : atteindre l'orgasme sans les mains, à partir d'une image entièrement banale."
            ],
            cadence: "3 à 4 fois par semaine, soit environ un jour sur deux."
        )
    ]
}
