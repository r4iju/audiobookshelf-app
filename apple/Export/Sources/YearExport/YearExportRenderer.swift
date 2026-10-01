import UIKit

/// Draws with UIGraphicsImageRenderer and Core Graphics so exports work on iOS 14, where
/// SwiftUI's ImageRenderer is unavailable and offscreen hosting snapshots can come out blank.
public enum YearExportRenderer {
    public static func render(_ snapshot: YearExportSnapshot, layout: YearExportLayout) -> YearExportArtifact {
        let size = layout.shape.pixelSize
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let data = png(size: size) { context in
            let canvas = ListenerCanvas(context: context, size: size, snapshot: snapshot)
            canvas.background()
            switch (layout.design, layout.shape) {
            case (.highlights, .portrait): canvas.highlightsPortrait()
            case (.highlights, _): canvas.highlightsSquare()
            case (.finishedBooks, .portrait): canvas.finishedPortrait()
            case (.finishedBooks, _): canvas.finishedSquare()
            case (.topLists, .portrait): canvas.topListsPortrait()
            case (.topLists, _): canvas.topListsSquare()
            case (.compact, _): canvas.compactBanner()
            default: break
            }
        }
        let suffix: String
        switch (layout.design, layout.shape) {
        case (.compact, _): suffix = "_short"
        case (.highlights, .portrait): suffix = "_story"
        case (.finishedBooks, .portrait): suffix = "_finished_story"
        case (.finishedBooks, _): suffix = "_finished"
        case (.topLists, .portrait): suffix = "_top_story"
        case (.topLists, _): suffix = "_top"
        default: suffix = ""
        }
        return artifact(id: snapshot.id, year: snapshot.year, layout: layout, data: data,
                        fileName: "audiobookshelf_my_\(snapshot.year)\(suffix).png", shareText: snapshot.shareText)
    }

    public static func render(_ snapshot: YearExportServerSnapshot, layout: YearExportLayout) -> YearExportArtifact {
        let size = layout.shape.pixelSize
        let data = png(size: size) { context in
            let canvas = ServerCanvas(context: context, size: size, snapshot: snapshot)
            canvas.background()
            switch layout.design {
            case .serverAdditions: canvas.additions(portrait: layout.shape == .portrait)
            case .serverPeople: canvas.lists([("TOP AUTHORS", snapshot.topAuthors), ("TOP NARRATORS", snapshot.topNarrators)], portrait: layout.shape == .portrait)
            case .serverGenres: canvas.lists([("TOP AUTHORS", snapshot.topAuthors), ("TOP GENRES", snapshot.topGenres)], portrait: layout.shape == .portrait)
            default: break
            }
        }
        var suffix: String
        switch layout.design {
        case .serverPeople: suffix = "_people"
        case .serverGenres: suffix = "_genres"
        default: suffix = ""
        }
        if layout.shape == .portrait { suffix += "_story" }
        return artifact(id: snapshot.id, year: snapshot.year, layout: layout, data: data,
                        fileName: "audiobookshelf_server_\(snapshot.year)\(suffix).png", shareText: snapshot.shareText)
    }

    private static func png(size: CGSize, draw: (CGContext) -> Void) -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).pngData { draw($0.cgContext) }
    }

    private static func artifact(id: UUID, year: Int, layout: YearExportLayout, data: Data, fileName: String, shareText: String) -> YearExportArtifact {
        YearExportArtifact(
            snapshotID: id, year: year, layout: layout, pngData: data, fileName: fileName, shareText: shareText,
            accessibilityLabel: "\(layout.design.title) \(layout.shape.title.lowercased()) image. " + shareText.replacingOccurrences(of: "\n", with: ". ")
        )
    }
}

private struct ListenerCanvas: Canvas {
    let context: CGContext
    let size: CGSize
    let snapshot: YearExportSnapshot
    var year: Int { snapshot.year }
    var mosaic: [CGImage] { snapshot.mosaic }

    // MARK: Layouts

    func highlightsSquare() {
        header(y: 72)
        let width = (contentWidth - 24) / 2
        let cards = statCards(includeTime: true)
        for (index, card) in cards.enumerated() {
            let rect = CGRect(x: margin + CGFloat(index % 2) * (width + 24), y: 208 + CGFloat(index / 2) * 244, width: width, height: 220)
            statCard(card, in: rect)
        }
        let area = CGRect(x: margin, y: 720, width: contentWidth, height: 288)
        let facts = highlightFacts(includeLongest: false)
        guard snapshot.hasListening, !facts.isEmpty else { return emptyMessage(in: area) }
        for (index, fact) in facts.prefix(4).enumerated() {
            let rect = CGRect(x: margin + CGFloat(index % 2) * (width + 24), y: area.minY + CGFloat(index / 2) * 156, width: width, height: 132)
            factCell(fact, in: rect)
        }
    }

    func highlightsPortrait() {
        header(y: 112)
        let time = snapshot.listeningTime
        text("TIME LISTENING", font: font(28, .bold), color: Self.accent, in: CGRect(x: margin, y: 300, width: contentWidth, height: 36), kern: 4)
        text(time.value, font: fitted(time.value, size: 240, weight: .heavy, width: contentWidth), color: .white, in: CGRect(x: margin, y: 336, width: contentWidth, height: 280))
        text(time.unit, font: font(56, .semibold), color: Self.secondary, in: CGRect(x: margin, y: 610, width: contentWidth, height: 70))
        let cards = statCards(includeTime: false)
        let width = (contentWidth - 48) / 3
        for (index, card) in cards.enumerated() {
            statCard(card, in: CGRect(x: margin + CGFloat(index) * (width + 24), y: 740, width: width, height: 250), compact: true)
        }
        let area = CGRect(x: margin, y: 1060, width: contentWidth, height: 760)
        let facts = highlightFacts(includeLongest: true)
        guard snapshot.hasListening, !facts.isEmpty else { return emptyMessage(in: area) }
        for (index, fact) in facts.prefix(5).enumerated() {
            let rect = CGRect(x: margin, y: area.minY + CGFloat(index) * 152, width: contentWidth, height: 132)
            if index > 0 { divider(y: rect.minY - 10) }
            factCell(fact, in: rect)
        }
    }

    func topListsSquare() {
        header(y: 72)
        let cards = statCards(includeTime: true)
        let width = (contentWidth - 72) / 4
        for (index, card) in cards.enumerated() {
            statCard(card, in: CGRect(x: margin + CGFloat(index) * (width + 24), y: 208, width: width, height: 240), compact: true)
        }
        let lists = rankedLists()
        let columnWidth = (contentWidth - CGFloat(lists.count - 1) * 48) / CGFloat(max(lists.count, 1))
        for (index, list) in lists.enumerated() {
            rankedList(list.title, list.items, in: CGRect(x: margin + CGFloat(index) * (columnWidth + 48), y: 492, width: columnWidth, height: 536), rowHeight: 96)
        }
    }

    func topListsPortrait() {
        header(y: 112)
        let width = (contentWidth - 24) / 2
        for (index, card) in statCards(includeTime: true).enumerated() {
            statCard(card, in: CGRect(x: margin + CGFloat(index % 2) * (width + 24), y: 260 + CGFloat(index / 2) * 224, width: width, height: 200))
        }
        var y: CGFloat = 740
        for list in rankedLists() {
            let height = 56 + CGFloat(list.items.count) * 92
            rankedList(list.title, list.items, in: CGRect(x: margin, y: y, width: contentWidth, height: height), rowHeight: 92)
            y += height + 40
        }
    }

    /// Legacy variant 1: "Some books finished this year..." over the cover mosaic.
    func finishedSquare() {
        header(y: 72)
        let cards = statCards(includeTime: true)
        let width = (contentWidth - 72) / 4
        for (index, card) in cards.enumerated() {
            statCard(card, in: CGRect(x: margin + CGFloat(index) * (width + 24), y: 208, width: width, height: 240), compact: true)
        }
        text("SOME BOOKS FINISHED THIS YEAR", font: font(26, .bold), color: Self.accent, in: CGRect(x: margin, y: 492, width: contentWidth, height: 34), kern: 3)
        coverGrid(snapshot.finishedCovers, in: CGRect(x: margin, y: 548, width: contentWidth, height: 460))
    }

    func finishedPortrait() {
        header(y: 112)
        let width = (contentWidth - 24) / 2
        for (index, card) in statCards(includeTime: true).enumerated() {
            statCard(card, in: CGRect(x: margin + CGFloat(index % 2) * (width + 24), y: 260 + CGFloat(index / 2) * 224, width: width, height: 200))
        }
        text("SOME BOOKS FINISHED THIS YEAR", font: font(28, .bold), color: Self.accent, in: CGRect(x: margin, y: 760, width: contentWidth, height: 36), kern: 3)
        coverGrid(snapshot.finishedCovers, in: CGRect(x: margin, y: 820, width: contentWidth, height: 1000))
    }

    func compactBanner() {
        let headerWidth: CGFloat = 540
        header(y: 72, width: headerWidth)
        text(String(snapshot.year), font: font(150, .heavy), color: UIColor(white: 1, alpha: 0.12), in: CGRect(x: margin - 6, y: 250, width: headerWidth, height: 180))
        let cards = [
            StatCard(symbol: "checkmark.seal.fill", value: snapshot.number(snapshot.booksFinished), label: snapshot.booksFinished == 1 ? "book finished" : "books finished"),
            StatCard(symbol: "books.vertical.fill", value: snapshot.number(snapshot.booksListened), label: snapshot.booksListened == 1 ? "book listened to" : "books listened to")
        ]
        let x = margin + headerWidth + 24
        let width = (size.width - margin - x - 24) / 2
        for (index, card) in cards.enumerated() {
            statCard(card, in: CGRect(x: x + CGFloat(index) * (width + 24), y: 72, width: width, height: size.height - 144))
        }
    }

    // MARK: Content

    func statCards(includeTime: Bool) -> [StatCard] {
        let time = snapshot.listeningTime
        var cards = [
            StatCard(symbol: "checkmark.seal.fill", value: snapshot.number(snapshot.booksFinished), label: snapshot.booksFinished == 1 ? "book finished" : "books finished"),
            StatCard(symbol: "books.vertical.fill", value: snapshot.number(snapshot.booksListened), label: snapshot.booksListened == 1 ? "book listened to" : "books listened to"),
            StatCard(symbol: "headphones", value: snapshot.number(snapshot.sessions), label: snapshot.sessions == 1 ? "session" : "sessions")
        ]
        if includeTime { cards.insert(StatCard(symbol: "clock.fill", value: time.value, label: "\(time.unit) listening"), at: 1) }
        return cards
    }

    func highlightFacts(includeLongest: Bool) -> [Fact] {
        var facts: [Fact] = []
        if let value = snapshot.narrator { facts.append(Fact(title: "TOP NARRATOR", value: value.name, detail: snapshot.duration(value.seconds))) }
        if let value = snapshot.topGenres.first { facts.append(Fact(title: "TOP GENRE", value: value.name, detail: snapshot.duration(value.seconds))) }
        if let value = snapshot.topAuthors.first { facts.append(Fact(title: "TOP AUTHOR", value: value.name, detail: snapshot.duration(value.seconds))) }
        if let value = snapshot.month { facts.append(Fact(title: "TOP MONTH", value: value.name, detail: snapshot.duration(value.seconds))) }
        if includeLongest, let value = snapshot.longestBook { facts.append(Fact(title: "LONGEST BOOK FINISHED", value: value.name, detail: snapshot.duration(value.seconds))) }
        return facts
    }

    func rankedLists() -> [(title: String, items: [YearExportSnapshot.Ranked])] {
        [("TOP AUTHORS", snapshot.topAuthors), ("TOP GENRES", snapshot.topGenres)].filter { !$0.1.isEmpty }
    }

    func rankedList(_ title: String, _ items: [YearExportSnapshot.Ranked], in rect: CGRect, rowHeight: CGFloat) {
        rankedList(title, items.map { ($0.name, snapshot.duration($0.seconds)) }, in: rect, rowHeight: rowHeight)
    }

    func emptyMessage(in area: CGRect) {
        let rect = CGRect(x: area.minX, y: area.minY, width: area.width, height: min(area.height, 360))
        panel(rect)
        let inner = rect.insetBy(dx: 40, dy: 40)
        symbol("sparkles", color: Self.accent, in: CGRect(x: inner.midX - 32, y: inner.midY - 96, width: 64, height: 64))
        text("No listening recorded in \(snapshot.year)", font: font(40, .bold), color: .white, in: CGRect(x: inner.minX, y: inner.midY - 12, width: inner.width, height: 52), alignment: .center)
        text("Press play and your year will fill in here.", font: font(28, .regular), color: Self.secondary, in: CGRect(x: inner.minX, y: inner.midY + 46, width: inner.width, height: 72), alignment: .center, lines: 2)
    }
}

/// The legacy admin canvas: additions, collection growth, then covers or two name lists.
private struct ServerCanvas: Canvas {
    let context: CGContext
    let size: CGSize
    let snapshot: YearExportServerSnapshot
    var year: Int { snapshot.year }
    var mosaic: [CGImage] { snapshot.covers }

    func additions(portrait: Bool) {
        let y = top(portrait: portrait)
        let area = CGRect(x: margin, y: y, width: contentWidth, height: size.height - y - 72)
        let covers = Array(snapshot.covers.prefix(5))
        guard !covers.isEmpty else {
            let format = snapshot.format
            factCell(Fact(title: "IN YOUR LIBRARY", value: format.count(snapshot.libraryBooks, "book", "books"),
                          detail: "\(format.duration(snapshot.listeningSeconds)) listened this year"), in: CGRect(x: margin, y: y, width: contentWidth, height: 132))
            return
        }
        text("SOME ADDITIONS INCLUDE", font: font(portrait ? 28 : 26, .bold), color: Self.accent, in: CGRect(x: margin, y: area.minY, width: contentWidth, height: 36), kern: 3)
        coverGrid(covers, in: CGRect(x: margin, y: area.minY + 56, width: contentWidth, height: area.height - 56))
    }

    func lists(_ lists: [(title: String, items: [YearExportSnapshot.Ranked])], portrait: Bool) {
        var y = top(portrait: portrait)
        let lists = lists.filter { !$0.items.isEmpty }
        // Names only, as the legacy server canvas showed them.
        if portrait {
            for list in lists {
                let items = list.items.prefix(3).map { ($0.name, "") }
                let height = 56 + CGFloat(items.count) * 72
                rankedList(list.title, items, in: CGRect(x: margin, y: y, width: contentWidth, height: height), rowHeight: 72)
                y += height + 40
            }
        } else {
            let columnWidth = (contentWidth - CGFloat(lists.count - 1) * 48) / CGFloat(max(lists.count, 1))
            for (index, list) in lists.enumerated() {
                rankedList(list.title, list.items.prefix(3).map { ($0.name, "") },
                           in: CGRect(x: margin + CGFloat(index) * (columnWidth + 48), y: y, width: columnWidth, height: size.height - y - 72), rowHeight: 72)
            }
        }
    }

    /// Header, the three legacy boxes and the collection totals; returns where the variant starts.
    private func top(portrait: Bool) -> CGFloat {
        header(y: portrait ? 112 : 72, title: "\(snapshot.year) SERVER YEAR IN REVIEW")
        let format = snapshot.format
        let cards = [
            StatCard(symbol: "plus.square.on.square", value: format.number(Double(snapshot.booksAdded)), label: snapshot.booksAdded == 1 ? "book added" : "books added"),
            StatCard(symbol: "person.2.fill", value: format.number(Double(snapshot.authorsAdded)), label: snapshot.authorsAdded == 1 ? "author added" : "authors added"),
            StatCard(symbol: "headphones", value: format.number(Double(snapshot.sessions)), label: snapshot.sessions == 1 ? "session" : "sessions")
        ]
        let cardsY: CGFloat = portrait ? 260 : 208
        let width = (contentWidth - 48) / 3
        for (index, card) in cards.enumerated() {
            statCard(card, in: CGRect(x: margin + CGFloat(index) * (width + 24), y: cardsY, width: width, height: portrait ? 250 : 220), compact: true)
        }
        var facts: [Fact] = []
        if snapshot.collectionBytes > 0 || snapshot.addedBytes > 0 {
            facts.append(Fact(title: "COLLECTION GREW TO", value: format.bytes(snapshot.collectionBytes), detail: "+\(format.bytes(snapshot.addedBytes)) this year"))
        }
        if snapshot.collectionSeconds > 0 || snapshot.addedSeconds > 0 {
            facts.append(Fact(title: "TOTAL DURATION", value: format.longDuration(snapshot.collectionSeconds), detail: "+\(format.longDuration(snapshot.addedSeconds)) this year"))
        }
        var y = cardsY + (portrait ? 250 : 220) + 40
        if portrait {
            for (index, fact) in facts.enumerated() {
                if index > 0 { divider(y: y - 10) }
                factCell(fact, in: CGRect(x: margin, y: y, width: contentWidth, height: 132))
                y += 152
            }
        } else if !facts.isEmpty {
            let factWidth = (contentWidth - 24) / 2
            for (index, fact) in facts.enumerated() {
                factCell(fact, in: CGRect(x: margin + CGFloat(index) * (factWidth + 24), y: y, width: factWidth, height: 132))
            }
            y += 152
        }
        return y + (portrait ? 40 : 16)
    }
}

/// Shared drawing for both canvases. Covers arrive as decoded pixels only.
private protocol Canvas {
    var context: CGContext { get }
    var size: CGSize { get }
    var year: Int { get }
    var mosaic: [CGImage] { get }
}

private struct StatCard { let symbol: String; let value: String; let label: String }
private struct Fact { let title: String; let value: String; let detail: String }

extension Canvas {
    static var accent: UIColor { UIColor(red: 1, green: 0.86, blue: 0.44, alpha: 1) }
    static var secondary: UIColor { UIColor(white: 1, alpha: 0.68) }
    var margin: CGFloat { size.width > 1200 ? 64 : 72 }
    var contentWidth: CGFloat { size.width - margin * 2 }

    // MARK: Components

    func background() {
        let colors = [UIColor(red: 0.10, green: 0.08, blue: 0.07, alpha: 1).cgColor, UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1).cgColor] as CFArray
        let space = CGColorSpaceCreateDeviceRGB()
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width * 0.3, y: size.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        coverMosaic()
        glow(UIColor(red: 0.80, green: 0.62, blue: 0.29, alpha: 0.55), center: CGPoint(x: size.width * 0.95, y: size.height * 0.02), radius: max(size.width, size.height) * 0.75)
        glow(UIColor(red: 0.55, green: 0.27, blue: 0.13, alpha: 0.35), center: CGPoint(x: 0, y: size.height), radius: max(size.width, size.height) * 0.6)
    }

    func glow(_ color: UIColor, center: CGPoint, radius: CGFloat) {
        let colors = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    func header(y: CGFloat, width: CGFloat? = nil, title: String? = nil) {
        let width = width ?? contentWidth
        let badge = CGRect(x: margin, y: y, width: 96, height: 96)
        Self.accent.setFill()
        UIBezierPath(roundedRect: badge, cornerRadius: 26).fill()
        symbol("headphones", color: UIColor(white: 0.08, alpha: 1), in: badge.insetBy(dx: 20, dy: 20))
        let x = badge.maxX + 24
        text("audiobookshelf", font: font(40, .semibold), color: Self.accent, in: CGRect(x: x, y: y + 2, width: width - x + margin, height: 50))
        text(title ?? "\(year) YEAR IN REVIEW", font: font(28, .heavy), color: .white, in: CGRect(x: x, y: y + 54, width: width - x + margin, height: 36), kern: 3)
    }

    func statCard(_ card: StatCard, in rect: CGRect, compact: Bool = false) {
        panel(rect)
        let inset = rect.insetBy(dx: compact ? 24 : 32, dy: compact ? 24 : 30)
        let symbolSize: CGFloat = compact ? 40 : 52
        let symbolX = compact ? inset.minX : inset.maxX - symbolSize
        symbol(card.symbol, color: Self.accent, in: CGRect(x: symbolX, y: inset.minY, width: symbolSize, height: symbolSize))
        let labelFont = font(compact ? 24 : 30, .medium)
        let labelLines = compact ? 2 : 1
        let labelHeight = ceil(labelFont.lineHeight) * CGFloat(labelLines)
        let labelRect = CGRect(x: inset.minX, y: inset.maxY - labelHeight, width: inset.width, height: labelHeight)
        let valueFont = fitted(card.value, size: compact ? 64 : 84, weight: .bold, width: inset.width)
        let valueRect = CGRect(x: inset.minX, y: labelRect.minY - valueFont.lineHeight, width: inset.width, height: valueFont.lineHeight)
        text(card.value, font: valueFont, color: .white, in: valueRect)
        text(card.label, font: labelFont, color: Self.secondary, in: labelRect, lines: labelLines)
    }

    func factCell(_ fact: Fact, in rect: CGRect) {
        text(fact.title, font: font(24, .bold), color: Self.accent, in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 30), kern: 3)
        text(fact.value, font: font(42, .bold), color: .white, in: CGRect(x: rect.minX, y: rect.minY + 36, width: rect.width, height: 54))
        text(fact.detail, font: font(26, .regular), color: Self.secondary, in: CGRect(x: rect.minX, y: rect.minY + 94, width: rect.width, height: 34))
    }

    func rankedList(_ title: String, _ items: [(name: String, detail: String)], in rect: CGRect, rowHeight: CGFloat) {
        text(title, font: font(26, .bold), color: Self.accent, in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 34), kern: 3)
        for (index, item) in items.prefix(5).enumerated() {
            let row = CGRect(x: rect.minX, y: rect.minY + 56 + CGFloat(index) * rowHeight, width: rect.width, height: rowHeight - 12)
            text("\(index + 1)", font: font(40, .heavy), color: Self.accent.withAlphaComponent(0.85), in: CGRect(x: row.minX, y: row.minY + 4, width: 52, height: 50))
            let textRect = CGRect(x: row.minX + 60, y: row.minY, width: row.width - 60, height: row.height)
            text(item.name, font: font(38, .bold), color: .white, in: CGRect(x: textRect.minX, y: textRect.minY, width: textRect.width, height: 50))
            if !item.detail.isEmpty {
                text(item.detail, font: font(24, .regular), color: Self.secondary, in: CGRect(x: textRect.minX, y: textRect.minY + 50, width: textRect.width, height: 32))
            }
        }
    }

    /// Up to five covers as center-cropped rounded squares, sized to fill `rect` and centered.
    func coverGrid(_ covers: [CGImage], in rect: CGRect, spacing: CGFloat = 24) {
        let covers = Array(covers.prefix(5))
        guard !covers.isEmpty else { return }
        var best = (columns: 1, side: CGFloat(0))
        for columns in 1...covers.count {
            let rows = CGFloat((covers.count + columns - 1) / columns)
            let side = min((rect.width - CGFloat(columns - 1) * spacing) / CGFloat(columns), (rect.height - (rows - 1) * spacing) / rows)
            if side > best.side { best = (columns, side) }
        }
        let side = floor(min(best.side, 420))
        for (index, cover) in covers.enumerated() {
            let row = index / best.columns
            let inRow = min(best.columns, covers.count - row * best.columns)
            let rowWidth = CGFloat(inRow) * side + CGFloat(inRow - 1) * spacing
            let x = rect.midX - rowWidth / 2 + CGFloat(index % best.columns) * (side + spacing)
            let tile = CGRect(x: x, y: rect.minY + CGFloat(row) * (side + spacing), width: side, height: side)
            context.saveGState()
            let path = UIBezierPath(roundedRect: tile, cornerRadius: 20)
            path.addClip()
            draw(cover, filling: tile)
            context.restoreGState()
            UIColor(white: 1, alpha: 0.18).setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }

    /// The legacy background: a 5 x 5 cover wall rotated -25 degrees at low opacity, under a scrim.
    func coverMosaic() {
        guard !mosaic.isEmpty else { return }
        let tile = size.width * 215 / 800
        let extent = (size.width * size.width + size.height * size.height).squareRoot()
        let count = Int((extent / tile).rounded(.up)) + 1
        context.saveGState()
        context.translateBy(x: size.width / 2, y: size.height / 2)
        context.rotate(by: -25 * .pi / 180)
        let start = -CGFloat(count) * tile / 2
        for row in 0..<count {
            for column in 0..<count {
                draw(mosaic[(row * count + column) % mosaic.count], filling: CGRect(x: start + CGFloat(column) * tile, y: start + CGFloat(row) * tile, width: tile, height: tile), alpha: 0.25)
            }
        }
        context.restoreGState()
        UIColor(white: 0, alpha: 0.3).setFill()
        UIRectFillUsingBlendMode(CGRect(origin: .zero, size: size), .normal)
    }

    /// Center-crops `image` to the aspect of `rect`, drawn upright in UIKit coordinates.
    func draw(_ image: CGImage, filling rect: CGRect, alpha: CGFloat = 1) {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let scale = max(rect.width / width, rect.height / height)
        let crop = CGRect(x: (width - rect.width / scale) / 2, y: (height - rect.height / scale) / 2, width: rect.width / scale, height: rect.height / scale).integral
        UIImage(cgImage: image.cropping(to: crop) ?? image).draw(in: rect, blendMode: .normal, alpha: alpha)
    }

    func panel(_ rect: CGRect) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 36)
        UIColor(white: 1, alpha: 0.07).setFill()
        path.fill()
        UIColor(white: 1, alpha: 0.14).setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    func divider(y: CGFloat) {
        UIColor(white: 1, alpha: 0.12).setFill()
        UIRectFillUsingBlendMode(CGRect(x: margin, y: y, width: contentWidth, height: 2), .normal)
    }

    // MARK: Primitives

    func font(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: rounded, size: size)
    }

    func fitted(_ string: String, size: CGFloat, weight: UIFont.Weight, width: CGFloat) -> UIFont {
        var candidate = font(size, weight)
        while candidate.pointSize > size * 0.4, (string as NSString).size(withAttributes: [.font: candidate]).width > width {
            candidate = font(candidate.pointSize - 4, weight)
        }
        return candidate
    }

    func text(_ string: String, font: UIFont, color: UIColor, in rect: CGRect, alignment: NSTextAlignment = .left, lines: Int = 1, kern: CGFloat = 0) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph, .kern: kern]
        let bounded = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(rect.height, font.lineHeight * CGFloat(lines) + 1))
        NSAttributedString(string: string, attributes: attributes).draw(with: bounded, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }

    func symbol(_ name: String, color: UIColor, in rect: CGRect) {
        let configuration = UIImage.SymbolConfiguration(pointSize: rect.height, weight: .semibold)
        guard let image = UIImage(systemName: name, withConfiguration: configuration)?.withTintColor(color, renderingMode: .alwaysOriginal) else { return }
        let scale = min(rect.width / image.size.width, rect.height / image.size.height)
        let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2, width: fitted.width, height: fitted.height))
    }
}
