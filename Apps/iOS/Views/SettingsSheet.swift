import BetterDropCore
import BetterDropUI
import SwiftUI

struct SettingsSheet: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var confirmingForget = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        LightOrb(energy: model.isConnected ? 0.7 : 0.25)
                            .frame(width: 110, height: 110)
                        Wordmark(size: 20)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Name", text: $name)
                        .onSubmit { model.rename(name) }
                } header: {
                    Text("This \(model.device.kind == .iPad ? "iPad" : "iPhone")")
                } footer: {
                    Text("What your Mac calls this device.")
                }

                if let mac = model.pairedMac {
                    Section("Mac") {
                        LabeledContent {
                            Text(status)
                                .foregroundStyle(model.isConnected ? .green : .secondary)
                        } label: {
                            Label(mac.device.name, systemImage: "laptopcomputer")
                        }
                        Button("Forget This Mac", role: .destructive) { confirmingForget = true }
                    }
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
                    Link(destination: URL(string: "https://github.com/Pallepadehat/BetterDrop")!) {
                        Label("BetterDrop on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Your files are in the Files app too, under On My iPhone → BetterDrop. Everything goes straight between your devices, end-to-end encrypted, never through the internet. Files over 8 MB carry on in the background.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        model.rename(name)
                        dismiss()
                    }
                }
            }
            .onAppear { name = model.device.name }
            .confirmationDialog("Forget \(model.pairedMac?.device.name ?? "this Mac")?", isPresented: $confirmingForget, titleVisibility: .visible) {
                Button("Forget", role: .destructive) {
                    model.forgetMac()
                    dismiss()
                }
            } message: {
                Text("You'll need to hold your iPhone next to it and connect again.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var status: String {
        switch model.connection {
        case .connected: String(localized: "Connected")
        case .connecting: String(localized: "Connecting…")
        case .idle: String(localized: "Not nearby")
        }
    }
}
