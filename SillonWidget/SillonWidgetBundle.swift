//
//  SillonWidgetBundle.swift
//  SillonWidget
//
//  Point d'entrée du bundle de widgets. Pour l'instant un seul widget : « Lecture en cours ».
//  (Les gabarits Control et Live Activity générés par Xcode ne sont pas exposés ici.)
//

import WidgetKit
import SwiftUI

@main
struct SillonWidgetBundle: WidgetBundle {
    var body: some Widget {
        SillonWidget()
    }
}
