import UIKit
import GRDB
import GRDBCollections

class ImmutableDatabasePoolPlayersViewController: UITableViewController {
    private var players: FetchedResults<Player>!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let request = Player.all().orderedByScore()
        players = try! DatabasePool.mutable.read { try request.fetchResults($0) }
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
        return cell
    }
}
