// Copyright 2020 Esri
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import UIKit
import AVFoundation
import ArcGIS
import ArcGISToolkit

// MARK: - Navigate the route

class NavigateARNavigatorViewController: UIViewController {
    // MARK: Storyboard views
    
    /// The label to display route-planning status.
    @IBOutlet weak var statusLabel: UILabel!
    /// The bar button to calibrate navigation heading.
    @IBOutlet weak var calibrateButtonItem: UIBarButtonItem!
    /// The bar button to start navigation.
    @IBOutlet weak var startButtonItem: UIBarButtonItem!
    /// The `ArcGISARView` managed by the view controller.
    @IBOutlet weak var arView: ArcGISARView! {
        didSet {
            arView.sceneView.scene = makeScene()
            arView.sceneView.graphicsOverlays.add(makeRouteOverlay())
            // Turn the space and atmosphere effects on for an immersive experience.
            arView.sceneView.spaceEffect = .transparent
            arView.sceneView.atmosphereEffect = .none
            arView.locationDataSource = AGSCLLocationDataSource()
        }
    }
    
    // MARK: Instance properties
    
    /// The route result solved by the route task, received from route planner.
    var routeResult: AGSRouteResult!
    /// The route task that solves the route using the online routing service, received from route planner.
    var routeTask: AGSRouteTask!
    /// The parameters for route task to solve a route, received from route planner.
    var routeParameters: AGSRouteParameters!
    
    /// A boolean that indicates if the heading is being calibrated.
    var isCalibrating = false {
        didSet {
            elevationSurface.opacity = isCalibrating ? 0.6 : 0
        }
    }
    
    /// The route tracker for navigation. Use delegate methods to update tracking status.
    var routeTracker: AGSRouteTracker?
    /// The current route for navigation.
    var currentRoute: AGSRoute!
    /// The data source to track device location and provide updates to route tracker.
    let trackingLocationDataSource = AGSCLLocationDataSource()
    /// An `AVSpeechSynthesizer` for text to speech.
    let speechSynthesizer = AVSpeechSynthesizer()
    /// The graphic (with solid yellow 3D tube symbol) to represent the route.
    let routeGraphic = AGSGraphic()
    /// The elevation source with elevation service URL.
    let elevationSource = AGSArcGISTiledElevationSource(url: URL(string: "https://elevation3d.arcgis.com/arcgis/rest/services/WorldElevation3D/Terrain3D/ImageServer")!)
    /// The elevation surface set to the base surface of the scene.
    let elevationSurface = AGSSurface()
    /// A view controller that displays a slider to adjust navigation heading according to the basemap and elevation.
    lazy var calibrationVC = NavigateARCalibrationViewController(arcgisARView: arView)
    
    // MARK: Initialize route and graphics
    
    /// Create a scene.
    ///
    /// - Returns: A new `AGSScene` object.
    func makeScene() -> AGSScene {
        let scene = AGSScene(basemapType: .imageryWithLabels)
        elevationSurface.navigationConstraint = .none
        elevationSurface.opacity = 0.6
        elevationSurface.elevationSources = [elevationSource]
        scene.baseSurface = elevationSurface
        return scene
    }
    
    /// Create a graphic overlay and add graphics to it.
    ///
    /// - Returns: An `AGSGraphicsOverlay` object.
    func makeRouteOverlay() -> AGSGraphicsOverlay {
        let graphicsOverlay = AGSGraphicsOverlay()
        graphicsOverlay.sceneProperties?.surfacePlacement = .absolute
        let strokeSymbolLayer = AGSSolidStrokeSymbolLayer(
            width: 1.0,
            color: .yellow,
            geometricEffects: [],
            lineStyle3D: .tube
        )
        let polylineSymbol = AGSMultilayerPolylineSymbol(symbolLayers: [strokeSymbolLayer])
        let polylineRenderer = AGSSimpleRenderer(symbol: polylineSymbol)
        graphicsOverlay.renderer = polylineRenderer
        graphicsOverlay.graphics.add(routeGraphic)
        return graphicsOverlay
    }
    
    /// Set a route to current route and update graphic display.
    /// - Parameters:
    ///
    ///   - route: The new `AGSRoute` to set.
    ///   - completion: A closure to execute on successfully setting the new route and graphic.
    func setRouteAndGraphic(route: AGSRoute, onSuccess completion: (() -> Void)? = nil) {
        currentRoute = route
        let originalPolyline = route.routeGeometry!
        elevationSource.load { [weak self] (error: Error?) in
            if let error = error {
                self?.presentAlert(error: error)
                self?.setStatus(message: "Failed to load elevation source.")
            } else {
                self?.addElevationToPolyline(polyine: originalPolyline) { [weak self] (newPolyline: AGSPolyline) in
                    self?.routeGraphic.geometry = newPolyline
                    completion?()
                }
            }
        }
    }
    
    /// Densify the polyline geometry so the elevation can be adjusted every 0.3 meters,
    /// and add an elevation to the geometry.
    ///
    /// - Parameters:
    ///   - polyine: The polyline geometry of the route.
    ///   - z: A `Double` value representing z elevation.
    ///   - completion: A completion closure to execute after the polyline is generated with success or not.
    func addElevationToPolyline(
        polyine: AGSPolyline,
        elevation z: Double = 3,
        completion: @escaping (AGSPolyline) -> Void
    ) {
        if let densifiedPolyline = AGSGeometryEngine.densifyGeometry(polyine, maxSegmentLength: 0.3) as? AGSPolyline {
            let polylinebuilder = AGSPolylineBuilder(spatialReference: densifiedPolyline.spatialReference)
            let allPoints = densifiedPolyline.parts.array().flatMap { $0.points.array() }
            
            let buildGroup = DispatchGroup()
            allPoints.forEach { point in
                buildGroup.enter()
                elevationSurface.elevation(for: point) { [weak self] (elevation: Double, error: Error?) in
                    defer { buildGroup.leave() }
                    if let newpoint = AGSGeometryEngine.geometry(bySettingZ: elevation + z, in: point) as? AGSPoint {
                        // Put the new point 3 meters above the ground elevation.
                        polylinebuilder.add(newpoint)
                    } else if let error = error {
                        self?.presentAlert(error: error)
                    }
                }
            }
            
            buildGroup.notify(queue: .main) {
                completion(polylinebuilder.toGeometry())
            }
        } else {
            setStatus(message: "Failed to add elevation to route line.")
            completion(polyine)
        }
    }
    
    // MARK: Actions
    
    @IBAction func startTurnByTurn(_ sender: UIBarButtonItem) {
        routeTracker = AGSRouteTracker(routeResult: routeResult, routeIndex: 0)
        if routeTask.routeTaskInfo().supportsRerouting {
            routeTracker?.enableRerouting(
                with: routeTask,
                routeParameters: routeParameters,
                strategy: .toNextStop,
                visitFirstStopOnStart: true
            ) { [weak self] (error: Error?) in
                if let error = error {
                    self?.presentAlert(error: error)
                } else {
                    self?.routeTracker?.delegate = self
                }
            }
        } else {
            routeTracker?.delegate = self
        }
    }
    
    // MARK: UI
    
    func setStatus(message: String) {
        statusLabel.text = message
    }
    
    // MARK: UIViewController
    
    override func viewDidLoad() {
        super.viewDidLoad()
        isCalibrating = false
        // Start tracking.
        trackingLocationDataSource.locationChangeHandlerDelegate = self
        trackingLocationDataSource.start()
        // Set the route solved by route planner to the scene.
        // On success, enable calibration adjustment.
        setRouteAndGraphic(route: routeResult.routes.first!) { [weak self] in
            self?.calibrateButtonItem.isEnabled = true
            self?.setStatus(message: "Adjust calibration before starting.")
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        arView.startTracking(.continuous, completion: nil)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        arView.stopTracking()
    }
}

// MARK: - Route navigation status changes

extension NavigateARNavigatorViewController: AGSRouteTrackerDelegate {
    func routeTracker(
        _ routeTracker: AGSRouteTracker,
        didGenerateNewVoiceGuidance voiceGuidance: AGSVoiceGuidance
    ) {
        setSpeakDirection(with: voiceGuidance.text)
    }
    
    func routeTrackerRerouteDidStart(_ routeTracker: AGSRouteTracker) {
        setStatus(message: "Rerouting...")
    }
    
    func routeTracker(_ routeTracker: AGSRouteTracker, didUpdate trackingStatus: AGSTrackingStatus) {
        let currentManeuver = currentRoute.directionManeuvers[trackingStatus.currentManeuverIndex]
        setStatus(message: currentManeuver.directionText)
    }
    
    func routeTracker(
        _ routeTracker: AGSRouteTracker,
        rerouteDidCompleteWith trackingStatus: AGSTrackingStatus?,
        error: Error?
    ) {
        if let latestRoute = trackingStatus?.routeResult.routes.first {
            if latestRoute != self.currentRoute {
                setRouteAndGraphic(route: latestRoute)
            }
        }
    }
    
    func setSpeakDirection(with text: String?) {
        speechSynthesizer.stopSpeaking(at: AVSpeechBoundary.word)
        if let text = text {
            let speechUtterance = AVSpeechUtterance(string: text)
            speechUtterance.rate = AVSpeechUtteranceMaximumSpeechRate * 0.5
            speechSynthesizer.speak(speechUtterance)
        }
    }
}

// MARK: - AGSLocationChangeHandlerDelegate

extension NavigateARNavigatorViewController: AGSLocationChangeHandlerDelegate {
    func locationDataSource(
        _ locationDataSource: AGSLocationDataSource,
        locationDidChange location: AGSLocation
    ) {
        startButtonItem.isEnabled = true
        // Send location updates to route tracker if actively navigating.
        routeTracker?.trackLocation(location)
    }
}

// MARK: - Calibration popup

extension NavigateARNavigatorViewController {
    @IBAction func showCalibrationPopup(_ sender: UIBarButtonItem) {
        if isCalibrating {
            calibrationVC.dismiss(animated: true)
        } else {
            showPopup(calibrationVC, sourceButton: sender)
        }
        isCalibrating.toggle()
    }
    
    private func showPopup(_ controller: UIViewController, sourceButton: UIBarButtonItem) {
        controller.modalPresentationStyle = .popover
        if let presentationController = controller.popoverPresentationController {
            presentationController.delegate = self
            presentationController.barButtonItem = sourceButton
            presentationController.permittedArrowDirections = [.down, .up]
        }
        present(controller, animated: true)
    }
}

extension NavigateARNavigatorViewController: UIPopoverPresentationControllerDelegate {
    func popoverPresentationControllerDidDismissPopover(
        _ popoverPresentationController: UIPopoverPresentationController
    ) {
        isCalibrating = false
    }
}

extension NavigateARNavigatorViewController: UIAdaptivePresentationControllerDelegate {
    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        return .none
    }
}
