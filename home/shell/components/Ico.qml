import QtQuick
import qs.theme

// A single Nerd Font glyph. Nerd Font icons overflow their advance width and
// sit off the middle of the line, so a centred text box leaves them
// off-centre (very visible inside a circle). Ico keeps the box a plain text of
// the glyph would have, so layouts don't move, and draws the glyph with its
// visible shape in the middle of that box.
Item {
    id: root

    property string glyph: ""
    property alias color: label.color
    property alias font: label.font

    implicitWidth: ink.advanceWidth
    implicitHeight: line.height

    TextMetrics {
        id: ink
        font: label.font
        text: root.glyph
    }

    FontMetrics {
        id: line
        font: label.font
    }

    Text {
        id: label

        // tightBoundingRect is relative to the pen origin on the baseline.
        x: root.width / 2 - (ink.tightBoundingRect.x + ink.tightBoundingRect.width / 2)
        y: root.height / 2 - (line.ascent + ink.tightBoundingRect.y + ink.tightBoundingRect.height / 2)
        text: root.glyph
        color: Tokens.dim
        font.family: Tokens.fontIcons
        font.pixelSize: 16

        Behavior on color { ColorAnimation { duration: Tokens.animFast } }
    }
}
