//
//  AppearanceSettingsView.swift
//  StudyPulse
//

import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(RepositoryContainer.self) private var container

  var body: some View {
         List {
             Section {
                 SettingsDetailHeader(category: .appearance)
                     .listRowInsets(EdgeInsets())
                     .listRowBackground(Color.clear)
             }

                // Language & Theme
                Section {
                    NavigationLink(destination: PreferencesView()) {
                        Label("Language & Theme".localized(), systemImage: "gearshape")
                    }
                }

                // Home Layout
                Section {
                    NavigationLink(destination: HomeLayoutSettingsView()) {
                        Label("Home Layout".localized(), systemImage: "rectangle.3.group")
                    }
                    NavigationLink(destination: BrainUsageSettingsView()) {
                        Label("Brain Usage".localized(), systemImage: "brain.head.profile")
                    }
                }

                // Chart Type
                Section {
                    NavigationLink(destination: ChartTypeSettingsView()) {
                        HStack {
                            Label("Chart Type".localized(), systemImage: "chart.xyaxis.line")
                            Spacer()
                            Text(container.envManager.preferences.chartType.localizedDisplayName)
                                .scaledFont(size: 14)
                                .foregroundColor(.secondary)
                        }
                    }
                } footer: {
                    Text("Choose how grades are visualized: line, bar, pie, scatter, or heatmap.".localized())
                }

                // Widget
                Section {
                    trendWidgetSubjectPicker
                }

                // Plant Garden (主页植物卡片)
                Section {
                    Toggle(isOn: Binding(
                        get: { container.envManager.preferences.plantCardEnabled },
                        set: { container.envManager.preferences.plantCardEnabled = $0 }
                    )) {
                        Label("plant.card.toggle".localized(), systemImage: "leaf.fill")
                    }
                    NavigationLink(destination: PlantDetailView()) {
                        Label("plant.card.sectionTitle".localized(), systemImage: "leaf.circle")
                    }
                    HStack(spacing: 10) {
                        ForEach(PetalColorCatalog.all) { petal in
                            Button {
                                container.envManager.preferences.plantPetalColorId = petal.id
                            } label: {
                                Circle()
                                    .fill(petal.resolved(colorScheme: colorScheme))
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(
                                                container.envManager.preferences.plantPetalColorId == petal.id
                                                    ? Color.primary : Color.primary.opacity(0.15),
                                                lineWidth: container.envManager.preferences.plantPetalColorId == petal.id ? 2 : 1
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(PetalColorCatalog.localizedName(for: petal.id))
                        }
                    }
                } header: {
                    Text("plant.card.sectionTitle".localized())
                } footer: {
                    Text("plant.card.footer".localized())
                }
         }
         .listStyle(.insetGrouped)
         .background(Color(.systemGroupedBackground))
        .containerBackground(.clear, for: .navigation)
        .debugModeContainer()
        .debugLayoutBoundsAuto()
        .navigationTitle("Appearance & Layout".localized())
        .navigationBarTitleDisplayMode(.inline)
    }

    @Environment(\.colorScheme) private var colorScheme

    private var trendWidgetSubjectPicker: some View {
        let preferredSubject = TrendWidgetDataStore.loadPreferredSubject()
        let subjectsWithGrades = Dictionary(grouping: container.gradeRepo.grades, by: \.subject).keys.sorted()

        return Picker(selection: Binding<String?>(
            get: { preferredSubject },
            set: { newSubject in
                TrendWidgetDataStore.savePreferredSubject(newSubject)
                TrendWidgetSyncManager.syncTrend(grades: container.gradeRepo.grades, subjects: container.subjectRepo.subjects)
            }
        )) {
            Text("Auto".localized()).tag(String?.none)
            ForEach(subjectsWithGrades, id: \.self) { subjectName in
                Text(container.displayName(for: subjectName)).tag(String?.some(subjectName))
            }
        } label: {
            Label("Trend Widget Subject".localized(), systemImage: "chart.line.uptrend.xyaxis")
        }
    }
}
