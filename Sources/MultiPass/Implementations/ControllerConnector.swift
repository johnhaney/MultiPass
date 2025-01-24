//
//  ControllerConnector.swift
//
//
//  Created by John Haney on 7/6/24.
//

import Foundation
import GameController

final class ControllerConnector: MultiConnector, ObservableObject {
    let id: UUID = UUID()
    var multipass: MultiPass
    var router: [MultiPass.Participant: GCController] = [:]

    typealias Participant = ControllerPass
    
    init(multipass: MultiPass) {
        self.multipass = multipass
        for controller in GCController.controllers() {
            ensureParticipant(controller)
        }
    }
}

extension ControllerConnector {
    func send(data: Data, reliable: Bool) {}
}

extension ControllerConnector {
    func start() {
        GCController.startWirelessControllerDiscovery(completionHandler: checkControllers)
    }
    
    private func checkControllers() {
        for controller in GCController.controllers() {
            ensureParticipant(controller)
        }
    }
    
    func stop() {
        GCController.stopWirelessControllerDiscovery()
    }
    
    private func ensureParticipant(_ controller: GCController) {
        guard !router.values.contains(controller) else {
            return
        }
        let participant = MultiPass.Participant()
        router[participant] = controller
        multipass.add(managed: participant)
    }
}
