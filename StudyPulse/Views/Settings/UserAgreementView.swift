//
//  UserAgreementView.swift
//  StudyPulse
//
//  应用内展示的《用户使用协议》阅读页
//  In-app display of the User Agreement (Terms of Service).
//

import SwiftUI

// MARK: - UserAgreementView

struct UserAgreementView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hasScrolledToEnd = false
    @State private var showAcceptanceToast = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard

                    ForEach(Array(UserAgreementSection.all.enumerated()), id: \.offset) { index, section in
                        agreementSection(index: index, section: section)
                    }

                    footerCard
                }
                .padding()
            }
            .adaptiveMaxWidth(720)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("User Agreement".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done".localized()) { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if showAcceptanceToast {
                    acceptanceToast
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - 顶部信息卡片
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("StudyPulse")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("User Agreement".localized())
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }

            Divider().padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                labelRow(icon: "person.circle.fill", text: "Developer: Gao Chenkai")
                labelRow(icon: "tag.fill", text: "App: StudyPulse (iOS / iPadOS 18.6+)")
                labelRow(icon: "doc.badge.gearshape.fill", text: "Version: v1.0")
                labelRow(icon: "calendar", text: "Last Updated: 2026-06-27")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func labelRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 18)
            Text(text)
        }
    }

    // MARK: - 章节块
    private func agreementSection(index: Int, section: UserAgreementSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(index + 1).")
                    .font(.headline)
                    .foregroundColor(.blue)
                Text(section.titleKey.localized())
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph.localized())
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let bullets = section.bullets {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .foregroundColor(.blue)
                            Text(bullet.localized())
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.leading, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
    }

    // MARK: - 底部确认卡片
    private var footerCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 36))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            Text("By using StudyPulse, you confirm that you have read, understood, and agreed to the terms above.".localized())
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button {
                withAnimation {
                    showAcceptanceToast = true
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    withAnimation {
                        showAcceptanceToast = false
                    }
                }
            } label: {
                Label("I Have Read and Agree".localized(), systemImage: "hand.thumbsup.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var acceptanceToast: some View {
        Label("Thanks for confirming.".localized(), systemImage: "checkmark.circle.fill")
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(Color.green.opacity(0.95))
            )
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }
}

// MARK: - 协议章节数据模型

/// 用户使用协议章节定义。
/// 所有用户可见文字使用 `.localized()` 扩展以支持 iOS 26 多语言。
struct UserAgreementSection {
    let titleKey: String
    let paragraphs: [String]
    let bullets: [String]?

    static let all: [UserAgreementSection] = [
        UserAgreementSection(
            titleKey: "Agreement Overview",
            paragraphs: [
                "This User Agreement (\"Agreement\") is entered into between you (\"User\") and the StudyPulse development team (developer: Gao Chenkai, referred to as \"we\" or \"Developer\") for the StudyPulse application (the \"App\").",
                "By downloading, installing, or using the App, you confirm that you have read, understood, and agreed to be bound by all the terms of this Agreement. If you do not agree, please do not download, install, or use the App."
            ],
            bullets: nil
        ),
        UserAgreementSection(
            titleKey: "App Functions & Services",
            paragraphs: [
                "StudyPulse is a local academic management and health assistant tool for students, including grade tracking, mistake notes, exam planning, trend analysis, multi-curriculum support, multi-language UI, and HRV-based study readiness (optional).",
                "The Developer reserves the right to modify, upgrade, suspend, or terminate any function of the App at any time without prior notice."
            ],
            bullets: [
                "Grade tracking, mistake notes, exam planning, trend analysis.",
                "Optional HealthKit integration: HRV, heart rate, respiratory rate, sleep, and exercise minutes are processed locally unless you separately allow optional AI sharing.",
                "WidgetKit extensions for upcoming exams, score trends, and HRV readiness.",
                "CSV export of your data at any time."
            ]
        ),
        UserAgreementSection(
            titleKey: "Privacy & Data Protection",
            paragraphs: [
                "We take your privacy and data security very seriously. Your learning data (grades, mistake notes, exams, avatars) remains on your device unless you choose to share specific content through an AI feature. HealthKit data is read and processed locally unless you separately allow health data in AI requests. StudyPulse may write a 1-minute Mindful Session when diary sync is enabled; mood and energy values remain in the app.",
                "The App does not integrate any advertising SDKs, behavioral tracking SDKs, or social sharing SDKs. The App does not collect your personal information on the Developer's own servers."
            ],
            bullets: [
                "Data location: device's ~/Documents/, UserDefaults, and the App Group container only.",
                "No cloud sync. Optional AI requests go only to the endpoint you configure and require separate consent for health data.",
                "All permissions (Camera, Photos, Calendar, HealthKit, Notifications) are requested only when needed and require your explicit consent.",
                "You can export or delete your data at any time via the in-app features."
            ]
        ),
        UserAgreementSection(
            titleKey: "HealthKit Data — Special Notes",
            paragraphs: [
                "The App reads HealthKit data with your permission. When diary sync is enabled, it may write a 1-minute Mindful Session; it does not write HRV, heart rate, respiratory rate, sleep, or mood/energy values. The read data — HRV (SDNN), heart rate, respiratory rate, sleep, exercise minutes — is used locally to compute study readiness and personalized suggestions unless you separately allow health data in AI requests.",
                "HealthKit data is not used for advertising, marketing, data mining, or sale to any third party."
            ],
            bullets: nil
        ),
        UserAgreementSection(
            titleKey: "User Conduct",
            paragraphs: [
                "You agree to use the App lawfully and not to engage in any activity that violates applicable laws or regulations, infringes the rights of others, or harms the App or the Developer.",
                "You are solely responsible for all content you enter into the App, including grades, mistake photos, text notes, and avatars."
            ],
            bullets: [
                "Do not reverse engineer, decompile, or disassemble the App for commercial purposes.",
                "Do not enter other people's private information or health data without their consent.",
                "Do not use the App for any commercial activity (commercial use is prohibited under the CC BY-NC-SA 4.0 license).",
                "Do not use the App for any academic integrity violation (e.g. ghostwriting, exam cheating)."
            ]
        ),
        UserAgreementSection(
            titleKey: "Intellectual Property & License",
            paragraphs: [
                "All intellectual property rights in the App — including source code, UI design, icons, logo, brand name \"StudyPulse\", and the built-in StudyReadinessAlgorithm — are solely owned by the Developer Gao Chenkai, unless otherwise stated.",
                "The source code is published under the Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0) license. Any commercial use of the App or its derivative works requires prior written permission from the Developer."
            ],
            bullets: nil
        ),
        UserAgreementSection(
            titleKey: "Disclaimers",
            paragraphs: [
                "The App is provided on an \"as-is\" and \"as-available\" basis. To the maximum extent permitted by applicable law, the Developer makes no express or implied warranties regarding the App.",
                "Study readiness assessments and suggestions produced by the App are general algorithmic references only. They DO NOT constitute medical advice, medical diagnosis, or treatment. They are not a substitute for professional medical, psychological, or nutritional advice.",
                "If you have health concerns, please consult qualified medical professionals. In case of emergency, call your local emergency number or visit the nearest medical facility."
            ],
            bullets: nil
        ),
        UserAgreementSection(
            titleKey: "Limitation of Liability",
            paragraphs: [
                "To the maximum extent permitted by applicable law, the Developer's total liability to you for any damages arising from the use of (or inability to use) the App shall not exceed the amount you actually paid for the App (the App is free, so this cap is zero).",
                "This limitation does not apply to liability that cannot be excluded under applicable law (e.g. personal injury, or property damage caused by the Developer's gross negligence or willful misconduct)."
            ],
            bullets: nil
        ),
        UserAgreementSection(
            titleKey: "Data Backup & Loss",
            paragraphs: [
                "All your data is stored locally on your device only. The Developer does not provide cloud sync services. Data loss may occur due to device damage, system failure, accidental uninstallation, or other causes beyond the Developer's control.",
                "Please use the in-app CSV export feature regularly to back up your data. The Developer is not responsible for any data loss."
            ],
            bullets: nil
        ),
        UserAgreementSection(
            titleKey: "Minors & Children",
            paragraphs: [
                "Children under 14 must have a parent or legal guardian agree to this Agreement on their behalf. The guardian should supervise the minor's use of the App, including reasonable study-rest balance.",
                "If health data is used by a minor, the guardian must grant the HealthKit permission on the minor's behalf and understand that readiness suggestions are not medical advice."
            ],
            bullets: nil
        ),
        UserAgreementSection(
            titleKey: "Changes & Termination",
            paragraphs: [
                "The Developer may modify this Agreement from time to time. Material changes will be notified in-app and take effect 7 calendar days after the notice. Your continued use after the effective date constitutes acceptance of the modified Agreement.",
                "You may stop using the App at any time. The Developer may terminate this Agreement if you materially breach any of its terms."
            ],
            bullets: nil
        ),
        UserAgreementSection(
            titleKey: "Governing Law & Disputes",
            paragraphs: [
                "This Agreement is governed by the laws of the People's Republic of China. Any disputes shall first be resolved through friendly negotiation; failing that, either party may submit the dispute to the people's court with jurisdiction at the Developer's location.",
                "If any provision is held invalid, the remaining provisions remain in full force and effect."
            ],
            bullets: nil
        ),
        UserAgreementSection(
            titleKey: "Contact",
            paragraphs: [
                "If you have any questions, comments, or wish to exercise your data rights, please contact the Developer through the in-app Settings → About page, or refer to the USER_AGREEMENT.md file shipped with the source repository.",
                "We aim to respond within 15 business days."
            ],
            bullets: nil
        )
    ]
}

#Preview {
    UserAgreementView()
}
