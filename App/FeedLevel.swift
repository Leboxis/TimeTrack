enum FeedLevel: Int, CaseIterable {
    case zero, one, two, three, four

    var title: String { "Niveau \(rawValue)" }

    var subreddits: [String] {
        switch self {
        case .zero: ["BBWFeet", "MommyMilfs", "PublicFeetPics", "feet", "feetgooned", "vagina"]
        case .one: ["burstingout", "OnOff"]
        case .two: ["milfspanties", "classyboners"]
        case .three: ["ClothedForPrejacs"]
        case .four: ["CensoredFeet"]
        }
    }
}
