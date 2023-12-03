import Foundation


/// State for a watched file.
///
enum FileState: @unchecked Sendable { // unchecked: 'Data' should be Sendable
    case data(Data)
    case fileTooLarge
    case noReadableFile
    case fileReadError(Error)
}


extension FileState: Equatable {
    /// Equatable conformance
    ///
    /// Equal in case data or state is equal.
    /// Note: Two fileReadError values are considered equal regardless of the error they carry.
    ///
    static func ==(left: Self, right: Self) -> Bool {
        switch (left, right) {
        case (.data(let leftData), .data(let rightData))    : return leftData == rightData
        case (.fileTooLarge, .fileTooLarge)                 : return true
        case (.noReadableFile, .noReadableFile)             : return true
        case (.fileReadError, .fileReadError)               : return true

        default                                             : return false
        }
    }
}
