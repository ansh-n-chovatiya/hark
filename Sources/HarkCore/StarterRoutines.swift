/// Ready-made routines for a developer's day, offered in the settings window so nobody has to
/// start from an empty list. Each is plain shell the user can read and change.
public enum StarterRoutines {
    public static let all: [Routine] = [
        Routine(name: "branches", steps: [Step(shell: "git -C {repo} branch --show-current")]),
        Routine(name: "changes", steps: [Step(shell: "git -C {repo} status --short | wc -l | tr -d ' '")]),
        Routine(name: "commits today", steps: [
            Step(shell: "git -C {repo} log --since=midnight --oneline | wc -l | tr -d ' '"),
        ]),
        Routine(name: "pull all", steps: [Step(shell: "git -C {repo} pull --ff-only", destructive: true, timeout: 120)]),
        Routine(name: "is it up", steps: [
            Step(shell: #"curl -s -o /dev/null -m 3 -w "%{http_code}" http://localhost:{arg} || true"#),
        ]),
        Routine(name: "what is on port", steps: [
            Step(shell: "lsof -nP -iTCP:{arg} -sTCP:LISTEN | awk 'NR==2 {print $1}' | grep . || echo nothing"),
        ]),
        Routine(name: "stop port", steps: [Step(shell: "lsof -ti :{arg} | xargs kill", destructive: true)]),
        Routine(name: "containers", steps: [
            Step(shell: #"docker ps --format '{{.Names}}' | tr '\n' ' ' | grep . || echo none running"#),
        ]),
        Routine(name: "my reviews", steps: [
            Step(shell: "gh search prs --review-requested=@me --state=open --json title --jq length"),
        ]),
        Routine(name: "my pull requests", steps: [
            Step(shell: "gh search prs --author=@me --state=open --json title --jq length"),
        ]),
        Routine(name: "build status", steps: [
            Step(shell: #"cd {repo} && gh run list --limit 1 --json conclusion,status --jq '.[0] | (.conclusion // .status)'"#),
        ]),
        Routine(name: "ask claude", steps: [Step(shell: "claude -p {arg}", destructive: true, timeout: 600)]),
    ]

    /// The starter routines the user does not already have, by name.
    public static func missing(from routines: [Routine]) -> [Routine] {
        let have = Set(routines.map { $0.name.lowercased() })
        return all.filter { !have.contains($0.name.lowercased()) }
    }
}
