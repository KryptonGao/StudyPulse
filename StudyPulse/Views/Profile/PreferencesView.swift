//
//  PreferencesView.swift
//  StudyPulse
//
//  偏好设置页：主题色 / 玻璃效果 / 外观 / 语言 / 重启。
//  Preferences: theme color, glass effect, appearance, language, restart.
//

import SwiftUI

/// 应用偏好设置界面：语言、主题色、玻璃效果、外观模式。
/// Preferences screen: language, theme color, glass effect, appearance mode.
struct PreferencesView: View {
    @Environment(RepositoryContainer.self) private var container
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                themeColorSection
                glassEffectSection
                appearanceSection
                languageSection
                restartSection
            }
            .navigationTitle("Preferences".localized())
            .navigationBarTitleDisplayMode(.inline)
            .adaptiveMaxWidth(640)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done".localized()) {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - 主题色 Section

    private var themeColorSection: some View {
        Section(
            header: Text("Theme Color".localized()),
            footer: Text("Affects AccentColor, trend line and progress bars throughout the app.".localized())
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(ThemeAccent.allCases) { accent in
                        Button {
                            container.envManager.setAccentPalette(accent)
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(accent.color)
                                        .frame(width: 36, height: 36)
                                    if container.envManager.effectiveAccent == accent {
                                        Image(systemName: "checkmark")
                                            .scaledFont(size: 14, weight: .bold)
                                            .foregroundColor(.white)
                                    }
                                    Circle()
                                        .strokeBorder(
                                            container.envManager.effectiveAccent == accent
                                                ? Color.primary.opacity(0.4)
                                                : Color.primary.opacity(0.1),
                                            lineWidth: container.envManager.effectiveAccent == accent ? 2 : 1
                                        )
                                        .frame(width: 40, height: 40)
                                }
                                Text(accent.localizedDisplayName)
                                    .font(.caption2)
                                    .foregroundColor(container.envManager.effectiveAccent == accent ? .primary : .secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
    }

    // MARK: - 玻璃效果 Section

    private var glassEffectSection: some View {
        Section(
            header: Text("Liquid Glass Effect".localized()),
            footer: Text("Enable iOS 26 glass effect on supported cards (requires iOS 26+). Falls back to material on older systems.".localized())
        ) {
            Toggle(isOn: Binding(
                get: { container.envManager.glassEffectEnabled },
                set: { container.envManager.setGlassEffectEnabled($0) }
            )) {
                Label("Enable Glass Effect".localized(), systemImage: "drop.fill")
            }
        }
    }

    // MARK: - Appearance Section (旧)

    private var appearanceSection: some View {
        Section(
            header: Text("Appearance".localized()),
            footer: Text("Choose your preferred color scheme.".localized())
        ) {
            Picker("Theme".localized(), selection: Binding(
                get: { container.envManager.preferences.colorScheme },
                set: { container.envManager.setColorScheme($0) }
            )) {
                ForEach(ColorSchemeOption.allCases, id: \.self) { option in
                    HStack {
                        Image(systemName: option.icon)
                            .foregroundColor(.primary)
                            .frame(width: 24)
                        Text(option.localizedDisplayName)
                    }
                    .tag(option)
                }
            }
            .pickerStyle(.inline)
        }
    }

    // MARK: - Language Section

    private var languageSection: some View {
        Section(
            header: Text("Language".localized()),
            footer: Text("App language can be changed here independently of the system language.".localized())
        ) {
            Picker("App Language".localized(), selection: Binding(
                get: { container.envManager.preferences.appLanguage },
                set: { container.envManager.setLanguage($0) }
            )) {
                ForEach(AppPreferences.Language.allLocalized, id: \.code) { lang in
                    Text(lang.displayName)
                        .tag(lang.code)
                }
            }
        }
    }

    // MARK: - Restart Section

    private var restartSection: some View {
        Section(footer: Text("Language changes require app restart to take full effect.".localized())) {
            Button(role: .destructive) {
                restartApp()
            } label: {
                HStack {
                    Spacer()
                    Text("Restart Now".localized())
                    Spacer()
                }
            }
        }
    }
    
    private func restartApp() {
        // iOS 不支持程序内重启，提示用户手动重启
        exit(0)
    }
}

#Preview {
    PreferencesView()
}
