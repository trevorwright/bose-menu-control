import Foundation

/// A Bose BMAP function address: a block plus a function within that block.
struct BMAPFunction: Hashable, Sendable {
    let block: UInt8
    let function: UInt8

    static let firmwareVersion = BMAPFunction(block: 0, function: 5)
    static let deviceName = BMAPFunction(block: 1, function: 2)
    static let batteryStatus = BMAPFunction(block: 2, function: 2)
    static let modeCapabilities = BMAPFunction(block: 31, function: 2)
    static let currentMode = BMAPFunction(block: 31, function: 3)
    static let modeConfig = BMAPFunction(block: 31, function: 6)
    static let liveAudioSettings = BMAPFunction(block: 31, function: 10)
}

/// BMAP operator codes carried in the low nibble of the third header byte.
enum BMAPOperation: UInt8, Sendable {
    case set = 0
    case get = 1
    case setGet = 2
    case status = 3
    case error = 4
    case start = 5
    case result = 6
}

struct BMAPPacket: Equatable, Sendable {
    static let maxPayloadLength = 255

    let function: BMAPFunction
    /// Raw operator byte with the low nibble holding the operation code.
    let operationByte: UInt8
    let payload: [UInt8]

    var operation: BMAPOperation? { BMAPOperation(rawValue: operationByte & 0x0F) }

    init(_ function: BMAPFunction, operation: BMAPOperation, payload: [UInt8] = []) {
        precondition(payload.count <= Self.maxPayloadLength)
        self.function = function
        self.operationByte = operation.rawValue
        self.payload = payload
    }

    /// Parses a complete, reassembled BMAP frame. Returns nil when the length byte disagrees with the data.
    init?(frame: [UInt8]) {
        guard frame.count >= 4, frame.count == Int(frame[3]) + 4 else { return nil }
        function = BMAPFunction(block: frame[0], function: frame[1])
        operationByte = frame[2]
        payload = Array(frame.dropFirst(4))
    }

    var frame: [UInt8] {
        [function.block, function.function, operationByte, UInt8(payload.count)] + payload
    }

    /// Operators a device may use to answer a request with the given operator.
    static func expectedReplyOperations(for request: BMAPOperation) -> Set<BMAPOperation> {
        switch request {
        case .get, .setGet, .set: return [.status, .error]
        case .start: return [.result, .status, .error]
        case .status, .error, .result: return []
        }
    }

    func isReply(to request: BMAPPacket) -> Bool {
        guard function == request.function, let operation, let requested = request.operation else { return false }
        return Self.expectedReplyOperations(for: requested).contains(operation)
    }
}

enum BMAPError: Error, LocalizedError, Equatable {
    case notConnected
    case timeout(BMAPFunction)
    case deviceError(BMAPFunction, code: UInt8?)
    case malformedReply(BMAPFunction)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Headphones are not connected."
        case .timeout: return "The headphones did not respond in time."
        case .deviceError(_, let code):
            if let code { return "The headphones rejected the request (error \(code))." }
            return "The headphones rejected the request."
        case .malformedReply: return "The headphones sent an unexpected reply."
        case .writeFailed(let detail): return "Sending to the headphones failed: \(detail)"
        }
    }
}

/// Reassembles BLE-segmented BMAP frames. Each BLE notification starts with a header byte whose high
/// nibble is the last segment index and whose low nibble is this segment's index.
struct BLESegmentAssembler {
    private var buffer: [UInt8] = []
    private var expectedIndex = 0
    private var lastIndex: Int?

    /// Feeds one BLE notification. Returns a complete frame when the final segment arrives.
    mutating func consume(_ data: Data) -> [UInt8]? {
        guard let header = data.first else { return nil }
        let index = Int(header & 0x0F)
        let last = Int(header >> 4)
        if index == 0 {
            buffer = []
            expectedIndex = 0
            lastIndex = last
        }
        guard index == expectedIndex, lastIndex == last, index <= last else {
            reset()
            return nil
        }
        buffer.append(contentsOf: data.dropFirst())
        expectedIndex += 1
        guard index == last else { return nil }
        let frame = buffer
        reset()
        return frame
    }

    mutating func reset() {
        buffer = []
        expectedIndex = 0
        lastIndex = nil
    }
}
