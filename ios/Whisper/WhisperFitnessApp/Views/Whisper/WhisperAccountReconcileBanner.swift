import SwiftUI

/// Slim amber banner that appears at the top of `WhisperRootView` when the
/// live Supabase session UID differs from the locally cached
/// `AccountStorage.currentUserID`. One tap fires the server-side relink RPC
/// (`whisper_relink_client_uid`) which rewrites `client_user_id` from the
/// old UID to the new one across coach tables in a single transaction.
struct WhisperAccountReconcileBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var identity = WhisperIdentityService.shared

    var body: some View {
        if let mismatch = identity.mismatch {
            content(mismatch: mismatch)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func content(mismatch: WhisperIdentityService.UIDMismatch) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Your account ID changed")
                    .font(.subheadline.weight(.semibold))
                Text("Relink to restore coach messages and proposals.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let err = identity.lastError {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await identity.relink() }
            } label: {
                Group {
                    if identity.isRelinking {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Text("Relink")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .frame(minWidth: 64)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(Color.orange, in: .capsule)
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(identity.isRelinking)

            Button {
                identity.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }
}
