//
//  GroupConnector.swift
//
//
//  Created by John Haney on 7/6/24.
//

import Foundation
import Combine
import GroupActivities
import OSLog

fileprivate let logger = Logger(subsystem: "com.appsfromouterspace.MultiPass", category: "Group")

final class GroupConnector: MultiConnector, ObservableObject {
    let id: UUID = UUID()
    var router: [MultiPass.Participant: GroupActivities.Participant] = [:]
    var mapping: [GroupActivities.Participant: MultiPass.Participant] = [:]
    
    var subscriptions: Set<AnyCancellable> = Set()
    
    var reliableMessenger: GroupSessionMessenger?
    var unreliableMessenger: GroupSessionMessenger?
    
    typealias Participant = GroupPass
    
    var multipass: MultiPass

    init(multipass: MultiPass) {
        self.multipass = multipass
    }
    
    static func watch<Activity: GroupActivity>(activity: Activity.Type, connector: @escaping (GroupSession<Activity>) -> Void) async {
        for await session in Activity.sessions() {
            connector(session)
        }
    }
    
    func watch<Activity: GroupActivity>(activity: Activity.Type) async {
        await Self.watch(activity: activity) { session in
            self.setSession(session)
        }
    }
    
    func setSession<Activity: GroupActivity>(_ session: GroupSession<Activity>) {
        self.subscriptions.removeAll()
        
        let reliableMessenger = GroupSessionMessenger(session: session, deliveryMode: .reliable)
        self.reliableMessenger = reliableMessenger
        self.unreliableMessenger = GroupSessionMessenger(session: session, deliveryMode: .unreliable)
        
        session.$activeParticipants.removeDuplicates().sink { participants in
            do {
                let data = try self.multipass.helloMessage(again: true)
                reliableMessenger.send(data, completion: { error in
                    if let error {
                        logger.error("Group could not send hello: \(error.localizedDescription)")
                    }
                })
            } catch {
                logger.error("Group sent hello")
            }
        }.store(in: &self.subscriptions)
    }
}

extension GroupConnector {
    func send(data: Data, reliable: Bool = true) {
        guard let messenger = reliable ? reliableMessenger : unreliableMessenger
        else {
//            logger.info("Group not connected, not sending \(data.count) byte message")
            return
        }
        Task {
            do {
                try await messenger.send(data)
                logger.debug("Sent \(data.count) byte message")
            } catch {
                logger.error("Error sending \(data.count) byte message: \(error.localizedDescription)")
            }
        }
    }
}

extension GroupConnector {
    func start() {
        
    }
    
    func stop() {
        
    }
}
