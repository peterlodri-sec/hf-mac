import Testing
import Foundation

@testable import HFMac

struct MoeptimizerTests {

    @Test("MOE-ptimizer is a selectable inference source")
    func isAnInferenceSource() {
        #expect(InferenceSource.allCases.contains(.moeptimizer))
        #expect(InferenceSource.moeptimizer.rawValue.contains("MOE-ptimizer"))
        #expect(InferenceSource.moeptimizer.icon == "arrow.triangle.branch")
    }

    @Test("MOE-ptimizer carries a status label and an empty-chat hint")
    func copyIsPresent() {
        #expect(InferenceSource.moeptimizer.statusLabel.contains("proxy"))
        #expect(InferenceSource.moeptimizer.emptyHint.contains("moeptimizer"))
    }
}
