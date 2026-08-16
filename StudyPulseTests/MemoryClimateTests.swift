import XCTest
@testable import StudyPulse

final class MemoryClimateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func entry(daysAgo: Double, score: Double, quality: ReviewQuality) -> MasteryHistoryEntry {
        MasteryHistoryEntry(
            timestamp: now.addingTimeInterval(-daysAgo * 86_400),
            score: score,
            quality: quality.rawValue
        )
    }

    private func mistake(
        id: UUID = UUID(),
        subject: String = "Math",
        tags: [String],
        mastery: Double,
        daysOld: Double = 1,
        history: [MasteryHistoryEntry],
        repetitions: Int = 0,
        nextReviewDays: Double? = nil,
        lapses: Int = 0,
        phaseId: UUID? = nil
    ) -> MistakeNote {
        let state = nextReviewDays.map {
            ReviewState(
                repetitions: repetitions,
                nextReviewDate: now.addingTimeInterval($0 * 86_400),
                lastReviewDate: history.first?.timestamp,
                lapses: lapses
            )
        }
        return MistakeNote(
            id: id,
            title: tags.first ?? "Question",
            subject: subject,
            originalQuestion: "Q",
            source: "Test",
            date: now.addingTimeInterval(-daysOld * 86_400),
            errorReason: "",
            wrongSolution: "",
            correctSolution: "",
            reviewState: state,
            phaseId: phaseId,
            masteryScore: mastery,
            masteryHistory: history,
            tags: tags
        )
    }

    func testClassifiesClearFogFrozenAndSouthHumid() throws {
        let clear = mistake(
            tags: ["Geometry"],
            mastery: 0.86,
            history: [entry(daysAgo: 1, score: 0.86, quality: .good), entry(daysAgo: 3, score: 0.8, quality: .easy)],
            repetitions: 3,
            nextReviewDays: 5
        )
        XCTAssertEqual(
            MemoryClimateEngine.generate(mistakes: [clear], phaseId: nil, now: now).subjects.first?.weather,
            .clear
        )

        let fog = mistake(
            tags: ["Algebra"],
            mastery: 0.5,
            history: [entry(daysAgo: 1, score: 0.5, quality: .hard), entry(daysAgo: 4, score: 0.55, quality: .good)],
            repetitions: 2,
            nextReviewDays: 2
        )
        XCTAssertEqual(
            MemoryClimateEngine.generate(mistakes: [fog], phaseId: nil, now: now).subjects.first?.weather,
            .fog
        )

        let humid = mistake(
            tags: ["Calculus"],
            mastery: 0.5,
            history: [entry(daysAgo: 0.5, score: 0.5, quality: .good), entry(daysAgo: 5, score: 0.3, quality: .again)],
            repetitions: 1,
            nextReviewDays: 4,
            lapses: 1
        )
        XCTAssertEqual(
            MemoryClimateEngine.generate(mistakes: [humid], phaseId: nil, now: now).subjects.first?.weather,
            .southHumid
        )

        let frozen = mistake(
            tags: ["Trigonometry"],
            mastery: 0,
            daysOld: 30,
            history: []
        )
        XCTAssertEqual(
            MemoryClimateEngine.generate(mistakes: [frozen], phaseId: nil, now: now).subjects.first?.weather,
            .frozen
        )
    }

    func testThunderstormRequiresRelatedConceptsAndNegativeEvidenceOnBothSides() throws {
        let bridge = mistake(
            tags: ["Functions", "Sequences"],
            mastery: 0.3,
            history: [entry(daysAgo: 2, score: 0.3, quality: .again)]
        )
        let functions = mistake(
            tags: ["Functions"],
            mastery: 0.4,
            history: [entry(daysAgo: 3, score: 0.4, quality: .hard)]
        )
        let sequences = mistake(
            tags: ["Sequences"],
            mastery: 0.35,
            history: [entry(daysAgo: 4, score: 0.35, quality: .again)]
        )

        let climate = try XCTUnwrap(
            MemoryClimateEngine.generate(
                mistakes: [bridge, functions, sequences],
                phaseId: nil,
                now: now
            ).subjects.first
        )
        XCTAssertEqual(climate.weather, .thunderstorm)
        XCTAssertEqual(climate.interferences.first?.displayName, "Functions ↔ Sequences")

        let insufficient = MemoryClimateEngine.generate(
            mistakes: [bridge],
            phaseId: nil,
            now: now
        )
        XCTAssertNotEqual(insufficient.subjects.first?.weather, .thunderstorm)
    }

    func testThunderstormTakesPriorityOverRecentSuccess() throws {
        let a = mistake(
            tags: ["Functions", "Sequences"],
            mastery: 0.4,
            history: [
                entry(daysAgo: 0.25, score: 0.4, quality: .good),
                entry(daysAgo: 2, score: 0.3, quality: .again)
            ]
        )
        let b = mistake(
            tags: ["Functions"],
            mastery: 0.3,
            history: [entry(daysAgo: 3, score: 0.3, quality: .hard)]
        )
        let c = mistake(
            tags: ["Sequences"],
            mastery: 0.3,
            history: [entry(daysAgo: 4, score: 0.3, quality: .again)]
        )
        XCTAssertEqual(
            MemoryClimateEngine.generate(mistakes: [a, b, c], phaseId: nil, now: now).subjects.first?.weather,
            .thunderstorm
        )
    }

    func testNewUnreviewedSubjectIsOmittedAndPhaseIsRecorded() throws {
        let phase = UUID()
        let newNote = mistake(tags: ["New"], mastery: 0, history: [], phaseId: phase)
        let snapshot = MemoryClimateEngine.generate(mistakes: [newNote], phaseId: phase, now: now)
        XCTAssertTrue(snapshot.subjects.isEmpty)
        XCTAssertEqual(snapshot.phaseId, phase)
    }

    func testHistoryUpsertSeparatesPhasesAndPrunesToNinetyDays() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("memory-climate-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let firstPhase = UUID()
        let secondPhase = UUID()
        let climate = SubjectMemoryClimate(
            subject: "Math",
            weather: .clear,
            confidence: 0.8,
            averageMastery: 0.8,
            overdueRatio: 0,
            primaryConcepts: ["Functions"],
            interferences: [],
            evidenceMistakeIDs: []
        )

        for offset in 0..<95 {
            let date = now.addingTimeInterval(-Double(offset) * 86_400)
            let snapshot = MemoryClimateSnapshot(date: date, phaseId: firstPhase, subjects: [climate])
            MemoryClimateHistoryStore.upsert(snapshot, at: url, now: now)
        }
        MemoryClimateHistoryStore.upsert(
            MemoryClimateSnapshot(date: now, phaseId: secondPhase, subjects: [climate]),
            at: url,
            now: now
        )
        MemoryClimateHistoryStore.upsert(
            MemoryClimateSnapshot(date: now, phaseId: firstPhase, subjects: [
                SubjectMemoryClimate(
                    subject: "Math", weather: .fog, confidence: 0.7,
                    averageMastery: 0.5, overdueRatio: 0,
                    primaryConcepts: ["Functions"], interferences: [], evidenceMistakeIDs: []
                )
            ]),
            at: url,
            now: now
        )

        let loaded = MemoryClimateHistoryStore.load(from: url)
        XCTAssertEqual(loaded.filter { $0.phaseId == firstPhase }.count, 90)
        XCTAssertEqual(loaded.filter { $0.phaseId == secondPhase }.count, 1)
        XCTAssertEqual(
            loaded.first {
                $0.phaseId == firstPhase && Calendar.current.isDate($0.date, inSameDayAs: now)
            }?.subjects.first?.weather,
            .fog
        )
    }

    func testCorruptHistorySafelyReturnsEmpty() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("memory-climate-corrupt-\(UUID().uuidString).json")
        try Data("not-json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(MemoryClimateHistoryStore.load(from: url).isEmpty)
    }

    func testClearBoundaryAtMasterySeventy() throws {
        let atBoundary = mistake(
            tags: ["Geometry"],
            mastery: 0.70,
            history: [entry(daysAgo: 1, score: 0.7, quality: .good), entry(daysAgo: 3, score: 0.75, quality: .easy)],
            repetitions: 3,
            nextReviewDays: 5
        )
        XCTAssertEqual(
            MemoryClimateEngine.generate(mistakes: [atBoundary], phaseId: nil, now: now).subjects.first?.weather,
            .clear
        )

        let below = mistake(
            tags: ["Geometry"],
            mastery: 0.69,
            history: [entry(daysAgo: 1, score: 0.69, quality: .good), entry(daysAgo: 3, score: 0.72, quality: .easy)],
            repetitions: 3,
            nextReviewDays: 5
        )
        XCTAssertEqual(
            MemoryClimateEngine.generate(mistakes: [below], phaseId: nil, now: now).subjects.first?.weather,
            .fog
        )
    }

    func testThunderstormBoundaryAtExactlyThreeNegativeRetrievals() throws {
        let bridge = mistake(
            tags: ["Functions", "Sequences"],
            mastery: 0.3,
            history: [entry(daysAgo: 2, score: 0.3, quality: .again)]
        )
        let functions = mistake(
            tags: ["Functions"],
            mastery: 0.4,
            history: [entry(daysAgo: 3, score: 0.4, quality: .hard)]
        )
        let exactlyThree = MemoryClimateEngine.generate(
            mistakes: [bridge, functions],
            phaseId: nil,
            now: now
        )
        XCTAssertEqual(exactlyThree.subjects.first?.weather, .thunderstorm)
        XCTAssertEqual(exactlyThree.subjects.first?.interferences.first?.negativeRetrievalCount, 3)

        let onlyTwo = MemoryClimateEngine.generate(mistakes: [bridge], phaseId: nil, now: now)
        XCTAssertNotEqual(onlyTwo.subjects.first?.weather, .thunderstorm)
    }

    func testFrozenBoundaryAtTwentyOneDays() throws {
        let atBoundary = mistake(
            tags: ["Trigonometry"],
            mastery: 0,
            daysOld: 21,
            history: []
        )
        XCTAssertEqual(
            MemoryClimateEngine.generate(mistakes: [atBoundary], phaseId: nil, now: now).subjects.first?.weather,
            .frozen
        )

        let justBelow = mistake(
            tags: ["Trigonometry"],
            mastery: 0,
            daysOld: 20.999,
            history: []
        )
        XCTAssertTrue(
            MemoryClimateEngine.generate(mistakes: [justBelow], phaseId: nil, now: now).subjects.isEmpty
        )
    }

    func testSouthHumidBoundaryAtFortyEightHours() throws {
        let exactlyAtWindow = mistake(
            tags: ["Calculus"],
            mastery: 0.5,
            history: [entry(daysAgo: 2.0, score: 0.5, quality: .good), entry(daysAgo: 5, score: 0.4, quality: .again)],
            repetitions: 1,
            nextReviewDays: 4,
            lapses: 1
        )
        XCTAssertEqual(
            MemoryClimateEngine.generate(mistakes: [exactlyAtWindow], phaseId: nil, now: now).subjects.first?.weather,
            .southHumid
        )

        let justOutside = mistake(
            tags: ["Calculus"],
            mastery: 0.5,
            history: [entry(daysAgo: 2.0001, score: 0.5, quality: .good), entry(daysAgo: 5, score: 0.4, quality: .again)],
            repetitions: 1,
            nextReviewDays: 4,
            lapses: 1
        )
        XCTAssertEqual(
            MemoryClimateEngine.generate(mistakes: [justOutside], phaseId: nil, now: now).subjects.first?.weather,
            .fog
        )
    }

    func testInterleavingFallsBackToPlainQueueWhenNoContrast() throws {
        let due = mistake(
            tags: ["Functions"],
            mastery: 0.3,
            history: [entry(daysAgo: 1, score: 0.3, quality: .again)],
            repetitions: 1,
            nextReviewDays: -1
        )
        let clearClimate = MemoryClimateSnapshot(
            date: now,
            phaseId: nil,
            subjects: [
                SubjectMemoryClimate(
                    subject: "Math", weather: .clear, confidence: 0.8,
                    averageMastery: 0.8, overdueRatio: 0,
                    primaryConcepts: ["Functions"], interferences: [], evidenceMistakeIDs: []
                )
            ]
        )
        let stormPair = ConceptInterference(
            firstConcept: "Functions", secondConcept: "Sequences",
            negativeRetrievalCount: 3, relatedMistakeIDs: [], confidence: 0.8
        )
        let stormClimate = MemoryClimateSnapshot(
            date: now,
            phaseId: nil,
            subjects: [
                SubjectMemoryClimate(
                    subject: "Math", weather: .thunderstorm, confidence: 0.8,
                    averageMastery: 0.4, overdueRatio: 0.5,
                    primaryConcepts: ["Functions", "Sequences"],
                    interferences: [stormPair], evidenceMistakeIDs: [due.id]
                )
            ]
        )
        let nonMatching = mistake(
            tags: ["Algebra"],
            mastery: 0.5,
            history: [entry(daysAgo: 2, score: 0.5, quality: .good)],
            repetitions: 2,
            nextReviewDays: 5
        )

        // 空 due 队列 → 空结果。
        XCTAssertTrue(
            ClimateInterleavingEngine.buildQueue(due: [], allMistakes: [due], climate: stormClimate, now: now).isEmpty
        )
        // 无雷暴 → 全部 scheduled。
        let plain = ClimateInterleavingEngine.buildQueue(
            due: [due], allMistakes: [due], climate: clearClimate, now: now
        )
        XCTAssertEqual(plain.count, 1)
        XCTAssertTrue(plain.allSatisfy { !$0.isEarlyContrast })
        // 雷暴存在但无非到期/概念匹配卡 → 回退普通队列。
        let noContrast = ClimateInterleavingEngine.buildQueue(
            due: [due], allMistakes: [due, nonMatching], climate: stormClimate, now: now
        )
        XCTAssertEqual(noContrast.count, 1)
        XCTAssertTrue(noContrast.allSatisfy { !$0.isEarlyContrast })
    }

    func testInterleavingAddsBoundedNonDueContrastWithoutDuplicates() throws {
        let dueFunction = mistake(
            tags: ["Functions"],
            mastery: 0.3,
            history: [entry(daysAgo: 1, score: 0.3, quality: .again)],
            repetitions: 1,
            nextReviewDays: -1
        )
        let dueGeometry = mistake(
            tags: ["Geometry"],
            mastery: 0.5,
            history: [entry(daysAgo: 2, score: 0.5, quality: .hard)],
            repetitions: 1,
            nextReviewDays: -0.5
        )
        let earlySequence = mistake(
            tags: ["Sequences"],
            mastery: 0.4,
            history: [entry(daysAgo: 3, score: 0.4, quality: .again)],
            repetitions: 1,
            nextReviewDays: 5
        )
        let pair = ConceptInterference(
            firstConcept: "Functions",
            secondConcept: "Sequences",
            negativeRetrievalCount: 3,
            relatedMistakeIDs: [dueFunction.id, earlySequence.id],
            confidence: 0.8
        )
        let climate = MemoryClimateSnapshot(
            date: now,
            phaseId: nil,
            subjects: [
                SubjectMemoryClimate(
                    subject: "Math", weather: .thunderstorm, confidence: 0.8,
                    averageMastery: 0.4, overdueRatio: 0.5,
                    primaryConcepts: ["Functions", "Sequences"],
                    interferences: [pair],
                    evidenceMistakeIDs: [dueFunction.id, earlySequence.id]
                )
            ]
        )

        let queue = ClimateInterleavingEngine.buildQueue(
            due: [dueFunction, dueGeometry],
            allMistakes: [dueFunction, dueGeometry, earlySequence],
            climate: climate,
            now: now
        )
        XCTAssertEqual(queue.filter(\.isEarlyContrast).count, 1)
        XCTAssertEqual(Set(queue.map(\.id)).count, queue.count)
        XCTAssertEqual(queue.first(where: \.isEarlyContrast)?.id, earlySequence.id)
    }
}

@MainActor
final class MemoryClimateFlashcardViewModelTests: XCTestCase {
    private var now: Date { Date() }

    func testEarlyContrastRatingRecordsMasteryButDoesNotMoveSRSDateOrReinsert() throws {
        let due = makeMistake(tag: "Functions", nextDays: -1, qualities: [.again, .hard])
        let bridge = makeMistake(tags: ["Functions", "Sequences"], nextDays: -2, qualities: [.again])
        let early = makeMistake(tag: "Sequences", nextDays: 5, qualities: [.again])
        let setup = TestRepositoryContainerFactory.makeMockContainer()
        setup.mocks.mistake.mistakeSets = [due, bridge, early]
        setup.mocks.mistake.filteredMistakeSets = [due, bridge, early]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("memory-climate-vm-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let viewModel = FlashcardStudyViewModel(
            container: setup.container,
            filter: .dueQueue,
            climateHistoryURL: url
        )
        guard let earlyIndex = viewModel.queue.firstIndex(where: \.isEarlyContrast) else {
            return XCTFail("Expected an early contrast card")
        }
        viewModel.currentIndex = earlyIndex
        let originalDate = early.reviewState?.nextReviewDate
        viewModel.handleRating(.again)

        XCTAssertEqual(setup.mocks.mistake.recordReviewCalledCount, 1)
        XCTAssertEqual(setup.mocks.mistake.updateReviewStateCalledCount, 0)
        XCTAssertEqual(
            setup.mocks.mistake.mistakeSets.first(where: { $0.id == early.id })?.reviewState?.nextReviewDate,
            originalDate
        )
        XCTAssertTrue(viewModel.reinsertQueue.isEmpty)
        XCTAssertEqual(viewModel.stats.earlyContrastReviewed, 1)
    }

    private func makeMistake(
        tag: String,
        nextDays: Double,
        qualities: [ReviewQuality]
    ) -> MistakeNote {
        makeMistake(tags: [tag], nextDays: nextDays, qualities: qualities)
    }

    private func makeMistake(
        tags: [String],
        nextDays: Double,
        qualities: [ReviewQuality]
    ) -> MistakeNote {
        let history = qualities.enumerated().map { index, quality in
            MasteryHistoryEntry(
                timestamp: now.addingTimeInterval(-Double(index + 1) * 86_400),
                score: 0.3,
                quality: quality.rawValue
            )
        }
        return MistakeNote(
            title: tags.first ?? "Question",
            subject: "Math",
            originalQuestion: "Q",
            source: "Test",
            date: now.addingTimeInterval(-10 * 86_400),
            errorReason: "",
            wrongSolution: "",
            correctSolution: "",
            reviewState: ReviewState(
                repetitions: 1,
                nextReviewDate: now.addingTimeInterval(nextDays * 86_400),
                lastReviewDate: history.first?.timestamp
            ),
            masteryScore: 0.3,
            masteryHistory: history,
            tags: tags
        )
    }
}

// MARK: - RemediationTaskEngine

@MainActor
final class RemediationTaskEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func entry(daysAgo: Double, score: Double, quality: ReviewQuality) -> MasteryHistoryEntry {
        MasteryHistoryEntry(
            timestamp: now.addingTimeInterval(-daysAgo * 86_400),
            score: score,
            quality: quality.rawValue
        )
    }

    private func mistake(
        id: UUID = UUID(),
        subject: String = "Math",
        tags: [String],
        mastery: Double,
        daysOld: Double = 1,
        history: [MasteryHistoryEntry],
        repetitions: Int = 0,
        nextReviewDays: Double? = nil
    ) -> MistakeNote {
        let state = nextReviewDays.map {
            ReviewState(
                repetitions: repetitions,
                nextReviewDate: now.addingTimeInterval($0 * 86_400),
                lastReviewDate: history.first?.timestamp
            )
        }
        return MistakeNote(
            id: id,
            title: tags.first ?? "Question",
            subject: subject,
            originalQuestion: "Q",
            source: "Test",
            date: now.addingTimeInterval(-daysOld * 86_400),
            errorReason: "",
            wrongSolution: "",
            correctSolution: "",
            reviewState: state,
            masteryScore: mastery,
            masteryHistory: history,
            tags: tags
        )
    }

    private func climate(
        subject: String = "Math",
        weather: MemoryWeather,
        interferences: [ConceptInterference] = [],
        primaryConcepts: [String] = []
    ) -> MemoryClimateSnapshot {
        MemoryClimateSnapshot(
            date: now,
            phaseId: nil,
            subjects: [
                SubjectMemoryClimate(
                    subject: subject,
                    weather: weather,
                    confidence: 0.8,
                    averageMastery: 0.5,
                    overdueRatio: 0.3,
                    primaryConcepts: primaryConcepts,
                    interferences: interferences,
                    evidenceMistakeIDs: []
                )
            ]
        )
    }

    func testNoTaskWhenDominantIsClearOrSouthHumid() throws {
        XCTAssertNil(
            RemediationTaskEngine.generate(
                snapshot: climate(subject: "Math", weather: .clear),
                mistakes: [],
                now: now
            )
        )
        XCTAssertNil(
            RemediationTaskEngine.generate(
                snapshot: climate(subject: "Math", weather: .southHumid),
                mistakes: [],
                now: now
            )
        )
        XCTAssertNil(RemediationTaskEngine.generate(snapshot: .empty(date: now), mistakes: [], now: now))
    }

    func testNoTaskWhenNoMatchingSubjectMistakes() throws {
        let otherSubject = mistake(
            subject: "Physics",
            tags: ["Newton"],
            mastery: 0.5,
            history: [entry(daysAgo: 2, score: 0.5, quality: .hard)]
        )
        XCTAssertNil(
            RemediationTaskEngine.generate(
                snapshot: climate(subject: "Math", weather: .fog),
                mistakes: [otherSubject],
                now: now
            )
        )
    }

    func testFrozenTaskPrioritizesOverdueThenLongestUncalled() throws {
        let overdue = mistake(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            tags: ["Trigonometry"],
            mastery: 0.4,
            history: [entry(daysAgo: 2, score: 0.4, quality: .hard)],
            repetitions: 2,
            nextReviewDays: -5
        )
        let notOverdue = mistake(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            tags: ["Algebra"],
            mastery: 0.6,
            daysOld: 40,
            history: [entry(daysAgo: 39, score: 0.6, quality: .good)],
            repetitions: 2,
            nextReviewDays: 3
        )
        let task = try XCTUnwrap(
            RemediationTaskEngine.generate(
                snapshot: climate(subject: "Math", weather: .frozen),
                mistakes: [notOverdue, overdue],
                now: now
            )
        )
        XCTAssertEqual(task.strategy, .overdue)
        XCTAssertEqual(task.mistakes.map(\.id), [overdue.id, notOverdue.id])
    }

    func testFrozenWithoutOverdueUsesLongestUncalledFirst() throws {
        let recent = mistake(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            tags: ["Geometry"],
            mastery: 0.7,
            history: [entry(daysAgo: 3, score: 0.7, quality: .good)],
            repetitions: 3,
            nextReviewDays: 6
        )
        let stale = mistake(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            tags: ["Algebra"],
            mastery: 0.2,
            daysOld: 30,
            history: [entry(daysAgo: 29, score: 0.2, quality: .hard)],
            repetitions: 1,
            nextReviewDays: 4
        )
        let task = try XCTUnwrap(
            RemediationTaskEngine.generate(
                snapshot: climate(subject: "Math", weather: .frozen),
                mistakes: [recent, stale],
                now: now
            )
        )
        XCTAssertEqual(task.mistakes.map(\.id), [stale.id, recent.id])
    }

    func testThunderstormTaskCoversBothConceptsWithNegativeEvidenceFirst() throws {
        let pair = ConceptInterference(
            firstConcept: "Functions",
            secondConcept: "Sequences",
            negativeRetrievalCount: 3,
            relatedMistakeIDs: [],
            confidence: 0.8
        )
        let weakBridge = mistake(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
            tags: ["Functions", "Sequences"],
            mastery: 0.3,
            history: [entry(daysAgo: 2, score: 0.3, quality: .again)]
        )
        let strongFunctions = mistake(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
            tags: ["Functions"],
            mastery: 0.4,
            history: [entry(daysAgo: 3, score: 0.4, quality: .hard)]
        )
        let sequences = mistake(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
            tags: ["Sequences"],
            mastery: 0.35,
            history: [entry(daysAgo: 4, score: 0.35, quality: .again)]
        )
        let task = try XCTUnwrap(
            RemediationTaskEngine.generate(
                snapshot: climate(
                    subject: "Math",
                    weather: .thunderstorm,
                    interferences: [pair],
                    primaryConcepts: ["Functions", "Sequences"]
                ),
                mistakes: [weakBridge, strongFunctions, sequences],
                now: now
            )
        )
        XCTAssertEqual(task.strategy, .interference)
        XCTAssertEqual(task.weather, .thunderstorm)
        XCTAssertEqual(task.mistakes.count, 3)
        let conceptsByCard = task.mistakes.map {
            Set(MemoryClimateEngine.concepts(for: $0).map { $0.lowercased() })
        }
        XCTAssertTrue(conceptsByCard[0].contains("functions"))
        XCTAssertTrue(conceptsByCard[1].contains("sequences"))
        XCTAssertTrue(task.mistakes.allSatisfy {
            let set = Set(MemoryClimateEngine.concepts(for: $0).map { $0.lowercased() })
            return set.contains("functions") || set.contains("sequences")
        })
    }

    func testFogTaskPrioritizesRecentFailuresThenLowestMastery() throws {
        let recentlyMissed = mistake(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!,
            tags: ["Algebra"],
            mastery: 0.6,
            history: [
                entry(daysAgo: 1, score: 0.6, quality: .again),
                entry(daysAgo: 6, score: 0.65, quality: .good),
            ],
            repetitions: 2,
            nextReviewDays: 2
        )
        let lowestMastery = mistake(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!,
            tags: ["Geometry"],
            mastery: 0.2,
            history: [entry(daysAgo: 4, score: 0.2, quality: .hard)],
            repetitions: 1,
            nextReviewDays: 2
        )
        let stable = mistake(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000a")!,
            tags: ["Trigonometry"],
            mastery: 0.8,
            history: [entry(daysAgo: 3, score: 0.8, quality: .good)],
            repetitions: 4,
            nextReviewDays: 4
        )
        let task = try XCTUnwrap(
            RemediationTaskEngine.generate(
                snapshot: climate(subject: "Math", weather: .fog),
                mistakes: [stable, lowestMastery, recentlyMissed],
                now: now
            )
        )
        XCTAssertEqual(task.strategy, .weakSpot)
        XCTAssertEqual(task.mistakes.map(\.id), [recentlyMissed.id, lowestMastery.id, stable.id])
    }

    func testTaskCardCountRespectsTimeCap() throws {
        var notes: [MistakeNote] = []
        for index in 0..<20 {
            notes.append(
                mistake(
                    id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
                    tags: ["Algebra"],
                    mastery: 0.5,
                    history: [entry(daysAgo: 2, score: 0.5, quality: .hard)],
                    repetitions: 1,
                    nextReviewDays: -2
                )
            )
        }
        let task = try XCTUnwrap(
            RemediationTaskEngine.generate(
                snapshot: climate(subject: "Math", weather: .frozen),
                mistakes: notes,
                now: now
            )
        )
        XCTAssertLessThanOrEqual(task.mistakes.count, RemediationTaskEngine.maxCards)
        XCTAssertEqual(task.mistakes.count, RemediationTaskEngine.maxCards)
        XCTAssertLessThanOrEqual(task.estimatedMinutes, RemediationTaskEngine.maxDurationMinutes)
    }

    func testSingleCardEstimatesTwoMinutes() throws {
        let one = mistake(
            tags: ["Algebra"],
            mastery: 0.5,
            history: [entry(daysAgo: 2, score: 0.5, quality: .hard)],
            repetitions: 1,
            nextReviewDays: -2
        )
        let task = try XCTUnwrap(
            RemediationTaskEngine.generate(
                snapshot: climate(subject: "Math", weather: .fog),
                mistakes: [one],
                now: now
            )
        )
        XCTAssertEqual(task.estimatedMinutes, 2)
    }

    func testGenerationIsDeterministic() throws {
        let notes = [
            mistake(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000000b")!,
                tags: ["Algebra"],
                mastery: 0.4,
                history: [entry(daysAgo: 2, score: 0.4, quality: .hard)],
                repetitions: 1,
                nextReviewDays: -1
            ),
            mistake(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000000c")!,
                tags: ["Geometry"],
                mastery: 0.6,
                history: [entry(daysAgo: 1, score: 0.6, quality: .again)],
                repetitions: 2,
                nextReviewDays: -3
            ),
        ]
        let snapshot = climate(subject: "Math", weather: .frozen)
        let first = RemediationTaskEngine.generate(snapshot: snapshot, mistakes: notes, now: now)
        let second = RemediationTaskEngine.generate(snapshot: snapshot, mistakes: notes, now: now)
        XCTAssertEqual(first?.mistakes.map(\.id), second?.mistakes.map(\.id))
    }
}
