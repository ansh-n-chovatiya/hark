import Testing
@testable import HarkCore

@Test func aSetupOpensProjectsThenTheOtherApps() {
    let routine = Setups.routine(
        named: "morning",
        apps: ["Google Chrome", "Quill Studio", "Slack"],
        editorWindows: ["relay.py — Shop-backend", "App.tsx — shop-frontend", "Welcome"],
        editorNames: ["Quill Studio", "Quill"],
        folders: ["Shop-backend", "shop-frontend", "pricing-engine"])

    #expect(routine.name == "morning")
    #expect(routine.steps.compactMap(\.say) == [
        "open the Shop-backend folder in Quill Studio",
        "open the shop-frontend folder in Quill Studio",
        "open Google Chrome app",
        "open Slack app",
    ])
    #expect(routine.steps.allSatisfy { !$0.destructive && $0.shell == nil })
    #expect(Setups.summary(of: routine) == "2 apps and 2 projects")
}

@Test func theEditorIsKeptWhenNoProjectIsOpenInIt() {
    let routine = Setups.routine(named: "notes", apps: ["Quill", "Notes"], editorWindows: ["Welcome"], editorNames: ["Quill"], folders: ["Shop-backend"])
    #expect(routine.steps.compactMap(\.say) == ["open Quill app", "open Notes app"])
    #expect(Setups.summary(of: routine) == "2 apps")
}

@Test func savingASetupIsParsedWithItsName() {
    let parser = RuleParser(aliases: [:])
    #expect(parser.parse("Save this setup as morning")?.verb == .save)
    #expect(parser.parse("Save this setup as morning")?.query == "morning")
    #expect(parser.parse("remember this setup as deep work")?.query == "deep work")
}
