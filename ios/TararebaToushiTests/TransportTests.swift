import Foundation
import Testing

@testable import TararebaToushi

nonisolated final class FixtureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        if url.path == "/timeout" {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        let status = url.path == "/missing" ? 404 : url.path == "/server" ? 500 : url.path == "/redirect" ? 302 : 200
        let contentType = url.path == "/html" ? "text/html" : "application/json"
        var headers = ["Content-Type": contentType]
        if url.path == "/redirect" { headers["Location"] = "https://other.example/" }
        if url.path == "/oversize" { headers["Content-Length"] = "3000000" }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if url.path == "/stream" {
            client?.urlProtocol(self, didLoad: Data(repeating: 32, count: AppConfiguration.maximumResponseBytes + 1))
        } else {
            client?.urlProtocol(self, didLoad: Data("{\"ok\":true}".utf8))
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct TransportTests {
    @Test(arguments: ["ok", "missing", "server", "html", "oversize", "stream", "timeout", "redirect"])
    func checksHTTPBeforeJSON(path: String) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let transport = URLSessionTransport(configuration: configuration)
        let url = try #require(URL(string: "https://fixture.example/\(path)"))
        if path == "ok" {
            #expect(try await transport.fetch(url) == Data("{\"ok\":true}".utf8))
        } else {
            await #expect(throws: (any Error).self) { try await transport.fetch(url) }
        }
    }

    @Test func httpIsNotAllowed() async throws {
        let url = try #require(URL(string: "http://fixture.example/"))
        await #expect(throws: DataIssue.self) { try await URLSessionTransport().fetch(url) }
    }
}
