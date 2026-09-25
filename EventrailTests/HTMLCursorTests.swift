import Testing
@testable import Eventrail

struct HTMLCursorTests {
    @Test func advanceStaysPutWhenTheMarkerIsMissing() {
        var cursor = HTMLCursor("<a>one</a><b>two</b>")
        let found = cursor.advance(past: "<b>")
        let missing = cursor.advance(past: "<c>")
        #expect(found)
        #expect(!missing)
        // A missing block must not move the cursor on to a later record.
        #expect(cursor.take(upTo: "</b>") == "two")
    }

    @Test func textReadsBetweenMarkersAndDropsTags() {
        var cursor = HTMLCursor(#"<div class="t"><p> Hello <em>world</em> </p></div>"#)
        #expect(cursor.text(after: #"<div class="t">"#, upTo: "</div>") == "Hello world")
    }

    @Test func textIsNilWhenTheElementIsEmpty() {
        var cursor = HTMLCursor(#"<p class="t">  </p>"#)
        #expect(cursor.text(after: #"<p class="t">"#, upTo: "</p>") == nil)
    }

    @Test func slicesSplitAtEachMarker() {
        let cursor = HTMLCursor("head<li>a</li><li>b</li><li>c</li>")
        let rows = cursor.slices(startingAt: "<li>").map(String.init)
        #expect(rows == ["<li>a</li>", "<li>b</li>", "<li>c</li>"])
    }

    @Test func slicesAreEmptyWithoutTheMarker() {
        #expect(HTMLCursor("<ul></ul>").slices(startingAt: "<li>").isEmpty)
    }

    @Test(arguments: [
        ("A &amp; B", "A & B"),
        ("&lt;tag&gt;", "<tag>"),
        ("&quot;q&quot; &apos;a&apos;", "\"q\" 'a'"),
        ("&#12354;&#x3044;", "あい"),
        ("I &hearts; live", "I \u{2665} live"),
        ("Rock & Roll", "Rock & Roll"),
        ("&unknown; &", "&unknown; &"),
    ])
    func decodesEntities(source: String, decoded: String) {
        #expect(HTMLEntities.decode(source) == decoded)
    }

    @Test func htmlTextTrimsAndDecodes() {
        #expect("  <b>水瀬いのり</b>&amp;<i>X</i>\n".htmlText == "水瀬いのり&X")
    }
}
