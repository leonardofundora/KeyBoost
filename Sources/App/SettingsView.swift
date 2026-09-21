import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: Model

    private let labelWidth: CGFloat = 170

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView { content }
            Divider()
            footer
        }
        .frame(minWidth: 540, minHeight: 540)
    }

    /// El cuerpo sin el `ScrollView`. Se usa tal cual en `body` y, aparte, permite
    /// renderizar la ventana a imagen con `ImageRenderer`, que no sabe dibujar scrolls.
    var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let problem = model.problem { warning(problem, level: .orange) }
            masterSwitch
            devices
            performance
            options
        }
        .padding(20)
    }

    /// Misma ventana, sin scroll: solo para la previsualización de desarrollo.
    var previewBody: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Spacer(minLength: 0)
            Divider()
            footer
        }
    }

    // MARK: - Cabecera

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: model.isBoosting ? "bolt.fill" : "bolt")
                .font(.system(size: 26))
                .foregroundStyle(model.isBoosting ? Color.accentColor : Color.secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("KeyBoost").font(.title2).bold()
                Text("Keeps Bluetooth LE keyboards on a low-latency link.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(model.headline)
                .font(.callout).bold()
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(model.stateColor.opacity(0.16)))
                .foregroundStyle(model.stateColor)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    // MARK: - Bloques

    private var masterSwitch: some View {
        section(nil) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Enabled").bold()
                    Text("When off, KeyBoost leaves every link alone.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { model.settings.enabled },
                    set: { value in model.edit { $0.enabled = value } }))
                    .labelsHidden()
            }
        }
    }

    private var devices: some View {
        section(L("Bluetooth LE devices")) {
            VStack(alignment: .leading, spacing: 8) {
                if model.status.devices.isEmpty {
                    Text("No connected device in sight.")
                        .foregroundStyle(.secondary).font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(model.status.devices) { device in
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(
                                get: { model.settings.boosts(device.address) },
                                set: { model.setBoosted(device.address, $0) }))
                                .labelsHidden()
                                .disabled(!model.settings.enabled)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(device.name)
                                Text("\(device.kind.label) · \(device.address)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(model.detail(for: device))
                                .font(.caption).monospacedDigit()
                                .foregroundStyle(device.boosted ? Color.green : Color.secondary)
                        }
                    }
                }
            }
        }
    }

    private var performance: some View {
        section(L("Performance")) {
            VStack(alignment: .leading, spacing: 12) {
                row(L("Link latency")) {
                    Picker("", selection: Binding(
                        get: { model.settings.latencyLevel },
                        set: { value in model.edit { $0.latencyLevel = value } })) {
                            ForEach(Settings.latencyChoices, id: \.level) { choice in
                                Text(choice.label).tag(choice.level)
                            }
                        }
                        .labelsHidden()
                }
                if let detail = model.latencyDetail { caption(detail) }
                if let text = model.latencyWarning {
                    warning(text, level: model.settings.latencyLevel == 2 ? .red : .orange)
                }

                Divider()

                row(L("Release when idle for")) {
                    Picker("", selection: Binding(
                        get: { model.settings.idleReleaseSeconds },
                        set: { value in model.edit { $0.idleReleaseSeconds = value } })) {
                            ForEach(Settings.idleChoices, id: \.seconds) { choice in
                                Text(choice.label).tag(choice.seconds)
                            }
                        }
                        .labelsHidden()
                }
                caption(L("After releasing, the keyboard goes back to saving power. The next "
                          + "keystroke arrives a little late; everything after it is instant."))
            }
        }
    }

    private var options: some View {
        section(nil) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Show in the menu bar", isOn: Binding(
                    get: { model.settings.showMenuBarIcon },
                    set: { value in model.edit { $0.showMenuBarIcon = value } }))
                VStack(alignment: .leading, spacing: 1) {
                    Toggle("Start at login", isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }))
                    caption(L("Without this, KeyBoost stops working when you restart the Mac."))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack {
            Text("Closing this window does not stop the boost.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Show log…") {
                NSWorkspace.shared.selectFile(Paths.log.path, inFileViewerRootedAtPath: "")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    // MARK: - Piezas reutilizables

    /// Caja de sección. Hecha a mano en vez de con `GroupBox` porque este último
    /// no se dibuja al renderizar la vista a imagen, y sin poder verla no se puede revisar.
    private func section<C: View>(_ title: String?, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(.subheadline).bold().foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 9)
                    .fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Color.primary.opacity(0.10)))
        }
    }

    /// Etiqueta a la izquierda con ancho fijo: así todos los controles quedan alineados.
    private func row<C: View>(_ label: String, @ViewBuilder control: () -> C) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: labelWidth, alignment: .leading)
                .layoutPriority(1)
            control()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func warning(_ text: String, level: Color) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill").font(.caption)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(level)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 7).fill(level.opacity(0.12)))
    }
}
