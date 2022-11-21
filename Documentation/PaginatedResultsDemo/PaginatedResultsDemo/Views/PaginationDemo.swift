import Combine
import GRDBCollections
import SwiftUI
import os.log

struct Item: Identifiable {
    var id: Int
    var name: String
}

struct DemoDataSource: PaginationDataSource {
    var firstPageIdentifier: Int { 0 }
    
    /// The number of pages
    var pageCount: Int
    
    /// The number of items per page
    var pageSize: Int
    
    /// The number of items with a reused id in a page
    var overlap: Int
    
    /// The delay before the page is produced
    var delay: Duration
    
    /// A closure that can prevent the page from being produced by throwing an error
    var check: (() throws -> Void)?
    
    func page(at pageIdentifier: Int) async throws -> Page<Item, Int> {
        try await Task.sleep(for: delay)
        try check?()
        let elements = (0..<pageSize).map { index in
            let id = pageIdentifier * (pageSize - overlap) + index
            return Item(id: id, name: "Page \(pageIdentifier) / Item \(index)")
        }
        return Page(
            elements: elements,
            nextPageIdentifier: (pageIdentifier + 1) >= pageCount ? nil : pageIdentifier + 1)
    }
}

struct PaginationDemoList: View {
    enum DemoCase: CaseIterable, Equatable, Hashable {
        case fast
        case slowOverlap
        case slowAndFlaky
        
        var localizedName: LocalizedStringKey {
            switch self {
            case .fast: return "Fast"
            case .slowOverlap: return "Slow + Overlap"
            case .slowAndFlaky: return "Slow And Flaky"
            }
        }
        
        @MainActor
        var results: PaginatedResults<Item, Item.ID> {
            switch self {
            case .fast:
                return PaginatedResults(
                    dataSource: DemoDataSource(
                        pageCount: 20,
                        pageSize: 50,
                        overlap: 0,
                        delay: .milliseconds(100)),
                    prefetchStrategy: .infiniteScroll(minimumElementsAtBottom: 50))
                
            case .slowOverlap:
                return PaginatedResults(
                    dataSource: DemoDataSource(
                        pageCount: 6,
                        pageSize: 10,
                        overlap: 2,
                        delay: .seconds(1)),
                    prefetchStrategy: .infiniteScroll(minimumElementsAtBottom: 5))
                
            case .slowAndFlaky:
                return PaginatedResults(
                    dataSource: DemoDataSource(
                        pageCount: 6,
                        pageSize: 5,
                        overlap: 0,
                        delay: .seconds(1),
                        check: {
                            if Bool.random() {
                                throw URLError(.notConnectedToInternet)
                            }
                        }),
                    prefetchStrategy: .infiniteScroll(minimumElementsAtBottom: 5))
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            List(DemoCase.allCases, id: \.self) { demoCase in
                NavigationLink(demoCase.localizedName, value: demoCase)
            }
            .navigationDestination(for: DemoCase.self) { demoCase in
                PaginationDemoView(results: demoCase.results)
                    .navigationTitle(demoCase.localizedName)
            }
            .navigationTitle("Pagination Demos")
        }
    }
}

struct PaginationDemoView: View {
    @StateObject var results: PaginatedResults<Item, Item.ID>
    @State var presentsError: Bool = false
    
    var body: some View {
        List {
            Section {
                ForEach(results.elements) { paginatedItem in
                    ItemRow(item: paginatedItem.element)
                        .fetchNextPageIfNeeded(from: paginatedItem)
                }
            } footer: {
                switch results.state {
                case .loadingNextPage:
                    loadingView
                case .completed:
                    completedView
                case .notCompleted:
                    loadNextPageButton
                }
            }
        }
        .listStyle(.grouped)
        
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
        } message: { error in
            Text(error.localizedDescription)
        }
        
        .toolbar {
            if results.isLoadingPage {
                ProgressView().progressViewStyle(.circular)
            }
            
            Button {
                Task {
                    do {
                        try await results.removeAllAndRefresh()
                    } catch {
                        presentsError = true
                    }
                }
            } label: { Text("Refresh") }
        }
    }
    
    var completedView: some View {
        Text("End of List")
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .center)
            .foregroundStyle(.secondary)
    }
    
    var loadingView: some View {
        Text("Loading…")
            .font(.callout)
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
            VStack(alignment: .center) {
                if let error = results.error {
                    Text(error.localizedDescription)
                        .multilineTextAlignment(.leading)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .foregroundColor(.primary)
                        .padding(.bottom, 4)
                }
                Text("Load Next Page")
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
    func retryButton(from error: PaginationError) -> some View {
        Button {
            Task {
                do {
                    try await results.retry(from: error)
                } catch {
                    presentsError = true
                }
            }
        } label: { Text("Retry") }
    }
}

struct ItemRow: View {
    let item: Item
    
    var body: some View {
        HStack {
            Text(item.name)
            Spacer()
            Text("ID \(item.id)")
                .foregroundStyle(.secondary)
        }
    }
}
