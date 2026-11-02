import SwiftUI

/// Settings screen — currently exposes the photo grid limit.
struct SettingsView: View {

    @AppStorage(AppConfig.photoLimitKey) private var photoLimit = AppConfig.defaultPhotoLimit
    @Environment(\.dismiss) private var dismiss

    /// Allowed values for the grid limit picker.
    private let limits = [4, 9, 16, 25]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Photos to show", selection: $photoLimit) {
                        ForEach(limits, id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Grid size")
                } footer: {
                    Text("Sets how many of the most recent photos are shown in the grid.")
                }

                Section("Device") {
                    LabeledContent("Device ID", value: AppConfig.deviceId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
