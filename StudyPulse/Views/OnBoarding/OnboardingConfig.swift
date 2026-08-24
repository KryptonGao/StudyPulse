//
//  OnboardingConfig.swift
//  StudyPulse
//
//  Created by Chenkai Gao on 2026/3/29.
//  替换原 WSOnBoarding 配置：使用原生 SwiftUI 数据模型
//

import SwiftUI

/// 原生 iOS 26 风格的引导页 / 新功能介绍页内容配置。
struct OnboardingConfig {
    /// 页面类型：欢迎页 或 新功能介绍页
    enum PageType {
        case welcome
        case whatsNew
    }

    /// 单个特性项。
    struct Feature: Identifiable, Hashable {
        let id = UUID()
        let icon: String
        let title: String
        let description: String
        let color: Color

        // 业务字段相同的 Feature 视为相同实例，忽略 UUID
        static func == (lhs: Feature, rhs: Feature) -> Bool {
            lhs.icon == rhs.icon && lhs.title == rhs.title
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(icon)
            hasher.combine(title)
        }
    }

    let appName: String
    let introText: String
    let features: [Feature]
    let iconSymbol: String
    let primaryColor: Color
    let continueButtonText: String
    let disclaimerText: String?
    let pageType: PageType

    /// 首次启动时附带的「基础信息填写」流程；
    /// nil = 当前 OnBoarding 不包含填写步骤（whatsNew / 旧的纯介绍 welcome）。
    /// 非 nil = 介绍结束后追加 6 页基础信息填写（OnboardingProfileStep）。
    let profileFlow: ProfileFlowConfig?
}

extension OnboardingConfig {
    /// 首次启动时附带的「基础信息填写」流程配置。
    struct ProfileFlowConfig {
        /// 填写阶段的「最后一步」按钮文案
        let finishButtonText: String
        /// 填写阶段的副标题（出现在每页标题正下方）
        let sectionHeader: String
        /// 填写阶段第 6 步（目标）的「稍后填写」按钮文案
        let skipGoalsText: String
    }
}

extension OnboardingConfig {
    /// 首次启动欢迎页配置。
    static var welcome: OnboardingConfig {
        OnboardingConfig(
            appName: "StudyPulse",
            introText: "Track grades, master mistakes, plan exams — and let your body guide when to study with HealthKit insights.".localized(),
            features: [
                Feature(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Tracking & Trends".localized(),
                    description: "Log scores across subjects and watch your progress unfold with interactive trend charts.".localized(),
                    color: .blue
                ),
                Feature(
                    icon: "doc.text.magnifyingglass",
                    title: "Mistake Notes".localized(),
                    description: "Snap photos of errors, auto-extract text with OCR, and review with plain text.".localized(),
                    color: .orange
                ),
                Feature(
                    icon: "heart.text.square",
                    title: "HealthKit Ready".localized(),
                    description: "Connect Apple Health for daily study suggestions tailored to your HRV and recovery state.".localized(),
                    color: .pink
                ),
                Feature(
                    icon: "calendar.badge.clock",
                    title: "Exam Planning".localized(),
                    description: "Schedule exams with countdown, calendar sync, and smart preparation reminders.".localized(),
                    color: .green
                ),
            ],
            iconSymbol: "graduationcap.fill",
            primaryColor: .blue,
            continueButtonText: "Continue".localized(),
            disclaimerText: "Your learning data stays on device. HealthKit signals are processed locally unless you separately allow optional AI sharing; diary sync may write a 1-minute Mindful Session.".localized(),
            pageType: .welcome,
            // 首次启动 welcome 流程附带 6 页基础信息填写
            profileFlow: OnboardingConfig.ProfileFlowConfig(
                finishButtonText: "Start Using StudyPulse".localized(),
                sectionHeader: "Basic Info".localized(),
                skipGoalsText: "Skip for now".localized()
            )
        )
    }

    /// 新功能介绍页配置 — 每次版本更新后展示。
    ///
    /// ═══════════════════════════════════════════════
    /// 每次发布新版本时，记得在这里更新 features 内容
    /// 把本次新增/改进的功能写进来
    /// ═══════════════════════════════════════════════
    static var whatsNew: OnboardingConfig {
        OnboardingConfig(
            appName: "StudyPulse",
            introText: "Here's what's new in this version.".localized(),
            features: [
                Feature(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Tracking & Trends".localized(),
                    description: "Log scores across subjects and watch your progress unfold with interactive trend charts.".localized(),
                    color: .blue
                ),
                Feature(
                    icon: "doc.text.magnifyingglass",
                    title: "Mistake Notes".localized(),
                    description: "Snap photos of errors, auto-extract text with OCR, and review with plain text.".localized(),
                    color: .orange
                ),
                Feature(
                    icon: "heart.text.square",
                    title: "HealthKit Ready".localized(),
                    description: "Connect Apple Health for daily study suggestions tailored to your HRV and recovery state.".localized(),
                    color: .pink
                ),
                Feature(
                    icon: "calendar.badge.clock",
                    title: "Exam Planning".localized(),
                    description: "Schedule exams with countdown, calendar sync, and smart preparation reminders.".localized(),
                    color: .green
                ),
            ],
            iconSymbol: "graduationcap.fill",
            primaryColor: .blue,
            continueButtonText: "Continue".localized(),
            disclaimerText: nil,
            pageType: .whatsNew,
            // 新功能介绍页不带基础信息填写
            profileFlow: nil
        )
    }
}
