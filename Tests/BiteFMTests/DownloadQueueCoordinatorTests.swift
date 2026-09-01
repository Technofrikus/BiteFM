import XCTest
@testable import BiteFMCore

final class DownloadQueueCoordinatorTests: XCTestCase {
    func testReservationsCountAgainstConcurrencyLimitAndRejectDuplicates() {
        var coordinator = DownloadQueueCoordinator(maxConcurrentDownloads: 2)

        XCTAssertTrue(coordinator.reservePreparation(for: 101, activeTerminIDs: []))
        XCTAssertFalse(coordinator.reservePreparation(for: 101, activeTerminIDs: []))
        XCTAssertTrue(coordinator.reservePreparation(for: 102, activeTerminIDs: []))
        XCTAssertFalse(coordinator.reservePreparation(for: 103, activeTerminIDs: []))

        coordinator.releasePreparation(for: 101)
        XCTAssertTrue(coordinator.reservePreparation(for: 103, activeTerminIDs: []))
    }

    func testActiveDownloadPreventsPreparationForSameEpisode() {
        var coordinator = DownloadQueueCoordinator(maxConcurrentDownloads: 2)

        XCTAssertFalse(coordinator.reservePreparation(for: 101, activeTerminIDs: [101]))
        XCTAssertTrue(coordinator.reservePreparation(for: 102, activeTerminIDs: [101]))
        XCTAssertFalse(coordinator.reservePreparation(for: 103, activeTerminIDs: [101]))
    }

    func testConcurrentQueueRequestIsCoalescedIntoOneRerun() {
        var coordinator = DownloadQueueCoordinator(maxConcurrentDownloads: 2)

        XCTAssertTrue(coordinator.beginQueueProcessing())
        XCTAssertFalse(coordinator.beginQueueProcessing())
        XCTAssertFalse(coordinator.beginQueueProcessing())
        XCTAssertTrue(coordinator.finishQueueProcessing())

        XCTAssertTrue(coordinator.beginQueueProcessing())
        XCTAssertFalse(coordinator.finishQueueProcessing())
    }

    func testTaskCreationRequiresReservationAndRechecksActiveEpisode() {
        var coordinator = DownloadQueueCoordinator(maxConcurrentDownloads: 2)
        XCTAssertTrue(coordinator.reservePreparation(for: 101, activeTerminIDs: []))

        XCTAssertTrue(coordinator.canCreateTask(for: 101, activeTerminIDs: []))
        XCTAssertFalse(coordinator.canCreateTask(for: 101, activeTerminIDs: [101]))
        XCTAssertFalse(coordinator.canCreateTask(for: 102, activeTerminIDs: []))
    }

    func testBudgetDecisionPausesQueueWithoutRequestingAnotherPass() {
        var coordinator = DownloadQueueCoordinator(maxConcurrentDownloads: 2)

        XCTAssertTrue(coordinator.beginQueueProcessing())
        XCTAssertTrue(coordinator.reservePreparation(for: 101, activeTerminIDs: []))
        XCTAssertTrue(coordinator.beginBudgetDecision())
        XCTAssertTrue(coordinator.releasePreparation(for: 101))

        XCTAssertFalse(coordinator.beginQueueProcessing())
        XCTAssertFalse(coordinator.finishQueueProcessing())

        coordinator.finishBudgetDecision()
        XCTAssertTrue(coordinator.beginQueueProcessing())
    }

    func testDeletionPlanDeletesOnlyOldestPrefixNeededToFit() {
        let plan = DownloadBudgetPolicy.deletionPlan(
            currentReservedBytes: 900,
            additionalBytes: 300,
            limitBytes: 1_000,
            oldestFirstCandidates: [
                .init(terminID: 1, bytes: 120),
                .init(terminID: 2, bytes: 100),
                .init(terminID: 3, bytes: 500)
            ]
        )

        XCTAssertEqual(plan, .delete(terminIDs: [1, 2]))
    }

    func testDeletionPlanIsImpossibleWithoutDeletingAnythingWhenTargetCannotFit() {
        let plan = DownloadBudgetPolicy.deletionPlan(
            currentReservedBytes: 400,
            additionalBytes: 1_100,
            limitBytes: 1_000,
            oldestFirstCandidates: [
                .init(terminID: 1, bytes: 200),
                .init(terminID: 2, bytes: 200)
            ]
        )

        XCTAssertEqual(plan, .impossible)
    }

    func testForegroundAdmissionRejectsPersistedQueueEntryThatExceedsBudget() {
        let rejected = DownloadBudgetPolicy.queuedTerminIDsExceedingBudget(
            baseReservedBytes: 900,
            limitBytes: 1_000,
            oldestFirstCandidates: [
                .init(terminID: 101, bytes: 80),
                .init(terminID: 102, bytes: 200)
            ]
        )

        XCTAssertEqual(rejected, [102])
    }

    func testLimitPlannerSkipsIntermediateOptionThatStillDoesNotFit() {
        let option = DownloadBudgetPolicy.smallestLimitOption(
            after: 500,
            fitting: 1_500,
            options: [
                ("1 GB", 1_000),
                ("2 GB", 2_000),
                ("3 GB", 3_000)
            ]
        )

        XCTAssertEqual(option?.label, "2 GB")
        XCTAssertEqual(option?.bytes, 2_000)
    }
}
