import CoreGraphics
import Testing
@testable import CmuxTerminal

@Suite struct TerminalPinchFontSizeAccumulatorTests {
    private let perPoint = TerminalPinchFontSizeAccumulator.magnificationPerPoint

    @Test func smallDeltasCarryUntilAWholePoint() {
        var accumulator = TerminalPinchFontSizeAccumulator()
        #expect(accumulator.consume(perPoint * 0.4) == 0)
        #expect(accumulator.consume(perPoint * 0.4) == 0)
        #expect(accumulator.consume(perPoint * 0.4) == 1)
    }

    @Test func largeDeltaStepsSeveralPointsAtOnce() {
        var accumulator = TerminalPinchFontSizeAccumulator()
        #expect(accumulator.consume(perPoint * 3.5) == 3)
        #expect(accumulator.consume(perPoint * 0.5) == 1)
    }

    @Test func pinchingInShrinksAndReversalGivesBackCarry() {
        var accumulator = TerminalPinchFontSizeAccumulator()
        #expect(accumulator.consume(perPoint * 0.6) == 0)
        #expect(accumulator.consume(-perPoint * 0.6) == 0)
        #expect(accumulator.consume(-perPoint * 2.2) == -2)
    }

    @Test func resetDropsCarry() {
        var accumulator = TerminalPinchFontSizeAccumulator()
        #expect(accumulator.consume(perPoint * 0.9) == 0)
        accumulator.reset()
        #expect(accumulator.consume(perPoint * 0.5) == 0)
    }

    @Test func ignoresNonFiniteDeltas() {
        var accumulator = TerminalPinchFontSizeAccumulator()
        #expect(accumulator.consume(.nan) == 0)
        #expect(accumulator.consume(.infinity) == 0)
        #expect(accumulator.consume(perPoint) == 1)
    }

    @Test func bindingActionsMatchKeyboardFontSizeActions() {
        #expect(TerminalPinchFontSizeAccumulator.bindingAction(forSteps: 0) == nil)
        #expect(TerminalPinchFontSizeAccumulator.bindingAction(forSteps: 1) == "increase_font_size:1")
        #expect(TerminalPinchFontSizeAccumulator.bindingAction(forSteps: -2) == "decrease_font_size:2")
    }
}
