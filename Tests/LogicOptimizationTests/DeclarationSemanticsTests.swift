import Testing
import LogicOptimizationProbeSupport

@Suite(.timeLimit(.minutes(1)))
struct DeclarationSemanticsTests {
    @Test func wideBlockingConversion() throws { try DeclarationSemanticsContractProbe.wideBlockingConversion() }
    @Test func partialNBAAndSampling() throws { try DeclarationSemanticsContractProbe.partialNBAAndSampling() }
    @Test func hierarchyAndContinuousConversion() throws { try DeclarationSemanticsContractProbe.hierarchyAndContinuousConversion() }
    @Test func undrivenNetAndVariableDefaults() throws { try DeclarationSemanticsContractProbe.undrivenNetAndVariableDefaults() }
    @Test func stateInitialRanges() throws { try DeclarationSemanticsContractProbe.stateInitialRanges() }
    @Test func convertedLocalControlsQualifyActualBranches() throws { try DeclarationSemanticsContractProbe.convertedLocalControlsQualifyActualBranches() }
    @Test func netInitializersRemainLiveDrivers() throws { try DeclarationSemanticsContractProbe.netInitializersRemainLiveDrivers() }
    @Test func inputConversionPrecedesClockEdgeDetection() throws { try DeclarationSemanticsContractProbe.inputConversionPrecedesClockEdgeDetection() }
    @Test func unwrittenNetBitsStayHighImpedance() throws { try DeclarationSemanticsContractProbe.unwrittenNetBitsStayHighImpedance() }
}
