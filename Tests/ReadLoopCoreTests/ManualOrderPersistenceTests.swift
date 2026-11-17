import Foundation
import LibraryCore
import Persistence
import Testing

/// The shelf's manual order is stored per book; a swap rewrites only the two
/// books involved, and a book that was never dragged keeps a nil order.
@Test func manualOrderRoundTripsAndOnlyTouchesSwappedBooks() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)

    let first = Book(fingerprint: .init(rawValue: "manual-1"), title: "第一本", fileName: "1.epub", fileSize: 1)
    let second = Book(fingerprint: .init(rawValue: "manual-2"), title: "第二本", fileName: "2.epub", fileSize: 1)
    let third = Book(fingerprint: .init(rawValue: "manual-3"), title: "第三本", fileName: "3.epub", fileSize: 1)
    let untouched = Book(fingerprint: .init(rawValue: "manual-4"), title: "没拖过", fileName: "4.epub", fileSize: 1)

    for (index, book) in [first, second, third].enumerated() {
        try await books.insert(book)
        try await books.updateManualOrder([book.id: index])
    }
    try await books.insert(untouched)

    // Swap the first and the third; the middle book must not move.
    try await books.updateManualOrder([first.id: 2, third.id: 0])

    let storedFirst = try await books.book(id: first.id)
    let storedSecond = try await books.book(id: second.id)
    let storedThird = try await books.book(id: third.id)
    let storedUntouched = try await books.book(id: untouched.id)

    #expect(storedFirst?.manualOrder == 2)
    #expect(storedThird?.manualOrder == 0)
    #expect(storedSecond?.manualOrder == 1)

    if let order = storedUntouched?.manualOrder {
        Issue.record("未拖过的书不该有顺序：\(order)")
    }
}
