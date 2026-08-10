import Foundation

/// Inserts MusicXML `print new-system` markers so Verovio can engrave a fixed
/// number of measures per system when `breaks` is `"encoded"`.
public enum MusicXMLSystemBreakLayout {
    public static let measuresPerSystem = 4

    public static func applying(measuresPerSystem: Int, to musicXML: String) throws -> String {
        precondition(measuresPerSystem > 0)
        let document = try XMLDocument(xmlString: musicXML, options: [])
        guard let root = document.rootElement() else { return musicXML }

        let measureGroups: [[XMLElement]]
        if root.name == "score-timewise" {
            measureGroups = [root.elements(forName: "measure")]
        } else {
            measureGroups = root.elements(forName: "part").map { $0.elements(forName: "measure") }
        }

        for measures in measureGroups {
            for (index, measure) in measures.enumerated() {
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
