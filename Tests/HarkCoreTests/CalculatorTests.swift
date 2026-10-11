import Testing

@testable import HarkCore

@Suite struct CalculatorTests {
    @Test func percentagesAndSums() {
        #expect(Calculator.answer("What is 18 percent of 240?") == "18 percent of 240 is 43.2")
        #expect(Calculator.answer("12 times 7") == "12 times 7 is 84")
        #expect(Calculator.answer("calculate 15 plus 27") == "15 plus 27 is 42")
        #expect(Calculator.answer("10 divided by 4") == "10 divided by 4 is 2.5")
    }

    @Test func unitsConvertWithinOneKind() {
        #expect(Calculator.answer("convert 5 miles to km") == "5 miles is 8.0467 km")
        #expect(Calculator.answer("100 celsius to fahrenheit") == "100 celsius is 212 fahrenheit")
        #expect(Calculator.answer("convert 5 kg to miles") == nil)
        #expect(Calculator.answer("how many kilometres is 26 miles") == "26 miles is 41.8429 kilometres")
    }

    @Test func ordinaryCommandsAreNotCalculations() {
        #expect(Calculator.answer("open slack") == nil)
        #expect(Calculator.answer("switch to chrome") == nil)
        #expect(Calculator.answer("open tab 2") == nil)
    }
}

@Suite struct TimerAndFocusTests {
    @Test func timersAndReminders() {
        #expect(TimerCommand.parse("set a 10 minute timer") == TimerCommand(seconds: 600, label: nil))
        #expect(TimerCommand.parse("remind me in 20 minutes to check the oven") == TimerCommand(seconds: 1200, label: "check the oven"))
        #expect(TimerCommand.parse("timer for an hour")?.seconds == 3600)
        #expect(TimerCommand.parse("timer for 1 hour 30 minutes")?.spoken == "1 hour 30 minutes")
        #expect(TimerCommand.parse("open slack") == nil)
    }

    @Test func focusNamesAProject() {
        #expect(FocusCommand.project(in: "focus on shop") == "shop")
        #expect(FocusCommand.project(in: "switch to the billing project") == "billing")
        #expect(FocusCommand.project(in: "switch to chrome") == nil)
    }
}
