//
//  SecureEndpointURL.swift
//  StudyPulse
//
//  Shared endpoint validation for authentication and LLM traffic.
//

import Foundation

/// Normalizes a configured endpoint and enforces HTTPS before any request is built.
/// A missing scheme is intentionally treated as an HTTPS hostname for backwards
/// compatibility with existing settings such as `spapi.chenkai.space`.
nonisolated enum SecureEndpointURL {
    enum ValidationError: Error, Equatable {
        case invalid
        case insecureScheme
        case missingHost
    }

    static func make(base: String, appending path: String? = nil) throws -> URL {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.invalid }

        let candidate: String
        if hasScheme(trimmed) {
            candidate = trimmed
        } else {
            candidate = "https://\(trimmed)"
        }

        guard let components = URLComponents(string: candidate) else {
            throw ValidationError.invalid
        }
        guard components.scheme?.lowercased() == "https" else {
            if components.scheme?.lowercased() == "http" {
                throw ValidationError.insecureScheme
            }
            throw ValidationError.invalid
        }
        guard let host = components.host, !host.isEmpty else {
            throw ValidationError.missingHost
        }
        // Credentials embedded in an endpoint URL could be logged or copied
        // accidentally. API keys and session tokens belong in Keychain/headers.
        guard components.user == nil, components.password == nil else {
            throw ValidationError.invalid
        }

        var url = components.url
        if let path {
            let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !normalizedPath.isEmpty {
                url = url?.appendingPathComponent(normalizedPath)
            }
        }
        guard let url else { throw ValidationError.invalid }
        return url
    }

    private static func hasScheme(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*://"#, options: .regularExpression) != nil
    }
}
