//
//  ENTScheduleApp.swift
//  ENTSchedule
//
//  Created by vl.korzh on 30.01.2026.
//

import SwiftUI
import CoreData

@main
struct ENTScheduleApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
