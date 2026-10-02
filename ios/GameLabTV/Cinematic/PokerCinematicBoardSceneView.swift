import SwiftUI
import SceneKit

/// A Poker-specific cinematic table scene, built directly on
/// `CinematicCameraRig` and `CinematicLighting` (the same primitives
/// `CinematicBoardSceneView` demonstrates) rather than through that generic
/// wrapper -- Poker needs its content (seat count, community-card reveals,
/// a dealer whose gestures are timed off real hand events) driven by real
/// `PokerBoardState`, not just a `TablePhase` label, so this view owns its
/// own `SCNScene` content while reusing the rig/lighting classes verbatim.
///
/// `TablePhase` (dealing/betting/reveal/results) is still the vocabulary the
/// camera and lighting speak; `PokerEngine`'s own phases (preflop/flop/turn/
/// river/showdown) are mapped onto it in `tablePhase(for:)` below.
struct PokerCinematicBoardSceneView: UIViewRepresentable {
    var state: PokerBoardState

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraRig.cameraNode
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .black
        view.isPlaying = true
        view.rendersContinuously = true
        context.coordinator.apply(state, animated: false)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.apply(state, animated: true)
    }

    @MainActor
    final class Coordinator {
        let scene = SCNScene()
        let cameraRig: CinematicCameraRig
        let lighting: CinematicLighting
        private let dealer = PokerDealerNode()

        private let tableRadius: Float = 2.2
        private let seatMarkersNode = SCNNode()
        private let communitySlotNodes: [SCNNode]
        private let faceDownMaterial: SCNMaterial
        private let faceUpMaterial: SCNMaterial

        private var lastSeatCount = -1
        private var lastCommunityCount = 0
        private var lastMappedPhase: TablePhase?
        private var lastReactedWinnerID: String?

        init() {
            let initialShot = Coordinator.shot(for: .dealing, tableRadius: tableRadius)
            cameraRig = CinematicCameraRig(initialShot: initialShot)
            lighting = CinematicLighting(tableRadius: tableRadius)

            let faceDown = SCNMaterial()
            faceDown.lightingModel = .physicallyBased
            // A felt-dark inset marker: these slots used to be chunky raised
            // slabs that competed with the SwiftUI card row floating above
            // them (and, as the camera moved, could visually collide with the
            // "Community Cards" label). They are now flush with the felt and
            // read as table insets, not cards.
            faceDown.diffuse.contents = UIColor(red: 0.05, green: 0.22, blue: 0.14, alpha: 1)
            faceDown.roughness.contents = 0.9
            faceDownMaterial = faceDown

            let faceUp = SCNMaterial()
            faceUp.lightingModel = .physicallyBased
            faceUp.diffuse.contents = UIColor(red: 0.55, green: 0.85, blue: 0.62, alpha: 1)
            faceUp.roughness.contents = 0.6
            faceUpMaterial = faceUp

            // `tableRadius` is a stored property, so reading it here (even
            // just as a bare identifier) captures `self` -- and this
            // closure runs while `communitySlotNodes` (one of self's own
            // stored properties) is still mid-assignment, which the
            // compiler rejects outright ("'self' captured by a closure
            // before all members were initialized"). Copying it to a local
            // constant first means the closure captures a plain Float
            // instead of self.
            let radius = tableRadius
            communitySlotNodes = (0..<5).map { i -> SCNNode in
                // Flush with the felt (table top sits at y = 0.04) so the
                // markers read as inlaid card guides, never as raised slabs.
                let slot = SCNNode(geometry: SCNBox(width: 0.34, height: 0.01, length: 0.46, chamferRadius: 0.005))
                slot.geometry?.materials = [faceDown]
                slot.position = SCNVector3(Float(i - 2) * 0.42, 0.042, -radius * 0.4)
                return slot
            }

            scene.rootNode.addChildNode(cameraRig.cameraNode)
            lighting.addToScene(scene)
            scene.rootNode.addChildNode(seatMarkersNode)
            communitySlotNodes.forEach { scene.rootNode.addChildNode($0) }

            buildTableAndFloor()

            dealer.rootNode.position = SCNVector3(0, 0, -(tableRadius + 0.55))
            scene.rootNode.addChildNode(dealer.rootNode)
        }

        // MARK: - Table dressing (built once)

        private func buildTableAndFloor() {
            let floor = SCNNode(geometry: SCNCylinder(radius: CGFloat(tableRadius) * 3.2, height: 0.02))
            let floorMaterial = SCNMaterial()
            floorMaterial.lightingModel = .physicallyBased
            floorMaterial.diffuse.contents = UIColor(white: 0.04, alpha: 1)
            floorMaterial.roughness.contents = 0.9
            floor.geometry?.materials = [floorMaterial]
            floor.position = SCNVector3(0, -0.06, 0)
            scene.rootNode.addChildNode(floor)

            let tableGeometry = SCNCylinder(radius: CGFloat(tableRadius), height: 0.08)
            let felt = SCNMaterial()
            felt.lightingModel = .physicallyBased
            felt.diffuse.contents = UIColor(red: 0.07, green: 0.30, blue: 0.19, alpha: 1)
            felt.roughness.contents = 0.85
            tableGeometry.materials = [felt]
            let tableNode = SCNNode(geometry: tableGeometry)
            scene.rootNode.addChildNode(tableNode)

            let rim = SCNNode(geometry: SCNTorus(ringRadius: CGFloat(tableRadius), pipeRadius: 0.05))
            let rimMaterial = SCNMaterial()
            rimMaterial.lightingModel = .physicallyBased
            rimMaterial.diffuse.contents = UIColor(red: 0.28, green: 0.16, blue: 0.06, alpha: 1)
            rimMaterial.roughness.contents = 0.4
            rim.geometry?.materials = [rimMaterial]
            rim.position = SCNVector3(0, 0.02, 0)
            scene.rootNode.addChildNode(rim)

            let potMarker = SCNNode(geometry: SCNCylinder(radius: 0.2, height: 0.05))
            let potMaterial = SCNMaterial()
            potMaterial.lightingModel = .physicallyBased
            potMaterial.diffuse.contents = UIColor(white: 0.85, alpha: 1)
            potMaterial.metalness.contents = 0.6
            potMaterial.roughness.contents = 0.3
            potMarker.geometry?.materials = [potMaterial]
            potMarker.position = SCNVector3(0, 0.06, tableRadius * 0.25)
            scene.rootNode.addChildNode(potMarker)
        }

        private func rebuildSeatMarkers(count: Int) {
            guard count != lastSeatCount else { return }
            lastSeatCount = count
            seatMarkersNode.childNodes.forEach { $0.removeFromParentNode() }

            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.diffuse.contents = UIColor(white: 0.15, alpha: 1)
            material.roughness.contents = 0.7

            let n = max(count, 1)
            for i in 0..<n {
                let angle = (Float(i) + 0.5) / Float(n) * 2 * .pi
                let marker = SCNNode(geometry: SCNBox(width: 0.3, height: 0.04, length: 0.3, chamferRadius: 0.02))
                marker.geometry?.materials = [material]
                marker.position = SCNVector3(
                    tableRadius * 0.82 * cos(angle),
                    0.05,
                    tableRadius * 0.82 * sin(angle)
                )
                seatMarkersNode.addChildNode(marker)
            }
        }

        // MARK: - Live state -> scene

        func apply(_ state: PokerBoardState, animated: Bool) {
            rebuildSeatMarkers(count: state.playerSeats.count)

            let revealedCount = min(state.communityCards.count, communitySlotNodes.count)
            for (i, slot) in communitySlotNodes.enumerated() {
                slot.geometry?.materials = [i < revealedCount ? faceUpMaterial : faceDownMaterial]
            }

            let mappedPhase = Coordinator.tablePhase(for: state.phase)
            let newCount = state.communityCards.count
            let cardsRevealedNow = newCount - lastCommunityCount

            guard animated else {
                cameraRig.transition(to: Coordinator.shot(for: mappedPhase, tableRadius: tableRadius), duration: 0)
                lighting.apply(Coordinator.mood(for: mappedPhase), duration: 0)
                lastCommunityCount = newCount
                lastMappedPhase = mappedPhase
                return
            }

            if cardsRevealedNow > 0 {
                // New community cards just hit the table: the dealer deals
                // them and the camera pushes in tight on the reveal, then
                // settles back on whichever shot the resulting phase calls
                // for (almost always the wider betting shot).
                dealer.playDeal(cardCount: cardsRevealedNow)
                cameraRig.transition(to: Coordinator.revealShot(tableRadius: tableRadius), duration: 1.1)
                lighting.apply(.tense, duration: 1.0)

                let settleShot = Coordinator.shot(for: mappedPhase, tableRadius: tableRadius)
                let settleMood = Coordinator.mood(for: mappedPhase)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) { [weak self] in
                    guard let self else { return }
                    self.cameraRig.transition(to: settleShot, duration: 1.4)
                    self.lighting.apply(settleMood, duration: 1.4)
                }
            } else if mappedPhase != lastMappedPhase {
                cameraRig.transition(to: Coordinator.shot(for: mappedPhase, tableRadius: tableRadius))
                lighting.apply(Coordinator.mood(for: mappedPhase))
            }

            if mappedPhase == .results {
                if let winnerID = state.winnerID, winnerID != lastReactedWinnerID {
                    lastReactedWinnerID = winnerID
                    let leanRight = state.playerSeats.firstIndex { $0.id == winnerID }.map {
                        Coordinator.seatIsOnRightHalf(index: $0, of: state.playerSeats.count)
                    }
                    dealer.playShowdownReaction(leanRight: leanRight)
                } else if state.winnerID == nil && lastReactedWinnerID == nil {
                    // Showdown reached without a determinable single winner
                    // (e.g. a split pot) -- still give the moment a beat.
                    lastReactedWinnerID = ""
                    dealer.playShowdownReaction(leanRight: nil)
                }
            } else {
                lastReactedWinnerID = nil
            }

            lastCommunityCount = newCount
            lastMappedPhase = mappedPhase
        }

        /// Same left/right convention the seat-marker ring uses: `angle`
        /// increases counter-clockwise from the +x axis, and the camera
        /// looks toward the table from the +z side, so a positive x is
        /// "camera's right".
        private static func seatIsOnRightHalf(index: Int, of count: Int) -> Bool {
            guard count > 0 else { return false }
            let angle = (Float(index) + 0.5) / Float(count) * 2 * .pi
            return cos(angle) > 0
        }

        // MARK: - Engine phase -> cinematic vocabulary

        private static func tablePhase(for enginePhase: String) -> TablePhase {
            switch enginePhase {
            case "preflop": return .dealing
            case "flop", "turn", "river": return .betting
            case "showdown": return .results
            default: return .betting
            }
        }

        private static func mood(for phase: TablePhase) -> PhaseLightingMood {
            switch phase {
            case .dealing: return .warm
            case .betting: return .neutral
            case .reveal: return .tense
            case .results: return .tense // showdown is the climax, not a wind-down
            }
        }

        private static func shot(for phase: TablePhase, tableRadius: Float) -> CameraShot {
            switch phase {
            case .dealing:
                // Wide establishing shot -- whole table and the dealer both
                // in frame. The look-at point sits up and toward the dealer
                // (head ~1.75 at z = -(r + 0.55)) so the dealer is framed
                // fully instead of being cropped to legs at the top edge.
                return CameraShot(
                    position: SCNVector3(0, tableRadius * 1.5, tableRadius * 1.8),
                    lookAt: SCNVector3(0, tableRadius * 0.15, -tableRadius * 0.28),
                    fieldOfView: 58,
                    focusDistance: CGFloat(tableRadius * 1.9)
                )
            case .betting:
                // The everyday "hand in progress" shot (flop/turn/river).
                // Framed to keep the dealer fully visible above the table --
                // the previous lower look-at left only the dealer's legs at
                // the top edge of frame in flop/turn screenshots.
                return CameraShot(
                    position: SCNVector3(0, tableRadius * 1.15, tableRadius * 1.7),
                    lookAt: SCNVector3(0, tableRadius * 0.24, -tableRadius * 0.58),
                    fieldOfView: 47,
                    focusDistance: CGFloat(tableRadius * 1.2)
                )
            case .reveal:
                return revealShot(tableRadius: tableRadius)
            case .results:
                // Shot from the players' side (front of the dealer, who
                // faces +z) rather than from behind the dealer -- the old
                // shot sat on the dealer's axis behind them, so the dealer's
                // body filled the frame and blocked the table. Pulled back
                // and high so the dealer's showdown reaction, the card row,
                // and every seat are visible at once.
                return CameraShot(
                    position: SCNVector3(0, tableRadius * 1.7, tableRadius * 1.6),
                    lookAt: SCNVector3(0, tableRadius * 0.2, -tableRadius * 0.9),
                    fieldOfView: 52,
                    focusDistance: CGFloat(tableRadius * 1.8)
                )
            }
        }

        /// A tight, telephoto-feeling push toward the community-card row,
        /// used as a transient beat rather than a resting shot.
        private static func revealShot(tableRadius: Float) -> CameraShot {
            CameraShot(
                position: SCNVector3(0, tableRadius * 0.5, tableRadius * 0.55),
                lookAt: SCNVector3(0, 0.05, -tableRadius * 0.25),
                fieldOfView: 30,
                focusDistance: CGFloat(tableRadius * 0.75)
            )
        }
    }
}
