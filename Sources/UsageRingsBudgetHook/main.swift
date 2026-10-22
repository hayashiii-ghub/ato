import Darwin
import Foundation
import UsageCore

// Invalid input, missing usage, and locked state must never fail or suspend an agent's work.
signal(SIGPIPE, SIG_IGN)
var output = Data("{}".utf8)
if let options = AgentBudgetHookOptions.parse(arguments: Array(CommandLine.arguments.dropFirst())),
   let payload = AgentBudgetHook.readStandardInput() {
    output = AgentBudgetHook.run(options: options, payload: payload)
}
output.append(0x0A)
try? FileHandle.standardOutput.write(contentsOf: output)
exit(0)
