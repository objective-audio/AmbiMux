import AVFoundation
import CoreAudioTypes
import Foundation

// Generate unique filename in specified directory with given filename
nonisolated func generateUniqueFileName(
    directory: String, fileName: String, extension fileExtension: String
) -> String {
    let directoryURL = URL(fileURLWithPath: directory)

    var counter = 1
    var newFileName = "\(fileName).\(fileExtension)"
    var newPath = directoryURL.appendingPathComponent(newFileName).path

    while FileManager.default.fileExists(atPath: newPath) {
        newFileName = "\(fileName)_\(counter).\(fileExtension)"
        newPath = directoryURL.appendingPathComponent(newFileName).path
        counter += 1
    }

    return newPath
}

// Generate output file path
nonisolated func generateOutputPath(outputPath: String?, videoPath: String) -> String {
    let sourcePath = outputPath ?? videoPath
    let url = URL(fileURLWithPath: sourcePath)

    let directory = url.deletingLastPathComponent().path
    let fileName = url.deletingPathExtension().lastPathComponent
    let fileExtension = "mov"  // Always output in MOV format

    return generateUniqueFileName(
        directory: directory, fileName: fileName, extension: fileExtension)
}
