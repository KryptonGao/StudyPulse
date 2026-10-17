//
//  HomeViewModelRecomputeTests.swift
//  StudyPulseTests
//
//  回归测试:`HomeViewModel.recompute()` 的 dirty flag 签名必须识别「就地编辑」的成绩。
//  分数 / 排名 / 满分等字段变化,但 id 与 count 不变时,也要求重算
//  overallAverageRate / recentGrades / averageRateTrend / subjectSnapshots。
//
//  Regression tests for the HomeViewModel recompute dirty flag: in-place grade
//  edits (score / ranking / fullScore) keep id & count unchanged but must still
//  invalidate the cached signature.
//

import XCTest
@testable import StudyPulse

@MainActor
final class HomeViewModelRecomputeTests: XCTestCase {

    private func makeSUT(grade: Grade) -> (sut: HomeViewModel, mocks: MockRepositoryHub) {
        let (container, mocks) = TestRepositoryContainerFactory.makeMockContainer()
        mocks.grade.grades = [grade]
        mocks.grade.filteredGrades = [grade]
        let sut = HomeViewModel(container: container, hrvManager: .shared)
        return (sut, mocks)
    }

    /// 改分数(id / count 不变)后,`recompute()` 必须产出新的派生数据。
    func test_recompute_detectsInPlaceScoreEdit() {
        let (sut, mocks) = makeSUT(
            grade: Grade(subject: "Math", score: 80, examName: "Midterm")
        )
        sut.recompute()
        XCTAssertEqual(sut.overallAverageRate ?? -1, 80, accuracy: 0.001)
        XCTAssertEqual(sut.recentGrades.first?.score ?? -1, 80, accuracy: 0.001)
        XCTAssertEqual(sut.averageRateTrend, [80])

        // 就地改分:不新增 / 删除成绩,id 与 count 均不变。
        mocks.grade.grades[0].score = 40
        mocks.grade.filteredGrades[0].score = 40
        sut.recompute()

        XCTAssertEqual(sut.overallAverageRate ?? -1, 40, accuracy: 0.001)
        XCTAssertEqual(sut.recentGrades.first?.score ?? -1, 40, accuracy: 0.001)
        XCTAssertEqual(sut.subjectSnapshots.first?.averageRate ?? -1, 0.4, accuracy: 0.001)
        XCTAssertEqual(sut.averageRateTrend, [40])
    }

    /// 改排名 / 满分(不改 id)同样要触发重算。
    func test_recompute_detectsInPlaceRankingAndFullScoreEdit() {
        let (sut, mocks) = makeSUT(
            grade: Grade(subject: "Math", score: 80, examName: "Midterm")
        )
        sut.recompute()
        XCTAssertEqual(sut.overallAverageRate ?? -1, 80, accuracy: 0.001)

        mocks.grade.grades[0].ranking = 3
        mocks.grade.grades[0].fullScore = 200
        sut.recompute()

        // 80 / 200 = 40%(成绩自带满分优先于科目满分)。
        XCTAssertEqual(sut.overallAverageRate ?? -1, 40, accuracy: 0.001)
        XCTAssertEqual(sut.recentGrades.first?.ranking, 3)
    }
}
