import Foundation
import SwiftData
import os
// Persisted shape frozen as part of StudyPulseSchemaV1. Future changes require
// a new versioned record type and migration stage.
@Model final class ExamAutopsyRecord {
    @Attribute(.unique) var id: UUID; var examId: UUID; var subject: String
    @Attribute(.externalStorage) var paperImagesData: [Data]; @Attribute(.externalStorage) var itemsData: Data?; @Attribute(.externalStorage) var reportData: Data?
    var updatedAt: Date; var isAnalyzing: Bool; var lastError: String?; var importedMistakeIdsData: Data?; var importedTaskIdsData: Data?
    init(from value: ExamAutopsy) { id=value.id; examId=value.examId; subject=value.subject; paperImagesData=value.paperImages; itemsData=try? JSONEncoder().encode(value.items); reportData=try? value.report.map { try JSONEncoder().encode($0) }; updatedAt=value.updatedAt; isAnalyzing=value.isAnalyzing; lastError=value.lastError; importedMistakeIdsData=try? JSONEncoder().encode(value.importedMistakeIds); importedTaskIdsData=try? JSONEncoder().encode(value.importedTaskIds) }
    func snapshot() -> ExamAutopsy { ExamAutopsy(id:id, examId:examId, subject:subject, paperImages:paperImagesData, items:(itemsData.flatMap { try? JSONDecoder().decode([ExamAutopsyItem].self, from:$0) }) ?? [], report:reportData.flatMap { try? JSONDecoder().decode(ExamAutopsyReport.self, from:$0) }, updatedAt:updatedAt, isAnalyzing:isAnalyzing, lastError:lastError, importedMistakeIds:importedMistakeIdsData.flatMap { try? JSONDecoder().decode([UUID].self, from:$0) } ?? [], importedTaskIds:importedTaskIdsData.flatMap { try? JSONDecoder().decode([UUID].self, from:$0) } ?? []) }
}
@Observable @MainActor final class DefaultExamAutopsyRepository: ExamAutopsyRepository {
    var records: [ExamAutopsy] = []; private var context: ModelContext?
    func loadAll(context: ModelContext) async { self.context=context; records=(try? context.fetch(FetchDescriptor<ExamAutopsyRecord>()))?.map { $0.snapshot() } ?? [] }
    func record(for examId: UUID) -> ExamAutopsy? { records.first { $0.examId == examId } }
    func upsert(_ record: ExamAutopsy) {
        guard let context else {
            if let i=records.firstIndex(where:{$0.id==record.id}) { records[i]=record } else { records.append(record) }
            return
        }
        do {
            if let old = try context.fetch(FetchDescriptor<ExamAutopsyRecord>(predicate:#Predicate{$0.id==record.id})).first { context.delete(old) }
            context.insert(ExamAutopsyRecord(from:record))
            try context.save()
        } catch {
            context.rollback()
            Log.data.error("ExamAutopsyRepository upsert failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        if let i=records.firstIndex(where:{$0.id==record.id}) { records[i]=record } else { records.append(record) }
    }
    func delete(_ record: ExamAutopsy) {
        guard let context else {
            records.removeAll{$0.id==record.id}
            return
        }
        do {
            if let old = try context.fetch(FetchDescriptor<ExamAutopsyRecord>(predicate:#Predicate{$0.id==record.id})).first {
                context.delete(old)
                try context.save()
            }
        } catch {
            context.rollback()
            Log.data.error("ExamAutopsyRepository delete failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        records.removeAll{$0.id==record.id}
    }
}
