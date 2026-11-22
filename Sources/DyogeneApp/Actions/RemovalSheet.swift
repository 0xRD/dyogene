import DyogeneCore
import SwiftUI

/// The only way to remove anything: a sheet that says exactly what will happen, where Cancel is
/// the default button and the confirm button must be held down.
struct RemovalSheet: View {
    @Bindable var request: RemovalRequest
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 28))
                    .foregroundStyle(request.mode == .trash ? Color.lanternInk : Color.danger)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Typeface.display(20))
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            itemList

            ForEach(Array(Set(request.allowedItems.flatMap(\.warnings))).sorted(), id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.lanternInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if request.mode == .secureErase { eraseFacts }

            if request.needsAcknowledgement {
                Toggle(isOn: $request.acknowledged) {
                    Text(request.mode == .secureErase
                         ? "I understand this cannot be undone and that copies may remain in backups or snapshots."
                         : "I understand this skips the Trash and cannot be undone.")
                        .font(.system(size: 12.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.checkbox)
            }

            HStack {
                Button("Cancel") { model.removal = nil }
                    .keyboardShortcut(.defaultAction)
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                Spacer()
                HoldToConfirmButton(title: "Hold to \(request.mode.title)", duration: request.mode.holdDuration,
                                    destructive: request.mode != .trash, enabled: request.canConfirm, hold: request.hold) {
                    model.performRemoval()
                }
            }
            .padding(.top, 4)
        }
        .padding(22)
        .frame(width: 520)
    }

    private var symbol: String {
        switch request.mode {
        case .trash: "trash"
        case .permanent: "trash.slash"
        case .secureErase: "flame"
        }
    }

    private var title: String {
        let count = request.allowedItems.count
        let what = count == 1 ? "“\(request.allowedItems[0].name)”" : "\(count) items"
        switch request.mode {
        case .trash: return "Move \(what) to the Trash?"
        case .permanent: return "Delete \(what) permanently?"
        case .secureErase: return "Erase \(what) securely?"
        }
    }

    private var subtitle: String {
        let size = Format.bytes(request.totalSize)
        switch request.mode {
        case .trash:
            return "\(size) will move to the Trash. You can put it back until the Trash is emptied."
        case .permanent:
            return "\(size) will be deleted right away, without going through the Trash. It cannot be put back."
        case .secureErase:
            return "\(size) will be overwritten with random data, then deleted. It cannot be put back."
        }
    }

    private var itemList: some View {
        VStack(spacing: 0) {
            ForEach(request.items.prefix(8)) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.allowed ? "doc" : "nosign")
                        .foregroundStyle(item.allowed ? Color.inkSecondary : Color.danger)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        Text(item.refusal ?? item.path)
                            .font(.system(size: 10.5))
                            .foregroundStyle(item.allowed ? Color.inkSecondary : Color.danger)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text(Format.bytes(item.size)).font(Typeface.data(12))
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
            }
            if request.items.count > 8 {
                Text("and \(request.items.count - 8) more")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.bottom, 6)
            }
        }
        .background(Color.inset.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Honest facts about what an overwrite can and cannot do on this Mac.
    private var eraseFacts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("On an SSD, overwriting is best effort")
                .font(.system(size: 12.5, weight: .semibold))
            Text("The drive and APFS may keep older copies of the blocks out of reach. What really protects deleted data on a Mac is FileVault.")
                .font(.system(size: 12))
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let environment = request.environment {
                fact(ok: environment.fileVaultOn == true,
                     environment.fileVaultOn == nil ? "FileVault status unknown"
                        : environment.fileVaultOn! ? "FileVault is on: freed space stays encrypted" : "FileVault is off: old data may be recoverable from the drive")
                if let snapshots = environment.localSnapshots {
                    fact(ok: snapshots == 0, snapshots == 0 ? "No local snapshots" : "\(snapshots) local snapshot\(snapshots == 1 ? "" : "s") may still hold a copy")
                }
                if environment.timeMachineConfigured == true {
                    fact(ok: false, "Time Machine backups may still hold a copy")
                }
            } else {
                ProgressView().controlSize(.small)
            }
            fact(ok: true, "Files in iCloud or other clouds are not erased there")
        }
        .padding(12)
        .background(Color.danger.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.danger.opacity(0.25)))
    }

    private func fact(ok: Bool, _ text: String) -> some View {
        Label(text, systemImage: ok ? "checkmark.circle" : "exclamationmark.circle")
            .font(.system(size: 12))
            .foregroundStyle(ok ? Color.inkSecondary : Color.danger)
    }
}

/// A button that only fires after being held down for `duration` seconds. Releasing early, or
/// keyboard activation, does nothing.
struct HoldToConfirmButton: View {
    let title: String
    let duration: Double
    let destructive: Bool
    let enabled: Bool
    let hold: HoldState
    let action: () -> Void

    var body: some View {
        TimelineView(.animation(paused: hold.pressStarted == nil)) { timeline in
            let progress = hold.pressStarted.map { min(1, timeline.date.timeIntervalSince($0) / duration) } ?? 0
            let tint = destructive ? Color.dangerFill : Color.lantern
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(enabled ? 0.18 : 0.08))
                GeometryReader { geometry in
                    Capsule().fill(tint).frame(width: geometry.size.width * progress)
                }
                HStack(spacing: 8) {
                    ZStack {
                        Circle().stroke(tint.opacity(0.35), lineWidth: 2.5)
                        Circle().trim(from: 0, to: progress).stroke(progress > 0.5 ? Color.white : tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 16, height: 16)
                    Text(progress > 0 && progress < 1 ? "Keep holding…" : title)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(progress > 0.5 ? Color.white : (enabled ? Color.ink : Color.inkSecondary))
                .padding(.horizontal, 16)
            }
            .frame(width: 250, height: 34)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(enabled ? 0.7 : 0.25)))
            .onChange(of: progress >= 1) { _, done in
                if done && !hold.fired {
                    hold.fired = true
                    hold.pressStarted = nil
                    action()
                }
            }
        }
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if enabled && hold.pressStarted == nil && !hold.fired { hold.pressStarted = Date() }
                }
                .onEnded { _ in hold.pressStarted = nil }
        )
        .opacity(enabled ? 1 : 0.6)
        .help(enabled ? "Press and hold for \(duration.formatted()) seconds" : "Tick the box first")
        .accessibilityLabel(title)
        .accessibilityHint("Press and hold to confirm.")
    }
}
