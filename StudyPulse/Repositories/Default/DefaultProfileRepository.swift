//
//  DefaultProfileRepository.swift
//  StudyPulse
//
//  用户资料 (UserProfile) Repository 默认实现。
//  Default ProfileRepository implementation backed by SwiftData.
//

import Foundation
import SwiftData
import os

/// 用户资料 (UserProfile) Repository 默认实现。
/// Default ProfileRepository implementation backed by SwiftData.
@Observable @MainActor
final class DefaultProfileRepository: ProfileRepository {
    /// 内存中的资料（单例）
    /// In-memory profile (singleton).
    var profile: UserProfile = UserProfile()

    @ObservationIgnored
    private var modelContext: ModelContext?

    /// 用于 background fetch 的容器引用(Sendable)
    /// Container reference for background fetches (Sendable).
    @ObservationIgnored
    private var modelContainer: ModelContainer?

    /// 跨域引用:commitOnboardingProfile 会写 subjects(由 SubjectRepository 持有)
    /// Cross-domain ref: commitOnboardingProfile writes subjects (held by SubjectRepository).
    @ObservationIgnored
    weak var subjectRef: (any SubjectRepository)?

    init() {}

    /// 容器在 init 时调用,注入 SubjectRepository weak 引用。
    /// Called by the container on init; injects the SubjectRepository weak ref.
    func setSubjectRef(_ repo: any SubjectRepository) {
        self.subjectRef = repo
    }

    // MARK: - Lifecycle
    // MARK: - 生命周期 / Lifecycle

    /// 加载用户资料（首条 record）
    /// Load the user profile (first record).
    func loadAll(context: ModelContext) async {
        self.modelContext = context
        self.modelContainer = context.container
        guard let container = modelContainer else { return }
        // detached Task 内创建独立 background ModelContext,fetch + toSnapshot
        // 库空时返回 nil,主 actor 用 if let 兜底
        // Use an independent background ModelContext; return nil if empty.
        let snapshot: UserProfile? = await Task.detached(priority: .utility) {
            let ctx = ModelContext(container)
            let entities = (try? ctx.fetch(FetchDescriptor<UserProfileRecord>())) ?? []
            return entities.first?.toSnapshot()
        }.value
        // 回到 MainActor 赋值
        if let snapshot { self.profile = snapshot }
    }

    // MARK: - CRUD
    // MARK: - 增删改查 / CRUD

    /// 写入当前 profile 到 SwiftData（首条 record，upsert）
    /// Persist the current profile (upsert into the first record).
    func saveProfile() {
        guard let context = modelContext else { return }
        do {
            let existing = try context.fetch(FetchDescriptor<UserProfileRecord>())
            if let entity = existing.first {
                entity.username = profile.username
                entity.age = profile.age
                entity.educationLevel = profile.educationLevel
                entity.educationSystem = profile.educationSystem
                entity.region = profile.region
                entity.selectedSubjectsData = try? JSONEncoder().encode(profile.selectedSubjects)
                entity.theme = profile.theme
                entity.avatarFileName = profile.avatarFileName
                entity.realName = profile.realName
                entity.grade = profile.grade
                entity.className = profile.className
                entity.schoolName = profile.schoolName
                entity.studentId = profile.studentId
                entity.enrollmentYear = profile.enrollmentYear
                entity.examYear = profile.examYear
                entity.educationStage = profile.educationStage
                entity.regionCode = profile.regionCode
                entity.gender = profile.gender
                entity.targetSchool = profile.targetSchool
                entity.targetScore = profile.targetScore
            } else {
                context.insert(UserProfileRecord(from: profile))
            }
            try context.save()
            Log.data.debug("ProfileRepository saved profile to SwiftData")
            Log.record(.info, category: "Data", message: "ProfileRepository saved profile to SwiftData")
        } catch {
            Log.data.error("ProfileRepository saveProfile failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func commitOnboardingProfile(draft: OnboardingProfileDraft, selectedSubjectNames: [String]) {
        let stage = EducationStage(rawValue: draft.educationStage) ?? .highSchool
        let region = EducationConfig.region(named: draft.regionCode, stage: stage)
            ?? EducationConfig.defaultRegion(for: stage)

        // 同步基础字段
        profile.username = draft.username
        profile.realName = draft.realName
        profile.age = max(draft.age, 0)
        profile.gender = draft.gender
        profile.educationStage = draft.educationStage
        profile.educationLevel = draft.educationStage
        profile.educationSystem = region.displayName
        profile.regionCode = draft.regionCode
        profile.region = region.displayName
        profile.schoolName = draft.schoolName
        profile.grade = draft.grade
        profile.className = draft.className
        profile.studentId = draft.studentId
        profile.enrollmentYear = draft.enrollmentYear
        profile.examYear = draft.examYear
        profile.targetSchool = draft.targetSchool
        profile.targetScore = draft.targetScore

        // 同步选科:通过 SubjectRepository 间接持有 subjects 数组
        let configByName = Dictionary((region.subjects).map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let newSubjects: [Subject] = selectedSubjectNames.compactMap { name in
            if let cfg = configByName[name] {
                return Subject(
                    name: cfg.name,
                    displayName: cfg.displayName,
                    enabled: true,
                    fullScore: cfg.fullScore
                )
            }
            return Subject(name: name, displayName: name, enabled: true, fullScore: 100)
        }
        if let subjectRepo = subjectRef {
            if !newSubjects.isEmpty {
                subjectRepo.subjects = newSubjects
                subjectRepo.saveSubjects()
            } else {
                subjectRepo.applySmartSubjectRecommendation(stage: stage, regionCode: region.name)
            }
        } else {
            Log.data.warning("ProfileRepository commitOnboardingProfile: subjectRef is nil; subjects not synced")
        }

        // 写入 SwiftData
        saveProfile()
        Log.data.info("ProfileRepository onboarding committed: username=\(draft.username, privacy: .public) subjects=\(selectedSubjectNames.count, privacy: .public)")
        Log.record(.info, category: "Data", message: "ProfileRepository onboarding committed: username=\(draft.username) subjects=\(selectedSubjectNames.count)")
    }

    // MARK: - 头像
    // MARK: - 头像 / Avatar

    /// 保存头像到文件系统，写入 filename 到 profile
    /// Save the avatar to the filesystem and store its filename in profile.
    @discardableResult
    func saveAvatar(_ data: Data) -> String? {
        let filename = "avatar_\(UUID().uuidString).jpg"
        if !ImageStorage.save(data, filename: filename) { return nil }
        if let oldFilename = profile.avatarFileName, oldFilename != filename {
            ImageStorage.delete(filename: oldFilename)
        }
        profile.avatarFileName = filename
        Log.data.info("ProfileRepository saved avatar: \(filename, privacy: .public) bytes=\(data.count, privacy: .public)")
        return filename
    }

    func loadAvatar() -> Data? {
        guard let filename = profile.avatarFileName else { return nil }
        return ImageStorage.load(filename: filename)
    }

    func loadAvatarAsync() async -> Data? {
        guard let filename = profile.avatarFileName else { return nil }
        return await ImageStorage.loadAsync(filename: filename)
    }

    func deleteAvatar(filename: String) {
        ImageStorage.delete(filename: filename)
    }
}
