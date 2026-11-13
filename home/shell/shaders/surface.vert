#version 440
// Smoked glass for a rounded surface (components/Surface.qml), the vertex half: where each
// corner of the item falls on its screen, so the fragments know which part of what is
// behind them they see wherever the item has moved (a drawer sliding out moves its keys too).

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;

layout(location = 0) out vec2 qt_TexCoord0;
layout(location = 1) out vec2 screenUv;

// The same block as surface.frag's: Qt fills both from Surface.qml's properties.
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float ySign;        // -1 where y goes up in clip space (OpenGL), 1 where it goes down (Vulkan)
    float radius;       // corner radius, logical px
    float transmission; // what the smoke lets through of what is behind, for a dark tint
    float refraction;   // how far the bevel bends what is behind, logical px
    float bevel;        // how deep the bevel reaches in from the edge, logical px
    float rim;          // the glint on the edges facing the light
    float outline;      // 1: a border with no fill, only the rim
    float dim;          // what reaches the glass of what is behind (a dim between: less)
    float frost;        // how far the frosted face blurs what is behind, logical px
    float scatter;      // the light the frost spreads wide: bright dots glow through it
    float halo;         // the light the edge gathers from bright things near it
    float wobble;       // how far the face's unevenness shifts what is behind, logical px
    vec2 box;           // the item, logical px
    vec2 win;           // its window, logical px
    vec2 org;           // the window on its screen, logical px
    vec2 scr;           // the screen, logical px
    vec4 tint;          // the surface's colour
};

out gl_PerVertex { vec4 gl_Position; };

void main() {
    qt_TexCoord0 = qt_MultiTexCoord0;
    gl_Position = qt_Matrix * qt_Vertex;
    vec2 ndc = gl_Position.xy / gl_Position.w;
    vec2 inWindow = vec2(ndc.x * 0.5 + 0.5, ndc.y * 0.5 * ySign + 0.5) * win;
    screenUv = (org + inWindow) / scr;
}
