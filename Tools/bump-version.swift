import Foundation

// MARK: - Helper Functions

func shell(_ command: String) -> String {
    let task = Process()
    let pipe = Pipe()
    
    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.launchPath = "/bin/bash"
    task.launch()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
}

func getGitCommitCount() -> Int {
    let countString = shell("git rev-list --count HEAD")
    return Int(countString) ?? 0
}

// MARK: - Main Logic

let arguments = CommandLine.arguments
let isPatch = arguments.contains("patch")
let isMinor = arguments.contains("minor")
let isMajor = arguments.contains("major")
let isPreCommit = arguments.contains("pre-commit")

let projectFilePath = "project.yml"
guard let content = try? String(contentsOfFile: projectFilePath, encoding: .utf8) else {
    print("Error: Could not read project.yml")
    exit(1)
}

var lines = content.components(separatedBy: .newlines)
var updatedLines = [String]()

// Get current commit count. 
// If it's a pre-commit hook, the commit hasn't happened yet, so we add 1.
let commitCount = getGitCommitCount()
let newBuildNumber = isPreCommit ? commitCount + 1 : commitCount

print("Updating build number to: \(newBuildNumber)")

for line in lines {
    var updatedLine = line
    
    // Update CURRENT_PROJECT_VERSION
    if line.contains("CURRENT_PROJECT_VERSION:") {
        updatedLine = line.replacingOccurrences(of: #":\s*".*"#, with: ": \"\(newBuildNumber)\"", options: .regularExpression)
    }
    
    // Update MARKETING_VERSION if patch/minor/major is requested
    if (isPatch || isMinor || isMajor) && line.contains("MARKETING_VERSION:") {
        let pattern = #":\s*"(.*)""#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)) {

            let nsLine = line as NSString
            let currentVersion = nsLine.substring(with: match.range(at: 1))

            // Normalize to major.minor.patch (0.4 -> 0.4.0)
            var parts = currentVersion.components(separatedBy: ".").compactMap { Int($0) }
            while parts.count < 3 { parts.append(0) }

            if isMajor {
                parts = [parts[0] + 1, 0, 0]
            } else if isMinor {
                parts = [parts[0], parts[1] + 1, 0]
            } else {
                parts[2] += 1
            }
            let newVersion = parts.prefix(3).map(String.init).joined(separator: ".")
            updatedLine = line.replacingOccurrences(of: "\"\(currentVersion)\"", with: "\"\(newVersion)\"")
            print("Bumping Marketing Version: \(currentVersion) -> \(newVersion)")
        }
    }

    updatedLines.append(updatedLine)
}

let updatedContent = updatedLines.joined(separator: "\n")
try? updatedContent.write(toFile: projectFilePath, atomically: true, encoding: .utf8)

// Run xcodegen
print("Running xcodegen generate...")
let xcodegenOutput = shell("xcodegen generate")
print(xcodegenOutput)
