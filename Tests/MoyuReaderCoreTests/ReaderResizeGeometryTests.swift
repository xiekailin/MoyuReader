import Testing
@testable import MoyuReaderCore

@Suite("Reader resize geometry")
struct ReaderResizeGeometryTests {
    @Test("detects resize edges and corners")
    func detectsResizeEdgesAndCorners() {
        #expect(ReaderResizeGeometry.edge(
            at: .init(x: 4, y: 196),
            in: (width: 300, height: 200),
            threshold: 12
        ) == .topLeft)

        #expect(ReaderResizeGeometry.edge(
            at: .init(x: 296, y: 4),
            in: (width: 300, height: 200),
            threshold: 12
        ) == .bottomRight)

        #expect(ReaderResizeGeometry.edge(
            at: .init(x: 150, y: 4),
            in: (width: 300, height: 200),
            threshold: 12
        ) == .bottom)

        #expect(ReaderResizeGeometry.edge(
            at: .init(x: 150, y: 100),
            in: (width: 300, height: 200),
            threshold: 12
        ) == nil)
    }

    @Test("resizes from right and top edges")
    func resizesFromRightAndTopEdges() {
        let original = ReaderResizeGeometry.Rect(x: 10, y: 20, width: 300, height: 200)

        let resized = ReaderResizeGeometry.resizedFrame(
            original: original,
            edge: .topRight,
            delta: .init(x: 50, y: 40),
            minimumSize: (width: 180, height: 90)
        )

        #expect(resized == .init(x: 10, y: 20, width: 350, height: 240))
    }

    @Test("resizes from left and bottom while preserving opposite edges")
    func resizesFromLeftAndBottom() {
        let original = ReaderResizeGeometry.Rect(x: 10, y: 20, width: 300, height: 200)

        let resized = ReaderResizeGeometry.resizedFrame(
            original: original,
            edge: .bottomLeft,
            delta: .init(x: 40, y: 50),
            minimumSize: (width: 180, height: 90)
        )

        #expect(resized == .init(x: 50, y: 70, width: 260, height: 150))
    }

    @Test("resizing honors minimum size")
    func resizingHonorsMinimumSize() {
        let original = ReaderResizeGeometry.Rect(x: 10, y: 20, width: 300, height: 200)

        let resized = ReaderResizeGeometry.resizedFrame(
            original: original,
            edge: .bottomLeft,
            delta: .init(x: 400, y: 400),
            minimumSize: (width: 180, height: 90)
        )

        #expect(resized == .init(x: 130, y: 130, width: 180, height: 90))
    }
}
