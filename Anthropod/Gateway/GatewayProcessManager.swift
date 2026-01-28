import Foundation
import Network
import Observation

@MainActor
@Observable
final class GatewayProcessManager {
    static let shared = GatewayProcessManager()

    enum Status: Equatable {
        case stopped
        case starting
        case running(details: String?)
        case failed(String)

        var label: String {
            switch self {
            case .stopped: return "Stopped"
            case .starting: return "Starting…"
            case let .running(details):
                if let details, !details.isEmpty { return "Running (\(details))" }
                return "Running"
            case let .failed(reason): return "Failed: \(reason)"
            }
        }
    }

    private(set) var status: Status = .stopped
    private(set) var lastCommandDescription: String?
    private(set) var lastStartError: String?
    private(set) var lastProbe: String?
    private(set) var lastReadyError: String?
    private var process: Process?
    private var desiredActive = false
    private var preferredPort: Int?

    private init() {}

    func setActive(_ active: Bool) {
        desiredActive = active
        if !active {
            lastStartError = nil
            lastReadyError = nil
        }
        if active {
            startIfNeeded()
        } else {
            stop()
        }
    }

    func ensureGatewayRunning(endpoint: GatewayEndpoint, timeout: TimeInterval = 6) async -> Bool {
        guard shouldAutoStart(endpoint: endpoint) else { return true }

        preferredPort = endpoint.url.port
        let initialProbe = await PortProbe.isListening(host: endpoint.url.host, port: endpoint.url.port)
        lastProbe = Self.describeProbe(endpoint: endpoint, ok: initialProbe)
        if initialProbe {
            self.status = .running(details: "existing listener")
            return true
        }

        setActive(true)
        return await waitForGatewayReady(endpoint: endpoint, timeout: timeout)
    }

    private func startIfNeeded() {
        guard desiredActive else { return }
        guard process == nil else { return }

        status = .starting
        Task { [weak self] in
            await self?.startProcessIfConfigured()
        }
    }

    private func stop() {
        desiredActive = false
        process?.terminate()
        process = nil
        status = .stopped
    }

    private func startProcessIfConfigured() async {
        let port = preferredPort
            ?? Int(ProcessInfo.processInfo.environment["CLAWDBOT_GATEWAY_PORT"] ?? "")
            ?? 18789
        guard let command = GatewayCommandResolver.resolveGatewayCommand(port: port) else {
            status = .failed("Gateway command not configured")
            lastCommandDescription = nil
            lastStartError = "Gateway command not configured"
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments

        if let cwd = command.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        process.environment = command.environment
        lastCommandDescription = Self.describeCommand(command)
        lastStartError = nil

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            if proc.terminationStatus != 0 {
                let reason = "Gateway exited (\(proc.terminationStatus))"
                Task { @MainActor in
                    self.status = .failed(reason)
                }
            }
        }

        do {
            try process.run()
            self.process = process
            status = .running(details: "spawned")
        } catch {
            lastStartError = error.localizedDescription
            status = .failed("Failed to start gateway: \(error.localizedDescription)")
        }
    }

    private func waitForGatewayReady(endpoint: GatewayEndpoint, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let ready = await PortProbe.isListening(host: endpoint.url.host, port: endpoint.url.port)
            lastProbe = Self.describeProbe(endpoint: endpoint, ok: ready)
            if ready {
                status = .running(details: "ready")
                lastReadyError = nil
                return true
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        status = .failed("Gateway did not become ready")
        lastReadyError = "Gateway did not become ready"
        return false
    }

    private func shouldAutoStart(endpoint: GatewayEndpoint) -> Bool {
        let autoStart = ProcessInfo.processInfo.environment["ANTHROPOD_GATEWAY_AUTO_START"]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if let autoStart, ["0", "false", "no"].contains(autoStart) {
            return false
        }
        guard let host = endpoint.url.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    // Command resolution now lives in GatewayCommandResolver.

    private static func describeProbe(endpoint: GatewayEndpoint, ok: Bool) -> String {
        let host = endpoint.url.host ?? "unknown-host"
        let port = endpoint.url.port ?? 0
        return "tcp://\(host):\(port) -> \(ok ? "listening" : "not listening")"
    }

    private static func describeCommand(_ command: GatewayCommand) -> String {
        let args = command.arguments.joined(separator: " ")
        if let cwd = command.workingDirectory, !cwd.isEmpty {
            return "\(command.executable) \(args) (cwd: \(cwd))"
        }
        return "\(command.executable) \(args)"
    }
}

private enum PortProbe {
    private final class Resolution {
        nonisolated private let lock = NSLock()
        nonisolated(unsafe) private var resolved = false

        nonisolated func resolveIfNeeded(
            connection: NWConnection,
            continuation: CheckedContinuation<Bool, Never>,
            value: Bool
        ) {
            lock.lock()
            let shouldResolve = !resolved
            resolved = true
            lock.unlock()

            guard shouldResolve else { return }
            connection.cancel()
            continuation.resume(returning: value)
        }
    }

    static func isListening(host: String?, port: Int?) async -> Bool {
        guard let host, let port else { return false }
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return false }
        let endpointHost = NWEndpoint.Host(host)
        return await withCheckedContinuation { continuation in
            let connection = NWConnection(host: endpointHost, port: endpointPort, using: .tcp)
            let queue = DispatchQueue(label: "anthropod.portprobe")
            let resolution = Resolution()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resolution.resolveIfNeeded(
                        connection: connection,
                        continuation: continuation,
                        value: true
                    )
                case .failed, .cancelled:
                    resolution.resolveIfNeeded(
                        connection: connection,
                        continuation: continuation,
                        value: false
                    )
                default:
                    break
                }
            }

            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + 0.6) {
                resolution.resolveIfNeeded(
                    connection: connection,
                    continuation: continuation,
                    value: false
                )
            }
        }
    }
}
