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
}
