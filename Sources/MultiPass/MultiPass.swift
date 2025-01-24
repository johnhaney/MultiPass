import Foundation
import GroupActivities
import OSLog
import Combine

fileprivate let logger = Logger(subsystem: "com.appsfromouterspace.MultiPass", category: "Configuration")

public class MultiPass: ObservableObject {
    public static var none: MultiPass { MultiPass() }
    
    let configuration: Configuration
    public let localParticipant: Participant
    
    public private(set) var managedParticipants: CurrentValueSubject<Set<Participant>, Never> = CurrentValueSubject(Set())
    public private(set) var remoteParticipants: CurrentValueSubject<Set<Participant>, Never> = CurrentValueSubject(Set())
    
    public var participants: AnyPublisher<Set<MultiPass.Participant>, Never> {
        self.managedParticipants.combineLatest(remoteParticipants).map({ $0.0.union($0.1) }).eraseToAnyPublisher()
    }
    
    @Published public private(set) var messages: CurrentValueSubject<(MultiPassMessage, Participant.ID), Never>
    
    var messageTypes: [Int: MultiPassMessage.Type] = [:]
    
    var connectors: [any MultiConnector] = []
    
    public var localID: UUID { configuration.localID }
    
    private init() {
        self.configuration = Configuration(multipeerName: "", activityType: nil, messageTypes: [])
        localParticipant = Participant()
        messageTypes = [:]
        messages = CurrentValueSubject((ParticipantList(participants: []), UUID()))
    }
    
    public init(configuration: Configuration) {
        self.configuration = configuration
        localParticipant = Participant(self.configuration.localID)
        managedParticipants.value = Set([localParticipant])
        messageTypes = Dictionary(uniqueKeysWithValues: configuration.messageTypes.map({ ($0.multiPassMessageType, $0) }) + [(ParticipantList.multiPassMessageType, ParticipantList.self)])
        messages = CurrentValueSubject((ParticipantList(participants: []), configuration.localID))

        let types = messageTypes.map({ $0.value.multiPassMessageType })
        if types.count != Set(types).count {
            logger.error("Duplicate message types found, ensure each MultiPassMessage has a unique multiPassMessageType value. MultiPass will not send/receive some conflicting messages.")
        }

        passes.append(self)
        self.autostart()
    }
    
    func helloMessage(again: Bool) throws -> Data {
        try Self.pack(message: ParticipantList(participants: managedParticipants.value.map(\.id)), from: localParticipant.id)
    }
    
    public func startHosting() {
        if let activityType = configuration.activityType {
            let activity = activityType.init()
            Task {
                switch await activity.prepareForActivation() {
                case .activationPreferred:
                    print("shareplay hosting activating")
                    try? await activity.activate()
                case .activationDisabled:
                    print("shareplay hosting not available")
                case .cancelled:
                    print("shareplay hosting cancelled")
                }
            }
        }
    }
}

nonisolated(unsafe) fileprivate var passes: [MultiPass] = []

extension MultiPass {
    static func receive(data: Data, connector: any MultiConnector, participantCallback: @escaping (Participant) -> Void) throws {
        for pass in passes.reversed() {
            do {
                try pass.receive(data: data, connector: connector, participantCallback: participantCallback)
                break
            } catch {
                continue
            }
        }
    }
}

extension MultiPass {
    func autostart() {
        do {
            let connector = TouchscreenConnector(multipass: self)
            if configuration.touchscreenLimit > 0 {
                connector.addParticipant(configuration.localID)
            }
            connectors.append(connector)
        }

        do {
            nonisolated(unsafe) let connector = GroupConnector(multipass: self)
            connectors.append(connector)
            if let activity = configuration.activityType {
                Task { @MainActor in
                    await connector.watch(activity: activity)
                }
            }
        }
        
        do {
            if configuration.controllerLimit > 0 {
                let connector = ControllerConnector(multipass: self)
                connectors.append(connector)
            }
        }

        do {
            if let name = configuration.multipeerName,
               !name.isEmpty {
                let connector = MultipeerConnector(multipass: self, serviceName: name, peerID: configuration.localID)
                connectors.append(connector)
                switch configuration.multipeerListeningPreference {
                case .always:
                    connector.start()
                case .manual:
                    break
                }
            }
        }
    }
    
    public func start() {
        for connector in connectors {
            connector.start()
        }
    }
    
    public func stop() {
        for connector in connectors {
            connector.stop()
        }
    }
    
    func add(managed participant: Participant) {
        managedParticipants.value.insert(participant)
    }
    
    func add(remote participant: Participant) {
        remoteParticipants.value.insert(participant)
    }
    
    func add(remote participants: [Participant]) {
        remoteParticipants.value.formUnion(participants)
    }

    func remove(managed participant: Participant) {
        managedParticipants.value.remove(participant)
    }
    
    func remove(remote participant: Participant) {
        remoteParticipants.value.remove(participant)
    }
}

extension MultiPass {
    public protocol Activity: GroupActivity {
        init()
    }
    
    public struct ParticipantList: MultiPassMessage {
        public static var multiPassMessageType: Int { 6000 }
        
        public let participants: [Participant.ID]
        
        var actualParticipants: [Participant] {
            participants.map({ Participant($0) })
        }
    }
}

extension MultiPass {
    public struct Configuration {
        // Local Identifier
        public var localID: UUID
        
        // Multipeer
        public var multipeerName: String?
        
        // GroupActivity
        public var activityType: MultiPass.Activity.Type?
        
        // Messages
        public var messageTypes: [MultiPassMessage.Type]

        /// Preference for connecting via Multipeer. Defaults to `always`
        public var multipeerListeningPreference: MultipeerListeningPreference
        
        // Local multiplayer options
        public var localPlayerLimit: LocalPlayerLimit
        
        public enum MultipeerListeningPreference {
            case always
            case manual
        }
        
        public enum LocalPlayerLimit {
            case controllers(Int)
            case touchscreen(Int)
            case touchscreenAndControllers(Int, Int)
        }
        
        public init(multipeerName: String, activityType: MultiPass.Activity.Type?, messageTypes: [MultiPassMessage.Type], localPlayerLimit: LocalPlayerLimit = .touchscreen(1), multipeerListeningPreference: MultipeerListeningPreference = .always) {
            if let savedIDString = UserDefaults.standard.string(forKey: "com.appsfromouterspace.MultiPass.localID"),
               let savedID = UUID(uuidString: savedIDString) {
                localID = savedID
            } else {
                localID = UUID()
                UserDefaults.standard.setValue(localID.uuidString, forKey: "com.appsfromouterspace.MultiPass.localID")
            }
            self.multipeerName = multipeerName
            self.activityType = activityType
            self.messageTypes = messageTypes
            self.localPlayerLimit = localPlayerLimit
            self.multipeerListeningPreference = multipeerListeningPreference
        }
    }
}

struct MultiPassMessageTypeDuplicate: Error {}

extension MultiPass.Configuration {
    fileprivate var controllerLimit: Int {
        switch localPlayerLimit {
        case .touchscreen(_):
            return 0
        case .controllers(let limit):
            return limit
        case .touchscreenAndControllers(_, let limit):
            return limit
        }
    }
    
    fileprivate var touchscreenLimit: Int {
        switch localPlayerLimit {
        case .controllers(_):
            return 0
        case .touchscreen(let limit):
            return limit
        case .touchscreenAndControllers(let limit, _):
            return limit
        }
    }
}

extension MultiPass {
    public struct Participant: Identifiable, Sendable, Equatable, Hashable {
        public let id: UUID
        public init(_ id: UUID = UUID()) {
            self.id = id
        }
        
        public static func ==(lhs: Participant, rhs: Participant) -> Bool {
            lhs.id == rhs.id
        }
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }
}

public enum ConnectionState {
    case connected
    case connecting
    case disconnected
}

extension MultiPass {
    enum Error: Swift.Error {
        case unrecognized
        case internalError
    }
    
    struct Header: Codable {
        let messageType: Int
        let from: UUID
        let size: Int
    }
    
    static func pack<Message: MultiPassMessage>(message: Message, from: UUID) throws -> Data {
        let encoder = JSONEncoder()
        let payload = try encoder.encode(message)
        let header = Header(messageType: Message.multiPassMessageType, from: from, size: payload.count)
        let prefix = try encoder.encode(header)
        
        return prefix + payload
    }
    
    static func unpack(data: Data, expectedTypes: [Int: MultiPassMessage.Type]) throws -> (Int, any MultiPassMessage, from: UUID) {
        guard let endJson = "}".data(using: .utf8),
              let firstEnd = data.firstRange(of: endJson)
        else { throw Error.internalError }
        let decoder = JSONDecoder()
        let headerData = data.prefix(upTo: firstEnd.upperBound)
        let header = try decoder.decode(Header.self, from: headerData)
        let payload = data.suffix(header.size)
        for (messageType, MessageType) in expectedTypes {
            do {
                let message = try decoder.decode(MessageType.self, from: payload)
                return (messageType, message, header.from)
            } catch {
                continue
            }
        }
        throw Error.unrecognized
    }
}
