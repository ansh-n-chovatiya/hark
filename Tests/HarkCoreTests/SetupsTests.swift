import Testing
@testable import HarkCore

@Test func aSetupOpensProjectsThenTheOtherApps() {
    let routine = Setups.routine(
        named: "morning",
        apps: ["Google Chrome", "Code", "Slack"],
        editorWindows: ["relay.py — Shop-backend", "App.tsx — shop-frontend", "Welcome"],
        folders: ["Shop-backend", "shop-frontend", "pricing-engine"])

    #expect(routine.name == "morning")
    #expect(routine.steps.compactMap(\.say) == [
        "open the Shop-backend folder in VS Code",
        "open the shop-frontend folder in VS Code",
        "open Google Chrome app",
        "open Slack app",
    ])
    #expect(routine.steps.allSatisfy { !$0.destructive && $0.shell == nil })
    #expect(Setups.summary(of: routine) == "2 apps and 2 projects")
}

@Test func theEditorIsKeptWhenNoProjectIsOpenInIt() {
    let routine = Setups.routine(named: "notes", apps: ["Code", "Notes"], editorWindows: ["Welcome"], folders: ["Shop-backend"])
    #expect(routine.steps.compactMap(\.say) == ["open Code app", "open Notes app"])
    #expect(Setups.summary(of: routine) == "2 apps")
}

@Test func savingASetupIsParsedWithItsName() {
    let parser = RuleParser(aliases: [:])
    #expect(parser.parse("Save this setup as morning")?.verb == .save)
    #expect(parser.parse("Save this setup as morning")?.query == "morning")
    #expect(parser.parse("remember this setup as deep work")?.query == "deep work")
}
