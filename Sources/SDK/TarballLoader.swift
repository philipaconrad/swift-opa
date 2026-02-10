import ContainerizationArchive
import Foundation
import Rego

// TarballLoader returns a sequence of OPA bundle files from a gzipped tarball,
// while filtering out non-bundle-related files and enforcing size limits.
// I/O errors are propagated as failure cases of the results.
public struct TarballLoader: Sequence {
    let tarballURL: URL
    let maxFileSize: Int
    let keepFiles = Set(["data.json", "plan.json", ".manifest"])
    let keepExtensions = Set(["rego"])

    public init(fileURL: URL, maxFileSize: Int = 10 * 1024 * 1024) {  // 10MB default
        self.tarballURL = fileURL
        self.maxFileSize = maxFileSize
    }

    public func makeIterator() -> AnyIterator<Result<Rego.BundleFile, any Swift.Error>> {
        let reader: ArchiveReader
        do {
            reader = try ArchiveReader(file: tarballURL)
        } catch {
            // Return an iterator that yields the error once, then nil
            var errorReturned = false
            return AnyIterator {
                if !errorReturned {
                    errorReturned = true
                    return .failure(error)
                }
                return nil
            }
        }

        var archiveIterator = reader.makeStreamingIterator()

        return AnyIterator<Result<Rego.BundleFile, any Swift.Error>> {
            () -> Result<Rego.BundleFile, any Swift.Error>? in
            // This closure gets called each time next() is called on the iterator
            // We need to find the next valid entry and return it
            while let (entry, entryReader) = archiveIterator.next() {
                // Skip directories
                guard entry.fileType != .directory else {
                    continue
                }

                let filename = String(entry.path ?? "")
                let pathURL = URL(fileURLWithPath: filename)
                let lastComponent = pathURL.lastPathComponent
                let pathExtension = pathURL.pathExtension

                // Apply the same filtering logic as DirectoryLoader
                let shouldKeep =
                    self.keepFiles.contains(lastComponent) || self.keepExtensions.contains(pathExtension)

                guard shouldKeep else {
                    continue
                }

                // Check file size against the limit
                let fileSize = Int(entry.size ?? 0)
                guard fileSize <= self.maxFileSize else {
                    return .failure(TarballError.fileSizeExceeded(filename, fileSize, self.maxFileSize))
                }

                // Extract the file data.
                // This requires a read loop until EOF (0), or an error occurs (-1).
                let bufferSize = Int(Swift.min(fileSize, 4096))
                var result = Data()
                var part = Data(count: bufferSize)
                while true {
                    // c will always be one of three possibilities: number of bytes read, 0 on EOF, or -1 on error.
                    let c: Int = part.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> Int in
                        let typedPtr = ptr.bindMemory(to: UInt8.self)
                        return entryReader.read(typedPtr.baseAddress!, maxLength: bufferSize)
                    }
                    guard c > 0 else { break }
                    part.count = c
                    result.append(part)
                }
                let bundleFile = BundleFile(url: pathURL, data: result)
                return .success(bundleFile)

            }

            // No more entries
            return nil
        }
    }
}

public enum TarballError: Swift.Error, LocalizedError {
    case initializationError(Swift.Error)
    case fileSizeExceeded(String, Int, Int)  // filename, actual size, max size
    case fileExtractionError(String, Swift.Error)  // filename, underlying error
    case decompressionError(Swift.Error)

    public var errorDescription: String? {
        switch self {
        case .initializationError(let error):
            return "Failed to initialize tarball loader: \(error.localizedDescription)"
        case .fileSizeExceeded(let filename, let actualSize, let maxSize):
            return "File '\(filename)' size (\(actualSize) bytes) exceeds maximum allowed size (\(maxSize) bytes)"
        case .fileExtractionError(let filename, let error):
            return "Failed to extract file '\(filename)': \(error.localizedDescription)"
        case .decompressionError(let error):
            return "Failed to decompress gzipped tarball: \(error.localizedDescription)"
        }
    }
}

extension Rego.BundleLoader {
    public static func load(fromTarball url: URL) throws -> OPA.Bundle {
        let files = TarballLoader(fileURL: url)
        return try BundleLoader(fromFileSequence: files).load()
    }
}
