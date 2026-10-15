import Darwin
import Foundation

@main
enum UsageRingsCLIMain {
    static func main() async {
        let result = await UsageCLI.run(arguments: Array(CommandLine.arguments.dropFirst()))
        print(result.output)
        exit(result.exitCode)
    }
}
