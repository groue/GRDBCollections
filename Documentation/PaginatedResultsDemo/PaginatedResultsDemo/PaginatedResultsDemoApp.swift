import GRDB
import SwiftUI

@main
struct PaginatedResultsDemoApp: App {
    enum Tab: String {
        case players
        case paginationDemo
    }
    
    @AppStorage("selectedTab") var tab = Tab.players
    
    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                PlayersView()
                    .environment(\.dbPool, DatabasePool.shared)
                    .tag(Tab.players)
                    .tabItem {
                        Label("Players", systemImage: "cylinder.split.1x2")
                    }
                
                PaginationDemoList()
                    .tag(Tab.paginationDemo)
                    .tabItem {
                        Label("Pagination", systemImage: "ellipsis.circle")
                    }
            }
        }
    }
}

private struct DatabasePoolKey: EnvironmentKey {
    static var defaultValue: DatabasePool { DatabasePool.shared }
}

extension EnvironmentValues {
    var dbPool: DatabasePool {
        get { self[DatabasePoolKey.self] }
        set { self[DatabasePoolKey.self] = newValue }
    }
}
