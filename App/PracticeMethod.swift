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
        ),
        PracticeMethod(
            id: "shotgun",
            title: "Méthode Shotgun",
            summary: "Cinq techniques combinées en même temps pour devenir rapidement éjaculateur. Objectif : jouir en 30 secondes avec un seul doigt et du porno très soft.",
            steps: [
                "Matériel : chronomètre, tableur de suivi, lubrifiant, manchon en silicone, casque de réalité virtuelle, iphotoVR.",
                "Référence : trois masturbations aussi rapides que possible, sur trois jours différents. Noter les durées puis en faire la moyenne — sans cette base, l’entraînement est inutile.",
                "Suivi : consigner chaque durée dans un tableur et tracer la courbe. Voir celle-ci descendre est ce qui motive à continuer.",
                "Resensibilisation : porter un manchon en silicone en permanence sauf pour le nettoyage, pour réduire la stimulation quotidienne et la kératinisation.",
                "Déclencheur 2.0 : deux images. Le pré-déclencheur, non pornographique (ex. des pieds), pendant la masturbation ; le déclencheur, pornographique et rare, fixé intensément pendant tout l’orgasme puis coupé juste après. Le voir sans jouir affaiblit l’association.",
                "Stimulation réduite : uniquement du lubrifiant et un doigt sur la zone la plus sensible. Ne jamais revenir à la masturbation habituelle, cela réhabituerait à davantage de stimulation."
            ],
            cadence: "Trois séances au minimum sur trois jours différents pour la référence, puis aussi régulièrement que possible."
        )
    ]
}
