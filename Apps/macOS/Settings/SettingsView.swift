import BetterDropCore
import BetterDropUI
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Devices", systemImage: "iphone") { DevicesSettings() }
            Tab("Updates", systemImage: "sparkles") { UpdatesSettings() }
        }
        .frame(width: 480, height: 340)
    }
}

private struct GeneralSettings: View {
    @Environment(MacModel.self) private var model
    @State private var name = ""
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var preferences = model.preferences
        Form {
            TextField("This Mac's name", text: $name)
                .onSubmit { model.rename(name) }
                .onAppear { name = model.device.name }
            Picker("Your iPhone sits on the", selection: $preferences.edge) {
                Text("Left of the screen").tag(EdgeBloom.Edge.leading)
                Text("Right of the screen").tag(EdgeBloom.Edge.trailing)
            }
            Toggle("Show files in Finder when they arrive", isOn: $preferences.revealReceivedFiles)
            Toggle("Play sounds", isOn: $preferences.playsSounds)
            Toggle("Open BetterDrop when you log in", isOn: $launchesAtLogin)
                .onChange(of: launchesAtLogin) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchesAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            LabeledContent("Files are kept in") {
                Button(model.library.directory.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                    NSWorkspace.shared.open(model.library.directory)
                }
                .buttonStyle(.link)
            }
        }
        .formStyle(.grouped)
        .onDisappear { model.rename(name) }
    }
}

private struct DevicesSettings: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        Form {
            if model.pairedDevices.isEmpty {
                ContentUnavailableView("No devices yet", systemImage: "iphone.radiowaves.left.and.right",
                                       description: Text("Open BetterDrop on your iPhone and hold it next to your Mac."))
            } else {
                Section("Paired devices") {
                    ForEach(model.pairedDevices) { paired in
                        HStack {
                            Image(systemName: paired.device.kind.symbolName)
                                .frame(width: 22)
                            VStack(alignment: .leading) {
                                Text(paired.device.name)
                                Text(model.connected.contains { $0.id == paired.id } ? "Connected" : "Paired \(paired.pairedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Forget", role: .destructive) { model.forget(paired) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct UpdatesSettings: View {
    @State private var automatic = Updates.shared.checksAutomatically

    var body: some View {
        Form {
            Toggle("Check for updates every day", isOn: $automatic)
                .onChange(of: automatic) { _, value in Updates.shared.checksAutomatically = value }
            LabeledContent("Version", value: Bundle.main.version)
            Button("Check for Updates Now") { Updates.shared.checkNow() }
            Text("Updates come from GitHub releases and are checked against BetterDrop's signing key before they're installed. Nothing about you is sent.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

extension Bundle {
    var version: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}
