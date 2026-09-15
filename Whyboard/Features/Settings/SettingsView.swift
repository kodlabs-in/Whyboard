import SwiftUI

struct SettingsView: View {
  @AppStorage(NotePaperStyle.defaultStorageKey, store: AppPreferences.store)
  private var defaultPaperStyleRawValue = NotePaperStyle.defaultStyle.rawValue
  @AppStorage("drawWithFinger", store: AppPreferences.store) private var drawsWithFinger = false

  var body: some View {
    Form {
      Section {
        Picker("Default Paper", selection: $defaultPaperStyleRawValue) {
          ForEach(NotePaperStyle.selectableStyles) { style in
            paperStyleLabel(style)
              .tag(style.rawValue)
          }
        }
        .accessibilityIdentifier("default-paper-picker")
      } header: {
        Text("Paper")
      } footer: {
        Text("New and existing notes using “Use Default” follow this colour.")
      }

      Section("Writing") {
        Toggle("Draw with Finger", isOn: $drawsWithFinger)
      }

      Section("Privacy") {
        Label("Your notes stay on this iPad", systemImage: "lock.shield")
        Text("Whyboard works offline and does not send your drawings to a server.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func paperStyleLabel(_ style: NotePaperStyle) -> some View {
    Label {
      Text(style.name)
    } icon: {
      Circle()
        .fill(WhyboardTheme.paperColor(for: style))
        .stroke(WhyboardTheme.pageBorderColor(for: style), lineWidth: 1)
        .frame(width: 22, height: 22)
    }
  }
}
