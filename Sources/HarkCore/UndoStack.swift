public struct UndoStack: Sendable {
    private var steps: [UndoStep] = []
    private let limit: Int

    public init(limit: Int = 20) {
        self.limit = limit
    }

    public mutating func push(_ step: UndoStep) {
        steps.append(step)
        if steps.count > limit { steps.removeFirst() }
    }

    public mutating func pop() -> UndoStep? {
        steps.popLast()
    }
}
