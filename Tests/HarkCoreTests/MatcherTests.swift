import Foundation
import Testing
@testable import HarkCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func tab(_ title: String, site: String = "", minutesAgo: Double? = nil) -> Item {
    Item(id: "tab:\(title)", kind: .tab, title: title, detail: site, owner: "Google Chrome", lastUsed: used(minutesAgo))
}

private func window(_ title: String, app: String, minutesAgo: Double? = nil) -> Item {
    Item(id: "window:\(app):\(title)", kind: .window, title: title, owner: app, lastUsed: used(minutesAgo))
}

private func app(_ name: String) -> Item {
    Item(id: "app:\(name)", kind: .app, title: name, owner: name)
}

private func file(_ name: String, folder: String) -> Item {
    Item(id: "file:\(folder)/\(name)", kind: .file, title: name, detail: folder, owner: "Finder")
}

private func clip(_ text: String, kind: String, from owner: String, minutesAgo: Double) -> Item {
    Item(id: "clip:\(text)", kind: .clip, title: text, detail: kind, owner: owner, lastUsed: used(minutesAgo))
}

private func used(_ minutesAgo: Double?) -> Date? {
    minutesAgo.map { now.addingTimeInterval(-$0 * 60) }
}

private let desk: [Item] = [
    app("Google Chrome"), app("Code"), app("Slack"), app("Microsoft Teams"), app("Linear"),
    tab("Logs · shop-backend · Web Service - Render", site: "dashboard.render.com"),
    tab("Events · shop-backend - Render", site: "dashboard.render.com"),
    tab("ENG-29 Checkout redesign | Linear", site: "linear.app"),
    tab("Pull requests · acme/Shop-backend · GitHub", site: "github.com"),
    tab("Inbox (3) - Gmail", site: "mail.google.com"),
    window("relay.py — Shop-backend", app: "Code"),
    window("TakeFlow.tsx — shop-frontend", app: "Code"),
    window("scoring.py — pricing-engine", app: "Code"),
    window("Shop-backend — zsh", app: "Terminal"),
    file("phase-6-recording.md", folder: "~/Projects/checkout-plan"),
    file("phase-5-scoring.md", folder: "~/Projects/checkout-plan"),
    file("recording-consent.pdf", folder: "~/Documents"),
    clip("https://teams.microsoft.com/l/meetup-join/19%3ameeting", kind: "link", from: "Microsoft Teams", minutesAgo: 40),
    clip("https://dashboard.render.com/web/srv-123/logs", kind: "link", from: "Google Chrome", minutesAgo: 5),
    clip("uv run pytest tests/ -q", kind: "text", from: "Code", minutesAgo: 2),
]

private func ranked(_ said: String, in items: [Item] = desk) -> [Match] {
    rank(RuleParser(aliases: [:]).parse(said)!, in: items, now: now)
}

@Test func matcherExactTitleWins() {
    let matches = ranked("switch to Chrome")
    #expect(matches.first?.item.title == "Google Chrome")
    #expect(isClear(matches))

    let exact = ranked("open Render", in: [tab("Render"), tab("Logs · shop-backend - Render"), tab("Render pricing | Docs")])
    #expect(exact.first?.item.title == "Render")
}

@Test func matcherFindsTheRenderLogsTab() {
    let matches = ranked("the render logs tab")
    #expect(matches.first?.item.title == "Logs · shop-backend · Web Service - Render")
    #expect(isClear(matches))
}

@Test func matcherFindsTheVSCodeWindowForTheBackend() {
    let matches = ranked("the VS Code window for the backend")
    #expect(matches.first?.item.title == "relay.py — Shop-backend")
    #expect(matches.allSatisfy { $0.item.kind == .window })
    #expect(isClear(matches))
}

@Test func matcherFindsAFileByItsSpokenName() {
    let matches = ranked("phase six recording")
    #expect(matches.first?.item.title == "phase-6-recording.md")
    #expect(isClear(matches))
}

@Test func matcherFindsTheLinkCopiedFromTeams() {
    let matches = ranked("paste the link I copied from Teams")
    #expect(matches.first?.item.owner == "Microsoft Teams")
    #expect(matches.allSatisfy { $0.item.kind == .clip })
    #expect(isClear(matches))
}

@Test func matcherCreditsPartialWords() {
    #expect(ranked("be window").first?.item.title == "relay.py — Shop-backend")
    #expect(ranked("open the front window").first?.item.title == "TakeFlow.tsx — shop-frontend")
    #expect(ranked("scor file").first?.item.title == "phase-5-scoring.md")

    let whole = ranked("open logs", in: [tab("Logs"), tab("Logstash docs"), tab("Changelogs")]).map(\.item.title)
    #expect(whole == ["Logs", "Logstash docs", "Changelogs"])
}

@Test func matcherCreditsAbbreviationsNothingElseMatches() {
    let matches = ranked("open bknd", in: [window("Shop-backend — zsh", app: "Terminal"), tab("Inbox (3) - Gmail")])
    #expect(matches.map(\.item.title) == ["Shop-backend — zsh"])
    #expect(!isClear(matches))
}

@Test func matcherOwnerNarrows() {
    let both = ranked("shop backend")
    #expect(!isClear(both))

    let narrowed = ranked("shop backend in Terminal")
    #expect(narrowed.first?.item.title == "Shop-backend — zsh")
    #expect(isClear(narrowed))
}

@Test func matcherFoldsAnUnknownOwnerBackIntoTheDescription() {
    let matches = ranked("open sign in page", in: [tab("Sign in page - Acme"), tab("Sign up - Acme"), tab("Pricing page - Acme")])
    #expect(matches.first?.item.title == "Sign in page - Acme")
}

@Test func matcherFiltersByKind() {
    #expect(ranked("the linear tab").map(\.item.kind) == [.tab])
    #expect(ranked("the linear app").map(\.item.kind) == [.app])
    #expect(Set(ranked("linear").map(\.item.kind)) == [.tab, .app])
    #expect(ranked("close tab").count == desk.filter { $0.kind == .tab }.count)
}

@Test func matcherRecencyBreaksATie() {
    let older = tab("Inbox - Gmail", minutesAgo: 600)
    let newer = Item(id: "tab:second", kind: .tab, title: "Inbox - Gmail", owner: "Google Chrome", lastUsed: used(1))
    let never = Item(id: "tab:third", kind: .tab, title: "Inbox - Gmail", owner: "Google Chrome")
    #expect(ranked("gmail inbox", in: [older, never, newer]).map(\.item.id) == ["tab:second", "tab:Inbox - Gmail", "tab:third"])
}

@Test func matcherRecencyNeverOutranksABetterMatch() {
    let matches = ranked("render logs", in: [
        tab("Render pricing", minutesAgo: 0),
        tab("Logs · shop-backend - Render", minutesAgo: 6000),
    ])
    #expect(matches.first?.item.title == "Logs · shop-backend - Render")
}

@Test func matcherNearEqualItemsAreNotClear() {
    let matches = ranked("the render tab")
    #expect(matches.count >= 2)
    #expect(!isClear(matches))

    let twins = ranked("pull requests", in: [
        tab("Pull requests · acme/Shop-backend · GitHub"),
        tab("Pull requests · acme/shop-frontend · GitHub"),
    ])
    #expect(!isClear(twins))
}

@Test func matcherOneStrongItemIsClear() {
    #expect(isClear(ranked("open Slack")))
    #expect(isClear(ranked("the gmail tab")))
    #expect(isClear(ranked("takeflow")))
}

@Test func matcherWeakOrMissingMatchesAreNotClear() {
    #expect(ranked("open zebra crossing").isEmpty)
    #expect(!isClear([]))
    #expect(!isClear(ranked("open render zebra crossing")))
}

@Test func matcherScoresStayBetweenZeroAndOneBestFirst() {
    for said in ["chrome", "the render logs tab", "close tab", "paste from Teams", "checkout"] {
        let scores = ranked(said).map(\.score)
        #expect(scores.allSatisfy { $0 > 0 && $0 <= 1 })
        #expect(scores == scores.sorted(by: >))
    }
}

private func syntheticItems(_ count: Int) -> [Item] {
    let sites = ["Render", "Linear", "GitHub", "Gmail", "Google Docs", "Stack Overflow", "MDN Web Docs"]
    let subjects = ["Logs", "Events", "Pull requests", "Inbox", "Settings", "Deploys", "Metrics", "Billing"]
    let repos = ["Shop-backend", "shop-frontend", "pricing-engine", "hark", "docs-site"]
    let sources = ["relay.py", "TakeFlow.tsx", "scoring.py", "Matcher.swift", "index.md"]
    return (0..<count).map { index in
        let repo = repos[index % repos.count]
        switch index % 3 {
        case 0:
            let site = sites[index % sites.count]
            return Item(
                id: "tab:\(index)", kind: .tab, title: "\(subjects[index % subjects.count]) · \(repo) #\(index) - \(site)",
                detail: "\(site.lowercased()).com", owner: "Google Chrome", lastUsed: used(Double(index)))
        case 1:
            return Item(
                id: "window:\(index)", kind: .window, title: "\(sources[index % sources.count]) — \(repo)",
                owner: "Code", lastUsed: used(Double(index)))
        default:
            return Item(
                id: "file:\(index)", kind: .file, title: "phase-\(index)-recording.md",
                detail: "~/Projects/\(repo)/notes", owner: "Finder")
        }
    }
}

@Test func matcherRanksThreeThousandItemsQuickly() {
    let items = syntheticItems(3000)
    let parser = RuleParser(aliases: ["the backend": "Shop-backend"])
    let clock = ContinuousClock()
    for said in ["the render logs tab", "the VS Code window for the backend", "phase 6 recording"] {
        var fastest = Duration.seconds(1)
        var found = 0
        for _ in 0..<7 {
            let elapsed = clock.measure {
                found = rank(parser.parse(said)!, in: items, now: now).count
            }
            fastest = min(fastest, elapsed)
        }
        print("rank 3000 items for \"\(said)\": \(fastest) parse+rank, \(found) matches")
        #expect(found > 0)
        // A guard against the ranking becoming far slower, not a measurement: this is a debug
        // build timed while other tests and builds share the machine, where 4 ms has read as 7 and a
        // shared CI runner as 24.
        #expect(fastest < .milliseconds(60))
    }
}
