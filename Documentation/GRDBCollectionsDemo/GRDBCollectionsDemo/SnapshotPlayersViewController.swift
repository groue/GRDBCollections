import UIKit
import GRDB
import GRDBCollections

class SnapshotPlayersViewController: UITableViewController {
    private var players: FetchedResults<Player>!
    private var cancellable: AnyDatabaseCancellable?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        cancellable = ValueObservation
            .trackingConstantRegion { db in
                let request = Player.all().orderedByScore()
                try db.registerAccess(to: request)
                let snapshot = try DatabaseSnapshotPool(db)
                return try request.fetchResults(in: snapshot)
            }
            .start(
                in: DatabasePool.shared,
                scheduling: .immediate,
                onError: { error in
                    fatalError("\(error)")
                }, onChange: { [weak self] players in
                    guard let self else { return }
                    self.players = players
                    self.tableView.reloadData()
                })
        
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            try! DatabasePool.shared.write { db in
                let maxScore = try Player.maxScore.fetchOne(db) ?? 0
                _ = try Player(name: Player.randomName(), score: maxScore + 1).inserted(db)
            }
        }
    }

    // MARK: - Table view data source

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        players.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Player", for: indexPath)
        let player = players[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = player.name
        config.secondaryText = "\(player.score)"
        cell.contentConfiguration = config
        cell.selectionStyle = .none
        return cell
    }
}
