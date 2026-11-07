import Testing
@testable import Stow

@Suite("CPU core count input")
struct CPUCoreLimitInputTests {
    @Test(arguments: ["", " ", "0", "-1", "+2", "1.5", "1e2", "abc", "11", "999999999999999999999999"])
    func invalidEditsCannotBecomeAnExecutionLimit(_ text: String) {
        var input = CPUCoreLimitInput(threads: 4, available: 10)
        input.text = text
        #expect(!input.isValid(available: 10))
        #expect(input.customValue(available: 10) == nil)
    }

    @Test(arguments: [1, 10, 64, 128, 256])
    func everyAvailableCountWorksWithoutEnumeratingAMenu(_ count: Int) {
        var input = CPUCoreLimitInput(threads: 1, available: count)
        input.text = " \(count) "
        #expect(input.isValid(available: count))
        #expect(input.customValue(available: count) == count)
    }

    @Test func untouchedValueInheritsSettingsButEditingCreatesAnOverride() {
        var input = CPUCoreLimitInput(inherited: 3, available: 10)
        #expect(input.text == "3")
        #expect(input.isValid(available: 10))
        #expect(input.overrideValue(available: 10) == nil)
        input.edit("3")
        #expect(input.overrideValue(available: 10) == 3,
                "An explicit choice stays fixed even if the global setting later changes")
        input.edit("7")
        #expect(input.overrideValue(available: 10) == 7)
    }

    @Test func allCoresAndRestoredLimitsRespectTheCurrentMachine() {
        let inherited = CPUCoreLimitInput(available: 128)
        #expect(inherited.text == "128")
        #expect(inherited.overrideValue(available: 128) == nil)
        #expect(CPUCoreLimitInput(threads: 64, available: 10).overrideValue(available: 10) == 10)
        #expect(CPUCoreLimitInput(threads: 0, available: 10).overrideValue(available: 10) == 1)
        #expect(CPUCoreLimitInput(inherited: 64, available: 10).text == "10")
    }

    @Test func clearingTheFieldIsAnInvalidEditRatherThanAutomaticMode() {
        var input = CPUCoreLimitInput(inherited: 2, available: 10)
        input.edit("")
        #expect(input.isCustom)
        #expect(input.text.isEmpty)
        #expect(!input.isValid(available: 10))
        input.edit("4")
        #expect(input.isValid(available: 10))
        #expect(input.overrideValue(available: 10) == 4)
    }
}
