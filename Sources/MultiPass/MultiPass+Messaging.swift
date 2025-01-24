//
//  File.swift
//  
//
//  Created by John Haney on 7/6/24.
//

import Foundation

public protocol MultiPassMessage: Codable, Sendable {
    static var multiPassMessageType: Int { get }
}

// Send
extension MultiPass {
    public func send<Message: MultiPassMessage>(_ message: Message, from: Participant? = nil) throws {
        let payload = try Self.pack(message: message, from: from?.id ?? localID)
        for connector in self.connectors {
            connector.send(data: payload, reliable: true)
        }
    }
}

// Receive
extension MultiPass {
    func receive(data: Data, connector source: any MultiConnector, participantCallback: (Participant) -> Void) throws {
        let (messageType, message, fromID) = try Self.unpack(data: data, expectedTypes: messageTypes)
        let participant = Participant(fromID)
        if let message = message as? ParticipantList {
            add(remote: message.actualParticipants + [participant])
        } else {
            add(remote: participant)
        }
        participantCallback(participant)
        // Communicate the newest value
        messages.send((message, fromID))
        for connector in connectors {
            if connector.id != source.id {
                connector.send(data: data, reliable: true)
            }
        }
    }
}
