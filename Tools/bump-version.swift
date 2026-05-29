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
    
    // Update MARKETING_VERSION if 'patch' is requested
    if isPatch && line.contains("MARKETING_VERSION:") {
        let pattern = #":\s*"(.*)""#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)) {
            
            let nsLine = line as NSString
            let versionRange = match.range(at: 1)
            let currentVersion = nsLine.substring(with: versionRange)
            
            var components = currentVersion.components(separatedBy: ".")
            if components.count >= 3 {
                if let patch = Int(components[2]) {
                    components[2] = "\(patch + 1)"
                    let newVersion = components.joined(separator: ".")
                    updatedLine = line.replacingOccurrences(of: "\"\(currentVersion)\"", with: "\"\(newVersion)\"")
                    print("Bumping Marketing Version: \(currentVersion) -> \(newVersion)")
                }
            } else if components.count == 2 {
                // Handle 0.4 -> 0.4.1
                components.append("1")
                let newVersion = components.joined(separator: ".")
                updatedLine = line.replacingOccurrences(of: "\"\(currentVersion)\"", with: "\"\(newVersion)\"")
                print("Bumping Marketing Version: \(currentVersion) -> \(newVersion)")
            }
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
