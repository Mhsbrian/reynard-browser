//
//  Haptics.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

/// The system's haptic patterns, each used for what the Human Interface Guidelines give it to: selection
/// while a value changes, an impact where something in the interface is picked up or snaps into place, a
/// notification for how a task ended. The system plays none of them when haptics are turned off in Settings.
enum Haptics {
    private static let impactGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    
    static func prepareRigid() {
        impactGenerator.prepare()
    }
    
    static func rigid() {
        impactGenerator.impactOccurred()
    }
    
    static func success() {
        notificationGenerator.notificationOccurred(.success)
    }
    
    /// A choice changed: another tab, another segment, a step of zoom.
    static func selection() {
        selectionGenerator.selectionChanged()
    }

}
