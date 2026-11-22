# Design

## Idea

Diogenes lived in a jar and walked with a lantern looking for what matters. Dyogène is the
lantern you hold over your hoard. Everything in the identity comes from that scene: a night
(deep indigo, never flat black), one warm light (lantern amber), and the jar's content going
from fresh (patina teal) to forgotten (dust sand).

## Tokens

| Name | Hex | Use |
| --- | --- | --- |
| Night indigo | `#1C2140` | dark canvas, icon plate |
| Lantern amber | `#F2B33D` | the one accent: selection, focus, primary action |
| Glow | `#FFE6A8` | the lantern light on hovered tiles |
| Patina teal | `#4E8C84` | fresh, recently used |
| Dust sand | `#B9AE9C` | old, forgotten |
| Marble | `#EEEAE3` | light canvas |

Danger red appears only inside removal sheets. Type: New York (system serif) for titles and big
figures, SF Pro with monospaced digits for data. No bundled fonts.

## The map

- Area is size: easiest comparison there is.
- Dust is a log scale from today to three years. A folder is as fresh as its freshest file, so
  a dusty folder really was left alone. Unknown dates count as fresh (no accusation without
  evidence). Old tiles get grain, so dust also reads without colour vision.
- Containers are darker than their children so the gaps read as structure.
- One orchestrated motion: zooming (the new map grows out of the clicked tile, or pulls back
  out of it), plus the lantern looking around while scanning. Reduce Motion turns both off.
- The cursor lights the tile under it from the cursor's position, and in dark mode the rest of
  the map dims a little: holding a lantern.

## Removal

Destructive actions are never one click and never the first menu item. The sheet says exactly
what happens; Cancel is the default button; the confirm button fills while held. The Trash
comes first, with Put Back afterwards.

## The character

**Dyogène, the old sage.** After Diogenes, who lived in a jar and walked in daylight with a
lantern "looking for a man". A bald dome with a shine, white tufts over the ears, a long cloud
of a beard (never combed), bushy brows, warm cheeks, a teal robe with a sand fold, and a lantern
held up in his right hand.

- **Quirk:** his left eyebrow always sits a little higher. Curious lifts it further. Never make
  him frown or scold: he is wry, never mean.
- **Expressions** (`DyogeneExpression`): calm, curious, pleased (eyes closed in a smile),
  searching (eyes to his lantern, while scanning). Picked from what he looks at, never animated
  in a loop: no timer, no redraw while idle.
- **Voice** (`Remark` in Core): short lines in New York italic, in a speech bubble. Built from
  metadata only (size, age, kind, flags). He asks ("Treasure, or habit?"), he never decides.
- **Where:** welcome screen (introduces himself), the inspector (one remark about the selection),
  the scan overlay (searching), the Suspects header. Nowhere else: the map stays the map.
- **Drawing:** `DyogeneArt`, plain Core Graphics on a 100-point grid, fixed colours (he looks the
  same in light and dark mode, like a figure painted on a jar). Below 40 pt he drops strands,
  catchlights, smile lines and the flame. The icon renderer compiles the same file.
- **The icon:** he stands in his jar, only head and lantern above the rim; the jar's body is the
  treemap, fresh teal at the top, dust at the bottom.
