//
//  NetworkManager.swift
//  PTrack
//
//  Created by Codex on 2026/6/15.
//

import Foundation

enum NetworkHTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

enum NetworkParameterEncoding {
    case query
    case formURLEncoded
    case json
}

enum NetworkParameterValue: Encodable, CustomStringConvertible, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
    case string(String)
    case int(Int)
    case int64(Int64)
    case double(Double)
    case bool(Bool)
    case stringArray([String])

    init(stringLiteral value: String) {
        self = .string(value)
    }

    init(integerLiteral value: Int) {
        self = .int(value)
    }

    init(floatLiteral value: Double) {
        self = .double(value)
    }

    init(booleanLiteral value: Bool) {
        self = .bool(value)
    }

    var description: String {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return "\(value)"
        case .int64(let value):
            return "\(value)"
        case .double(let value):
            return "\(value)"
        case .bool(let value):
            return value ? "true" : "false"
        case .stringArray(let values):
            return values.joined(separator: ",")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .int64(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .stringArray(let values):
            try container.encode(values)
        }
    }
}

struct NetworkEndpoint {
    let url: URL
    let method: NetworkHTTPMethod
    var parameters: [String: NetworkParameterValue?]
    var parameterEncoding: NetworkParameterEncoding
    var headers: [String: String]
    var timeoutInterval: TimeInterval?

    init(
        url: URL,
        method: NetworkHTTPMethod,
        parameters: [String: NetworkParameterValue?] = [:],
        parameterEncoding: NetworkParameterEncoding? = nil,
        headers: [String: String] = [:],
        timeoutInterval: TimeInterval? = nil
    ) {
        self.url = url
        self.method = method
        self.parameters = parameters
        self.parameterEncoding = parameterEncoding ?? Self.defaultEncoding(for: method)
        self.headers = headers
        self.timeoutInterval = timeoutInterval
    }

    init(
        urlString: String,
        method: NetworkHTTPMethod,
        parameters: [String: NetworkParameterValue?] = [:],
        parameterEncoding: NetworkParameterEncoding? = nil,
        headers: [String: String] = [:],
        timeoutInterval: TimeInterval? = nil
    ) throws {
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL(urlString)
        }

        self.init(
            url: url,
            method: method,
            parameters: parameters,
            parameterEncoding: parameterEncoding,
            headers: headers,
            timeoutInterval: timeoutInterval
        )
    }

    private static func defaultEncoding(for method: NetworkHTTPMethod) -> NetworkParameterEncoding {
        switch method {
        case .get, .delete:
            return .query
        case .post, .put, .patch:
            return .json
        }
    }
}

struct EmptyNetworkResponse: Decodable {}

struct NetworkResponse<Response> {
    let value: Response
    let statusCode: Int
    let headers: [AnyHashable: Any]
    let data: Data
}

final class NetworkManager {
    static let shared = NetworkManager()

    private let session: URLSession
    private let defaultDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder

    init(
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        jsonEncoder: JSONEncoder = JSONEncoder()
    ) {
        self.session = session
        defaultDecoder = decoder
        self.jsonEncoder = jsonEncoder
    }

    func request<Response: Decodable>(
        _ endpoint: NetworkEndpoint,
        responseType: Response.Type = Response.self,
        decoder customDecoder: JSONDecoder? = nil
    ) async throws -> Response {
        try await response(endpoint, responseType: responseType, decoder: customDecoder).value
    }

    func response<Response: Decodable>(
        _ endpoint: NetworkEndpoint,
        responseType: Response.Type = Response.self,
        decoder customDecoder: JSONDecoder? = nil
    ) async throws -> NetworkResponse<Response> {
        let request = try makeURLRequest(endpoint)
        let (data, response): (Data, URLResponse)

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NetworkError.transportFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NetworkError.httpStatus(
                code: httpResponse.statusCode,
                message: decodedErrorMessage(from: data),
                data: data
            )
        }

        let value = try decode(
            Response.self,
            from: data,
            statusCode: httpResponse.statusCode,
            decoder: customDecoder ?? defaultDecoder
        )

        return NetworkResponse(
            value: value,
            statusCode: httpResponse.statusCode,
            headers: httpResponse.allHeaderFields,
            data: data
        )
    }

    func data(_ endpoint: NetworkEndpoint) async throws -> NetworkResponse<Data> {
        let request = try makeURLRequest(endpoint)
        let (data, response): (Data, URLResponse)

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NetworkError.transportFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NetworkError.httpStatus(
                code: httpResponse.statusCode,
                message: decodedErrorMessage(from: data),
                data: data
            )
        }

        return NetworkResponse(
            value: data,
            statusCode: httpResponse.statusCode,
            headers: httpResponse.allHeaderFields,
            data: data
        )
    }

    private func makeURLRequest(_ endpoint: NetworkEndpoint) throws -> URLRequest {
        var requestURL = endpoint.url
        let parameters = endpoint.parameters.compactMapValues { $0 }

        if endpoint.parameterEncoding == .query, !parameters.isEmpty {
            guard var components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) else {
                throw NetworkError.invalidURL(requestURL.absoluteString)
            }

            let existingItems = components.queryItems ?? []
            let newItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value.description) }
            components.queryItems = existingItems + newItems

            guard let url = components.url else {
                throw NetworkError.invalidURL(requestURL.absoluteString)
            }

            requestURL = url
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = endpoint.method.rawValue
        if let timeoutInterval = endpoint.timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }

        for (field, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        switch endpoint.parameterEncoding {
        case .query:
            break
        case .formURLEncoded:
            request.setValueIfMissing("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = formEncodedBody(parameters)
        case .json:
            request.setValueIfMissing("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try jsonEncoder.encode(parameters)
        }

        return request
    }

    private func decode<Response: Decodable>(
        _ responseType: Response.Type,
        from data: Data,
        statusCode: Int,
        decoder: JSONDecoder
    ) throws -> Response {
        if responseType == EmptyNetworkResponse.self, data.isEmpty {
            return EmptyNetworkResponse() as! Response
        }

        do {
            return try decoder.decode(responseType, from: data)
        } catch {
            throw NetworkError.decodingFailed(
                underlying: error,
                statusCode: statusCode,
                data: data
            )
        }
    }

    private func formEncodedBody(_ parameters: [String: NetworkParameterValue]) -> Data? {
        var components = URLComponents()
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value.description) }
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    private func decodedErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else {
            return nil
        }

        if let errorResponse = try? defaultDecoder.decode(NetworkErrorResponse.self, from: data) {
            let detailMessage = errorResponse.errors?
                .compactMap(\.message)
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return [errorResponse.message, errorResponse.error, detailMessage]
                .compactMap { $0 }
                .first { !$0.isEmpty }
        }

        return String(data: data, encoding: .utf8)
    }
}

enum NetworkError: LocalizedError {
    case decodingFailed(underlying: Error, statusCode: Int, data: Data)
    case httpStatus(code: Int, message: String?, data: Data)
    case invalidResponse
    case invalidURL(String)
    case transportFailed(Error)

    var errorDescription: String? {
        switch self {
        case .decodingFailed(let underlying, let statusCode, let data):
            return "Failed to decode response (\(statusCode)): \(underlying.localizedDescription). \(Self.preview(data))"
        case .httpStatus(let code, let message, let data):
            return message ?? "Request failed with HTTP \(code). \(Self.preview(data))"
        case .invalidResponse:
            return "The server returned an invalid response."
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .transportFailed(let error):
            return error.localizedDescription
        }
    }

    var statusCode: Int? {
        switch self {
        case .httpStatus(let code, _, _), .decodingFailed(_, let code, _):
            return code
        case .invalidResponse, .invalidURL, .transportFailed:
            return nil
        }
    }

    private static func preview(_ data: Data) -> String {
        guard !data.isEmpty,
              let string = String(data: data.prefix(280), encoding: .utf8),
              !string.isEmpty else {
            return ""
        }

        return "Body: \(string)"
    }
}

private struct NetworkErrorResponse: Decodable {
    let message: String?
    let error: String?
    let errors: [NetworkErrorDetail]?
}

private struct NetworkErrorDetail: Decodable {
    let message: String?
}

private extension URLRequest {
    mutating func setValueIfMissing(_ value: String, forHTTPHeaderField field: String) {
        if self.value(forHTTPHeaderField: field) == nil {
            setValue(value, forHTTPHeaderField: field)
        }
    }
}
