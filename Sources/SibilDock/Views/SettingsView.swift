import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = DockSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("SibilDock Settings")
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Attachment")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Picker("", selection: $settings.attachmentMode) {
                    ForEach(AttachmentMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            if settings.attachmentMode == .floating {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dock layout")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $settings.orientation) {
                        ForEach(DockOrientation.allCases) { orientation in
                            Text(orientation.label).tag(orientation)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            } else {
                Text("Edge-attached is always a vertical stack, pinned to the right edge — hover to expand, move away to collapse.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Toggle("Hide over full-screen apps", isOn: $settings.hidesDuringFullScreen)
                .font(.system(size: 12))
                .toggleStyle(.switch)
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 6) {
                Text("Widgets")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Drag to reorder, toggle to show or hide")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                List {
                    ForEach(settings.widgetOrder) { kind in
                        HStack {
                            Text(kind.label)
                                .font(.system(size: 12))
                            Spacer()
                            Toggle("", isOn: isEnabledBinding(for: kind))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                    }
                    .onMove { indices, newOffset in
                        settings.widgetOrder.move(fromOffsets: indices, toOffset: newOffset)
                    }
                }
                .listStyle(.inset)
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func isEnabledBinding(for kind: WidgetKind) -> Binding<Bool> {
        Binding(
            get: { !settings.disabledWidgets.contains(kind) },
            set: { isOn in
                if isOn {
                    settings.disabledWidgets.remove(kind)
                } else {
                    settings.disabledWidgets.insert(kind)
                }
            }
        )
    }
}
