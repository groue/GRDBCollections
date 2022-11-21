# ``GRDBCollections``

Collections for dealing with large database results 

## Overview

Fetching large results from database to memory is not always practical or possible. This package comes with two types that help dealing with this situation:

- ``FetchedResults`` is suited for UIKit data sources and lazy SwiftUI containers. It is a collection that delays database accesses until the application needs elements, and limits the number of elements in memory.
- ``PaginatedResults`` is suited for the `List` SwiftUI container. It is an `ObservableObject` that fetches pages of elements as the application needs them. It does not limit the number of elements in memory.

The package also comes with a generic pagination system that may be reused in other circumstances.  

## Topics

### Lazy Database Requests

- ``FetchedResults``

### Paginated Database Requests

- ``PaginatedResults``
- ``PaginatedRequest``
