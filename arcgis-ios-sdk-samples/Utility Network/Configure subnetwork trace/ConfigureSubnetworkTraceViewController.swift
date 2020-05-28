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
import ArcGIS

class ConfigureSubnetworkTraceViewController: UIViewController {
    @IBOutlet weak var mapView: AGSMapView!
    
    private let featureServiceURL = URL(string: "https://sampleserver7.arcgisonline.com/arcgis/rest/services/UtilityNetwork/NapervilleElectric/FeatureServer")!
    
    override func viewDidLoad() {
    super.viewDidLoad()
    
    //add the source code button item to the right of navigation bar
    (navigationItem.rightBarButtonItem as! SourceCodeBarButtonItem).filenames = ["ConfigureSubnetworkTraceViewController", "ConfigureSubnetworkTraceViewControllerConfigurations", "OptionsTableViewController"]
    }
}