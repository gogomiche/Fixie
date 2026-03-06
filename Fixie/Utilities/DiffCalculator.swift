import Foundation
import SwiftUI

enum DiffType {
    case unchanged
    case added
    case removed
}

struct DiffSegment: Identifiable {
    let id = UUID()
    let text: String
    let type: DiffType
}

class DiffCalculator {
    /// Normalize line endings and trim trailing whitespace per line
    static func normalizeLineEndings(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { line in
                var s = line
                while s.hasSuffix(" ") || s.hasSuffix("\t") {
                    s = String(s.dropLast())
                }
                return s
            }
            .joined(separator: "\n")
    }

    /// Calculates word-level diff between original and corrected text
    static func calculateDiff(original: String, corrected: String) -> [DiffSegment] {
        let normalizedOriginal = normalizeLineEndings(original)
        let normalizedCorrected = normalizeLineEndings(corrected)

        let originalWords = tokenize(normalizedOriginal)
        let correctedWords = tokenize(normalizedCorrected)
        let lcs = longestCommonSubsequence(originalWords, correctedWords)

        var result: [DiffSegment] = []

        var origIndex = 0
        var corrIndex = 0
        var lcsIndex = 0

        while origIndex < originalWords.count || corrIndex < correctedWords.count {
            if lcsIndex < lcs.count {
                // Add removed words (in original but not in LCS)
                while origIndex < originalWords.count && originalWords[origIndex] != lcs[lcsIndex] {
                    result.append(DiffSegment(text: originalWords[origIndex], type: .removed))
                    origIndex += 1
                }

                // Add added words (in corrected but not in LCS)
                while corrIndex < correctedWords.count && correctedWords[corrIndex] != lcs[lcsIndex] {
                    result.append(DiffSegment(text: correctedWords[corrIndex], type: .added))
                    corrIndex += 1
                }

                // Add unchanged word (in LCS)
                if lcsIndex < lcs.count {
                    result.append(DiffSegment(text: lcs[lcsIndex], type: .unchanged))
                    origIndex += 1
                    corrIndex += 1
                    lcsIndex += 1
                }
            } else {
                // Add remaining removed words
                while origIndex < originalWords.count {
                    result.append(DiffSegment(text: originalWords[origIndex], type: .removed))
                    origIndex += 1
                }

                // Add remaining added words
                while corrIndex < correctedWords.count {
                    result.append(DiffSegment(text: correctedWords[corrIndex], type: .added))
                    corrIndex += 1
                }
            }
        }

        return mergeAdjacentSegments(result)
    }

    /// Tokenize text into words while preserving whitespace
    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var currentToken = ""

        for char in text {
            if char.isWhitespace {
                if !currentToken.isEmpty {
                    tokens.append(currentToken)
                    currentToken = ""
                }
                tokens.append(String(char))
            } else {
                currentToken.append(char)
            }
        }

        if !currentToken.isEmpty {
            tokens.append(currentToken)
        }

        return tokens
    }

    /// Calculate LCS using dynamic programming
    private static func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        let m = a.count
        let n = b.count

        // Handle empty arrays - prevents invalid range 1...0
        guard m > 0 && n > 0 else { return [] }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 1...m {
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to find LCS
        var lcs: [String] = []
        var i = m, j = n

        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] {
                lcs.insert(a[i - 1], at: 0)
                i -= 1
                j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        return lcs
    }

    /// Merge adjacent segments of the same type
    private static func mergeAdjacentSegments(_ segments: [DiffSegment]) -> [DiffSegment] {
        guard !segments.isEmpty else { return [] }

        var merged: [DiffSegment] = []
        var currentText = segments[0].text
        var currentType = segments[0].type

        for i in 1..<segments.count {
            if segments[i].type == currentType {
                currentText += segments[i].text
            } else {
                merged.append(DiffSegment(text: currentText, type: currentType))
                currentText = segments[i].text
                currentType = segments[i].type
            }
        }

        merged.append(DiffSegment(text: currentText, type: currentType))
        return merged
    }

    /// Check if there are any actual changes
    static func hasChanges(original: String, corrected: String) -> Bool {
        return normalizeLineEndings(original) != normalizeLineEndings(corrected)
    }
}
