#if DEBUG
import Foundation
import Network

/// A single-request HTTP transport for the USB-forwarded debug interface.
/// DEBUG-only and USB loopback only; never expose this unauthenticated listener to LAN.
@MainActor
final class DebugHTTPServer {
    typealias Handler = @MainActor (String, String, Data) async -> (Int, Data)

    private final class Client {
        let connection: NWConnection
        var bytes = Data()
        var responding = false
        var timeout: Task<Void, Never>?
        var request: Task<Void, Never>?

        init(_ connection: NWConnection) { self.connection = connection }
    }

    private let handler: Handler
    var onStateChange: (@MainActor (Bool, String) -> Void)?
    private var listener: NWListener?
    private var clients: [UUID: Client] = [:]
    private let maximumBody = 64 * 1024
    private let maximumHeaders = 16 * 1024

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func start() throws {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: 18765)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            MainActor.assumeIsolated {
                guard let self, let listener, self.listener === listener else { return }
                switch state {
                case .ready:
                    self.onStateChange?(true, "USB: 127.0.0.1:18765")
                case .failed(let error):
                    self.stop()
                    self.onStateChange?(false, "监听失败：\(error.localizedDescription)")
                default:
                    break
                }
            }
        }
        self.listener = listener
        listener.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for id in Array(clients.keys) { close(id) }
    }

    private func accept(_ connection: NWConnection) {
        guard clients.count < 8, listener != nil else {
            connection.cancel()
            return
        }
        let id = UUID()
        let client = Client(connection)
        clients[id] = client
        client.timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            self?.close(id)
        }
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .failed, .cancelled: self?.close(id)
                default: break
                }
            }
        }
        connection.start(queue: .main)
        receive(id)
    }

    private func receive(_ id: UUID) {
        guard let client = clients[id], !client.responding else { return }
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
            [weak self] data, _, complete, error in
            MainActor.assumeIsolated {
                guard let self, let client = self.clients[id] else { return }
                if let data { client.bytes.append(data) }
                if error != nil { self.close(id); return }
                if self.consume(id) { return }
                if complete { self.close(id) } else { self.receive(id) }
            }
        }
    }

    /// Returns true when a response has begun; incomplete requests remain buffered.
    private func consume(_ id: UUID) -> Bool {
        guard let client = clients[id] else { return true }
        func reject(_ status: Int) -> Bool {
            respond(id, status: status, body: Data("{\"error\":\"request rejected\"}".utf8))
            return true
        }
        guard client.bytes.count <= maximumHeaders + maximumBody else { return reject(413) }
        guard let end = client.bytes.range(of: Data("\r\n\r\n".utf8)) else {
            return client.bytes.count > maximumHeaders ? reject(431) : false
        }
        guard end.upperBound <= maximumHeaders,
              let header = String(data: client.bytes[..<end.lowerBound], encoding: .utf8)
        else { return reject(400) }
        let lines = header.components(separatedBy: "\r\n")
        let requestLine = lines[0].components(separatedBy: " ")
        guard requestLine.count == 3, requestLine[2] == "HTTP/1.1" else { return reject(400) }
        let method = requestLine[0]
        guard method == "GET" || method == "POST" else { return reject(405) }
        let path = requestLine[1]
        guard path.hasPrefix("/"), !path.contains("#"),
              path.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { return reject(400) }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return reject(400) }
            let name = String(line[..<colon]).lowercased()
            let tokenCharacters = "!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyz"
            guard !name.isEmpty, name.allSatisfy({ tokenCharacters.contains($0) }),
                  headers[name] == nil else { return reject(400) }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard value.utf8.allSatisfy({ $0 >= 32 && $0 != 127 }) else { return reject(400) }
            headers[name] = value
        }
        guard headers["transfer-encoding"] == nil, headers["expect"] == nil,
              let host = headers["host"], !host.isEmpty else { return reject(400) }
        let length: Int
        if let raw = headers["content-length"] {
            guard !raw.isEmpty, raw.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                  let parsed = Int(raw) else { return reject(400) }
            length = parsed
        } else {
            guard method == "GET" else { return reject(411) }
            length = 0
        }
        guard length <= maximumBody else { return reject(413) }
        guard method != "GET" || length == 0 else { return reject(400) }
        let expected = end.upperBound + length
        guard client.bytes.count >= expected else { return false }
        guard client.bytes.count == expected else { return reject(400) }
        let body = Data(client.bytes[end.upperBound..<expected])
        client.responding = true
        client.request = Task { [weak self] in
            guard let self else { return }
            let (status, result) = await self.handler(method, path, body)
            guard !Task.isCancelled, self.clients[id] != nil else { return }
            self.respond(id, status: status, body: result)
        }
        return true
    }

    private func respond(_ id: UUID, status: Int, body: Data) {
        guard let client = clients[id] else { return }
        client.responding = true
        let code = (100...599).contains(status) ? status : 500
        let reasons = [200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized",
                       404: "Not Found", 405: "Method Not Allowed", 409: "Conflict",
                       411: "Length Required", 413: "Content Too Large",
                       431: "Request Header Fields Too Large", 500: "Internal Server Error"]
        let header = "HTTP/1.1 \(code) \(reasons[code] ?? "Response")\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        client.connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            MainActor.assumeIsolated { self?.close(id) }
        })
    }

    private func close(_ id: UUID) {
        guard let client = clients.removeValue(forKey: id) else { return }
        client.timeout?.cancel()
        client.request?.cancel()
        client.connection.cancel()
    }
}
#endif
