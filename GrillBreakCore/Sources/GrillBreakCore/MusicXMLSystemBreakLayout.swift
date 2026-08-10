import Foundation

/// Inserts MusicXML `print new-system` markers so Verovio can engrave a fixed
/// number of measures per system when `breaks` is `"encoded"`.
///
/// Also strips imported page-layout / measure widths that make Verovio's
/// auto-breaks pack the wrong number of bars per system (e.g. Audiveris 5+3).
public enum MusicXMLSystemBreakLayout {
    public static let measuresPerSystem = 4

    /// Page width in Verovio units sized for four measures; CSS then scales
    /// the SVG up to fill the Staff Melody scene.
    public static let pageWidth = 1200

    public static func applying(measuresPerSystem: Int, to musicXML: String) throws -> String {
        precondition(measuresPerSystem > 0)
        let document = try XMLDocument(
            xmlString: musicXML,
            options: [.nodeLoadExternalEntitiesNever]
        )
        guard let root = document.rootElement() else { return musicXML }

        stripPageLayout(from: root)

        let measureGroups: [[XMLElement]]
        if root.name == "score-timewise" {
            measureGroups = [root.elements(forName: "measure")]
        } else {
            measureGroups = root.elements(forName: "part").map { $0.elements(forName: "measure") }
        }

        for measures in measureGroups {
            for (index, measure) in measures.enumerated() {
                measure.removeAttribute(forName: "width")
                stripNewSystemPrints(from: measure)
                if index > 0 && index % measuresPerSystem == 0 {
                    let printElement = XMLElement(name: "print")
                    printElement.setAttributesWith(["new-system": "yes"])
                    measure.insertChild(printElement, at: 0)
                }
            }
        }

        return document.xmlString
    }

    private static func stripPageLayout(from root: XMLElement) {
        for defaults in root.elements(forName: "defaults") {
            for pageLayout in defaults.elements(forName: "page-layout") {
                pageLayout.detach()
            }
            if (defaults.children ?? []).isEmpty && (defaults.attributes ?? []).isEmpty {
                defaults.detach()
            }
        }
    }

    private static func stripNewSystemPrints(from measure: XMLElement) {
        for printElement in measure.elements(forName: "print") {
            guard printElement.attribute(forName: "new-system")?.stringValue == "yes" else {
                continue
            }
            printElement.removeAttribute(forName: "new-system")
            let attrs = printElement.attributes ?? []
            let children = printElement.children ?? []
            if attrs.isEmpty && children.isEmpty {
                printElement.detach()
            }
        }
    }
}
