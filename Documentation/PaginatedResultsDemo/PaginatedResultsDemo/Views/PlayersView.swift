import Combine
import GRDB
import GRDBCollections
import GRDBQuery
import SwiftUI

struct PlayerRequest: Queryable {
    enum Ordering {
        case byName
        case byScore
    }
    
    static var defaultValue: PaginatedRequest<Player> { .empty }
    
    var ordering: Ordering
    
    /// Returns a Combine publisher of database values.
    ///
    /// - parameter database: Provides access to the database.
    func publisher(in dbPool: DatabasePool) -> AnyPublisher<PaginatedRequest<Player>, Error> {
        dbPool
            .readPublisher { db in
                let request: QueryInterfaceRequest<Player>
                switch ordering {
                case .byScore:
                    request = Player.all().orderedByScore()
                case .byName:
                    request = Player.all().orderedByName()
                }
                
                try db.registerAccess(to: request)
                let snapshot = try DatabaseSnapshotPool(db)
                return try request.paginated(in: snapshot, pageSize: 50)
            }
            .eraseToAnyPublisher()
    }
}

struct PlayersView: View {
    @Query(PlayerRequest(ordering: .byScore), in: \.dbPool) var players
    
    var body: some View {
        NavigationStack {
            PlayerList(players: PaginatedResults(
                dataSource: players,
                prefetchStrategy: .infiniteScroll(minimumElementsAtBottom: 100)))
            .navigationTitle("Players")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToggleOrderingButton(ordering: $players.ordering)
                }
            }
        }
    }
}

struct PlayerList: View {
    @ObservedObject var players: PaginatedResults<Player, Player.ID>
    @State var presentsError: Bool = false
    
    var body: some View {
        List(players.elements) { paginatedPlayer in
            PlayerRow(player: paginatedPlayer.element)
                .fetchNextPageIfNeeded(from: paginatedPlayer)
        }
    }
}

private struct ToggleOrderingButton: View {
    @Binding var ordering: PlayerRequest.Ordering
    
    var body: some View {
        switch ordering {
        case .byName:
            Button {
                ordering = .byScore
            } label: {
                Label("Name", systemImage: "arrowtriangle.up.fill").labelStyle(.titleAndIcon)
            }
        case .byScore:
            Button {
                ordering = .byName
            } label: {
                Label("Score", systemImage: "arrowtriangle.down.fill").labelStyle(.titleAndIcon)
            }
        }
    }
}

struct PlayerRow: View {
    let player: Player
    
    var body: some View {
        HStack {
            Text(player.name)
            Spacer()
            Text("\(player.score) points")
                .foregroundStyle(.secondary)
        }
    }
}

//struct PlayersView_Previews: PreviewProvider {
//    static var previews: some View {
//        PlayersView()
//    }
//}
