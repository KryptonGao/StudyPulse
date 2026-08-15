//
//  TestModelContainerFactory.swift
//  StudyPulseTests
//
//  为单元测试与集成测试提供纯内存（In-Memory Only）SwiftData 容器工厂。
//  Provides in-memory SwiftData ModelContainer factory for unit and integration testing.
//

import Foundation
import SwiftData
@testable import StudyPulse

/// 测试用 SwiftData 内存容器工厂。
/// 每次调用 `makeInMemoryContainer()` 都会返回一个独立、不落盘、全隔离的 ModelContainer。
@MainActor
enum TestModelContainerFactory {

    /// 创建并返回一个新的只在内存中运行的 ModelContainer（包含与生产完全一致的 Schema）。
    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: StudyPulseSchemaV5.self)
        let config = ModelConfiguration("TestStudyPulse", schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: schema,
            migrationPlan: StudyPulseMigrationPlan.self,
            configurations: [config]
        )
    }

    /// 创建一个预载入默认科目（Math, English, Physics, Chemistry, Biology, History）的内存 ModelContainer。
    static func makeInMemoryContainerWithDefaultSubjects() throws -> ModelContainer {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let defaults = [
            SubjectRecord(id: UUID(), name: "Math", enabled: true, fullScore: 100, displayName: "Math"),
            SubjectRecord(id: UUID(), name: "English", enabled: true, fullScore: 100, displayName: "English"),
            SubjectRecord(id: UUID(), name: "Physics", enabled: true, fullScore: 100, displayName: "Physics"),
            SubjectRecord(id: UUID(), name: "Chemistry", enabled: true, fullScore: 100, displayName: "Chemistry"),
            SubjectRecord(id: UUID(), name: "Biology", enabled: true, fullScore: 100, displayName: "Biology"),
            SubjectRecord(id: UUID(), name: "History", enabled: true, fullScore: 100, displayName: "History")
        ]
        for sub in defaults {
            context.insert(sub)
        }
        try context.save()
        return container
    }
}
