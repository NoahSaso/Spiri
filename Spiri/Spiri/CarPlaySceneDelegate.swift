//
//  CarPlaySceneDelegate.swift
//  Spiri
//
//  Created by Noah Saso on 12/8/21.
//

import CarPlay
import SpiriKit
import Combine
import SwiftUI

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?

    var cancellables: Set<AnyCancellable> = []
    let spotify = SpiriKitSpotify()

    // CarPlay connected
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController

        spotify.fetchPlaylists(
            success: { playlists in
                let playlistItems = playlists
                    .sorted {
                        $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        < $1.name.trimmingCharacters(in: .whitespacesAndNewlines)      .lowercased()
                    }.map { p -> CPListItem in
                        let item = CPListItem(text: p.name, detailText: nil)
                        item.handler = { item, completion in
                            print(p.uri)
                        }
                        return item
                    }

                let section = CPListSection(items: playlistItems)
                let listTemplate = CPListTemplate(title: "Playlists", sections: [section])
                self.interfaceController?.pushTemplate(listTemplate, animated: true, completion: nil)
            }, failure: { error in
                print("fetch playlists failure: \(error)")
            })
    }

    // CarPlay disconnected
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnect interfaceController: CPInterfaceController) {
        self.interfaceController = nil
    }
}
