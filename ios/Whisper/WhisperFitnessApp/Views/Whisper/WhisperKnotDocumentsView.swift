import SwiftUI
import UniformTypeIdentifiers
import CryptoKit
import Supabase
import PDFKit
import AVKit
import Combine

nonisolated struct WhisperKnotDocument: Codable, Identifiable, Sendable {
    nonisolated struct Asset: Codable, Sendable, Equatable {
        let path: String
        let sha256: String
        let size: Int
        let contentType: String
        let resourceID: Int
    }
    nonisolated struct Bundle: Codable, Sendable, Equatable {
        let entry: String
        let assets: [Asset]
    }
    nonisolated struct VisualReview: Codable, Sendable {
        nonisolated struct Page: Codable, Sendable {
            let page: Int
            let sha256: String
            let verdict: String
            let issues: [String]
        }
        let version: String
        let finalSHA256: String
        let scope: String
        let status: String
        let pages: [Page]
    }
    nonisolated struct Provenance: Codable, Sendable {
        let senderID: String
        let senderName: String
        let sentAt: String
        let savedAt: String
        let messageID: String
        let originalDocumentID: String
    }
    var provenance: Provenance? = nil
    var visualReview: VisualReview? = nil
    var qualityShortfalls: [String]? = nil
    var deliveryNote: String? = nil
    var chatDeliveryNote: String? {
        guard let deliveryNote, !deliveryNote.isEmpty, deliveryNote.utf16.count <= 1200,
              !deliveryNote.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !deliveryNote.contains("`"), !deliveryNote.contains("<"), !deliveryNote.contains(">") else { return nil }
        return deliveryNote
    }
    let id: String
    let name: String
    let format: String
    let title: String?
    let deliveryLabel: String?
    let contentType: String
    let size: Int
    let sha256: String
    let pages: Int
    let proofPages: [Int]
    let createdAt: String
    let expiresAt: String
    let proposalID: String
    let review: String
    let sampled: Bool
    let sourceMessageID: String?
    let sourcePath: String?
    let bundle: Bundle?
    private static func digest(_ value: String) -> Bool { value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil }
    static func safePath(_ value: String, limit: Int = 240) -> Bool {
        !value.isEmpty && value.count <= limit && value.range(of: "^[a-zA-Z0-9][a-zA-Z0-9_. /-]*$", options: .regularExpression) != nil &&
        value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && !$0.hasPrefix(".") }
    }
    var valid: Bool {
        Self.digest(id) && Self.digest(sha256) && UUID(uuidString: proposalID) != nil && size > 0 && size <= 50_000_000 &&
        Self.safePath(name) && !name.contains("/") && !name.contains("\\") &&
        format.range(of: "^[a-z0-9][a-z0-9_-]{0,15}$", options: .regularExpression) != nil &&
        Self.validLabel(title, limit: 120) && Self.validLabel(deliveryLabel, limit: 48) &&
        name.lowercased().hasSuffix("." + format) && ["visual_ai", "not_requested", "unavailable", "issues"].contains(review) &&
        pages > 0 && pages <= 300 && proofPages.count <= 12 && Set(proofPages).count == proofPages.count &&
        proofPages.allSatisfy { $0 > 0 && $0 <= pages } &&
        (sourceMessageID == nil || UUID(uuidString: sourceMessageID!) != nil) && (sourcePath == nil || Self.safePath(sourcePath!, limit: provenance == nil ? 240 : 512)) && validBundle
    }
    private static func validLabel(_ label: String?, limit: Int) -> Bool {
        guard let label else { return true }
        return label.utf16.count <= limit && label.range(of: "[\\x00-\\x1f\\x7f]", options: .regularExpression) == nil
    }
    private var validBundle: Bool {
        guard let bundle else { return true }
        return format == "html" && bundle.entry == name && bundle.assets.count <= 64 &&
        Set(bundle.assets.map { $0.path.lowercased() }).count == bundle.assets.count &&
        Set(bundle.assets.map(\.resourceID)).count == bundle.assets.count &&
        bundle.assets.allSatisfy { Self.safePath($0.path) && $0.path.lowercased() != name.lowercased() && Self.digest($0.sha256) && $0.size > 0 && $0.size <= 50_000_000 && (100..<164).contains($0.resourceID) && $0.contentType.count <= 120 } &&
        bundle.assets.reduce(size, { $0 + $1.size }) <= 50_000_000
    }
    /// A refreshed card may add review observations, but cannot silently replace
    /// the original bytes or its verified local dependency map under the same ID.
    func identifiesSameOriginal(as other: Self) -> Bool {
        id == other.id && name == other.name && format == other.format && contentType == other.contentType &&
        size == other.size && sha256 == other.sha256 && proposalID == other.proposalID && bundle == other.bundle
    }
    var expires: Date {
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser.date(from: expiresAt) ?? ISO8601DateFormatter().date(from: expiresAt) ?? .distantPast
    }
    private var allPagesReviewed: Bool {
        guard let visualReview, visualReview.version == "knot_document_visual_v1",
              visualReview.finalSHA256 == sha256, visualReview.scope == "all_pages",
              ["pass", "issues"].contains(visualReview.status), visualReview.pages.count == pages,
              Set(visualReview.pages.map(\.page)).count == pages else { return false }
        return visualReview.pages.allSatisfy { page in
            page.page > 0 && page.page <= pages && Self.digest(page.sha256) &&
            (page.verdict == "pass" ? page.issues.isEmpty : page.verdict == "issues" && !page.issues.isEmpty)
        } && (visualReview.status == "pass" ? visualReview.pages.allSatisfy { $0.verdict == "pass" } : visualReview.pages.contains { $0.verdict == "issues" })
    }
    /// Saved findings remain authoritative even before the activity timeline loads.
    /// Delivery confirms captured bytes, not an overall quality verdict.
    var reviewNeedsAttention: Bool {
        qualityShortfalls?.isEmpty == false || review == "issues" ||
        visualReview != nil && !(allPagesReviewed && visualReview?.status == "pass" && review == "visual_ai")
    }
    var reviewLabel: String {
        if qualityShortfalls?.isEmpty == false { return "Delivered · quality shortfalls in Events" }
        if allPagesReviewed && visualReview?.status == "pass" && review == "visual_ai" { return "Visual AI review · every page" }
        if visualReview != nil { return "Visual review · see Events" }
        return review == "visual_ai" ? (sampled ? "Visual AI review · sample pages" : "Visual AI review · supplied pages") : review == "issues" ? "Delivered · review observations in Events" : "Private delivery · not visually reviewed"
    }
    var reviewDescription: String {
        if qualityShortfalls?.isEmpty == false { return "Delivered after review with remaining quality shortfalls recorded in Events, not an overall quality pass." }
        if allPagesReviewed && visualReview?.status == "pass" && review == "visual_ai" { return "Every rendered page passed visual AI review. Only selected previews may be stored here. This is not human certification or a guarantee of factual, formula or accessibility correctness." }
        if visualReview != nil { return "All-page visual review is not verified as a pass for this delivery. See Events for the recorded result." }
        if review == "visual_ai" { return sampled ? "Visual AI review passed on the first, middle and last pages only. Other pages were not visually reviewed." : "Visual AI review passed on the supplied rendered pages. This is not human certification or a guarantee of factual, formula or accessibility correctness." }
        return review == "issues" ? "The file is delivered. Visual review recorded observations in Events; it did not pass." : "Visual AI review was not completed for this delivery. Mechanical proof images are not a visual AI verdict. Verified identity does not certify contents or design."
    }
    /// Display only. Original filename, hashes, URLs and receipt identity never change.
    var displayTitle: String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { return title }
        var title = (name as NSString).deletingPathExtension
        for pattern in [
            "(?i)^knot-(?:[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}|[a-f0-9]{8})[-_ ]+",
            "(?i)[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}",
            "(?i)(?:^|[-_ ])(?:attempt|retry|revision|rev|v)[-_ ]?[0-9]+(?=$|[-_ ])",
            "(?i)(?:[-_ ]+(?:final|corrected|revised|complete|attempt[0-9]*|v[0-9]+))+$"
        ] { title = title.replacingOccurrences(of: pattern, with: " ", options: .regularExpression) }
        title = title.replacingOccurrences(of: "[-_ ]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Your file" : title.split(separator: " ").map { word in
            let text = String(word)
            return text == text.uppercased() ? text : text.prefix(1).uppercased() + text.dropFirst()
        }.joined(separator: " ")
    }
    var styleLabel: String {
        if let label = deliveryLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty { return label }
        switch format {
        case "pdf": return "PDF document"
        case "docx": return "Word document"
        case "xlsx": return "Spreadsheet"
        case "pptx": return "Slide deck"
        case "html": return "Interactive file"
        case "md", "txt": return "Text document"
        case "csv", "json": return "Data file"
        default: return "\(format.uppercased()) file"
        }
    }
    var identityLine: String { details + " · Verified identity" }
    var details: String { "\(format.uppercased()) · \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))" }
}

@MainActor enum WhisperKnotDocumentService {
    static func resource(_ document: WhisperKnotDocument, bot: String, conversationID: UUID, pageIndex: Int? = nil) async throws -> Data {
        guard document.valid else { throw URLError(.resourceUnavailable) }
        var fields: [String: WhisperKnotReceiptJSON] = ["action": .string(pageIndex == nil ? "file" : "preview"), "documentID": .string(document.id)]
        if let pageIndex {
            guard document.proofPages.indices.contains(pageIndex) else { throw URLError(.resourceUnavailable) }
            fields["pageIndex"] = .number(Double(pageIndex))
        }
        let data: Data
        if bot == WhisperKnotDMArtifacts.storageBot {
            guard pageIndex == nil else { throw URLError(.resourceUnavailable) }
            data = try await WhisperKnotArtifactSharing.resource(conversationID, action: "file")
        } else {
            data = try await WhisperKnotShellEvidenceService.fetch("documents", bot: bot, conversationID: conversationID.uuidString.lowercased(), fields: fields)
        }
        if pageIndex == nil { try await verify(data, size: document.size, sha256: document.sha256) }
        else { guard data.count <= 1_800_000, Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10] else { throw URLError(.cannotDecodeContentData) } }
        return data
    }
    static func asset(_ document: WhisperKnotDocument, asset: WhisperKnotDocument.Asset, bot: String, conversationID: UUID) async throws -> Data {
        guard document.valid, document.bundle?.assets.contains(where: { $0.resourceID == asset.resourceID && $0.sha256 == asset.sha256 }) == true else { throw URLError(.resourceUnavailable) }
        let data: Data
        if bot == WhisperKnotDMArtifacts.storageBot {
            data = try await WhisperKnotArtifactSharing.resource(conversationID, action: "asset", resourceID: asset.resourceID)
        } else {
            data = try await WhisperKnotShellEvidenceService.fetch("documents", bot: bot, conversationID: conversationID.uuidString.lowercased(), fields: ["action": .string("asset"), "documentID": .string(document.id), "resourceID": .number(Double(asset.resourceID))])
        }
        try await verify(data, size: asset.size, sha256: asset.sha256)
        return data
    }
    @concurrent private static func verify(_ data: Data, size: Int, sha256: String) async throws {
        try Task.checkCancellation()
        guard data.count == size, SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == sha256 else { throw URLError(.cannotDecodeContentData) }
    }
    static func list(bot: String, conversationID: UUID) async throws -> [WhisperKnotDocument] {
        struct Result: Decodable { let documents: [WhisperKnotDocument] }
        let data = try await WhisperKnotShellEvidenceService.fetch("documents", bot: bot, conversationID: conversationID.uuidString.lowercased(), fields: ["action": .string("list")])
        let value = try JSONDecoder().decode(Result.self, from: data)
        guard value.documents.count <= 500 else { throw URLError(.cannotDecodeContentData) }
        return value.documents.filter(\.valid)
    }
    static func eraseForAccountRemoval() async throws {
        let generation = AccountStorage.generation, owner = AccountStorage.currentUserID.lowercased()
        let auth = try await SupabaseService.shared.client.auth.session
        guard auth.user.id.uuidString.lowercased() == owner, generation == AccountStorage.generation else { throw CancellationError() }
        let config = URLSessionConfiguration.ephemeral; config.urlCache = nil
        let transport = URLSession(configuration: config)
        defer { transport.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: WhisperKnotBackend.origin + "/knot/documents")!)
        request.httpMethod = "DELETE"; request.timeoutInterval = 20
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "X-Whisper-Authorization")
        let (_, response) = try await transport.data(for: request)
        guard generation == AccountStorage.generation, (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    }
}

/// Always mounted outside lazy messages. The parent places returned cards at
/// their source turn; loading and original retention do not depend on scrolling.
struct WhisperKnotDocumentsView: View {
    let bot: WhisperKnotBot
    let conversationID: UUID
    var revision: Int = 0
    var working = false
    var enabled = true
    var anchoredIDs = Set<UUID>()
    var loaded: ([WhisperKnotDocument]) -> Void = { _ in }
    var contentChanged: () -> Void = {}
    @Environment(\.scenePhase) private var phase
    @State private var documents: [WhisperKnotDocument] = []
    @State private var refreshID = UUID()
    @State private var generation = AccountStorage.generation
    @State private var unavailable = false
    @State private var retained = Set<String>()
    private var key: String { "\(bot.rawValue):\(conversationID):\(revision):\(working):\(phase):\(enabled):\(refreshID)" }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WhisperKnotDocumentRows(documents: documents.filter { document in
                guard let source = document.sourceMessageID.flatMap(UUID.init(uuidString:)) else { return true }
                return !anchoredIDs.contains(source)
            }, bot: bot, conversationID: conversationID, enabled: enabled, deferThumbnails: working)
            if unavailable && enabled {
                Button { refreshID = UUID() } label: { Label("Files couldn’t sync. Tap to retry", systemImage: "arrow.clockwise").font(.footnote).foregroundStyle(.secondary) }
                    .buttonStyle(.plain).frame(minHeight: 44)
            }
        }
        .task(id: key) { await load() }
        .onChange(of: documents.map(\.id)) { _, _ in loaded(documents); contentChanged() }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperKnotContextChanged"))) { _ in documents = []; loaded([]); refreshID = UUID() }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in documents = []; loaded([]) }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperKnotFilesDeleted"))) { note in if note.object as? UUID == conversationID { documents = []; loaded([]) } }
    }
    private func load() async {
        guard enabled, phase == .active, generation == AccountStorage.generation, let lease = try? WhisperKnotOriginalStore.lease(conversationID) else { return }
        let local = WhisperKnotOriginalStore.documents(bot: bot.rawValue, lease: lease)
        if documents.isEmpty { documents = local; loaded(local) }
        do {
            let remote = try await WhisperKnotDocumentService.list(bot: bot.rawValue, conversationID: conversationID)
            guard !Task.isCancelled, lease.valid else { return }
            // Retain existing identities even if a legacy server has already
            // expired its snapshot. Only an explicit conversation deletion erases.
            // Include cards still in memory after a failed metadata write. A
            // later empty response from the new backend must not erase them.
            let retainedCards = try WhisperKnotOriginalStore.merged(local, retaining: documents)
            let value = try WhisperKnotOriginalStore.merged(remote, retaining: retainedCards)
            documents = value; loaded(value); unavailable = false
            do { try WhisperKnotOriginalStore.save(value, bot: bot.rawValue, lease: lease) }
            catch { unavailable = true } // A metadata-write failure must not hide the card or skip original retention.
            // Retain newest originals independently of visible cards. Bound eager
            // work to the byte budget; older evictions refetch on Preview/Share.
            guard !working else { return }
            var eagerBudget = 200_000_000
            for document in remote.reversed() where document.expires > Date() && !retained.contains(document.id) {
                let bytes = document.size + (document.bundle?.assets.reduce(0, { $0 + $1.size }) ?? 0)
                guard bytes <= eagerBudget else { continue }; eagerBudget -= bytes
                guard !Task.isCancelled, lease.valid else { return }
                do {
                    _ = try await WhisperKnotOriginalStore.original(document, bot: bot.rawValue, conversationID: conversationID)
                    if document.format == "html" { _ = try await WhisperKnotOriginalStore.bundle(document, bot: bot.rawValue, conversationID: conversationID) }
                    retained.insert(document.id)
                } catch { if !Task.isCancelled { print("knot_original_retention_unavailable") } }
            }
        } catch { if !Task.isCancelled, lease.valid { unavailable = true } }
    }
}

struct WhisperKnotDocumentRows: View {
    let documents: [WhisperKnotDocument]
    let bot: WhisperKnotBot
    let conversationID: UUID
    var enabled = true
    var deferThumbnails = false
    var directMessage = false
    @State private var selected: WhisperKnotDocument?
    var body: some View {
        ForEach(documents) { document in
            if !directMessage, let note = document.chatDeliveryNote {
                WhisperKnotReplyBubble(text: note, bot: bot)
            }
            WhisperKnotDocumentTile(document: document, bot: bot, conversationID: conversationID, enabled: enabled, deferThumbnails: deferThumbnails, directMessage: directMessage) {
                selected = document
            }
        }
        .fullScreenCover(item: $selected) { document in WhisperKnotDocumentPreview(document: document, bot: bot, conversationID: conversationID, directMessage: directMessage) }
        .onChange(of: enabled) { _, value in if !value { selected = nil } }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperKnotContextChanged"))) { _ in selected = nil }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in selected = nil }
    }
}

/// Measure at the reduced width, rather than scaling text or shrinking only
/// the tablet cap. Hit targets and Dynamic Type retain their native sizes.
struct WhisperKnotDocumentCardLayout: Layout {
    let pagePreview: Bool
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = Self.width(proposed: proposal.width, pagePreview: pagePreview)
        let height = subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: nil)).height ?? 0
        return CGSize(width: width, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
    static func width(proposed: CGFloat?, pagePreview: Bool) -> CGFloat {
        let cap: CGFloat = pagePreview ? 440 : 300
        let available = proposed.flatMap { $0.isFinite ? max(0, $0) : nil } ?? cap
        return min(cap, available) * (pagePreview ? 0.85 : 1)
    }
}
private struct WhisperKnotDocumentCardSizing: ViewModifier {
    let pagePreview: Bool
    func body(content: Content) -> some View {
        WhisperKnotDocumentCardLayout(pagePreview: pagePreview) { content }
    }
}

private struct WhisperKnotDocumentTile: View {
    let document: WhisperKnotDocument
    let bot: WhisperKnotBot
    let conversationID: UUID
    let enabled: Bool
    let deferThumbnails: Bool
    let directMessage: Bool
    let open: () -> Void
    private var storageBot: String { directMessage ? WhisperKnotDMArtifacts.storageBot : bot.rawValue }
    @State private var showFriendShare = false
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var image: UIImage?
    @State private var excerpt: String?
    @State private var original: URL?
    @State private var pin: UUID?
    @State private var visible = false
    @State private var htmlSession: WhisperKnotHTMLSession?
    @State private var previewGeneration = UUID()
    @State private var previewUnavailable = false
    private var interactive: Bool { document.format == "html" }
    private var textFile: Bool { ["md", "txt", "csv", "json", "js", "css", "py", "ts", "yaml", "yml", "rst", "tex", "log"].contains(document.format) }
    private var pagePreview: Bool { interactive || document.format == "pdf" || (!textFile && document.proofPages.first == 1) }
    private var tint: Color {
        switch document.format {
        case "pdf": .red
        case "docx": .blue
        case "xlsx", "csv": .green
        case "pptx": .orange
        case "html": .indigo
        default: Color(uiColor: .label)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if interactive {
                // Never wrap the live page in the card's open Button: buttons,
                // canvas taps and drags belong directly to the delivered page.
                livePage.padding(.horizontal, 4).padding(.top, 4)
                Button(action: open) { fileHeading }
                    .buttonStyle(.plain)
                    .accessibilityHint("Expands this same interactive page without restarting it.")
            } else {
                Button(action: open) {
                    VStack(alignment: .leading, spacing: 0) {
                        if pagePreview { pageThumbnail.padding(.horizontal, 4).padding(.top, 4) }
                        else if textFile { textThumbnail.padding(.horizontal, 4).padding(.top, 4) }
                        fileHeading
                    }.contentShape(.rect)
                }.buttonStyle(.plain)
            }
        }
        .foregroundStyle(.primary)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 22))
        .overlay(alignment: .bottomTrailing) {
            Menu {
                Button(interactive ? "Open interactive preview" : "Open document", systemImage: interactive ? "play.rectangle" : "doc.text", action: open)
                Button("Send to a friend", systemImage: "paperplane") { showFriendShare = true }
                if let original {
                    ShareLink(item: original) { Label("Share or save original", systemImage: "square.and.arrow.up") }
                } else {
                    Button("Open to share or save", systemImage: "square.and.arrow.up", action: open)
                }
            } label: {
                Image(systemName: "ellipsis").font(.body.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(width: 44, height: 44).contentShape(.rect)
            }
            .padding(.trailing, 3).padding(.bottom, 12)
            .accessibilityLabel("Options for \(document.displayTitle)")
        }
        .sheet(isPresented: $showFriendShare) { WhisperKnotArtifactShareSheet(document: document, bot: storageBot, conversationID: conversationID) }
        .modifier(WhisperKnotDocumentCardSizing(pagePreview: pagePreview))
        .disabled(!enabled)
        .accessibilityElement(children: .contain)
        .accessibilityHint(interactive ? "Live delivered HTML. Interact here, or expand using the file title or options." : document.styleLabel + ". Opens the delivered original; the thumbnail is only a preview.")
        .task(id: "\(document.id):\(bot.rawValue):\(conversationID):\(enabled):\(phase):\(visible):\(deferThumbnails)") { await loadPreview() }
        .onAppear { visible = true }
        .onChange(of: deferThumbnails) { _, value in
            if value && !interactive { previewGeneration = UUID() }
        }
        .onChange(of: phase) { _, value in if value != .active && !interactive { clear() } }
        .onChange(of: enabled) { _, value in if !value { clear() } }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperKnotContextChanged"))) { _ in clear() }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in clear() }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperKnotFilesDeleted"))) { note in if note.object as? UUID == conversationID { clear() } }
        .onDisappear { visible = false; clear() }
    }
    private var pageThumbnail: some View {
        Color(uiColor: .tertiarySystemBackground)
            .aspectRatio(1.5, contentMode: .fit)
            .overlay {
                if let image {
                    GeometryReader { geometry in
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                            .clipped()
                    }
                } else {
                    Image(systemName: "doc.richtext").font(.largeTitle).foregroundStyle(.tertiary)
                }
            }
            .clipShape(.rect(cornerRadius: 18))
            .accessibilityLabel(interactive ? "HTML thumbnail. Open to interact with this file." : image == nil ? "Document preview unavailable. Open to retry." : "Document thumbnail, page 1 of \(document.pages)")
    }
    private var fileHeading: some View {
        HStack(spacing: 12) {
            fileIcon
            VStack(alignment: .leading, spacing: 3) {
                Text(document.displayTitle).font(.body).lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                Text(interactive ? "Expand interactive preview" : document.details).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 14).padding(.trailing, 48).padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
    }
    private var livePage: some View {
        ZStack {
            Color(uiColor: .tertiarySystemBackground)
            if let htmlSession, htmlSession.valid {
                if htmlSession.failed {
                    Button("Reopen interactive preview", action: open).frame(minHeight: 44)
                } else {
                    WhisperKnotLiveHTML(session: htmlSession)
                    if htmlSession.loading { ProgressView("Opening preview…").padding(12).background(.regularMaterial, in: .rect(cornerRadius: 12)).allowsHitTesting(false) }
                }
            } else {
                Button(action: open) {
                    Label(previewUnavailable || deferThumbnails ? "Open interactive file" : "Preparing preview…", systemImage: "play.rectangle")
                        .font(.subheadline).frame(maxWidth: .infinity, maxHeight: .infinity)
                }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .frame(height: 320).clipShape(.rect(cornerRadius: 18))
    }
    private var textThumbnail: some View {
        Text(verbatim: excerpt ?? "Open the original to read this file.")
            .font(.subheadline).foregroundStyle(.secondary)
            .lineLimit(3).multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
            .padding(12)
            .background(Color(uiColor: .tertiarySystemBackground), in: .rect(cornerRadius: 18))
            .accessibilityLabel(excerpt.map { "Text preview: " + $0 } ?? "Text preview unavailable")
    }
    private var fileIcon: some View {
        Image(systemName: "doc.fill")
            .font(.system(size: 38)).foregroundStyle(tint.gradient)
            .overlay(alignment: .bottom) {
                Text(document.format.uppercased()).font(.system(size: 8, weight: .bold))
                    .foregroundStyle(["pdf", "docx", "xlsx", "csv", "pptx", "html"].contains(document.format) ? Color.white : Color(uiColor: .systemBackground))
                    .lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 3).padding(.bottom, 6)
            }
            .frame(width: 30, height: 40).accessibilityHidden(true)
    }
    private func clear() {
        previewGeneration = UUID(); htmlSession = nil; previewUnavailable = false
        image = nil; excerpt = nil; original = nil
        WhisperKnotOriginalStore.releasePin(pin); pin = nil
    }
    private func loadPreview() async {
        guard enabled, visible, !deferThumbnails, image == nil, phase == .active, let lease = try? WhisperKnotOriginalStore.lease(conversationID, directMessage: directMessage) else { return }
        let generation = previewGeneration
        do {
            if interactive {
                guard htmlSession == nil else { return }
                let session = try await WhisperKnotHTMLSessions.open(document, bot: storageBot, conversationID: conversationID)
                guard !Task.isCancelled, lease.valid, generation == previewGeneration else { return }
                original = session.original; htmlSession = session
                return
            }
            if pagePreview && document.format != "pdf" {
                let data = try await WhisperKnotDocumentService.resource(document, bot: storageBot, conversationID: conversationID, pageIndex: 0)
                guard !Task.isCancelled, lease.valid else { return }; image = UIImage(data: data)
                return
            }
            // Opaque files and large text originals stay on-demand in the opened viewer.
            guard document.format == "pdf" || (textFile && document.size <= 1_000_000) else { return }
            if pin == nil { pin = try WhisperKnotOriginalStore.pin(document, bot: storageBot, conversationID: conversationID) }
            let url = try await WhisperKnotOriginalStore.original(document, bot: storageBot, conversationID: conversationID)
            guard !Task.isCancelled, lease.valid else { return }
            original = url
            if document.format == "pdf" {
                let value = try await thumbnail(url)
                guard !Task.isCancelled, lease.valid else { return }; image = value
            } else if textFile {
                let value = try await textExcerpt(url)
                guard !Task.isCancelled, lease.valid else { return }; excerpt = value
            }
        } catch {
            // Keep the original card and its explicit open/retry path.
            if !Task.isCancelled, lease.valid, generation == previewGeneration { previewUnavailable = true }
        }
    }
    @concurrent private func textExcerpt(_ url: URL) async throws -> String {
        try Task.checkCancellation()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        // Display-only excerpt of the verified original, never completeness evidence.
        let data = try handle.read(upToCount: 4096) ?? Data()
        return String(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).prefix(420))
    }
    @concurrent private func thumbnail(_ url: URL) async throws -> UIImage {
        try Task.checkCancellation()
        guard let pdf = PDFDocument(url: url), !pdf.isLocked, pdf.pageCount == document.pages,
              let page = pdf.page(at: 0) else { throw WhisperKnotFileError.preview }
        let size = page.bounds(for: .mediaBox)
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { throw WhisperKnotFileError.preview }
        return page.thumbnail(of: CGSize(width: 880, height: 1180), for: .mediaBox)
    }
}

private struct WhisperKnotDocumentPreview: View {
    let document: WhisperKnotDocument
    let bot: WhisperKnotBot
    let conversationID: UUID
    let directMessage: Bool
    private var storageBot: String { directMessage ? WhisperKnotDMArtifacts.storageBot : bot.rawValue }
    @State private var showFriendShare = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var original: URL?
    @State private var files: [String: URL] = [:]
    @State private var text: String?
    @State private var player: AVPlayer?
    @State private var editing = false
    @State private var draftText = ""
    @State private var editedURL: URL?
    @State private var savingCopy = false
    @State private var showExport = false
    @State private var showIdentity = false
    @State private var confirmClose = false
    @State private var currentPage = 1
    @State private var htmlSession: WhisperKnotHTMLSession?
    private var hasEdits: Bool { document.format == "md" && text != nil && draftText != text }
    private var exportURLs: [URL] {
        if hasEdits { return editedURL.map { [$0] } ?? [] }
        if files.count > 1 { return files.keys.sorted().compactMap { files[$0] } }
        return original.map { [$0] } ?? []
    }
    @State private var issue: String?
    @State private var exportIssue = false
    @State private var previewFailed = false
    @State private var loading = true
    @State private var retry = UUID()
    @State private var invalidated = false
    @State private var pin: UUID?
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if loading { ProgressView("Retrieving original file…").frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if let original {
                    if previewFailed { ContentUnavailableView("Preview unavailable", systemImage: "doc.questionmark", description: Text("The original is still available to share or save.")) }
                    else { viewer(original).frame(maxWidth: .infinity, maxHeight: .infinity) }
                } else { ContentUnavailableView("File unavailable", systemImage: "doc.badge.arrow.up", description: Text(issue ?? "The delivery card is kept.")) }
                if let issue {
                    HStack {
                        Text(issue).font(.footnote).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        if !loading {
                            Button("Retry") {
                                if exportIssue { finishEditing() } else { retry = UUID() }
                            }.disabled(savingCopy).frame(minHeight: 44)
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 8)
                }
                if document.format == "html", !files.isEmpty, !loading {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("Interactive preview", systemImage: "hand.tap").font(.subheadline.weight(.medium))
                            Text("Runs locally · external connections blocked").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Button {
                            previewFailed = false; issue = nil; htmlSession?.restart()
                        } label: { Label("Restart", systemImage: "arrow.counterclockwise").font(.subheadline) }
                            .frame(minHeight: 44).accessibilityHint("Restarts the local preview. The delivered original stays unchanged.")
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(Color(uiColor: .secondarySystemBackground))
                }
                if hasEdits {
                    Text("Edited copy · original unchanged. Share or save to keep your edits.")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 8)
                }
            }
            .background(.black)
            .navigationTitle(document.displayTitle).navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { if hasEdits { confirmClose = true } else { dismiss() } } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close file")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if document.format == "md", text != nil {
                        Button {
                            if editing { finishEditing() } else { editing = true }
                        } label: { Image(systemName: editing ? "checkmark" : "pencil") }
                        .disabled(savingCopy)
                        .accessibilityLabel(editing ? "Finish editing copy" : "Edit a copy")
                    }
                    if !editing {
                        Menu {
                            Button("Send original to a friend", systemImage: "paperplane") { showFriendShare = true }
                            if !exportURLs.isEmpty && !savingCopy {
                                ShareLink(items: exportURLs) { Label(hasEdits ? "Share edited copy" : "Share", systemImage: "square.and.arrow.up") }
                                Button(hasEdits ? "Save edited copy to Files" : "Save to Files", systemImage: "folder") { showExport = true }
                            }
                            if hasEdits, let original {
                                ShareLink(item: original) { Label("Share unchanged original", systemImage: "doc") }
                            }
                            Button("File details", systemImage: "info.circle") { showIdentity = true }
                        } label: { Image(systemName: "ellipsis") }
                            .disabled(savingCopy).accessibilityLabel("File options")
                    }
                }
            }
        }
        .environment(\.colorScheme, .dark).tint(.white)
        .sheet(isPresented: $showExport) { WhisperKnotFileExport(urls: exportURLs) { showExport = false } }
        .sheet(isPresented: $showIdentity) { identitySheet }
        .sheet(isPresented: $showFriendShare) { WhisperKnotArtifactShareSheet(document: document, bot: storageBot, conversationID: conversationID) }
        .confirmationDialog("Close edited copy?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Discard local edits and close", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: { Text("Share or save the edited copy to keep it. The delivered original is unchanged.") }
        .task(id: retry) { await load() }
        .onChange(of: phase) { _, value in if value != .active { player?.pause() } }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperKnotContextChanged"))) { _ in clear() }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in clear() }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperKnotFilesDeleted"))) { note in if note.object as? UUID == conversationID { clear() } }
        .onDisappear {
            // Nested system pickers may cover the reader. Keep their source URLs
            // and draft alive until the reader itself is actually dismissed.
            guard !showExport, !showIdentity, !showFriendShare else { return }
            dispose()
        }
    }
    @ViewBuilder private func viewer(_ url: URL) -> some View {
        switch document.format {
        case "pdf":
            WhisperKnotNativePDF(url: url, pages: document.pages, currentPage: $currentPage, failed: failed)
                .overlay(alignment: .topLeading) {
                    Label("\(currentPage) of \(document.pages)", systemImage: "doc.on.doc")
                        .font(.subheadline.monospacedDigit()).foregroundStyle(.black)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.white.opacity(0.94), in: Capsule()).padding(16)
                        .allowsHitTesting(false).accessibilityLabel("Page \(currentPage) of \(document.pages)")
                }
        case "png", "jpg", "jpeg", "webp": WhisperKnotZoomImage(url: url, failed: failed)
        case "html":
            if let htmlSession, htmlSession.valid {
                if htmlSession.failed {
                    ContentUnavailableView("Preview interrupted", systemImage: "arrow.clockwise", description: Text("Tap Restart to reopen this same stored original. Page state may have been lost."))
                } else {
                    WhisperKnotLiveHTML(session: htmlSession, expanded: true)
                        .overlay {
                            if htmlSession.loading { ProgressView("Opening preview…").padding(18).background(.regularMaterial, in: .rect(cornerRadius: 14)).allowsHitTesting(false) }
                        }
                }
            } else { ContentUnavailableView("Interactive preview unavailable", systemImage: "gamecontroller", description: Text("The original is kept. Tap Retry to open it again.")) }
        case "txt", "md", "csv", "json", "js", "css", "py", "ts":
            if let text {
                if document.format == "md", editing { WhisperKnotMarkdownEditor(text: $draftText) }
                else { WhisperKnotFullText(text: document.format == "md" ? draftText : text, markdown: document.format == "md", monospaced: document.format != "md") }
            }
        case "mp3", "m4a", "wav", "mp4", "mov":
            if let player, let item = player.currentItem {
                VideoPlayer(player: player).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onReceive(item.publisher(for: \.status).receive(on: RunLoop.main)) { status in
                        if status == .failed { player.pause(); failed() }
                    }
                    .onReceive(player.publisher(for: \.status).receive(on: RunLoop.main)) { status in
                        if status == .failed { player.pause(); failed() }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification, object: item).receive(on: RunLoop.main)) { _ in
                        player.pause(); failed()
                    }
            }
        case "docx", "xlsx", "pptx", "gif": WhisperKnotQuickLook(url: url, failed: failed)
        default:
            ContentUnavailableView("Original file ready", systemImage: "doc.badge.arrow.up", description: Text("This format is available to share or save. It won’t run inside Whisper."))
        }
    }
    private func failed() { previewFailed = true; issue = WhisperKnotFileError.preview.localizedDescription }
    private func clear() {
        showExport = false; showIdentity = false; showFriendShare = false; editing = false
        dispose(); dismiss()
    }
    private func dispose() {
        invalidated = true
        // Releasing a presentation does not stop or discard its retained HTML
        // session. Account/permission/deletion boundaries invalidate it instead.
        htmlSession = nil
        player?.pause(); player = nil; original = nil; files = [:]; text = nil; draftText = ""
        WhisperKnotEditedCopy.remove(editedURL); editedURL = nil
        WhisperKnotOriginalStore.releasePin(pin); pin = nil
    }
    private var identitySheet: some View {
        NavigationStack {
            List {
                Section("Delivered original") {
                    LabeledContent("File", value: document.name)
                    Text(document.identityLine)
                    Text(document.reviewDescription)
                    if let path = document.sourcePath { Text(path).textSelection(.enabled) }
                    Text("SHA-256 · " + document.sha256).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                if let provenance = document.provenance {
                    Section("Received original") {
                        LabeledContent("From", value: provenance.senderName)
                        LabeledContent("Sent", value: provenance.sentAt)
                        LabeledContent("Saved", value: provenance.savedAt)
                        Text("This is your own copy. The sender’s browser data and game progress are not included.").font(.footnote)
                    }
                }
                Section {
                    Text("The original's identity never changes. Markdown edits are a separate local copy and are not a new verified delivery.")
                }
            }.navigationTitle("File details").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showIdentity = false } } }
        }
    }
    private func finishEditing() {
        editing = false
        guard !savingCopy else { return }
        if exportIssue { issue = nil; exportIssue = false }
        WhisperKnotEditedCopy.remove(editedURL); editedURL = nil
        guard hasEdits, let lease = try? WhisperKnotOriginalStore.lease(conversationID, directMessage: directMessage) else { return }
        let snapshot = draftText
        savingCopy = true
        Task {
            defer { savingCopy = false }
            do {
                let url = try await WhisperKnotEditedCopy.write(snapshot, originalName: document.name)
                guard lease.valid, !invalidated, text != nil, snapshot == draftText else { WhisperKnotEditedCopy.remove(url); return }
                WhisperKnotEditedCopy.remove(editedURL); editedURL = url
            } catch {
                guard lease.valid, !invalidated else { return }
                exportIssue = true
                issue = "The edited copy couldn’t be prepared for export. Your edits are kept here. Tap Retry to try saving the copy again."
            }
        }
    }
    private func load() async {
        guard !invalidated, let lease = try? WhisperKnotOriginalStore.lease(conversationID, directMessage: directMessage) else { return }
        loading = true; previewFailed = false; issue = nil; exportIssue = false; files = [:]; text = nil; player?.pause(); player = nil
        defer { loading = false }
        do {
            if pin == nil { pin = try WhisperKnotOriginalStore.pin(document, bot: storageBot, conversationID: conversationID) }
            let url = try await WhisperKnotOriginalStore.original(document, bot: storageBot, conversationID: conversationID)
            guard lease.valid, !Task.isCancelled, !invalidated else { return }
            original = url
            if document.format == "html" {
                let session = try await WhisperKnotHTMLSessions.open(document, bot: storageBot, conversationID: conversationID)
                guard lease.valid, !Task.isCancelled, !invalidated else { return }
                htmlSession = session
                files = [document.name: session.original]
                // Export the same verified dependency set used by the live page.
                if document.bundle != nil { files = try await WhisperKnotOriginalStore.bundle(document, bot: storageBot, conversationID: conversationID) }
            } else if ["txt", "md", "csv", "json", "js", "css", "py", "ts"].contains(document.format) {
                let value = try await readText(url)
                guard lease.valid, !Task.isCancelled, !invalidated else { return }
                text = value; draftText = value
            } else if ["mp3", "m4a", "wav", "mp4", "mov"].contains(document.format) {
                player = AVPlayer(url: url)
            }
            guard lease.valid, !Task.isCancelled, !invalidated else { original = nil; files = [:]; text = nil; player?.pause(); player = nil; return }
        } catch {
            guard lease.valid, !Task.isCancelled, !invalidated else { return }
            issue = (error as? WhisperKnotFileError)?.localizedDescription ?? "The original file couldn’t be opened. The card is kept. Tap Retry to try again."
            if original != nil && document.format != "html" { previewFailed = true }
        }
    }
    @concurrent private func readText(_ url: URL) async throws -> String {
        try Task.checkCancellation()
        return try String(contentsOf: url, encoding: .utf8)
    }
}
