import Testing
@testable import HarkCore

private func step(_ summary: String) -> UndoStep {
    UndoStep(summary: summary) {}
}

@Test func undoPopsNewestFirst() {
    var stack = UndoStack()
    stack.push(step("first"))
    stack.push(step("second"))
    #expect(stack.pop()?.summary == "second")
    #expect(stack.pop()?.summary == "first")
    #expect(stack.pop() == nil)
}

@Test func undoDropsOldestPastLimit() {
    var stack = UndoStack(limit: 2)
    for name in ["one", "two", "three"] { stack.push(step(name)) }
    #expect(stack.pop()?.summary == "three")
    #expect(stack.pop()?.summary == "two")
    #expect(stack.pop() == nil)
}
