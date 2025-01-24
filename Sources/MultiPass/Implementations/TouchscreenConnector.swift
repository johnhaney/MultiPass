//
//  TouchscreenConnector.swift
//  MultiPass
//
//  Created by John Haney on 7/14/24.
//

import Foundation
import OSLog

fileprivate let logger = Logger(subsystem: "com.appsfromouterspace.MultiPass", category: "Touchscreen")

class TouchscreenConnector: MultiConnector, ObservableObject {
    let id: UUID = UUID()
    var multipass: MultiPass

    init(multipass: MultiPass) {
        self.multipass = multipass
    }
    
    func addParticipant(_ id: UUID = UUID()) {
        multipass.add(managed: MultiPass.Participant(id))
    }
    
    func send(data: Data, reliable: Bool) {
    }
    
    func start() {
    }
    
    func stop() {
    }
}
