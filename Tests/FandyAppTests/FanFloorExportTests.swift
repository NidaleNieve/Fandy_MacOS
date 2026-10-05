import AppKit
import Foundation
import Testing
@testable import FandyApp
@testable import FandyCore

@Test func observedReadoutMatchesTwentyEightAndFiftyPercentFloorTargets() throws {
    for percent in [28.0, 50] {
        var fans = [Fan(id: 0, min: 2317, max: 7826, actual: 0), Fan(id: 1, min: 1800, max: 7200, actual: 0)]
        for index in fans.indices { fans[index].actualRPM = try fans[index].rpm(percent: percent) }
        #expect(abs(StatusPresentation.observedFanPercent(fans) - percent) < 0.000001)
    }
}

@MainActor @Test func allExportPanelsStartInDownloadsWithTheirExpectedFilename() {
    let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    for filename in [BuiltInProfiles.school.exportFilename, "Fandy Configuration.json", "Fandy Diagnostics.json"] {
        let panel = ExportSavePanel.make(filename: filename)
        #expect(panel.directoryURL == downloads)
        #expect(panel.nameFieldStringValue == filename)
        #expect(panel.allowedContentTypes == [.json])
    }
}
