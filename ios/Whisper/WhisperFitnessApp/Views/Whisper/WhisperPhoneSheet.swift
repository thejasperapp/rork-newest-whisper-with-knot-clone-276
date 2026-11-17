import SwiftUI

/// Reusable sheet for adding / updating the user's phone number. Used from
/// onboarding ("Add phone") and from Settings → "Phone number". Validates +
/// normalizes to E.164 via `WhisperPhoneService.normalizeE164` before saving.
struct WhisperPhoneSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var phoneService = WhisperPhoneService.shared

    @State private var dialCode: String = "+1"
    @State private var number: String = ""
    @State private var errorMessage: String?
    @State private var isSaving: Bool = false
    @State private var ownerGeneration: UUID = AccountStorage.generation
    @State private var removalNeedsRetry: Bool = false

    /// Optional completion fired after a successful save. The presenting
    /// screen can use this to advance an onboarding step or refresh state.
    var onSaved: (() -> Void)? = nil

    private struct Country: Identifiable, Hashable {
        let id: String  // dial code
        let flag: String
        let name: String
    }

    // A pragmatic set of countries. Country pickers in the App Store are
    // usually exhaustive — this list covers the bulk of real users without
    // shipping a 250-row catalog.
    private let countries: [Country] = [
        .init(id: "+1",   flag: "🇺🇸", name: "United States / Canada"),
        .init(id: "+44",  flag: "🇬🇧", name: "United Kingdom"),
        .init(id: "+61",  flag: "🇦🇺", name: "Australia"),
        .init(id: "+64",  flag: "🇳🇿", name: "New Zealand"),
        .init(id: "+353", flag: "🇮🇪", name: "Ireland"),
        .init(id: "+33",  flag: "🇫🇷", name: "France"),
        .init(id: "+49",  flag: "🇩🇪", name: "Germany"),
        .init(id: "+34",  flag: "🇪🇸", name: "Spain"),
        .init(id: "+39",  flag: "🇮🇹", name: "Italy"),
        .init(id: "+31",  flag: "🇳🇱", name: "Netherlands"),
        .init(id: "+46",  flag: "🇸🇪", name: "Sweden"),
        .init(id: "+47",  flag: "🇳🇴", name: "Norway"),
        .init(id: "+45",  flag: "🇩🇰", name: "Denmark"),
        .init(id: "+358", flag: "🇫🇮", name: "Finland"),
        .init(id: "+351", flag: "🇵🇹", name: "Portugal"),
        .init(id: "+30",  flag: "🇬🇷", name: "Greece"),
        .init(id: "+48",  flag: "🇵🇱", name: "Poland"),
        .init(id: "+52",  flag: "🇲🇽", name: "Mexico"),
        .init(id: "+55",  flag: "🇧🇷", name: "Brazil"),
        .init(id: "+54",  flag: "🇦🇷", name: "Argentina"),
        .init(id: "+56",  flag: "🇨🇱", name: "Chile"),
        .init(id: "+57",  flag: "🇨🇴", name: "Colombia"),
        .init(id: "+91",  flag: "🇮🇳", name: "India"),
        .init(id: "+81",  flag: "🇯🇵", name: "Japan"),
        .init(id: "+82",  flag: "🇰🇷", name: "South Korea"),
        .init(id: "+86",  flag: "🇨🇳", name: "China"),
        .init(id: "+852", flag: "🇭🇰", name: "Hong Kong"),
        .init(id: "+65",  flag: "🇸🇬", name: "Singapore"),
        .init(id: "+60",  flag: "🇲🇾", name: "Malaysia"),
        .init(id: "+62",  flag: "🇮🇩", name: "Indonesia"),
        .init(id: "+63",  flag: "🇵🇭", name: "Philippines"),
        .init(id: "+66",  flag: "🇹🇭", name: "Thailand"),
        .init(id: "+84",  flag: "🇻🇳", name: "Vietnam"),
        .init(id: "+90",  flag: "🇹🇷", name: "Turkey"),
        .init(id: "+971", flag: "🇦🇪", name: "United Arab Emirates"),
        .init(id: "+966", flag: "🇸🇦", name: "Saudi Arabia"),
        .init(id: "+972", flag: "🇮🇱", name: "Israel"),
        .init(id: "+27",  flag: "🇿🇦", name: "South Africa"),
        .init(id: "+234", flag: "🇳🇬", name: "Nigeria"),
        .init(id: "+254", flag: "🇰🇪", name: "Kenya")
    ]

    private var currentCountry: Country {
        countries.first(where: { $0.id == dialCode }) ?? countries[0]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        inputCard
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                        }
                        infoBlock
                        if phoneService.phone != nil || removalNeedsRetry {
                            Button(role: .destructive) {
                                Haptics.warning()
                                guard !isSaving else { return }
                                isSaving = true
                                Task {
                                    let error = await phoneService.remove()
                                    guard ownerGeneration == AccountStorage.generation else { return }
                                    isSaving = false
                                    if let error {
                                        errorMessage = error
                                        removalNeedsRetry = true
                                    } else {
                                        onSaved?()
                                        dismiss()
                                    }
                                }
                            } label: {
                                Text("Remove phone number")
                                    .font(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(WhisperTheme.card(colorScheme), in: Capsule())
                                    .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                            .disabled(isSaving)
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(phoneService.phone == nil ? "Add phone" : "Phone number")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(WhisperTheme.ink(colorScheme))
                        } else {
                            Text("Save").font(.body.weight(.bold))
                                .foregroundStyle(canSave ? WhisperTheme.ink(colorScheme) : WhisperTheme.muted(colorScheme))
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .task {
                await phoneService.hydrate()
                if let e164 = phoneService.phone, e164.hasPrefix("+") {
                    // Best-effort split into dial code + remainder.
                    if let match = countries.first(where: { e164.hasPrefix($0.id) }) {
                        dialCode = match.id
                        number = String(e164.dropFirst(match.id.count))
                    } else {
                        number = String(e164.dropFirst())
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in dismiss() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(phoneService.phone == nil ? "Add your phone number" : "Update your phone number")
                .font(.title2.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Used so friends in your contacts can find you on Whisper. Never shown on your profile.")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var inputCard: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(countries) { c in
                    Button {
                        Haptics.tap()
                        dialCode = c.id
                    } label: {
                        Text("\(c.flag)  \(c.name)  \(c.id)")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(currentCountry.flag)
                        .font(.title3)
                    Text(currentCountry.id)
                        .font(.body.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
            }
            .buttonStyle(.plain)

            TextField("Phone number", text: $number)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .font(.body)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                .onChange(of: number) { _, _ in errorMessage = nil }
        }
    }

    private var infoBlock: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.body.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            VStack(alignment: .leading, spacing: 4) {
                Text("You control discovery")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("Your number is stored on your account. Contact matching uses hashes of your number and email, not your address book’s raw details. Turn off discovery in Settings.")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
    }

    private var canSave: Bool {
        WhisperPhoneService.normalizeE164(dialCode + number) != nil
    }

    private func save() async {
        guard !isSaving, ownerGeneration == AccountStorage.generation else { return }
        Haptics.tap()
        isSaving = true
        defer { isSaving = false }
        let combined = dialCode + number
        let saveError = await phoneService.save(rawPhone: combined)
        guard ownerGeneration == AccountStorage.generation else { return }
        if let err = saveError {
            errorMessage = err
            Haptics.warning()
            return
        }
        Haptics.success()
        onSaved?()
        dismiss()
    }
}
