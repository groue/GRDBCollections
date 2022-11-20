import Combine
import GRDBCollections
import SwiftUI
import os.log

struct Player: Identifiable {
    var id: Int
    var name: String
}

struct DataSource: PaginationDataSource {
    var firstPageIdentifier: Int { 0 }
    var pageCount: Int
    var pageSize: Int
    var delay: Duration
    var success: () -> Bool
    
    func page(at pageIdentifier: Int) async throws -> Page<Player, Int> {
        try await Task.sleep(for: delay)
        if success() {
            let elements = (0..<pageSize).map {
                let id = Int.random(in: 0...1000)
                return Player(id: id, name: "Page \(pageIdentifier) - Item \($0)")
            }
            return Page(
                elements: elements,
                nextPageIdentifier: (pageIdentifier + 1) >= pageCount ? nil : pageIdentifier + 1)
        } else {
            throw URLError(.notConnectedToInternet)
        }
    }
}

struct ContentView: View {
    // Fast
    @StateObject var results = PaginatedResults(
        dataSource: DataSource(
            pageCount: 20,
            pageSize: 50,
            delay: .milliseconds(100),
            success: { true }),
        prefetchStrategy: .minimumElementsAtBottom(50))
    
//    // Slow
//    @StateObject var results = PaginatedResults(
//        dataSource: DataSource(
//            pageCount: 20,
//            pageSize: 5,
//            delay: .seconds(1),
//            success: { true }),
//        prefetchStrategy: .noPrefetch)
//        prefetchStrategy: .minimumElements(6))
//        prefetchStrategy: .minimumElementsAtBottom(10))
//
//    // Slow and Flaky
//    @StateObject var results = PaginatedResults(
//        dataSource: DataSource(
//            pageCount: 20,
//            pageSize: 5,
//            delay: .seconds(1),
//            success: { Bool.random() }),
//        prefetchStrategy: .minimumElementsAtBottom(10))

    @State var presentsError: Bool = false
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollView in
                List {
                    ForEach(results.elements) { paginatedElement in
                        PlayerRow(player: paginatedElement.element)
                            .onAppear(perform: paginatedElement.prefetchIfNeeded)
                            .id(paginatedElement.id)
                    }
                    
                    switch results.state {
                    case .loading:
                        loadingView
                    case .completed:
                        EmptyView()
                    case .notCompleted:
                        loadNextPageButton
                    }
                }
                .refreshable {
                    do {
                        try await results.refresh()
                    } catch {
                        presentsError = true
                    }
                }
                .alert("An Error Occurred", isPresented: $presentsError, presenting: results.error) { error in
                    Button(role: .cancel) { } label: { Text("Cancel") }
                    retryButton(from: error)
                } message: { Text($0.localizedDescription) }
                .navigationTitle("Players")
                .toolbar {
                    Button {
                        Task {
                            do {
                                try await results.refresh()
                                if let id = results.elements.first?.id {
                                    scrollView.scrollTo(id)
                                }
                            } catch {
                                presentsError = true
                            }
                        }
                    } label: { Text("Refresh") }
                }
            }
        }
    }
    
    var loadingView: some View {
        Text("Loading…")
            .frame(maxWidth: .infinity, alignment: .center)
            .foregroundStyle(.secondary)
    }
    
    var loadNextPageButton: some View {
        Button {
            Task {
                do {
                    try await results.fetchNextPage()
                } catch {
                    presentsError = true
                }
            }
        } label: {
            Text("Load Next Page")
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
    func retryButton(from error: PaginationError) -> some View {
        Button {
            Task {
                switch error {
                case .refresh:
                    do {
                        try await results.refresh()
                    } catch {
                        presentsError = true
                    }
                case .nextPage:
                    do {
                        try await results.fetchNextPage()
                    } catch {
                        presentsError = true
                    }
                }
            }
        } label: { Text("Retry") }
    }
}

struct PlayerRow: View {
    let player: Player
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(player.name)
            Text("\(player.id)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
