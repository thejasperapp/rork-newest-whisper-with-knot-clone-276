import Foundation

/// Bundled previews retain public image references in Story metadata for older clients.
nonisolated enum WhisperStoryTrayArtwork: String, CaseIterable, Identifiable {
    case vote, soundDial, soundSwirl, soundWord, thursday, win, letterL, eyes, fourK, bestLife, yum, couldBeWorse

    var id: String { rawValue }
    static let illustratedRow: [Self] = [.soundDial, .soundSwirl, .soundWord, .thursday]
    static let remainingRows: [Self] = [.win, .letterL, .eyes, .fourK, .bestLife, .yum, .couldBeWorse]

    var title: String {
        switch self {
        case .vote: "Vote"
        case .soundDial: "Sound on, volume dial"
        case .soundSwirl: "Sound on, swirl"
        case .soundWord: "Sound on"
        case .thursday: "Thursday"
        case .win: "W, win"
        case .letterL: "L, hand sign"
        case .eyes: "Sparkly eyes"
        case .fourK: "4K television"
        case .bestLife: "Best life"
        case .yum: "Yum"
        case .couldBeWorse: "It could be worse"
        }
    }

    var assetName: String {
        switch self {
        case .vote: "vote_sticker"
        case .soundDial: "hand_volume_dial_sticker"
        case .soundSwirl: "sound_on_sticker_2"
        case .soundWord: "sound_on_sticker"
        case .thursday: "thursday_groovy_sticker"
        case .win: "lilac_w_sticker_starburst"
        case .letterL: "hand_l_sign_sticker"
        case .eyes: "sparkly_eyes_pink_lips_sticker"
        case .fourK: "retro_tv_4k_sticker"
        case .bestLife: "isolate_and_recreate"
        case .yum: "yum_candy_sticker"
        case .couldBeWorse: "could_be_worse_cloud_sticker"
        }
    }

    var url: String {
        switch self {
        case .vote: "https://zep16h4vwxx7d9ntwuap0.rork.app/~assets/img/66848ae7-bafb-424c-8e9f-ebdfffdddd81.png"
        case .soundDial: "https://zep16h4vwxx7d9ntwuap0.rork.app/~assets/img/3df04f0c-fbb3-455e-911e-ee15b24bb2f8.png"
        case .soundSwirl: "https://zep16h4vwxx7d9ntwuap0.rork.app/~assets/img/807bb86c-80a1-4f4e-8ee7-25aa821ca43e.png"
        case .soundWord: "https://zep16h4vwxx7d9ntwuap0.rork.app/~assets/img/14ac10f9-b4c4-49ba-9b28-1ac88c53dfc9.png"
        case .thursday: "https://zep16h4vwxx7d9ntwuap0.rork.app/~assets/img/ab5d3335-bc72-4253-9142-ca23cdbdfb79.png"
        case .win: "https://zep16h4vwxx7d9ntwuap0.rork.app/~assets/img/88710401-1a17-4a04-ae3d-7f88906a220b.png"
        case .letterL: "https://zep16h4vwxx7d9ntwuap0.rork.app/~assets/img/b61cd803-7c7d-4590-b28f-589180bfdec7.png"
        case .eyes: "https://zep16h4vwxx7d9ntwuap0.rork.app/~assets/img/ccc1b0ec-260c-4b1c-a8c6-e101dc0ba4e2.png"
        case .fourK: "https://zep16h4vwxx7d9ntwuap0.rork.app/~assets/img/c1b4c412-45c7-4c17-9a2f-bb9b4d101d9f.png"
        case .bestLife: "https://zep16h4vwxx7d9ntwuap0.rork.app/~assets/img/f889f937-b3ef-4fb9-bc04-c2ae6dcd0c01.png"
        case .yum: "https://zep16h4vwxx7d9ntwuap0.rork.app/~assets/img/af12b9c3-a515-41cb-91e0-4216e3fa38a9.png"
        case .couldBeWorse: "https://zep16h4vwxx7d9ntwuap0.rork.app/~assets/img/b7527ee9-d862-4bc8-a1ea-f8c31de907e8.png"
        }
    }

    static func bundledAsset(for url: String) -> String? {
        allCases.first { $0.url == url }?.assetName
    }
}
