import SwiftUI

/// Presentation identity is separate from the editor's mutation and routing state.
enum WhisperStoryTrayTool: String, Identifiable, CaseIterable {
    case location = "Location", mention = "Mention", music = "Music"
    case gif = "GIF", addYours = "Add Yours", frames = "Frames"
    case photostrip = "Photostrip", cutouts = "Cutouts", photo = "Photo"
    case questions = "Questions", avatar = "Avatar", reaction = "Reaction"
    case poll = "Poll", slider = "Slider", link = "Link", hashtag = "Hashtag"
    case donation = "Donation", countdown = "Countdown"
    case templates = "Templates", portrait = "Portrait", layout = "Layout"

    var id: String { rawValue }

    static let referenceRows: [[Self]] = [
        [.location, .mention, .music], [.gif, .addYours, .frames],
        [.photostrip, .cutouts, .photo], [.questions, .avatar, .reaction],
        [.poll, .slider, .link, .hashtag], [.donation, .countdown]
    ]
    static let extraTools: [Self] = [.templates, .portrait, .layout]

    /// Widths measured relative to a 390-point rendering of IMG_2968.
    var referenceWidth: CGFloat {
        switch self {
        case .location: 106
        case .mention: 96
        case .music, .photo: 85
        case .gif, .link: 71
        case .addYours: 119
        case .frames: 113
        case .photostrip, .countdown: 126
        case .cutouts: 101
        case .questions: 115
        case .avatar: 106
        case .reaction: 44
        case .poll: 68
        case .slider: 89
        case .hashtag: 95
        case .donation: 108
        case .templates: 115
        case .portrait, .layout: 100
        }
    }

    var title: String {
        switch self {
        case .mention: "mention"
        case .hashtag: "hashtag"
        default: rawValue
        }
    }

    var symbol: String {
        switch self {
        case .location: "mappin"
        case .mention: "at"
        case .music: "music.note"
        case .gif: "magnifyingglass"
        case .addYours: "plus.square.on.square"
        case .frames: "photo.on.rectangle.angled"
        case .photostrip: "photo.stack"
        case .cutouts: "scissors"
        case .photo: "photo"
        case .questions: "questionmark.bubble"
        case .avatar, .portrait: "person.crop.circle"
        case .reaction: "face.smiling"
        case .poll: "text.alignleft"
        case .slider: "slider.horizontal.3"
        case .link: "link"
        case .hashtag: "number"
        case .donation: "heart.circle"
        case .countdown: "circle.dotted"
        case .templates: "square.on.square"
        case .layout: "rectangle.split.2x2"
        }
    }

    var tint: Color {
        switch self {
        case .location: Color(red: 0.48, green: 0.20, blue: 1)
        case .mention: Color(red: 1, green: 0.43, blue: 0.07)
        case .music, .addYours: Color(red: 0.95, green: 0.13, blue: 0.46)
        case .gif, .cutouts, .photo: Color(red: 0.28, green: 0.80, blue: 0.39)
        case .questions, .poll, .hashtag, .countdown: Color(red: 0.85, green: 0.08, blue: 0.78)
        case .link, .donation: Color(red: 0.17, green: 0.60, blue: 1)
        default: .orange
        }
    }

    var tilt: Double {
        switch self {
        case .gif, .photostrip, .hashtag: 1
        case .addYours, .avatar, .poll: -1
        default: 0
        }
    }

    var unavailableMessage: String? {
        switch self {
        case .addYours: "Shared Add Yours prompts and participant galleries aren't available in Whisper yet. No prompt has been added."
        case .avatar: "Personalized avatar creation and avatar stickers aren't available in Whisper yet. This illustration is a tool preview, not your avatar."
        case .donation: "Nonprofit discovery and donation collection aren't connected in Whisper yet. No fundraiser has been created."
        default: nil
        }
    }
}
