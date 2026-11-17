import SwiftUI

/// A full-width sponsored placement. Impression timing follows real scroll visibility.
struct WhisperSponsoredAdCard: View {
    let ad: WhisperServedAd
    let service: WhisperFeedAdService
    let isFeedActive: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible: Bool = false
    @State private var hidden: Bool = false
    @State private var showWhy: Bool = false
    @State private var showBrowser: Bool = false
    @State private var showReport: Bool = false
    @State private var showShare: Bool = false
    @State private var reportBusy: Bool = false
    @State private var notice: String?
    @State private var image: UIImage?
    @State private var imageLoaded: Bool = false
    @State private var ctaReady: Bool = false

    private var active: Bool {
        visible && !hidden && isFeedActive && scenePhase == .active
            && !showBrowser && !showWhy && !showReport && !showShare && !reportBusy && notice == nil
    }
    private var impressionEligible: Bool { active && (service.placement == .comments || ad.videoURL != nil || image != nil) }
    // Loading and loaded creatives occupy the same space; fit preserves artwork.
    private let ratio: CGFloat = 4 / 5

    var body: some View {
        Group {
            if hidden {
                HStack {
                    Text("Ad hidden for this visit").font(.footnote).foregroundStyle(WhisperTheme.muted(scheme))
                    Spacer()
                    Button("Undo") { hidden = false }.font(.footnote.weight(.semibold)).frame(minHeight: 44)
                }.padding(.horizontal, 16)
            } else if service.placement == .comments {
                compactContent
            } else if service.placement == .reels {
                reelContent
            } else {
                content
            }
        }
        .foregroundStyle(WhisperTheme.ink(scheme))
        .background(WhisperTheme.surface(scheme))
        .onScrollVisibilityChange(threshold: 0.5) { visible = $0 }
        .onDisappear { visible = false }
        .task(id: "\(ad.id)-\(impressionEligible)") {
            ctaReady = false
            guard impressionEligible else { return }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard impressionEligible, !Task.isCancelled else { return }
            await service.impression(ad.id)
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard impressionEligible, !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) { ctaReady = true }
        }
        .task(id: ad.image_url) {
            image = nil
            imageLoaded = false
            let loaded: UIImage?
            if let url = ad.imageURL { loaded = await WhisperImageCache.load(url, maxPixelSize: 1536) }
            else { loaded = nil }
            guard !Task.isCancelled else { return }
            image = loaded
            imageLoaded = true
        }
        .sheet(isPresented: $showBrowser) {
            if let url = ad.destination { WhisperPitchSafariSheet(url: url) }
        }
        .sheet(isPresented: $showShare) {
            if let url = ad.destination { ShareActivityView(items: [url]) }
        }
        .alert("About this ad", isPresented: $showWhy) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This is a paid placement from \(ad.business_name). Whisper's ad rotation can use account roles and follower ranges selected by advertisers. Hiding this card only affects this visit.")
        }
        .confirmationDialog("Report this ad", isPresented: $showReport, titleVisibility: .visible) {
            Button("Misleading or scam") { report("Misleading or scam") }
            Button("Inappropriate content") { report("Inappropriate content") }
            Button("Other concern") { report("Other concern") }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Whisper Ads", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) { notice = nil }
        } message: { Text(notice ?? "") }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                WhisperCachedAsyncImage(url: WhisperServedAd.webURL(ad.business_logo_url)) { phase in
                    if let logo = phase.image { logo.resizable().scaledToFill() }
                    else { Image(systemName: "building.2").font(.body).frame(maxWidth: .infinity, maxHeight: .infinity).background(WhisperTheme.card(scheme)) }
                }.frame(width: 38, height: 38).clipShape(.circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ad.business_name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("Sponsored").font(.caption).foregroundStyle(WhisperTheme.muted(scheme))
                }
                Spacer(minLength: 8)
                Text("Ad").font(.caption2.weight(.semibold)).foregroundStyle(WhisperTheme.muted(scheme))
                Menu {
                    Button("Hide ad", systemImage: "eye.slash") { hidden = true }
                    Button("Why this ad?", systemImage: "info.circle") { showWhy = true }
                    Button("Report ad", systemImage: "flag", role: .destructive) { showReport = true }
                        .disabled(reportBusy)
                    if let url = URL(string: "https://www.mydailywhisper.com/ad-library") {
                        Link("Ad Library", destination: url)
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }.accessibilityLabel("Ad options")
            }.padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 8)

            Color.black.aspectRatio(ratio, contentMode: .fit)
                .overlay {
                    if let video = ad.videoURL, active {
                        WhisperVideoView(url: video, startsMuted: true)
                    } else if let image {
                        Image(uiImage: image).resizable().scaledToFit().allowsHitTesting(false)
                    } else if !imageLoaded {
                        ProgressView().tint(.white)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: ad.videoURL == nil ? "photo" : "play.circle").font(.title)
                            Text(ad.videoURL == nil ? "Creative unavailable" : "Video ad").font(.caption)
                        }.foregroundStyle(.white.opacity(0.8))
                    }
                }.clipped()

            if ad.destination != nil {
                Button(action: openAd) {
                    HStack {
                        Text(ad.cta_label.isEmpty ? "Learn more" : ad.cta_label).font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold))
                    }.padding(.horizontal, 16).frame(minHeight: 46)
                        .foregroundStyle(ctaReady ? WhisperTheme.surface(scheme) : WhisperTheme.ink(scheme))
                        .background(ctaReady ? WhisperTheme.ink(scheme) : WhisperTheme.card(scheme))
                }.buttonStyle(.plain).accessibilityHint("Opens the advertiser's website")
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(ad.headline).font(.subheadline.weight(.semibold))
                    Spacer()
                    if ad.destination != nil {
                        Button { showShare = true } label: { Image(systemName: "paperplane").frame(width: 44, height: 44) }
                            .accessibilityLabel("Share ad")
                    }
                }
                if let body = ad.body, !body.isEmpty {
                    Text(body).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.horizontal, 16).padding(.bottom, 16)
        }
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "building.2").font(.subheadline)
                Text(ad.business_name).font(.caption.weight(.semibold)).lineLimit(1)
                Text("Sponsored · Ad").font(.caption2).foregroundStyle(WhisperTheme.muted(scheme))
                Spacer(minLength: 0)
                placementMenu
            }
            Text(ad.headline).font(.subheadline.weight(.semibold))
            if let body = ad.body { Text(body).font(.footnote).lineLimit(3) }
            if ad.destination != nil {
                Button(action: openAd) {
                    HStack { Text(ad.cta_label.isEmpty ? "Learn more" : ad.cta_label); Spacer(); Image(systemName: "arrow.up.right") }
                        .font(.footnote.weight(.semibold)).frame(minHeight: 44)
                }.buttonStyle(.plain)
            }
        }.padding(16)
    }

    private var reelContent: some View {
        GeometryReader { geometry in
            Color.black
                .overlay {
                    if let video = ad.videoURL, active {
                        WhisperVideoView(url: video, startsMuted: true)
                            .frame(width: geometry.size.width, height: geometry.size.height * 0.62)
                    } else if let image {
                        Image(uiImage: image).resizable().scaledToFit().allowsHitTesting(false)
                    } else { Image(systemName: "play.rectangle").font(.largeTitle).foregroundStyle(.white.opacity(0.5)) }
                }
                .clipped()
                .overlay(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ad.business_name).font(.headline)
                                Text("Sponsored · Ad").font(.caption)
                            }
                            Spacer()
                            placementMenu
                        }
                        Text(ad.headline).font(.title3.weight(.semibold)).lineLimit(2)
                        if let body = ad.body { Text(body).font(.subheadline).lineLimit(3) }
                        if ad.destination != nil {
                            Button(action: openAd) {
                                HStack { Text(ad.cta_label.isEmpty ? "Learn more" : ad.cta_label); Spacer(); Image(systemName: "arrow.up.right") }
                                    .font(.subheadline.weight(.semibold)).padding(.horizontal, 16).frame(minHeight: 48)
                                    .foregroundStyle(.black).background(.white, in: .rect(cornerRadius: 12))
                            }.buttonStyle(.plain)
                        }
                    }
                    .foregroundStyle(.white).padding(.horizontal, 20).padding(.top, 36).padding(.bottom, 100)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                }
        }
    }

    private var placementMenu: some View {
        Menu {
            Button("Hide ad", systemImage: "eye.slash") { hidden = true }
            Button("Why this ad?", systemImage: "info.circle") { showWhy = true }
            if ad.destination != nil { Button("Share ad", systemImage: "paperplane") { showShare = true } }
            Button("Report ad", systemImage: "flag", role: .destructive) { showReport = true }.disabled(reportBusy)
            if let url = URL(string: "https://www.mydailywhisper.com/ad-library") { Link("Ad Library", destination: url) }
        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
        .accessibilityLabel("Ad options")
    }

    private func openAd() {
        guard ad.destination != nil else { return }
        Haptics.tap()
        showBrowser = true
        Task { await service.click(ad.id) }
    }

    private func report(_ reason: String) {
        guard !reportBusy else { return }
        reportBusy = true
        let viewerID = AccountStorage.currentUserID
        Task {
            guard viewerID == AccountStorage.currentUserID else { reportBusy = false; return }
            let submitted = await WhisperProblemReports.submit(kind: "bug", details: "Ad report: \(reason)",
                context: ["area": "ads", "adId": ad.id, "advertiser": ad.business_name, "platform": "ios"])
            reportBusy = false
            guard viewerID == AccountStorage.currentUserID else { return }
            notice = submitted ? "Your ad report was sent for review." : "Your report wasn't sent. Please try again."
        }
    }
}
