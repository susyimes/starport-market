# Starport Market visual system

Starport Market is a calm trading instrument floating over a loud alien night
market. The interface stays structured and readable; the stall, customers,
signage, and tiny ambient motion carry the life of the world.

This production guide was curated by Codex after a Kimi K3 ACP art-direction
review (`session_f3aac242-2bf1-48fe-a548-51853664cc03`) and direct comparison
against deterministic Pyxel captures. The implementation remains code-native
and uses Pyxel's default 16-color palette.

## Color semantics

| Token | Index | Meaning |
| --- | ---: | --- |
| `INK` / `NIGHT` | 0 / 1 | Background, card surfaces, deepest shadow |
| `PLUM` | 2 | Selected rows and recessed interactive depth |
| `MOSS` | 3 | Stable and organic secondary accents |
| `RUST` / `ORANGE` | 4 / 9 | Physical stall materials and spoilage warnings |
| `SLATE` / `STEEL` | 5 / 6 | Inactive structure and neutral information |
| `PAPER` | 7 | Primary readable text |
| `DANGER` | 8 | Losses, blocking errors, stockouts |
| `AMBER` | 10 | Credits and commercial value |
| `MINT` | 11 | Profit, completed sales, positive outcomes |
| `CYAN` | 12 | Navigation, focus, and player action |
| `MUTED` | 13 | Labels, hints, disabled content |
| `MAGENTA` | 14 | Market signals, demand, reputation, promotion |
| `PEACH` | 15 | Rare warm highlights and eye glints |

Do not casually swap semantic colors. A player should recognize money, gain,
danger, and interaction before reading a label.

## Component rules

- Cards use a dark fill, two-pixel offset shadow, quiet slate border, and one
  colored top highlight. The top highlight owns the card's semantic accent.
- Focused table rows use a plum fill, cyan left rail, and visible cursor. Zebra
  striping may use `NIGHT`, never another semantic color.
- Small sprites use an outline plus at most three values. Their silhouette must
  survive at native 1x scale.
- Primary actions use cyan or amber keycaps. Magenta is reserved for market
  signals and promotion, not generic decoration.
- Body copy is `PAPER`; labels and hints are `MUTED` or `STEEL`. Text never
  relies on animation to remain legible.

## Screen hierarchy

| Screen | Primary read | Secondary read | Living layer |
| --- | --- | --- | --- |
| Title | Logo and `SPACE` action | 18-night promise and guide | Stall, M0X, customers, orbital traffic |
| Planning | Selected good and order/price | Signal, budget, campaign, upgrade | Focus pulse and product idle frames |
| Report | Profit and sold/demand | Costs, reputation, per-good result | Walking customers, coins, stall activity |
| Final | Rank and score | Ledger, milestones, reputation | Badge pulse, M0X wave, restrained confetti |
| Help | Three-step loop or six tactics | Key map and Agent Bay | Color-coded examples only |

## Motion budget

- UI transitions complete within eight frames and never block input.
- Robot idle uses a one-pixel, two-frame bob; its eyes occasionally shift.
- Customer walk cycles use two frames and constant velocity.
- At most eight non-star ambient objects animate together on a gameplay screen.
- The final rank is the only ceremonial moment; every other animation is quiet
  feedback rather than spectacle.

## Visual acceptance

1. All six deterministic documentation screens capture without an exception.
2. Five products remain distinguishable by silhouette and accent.
3. Six customer groups remain distinguishable by headwear or body shape.
4. The selected product, order quantity, asking price, and open-market action
   are visible without consulting the guide.
5. Money is amber, profit is mint, danger is red-magenta, market signals are
   magenta, and navigation is cyan throughout the product.
6. No blur, gradients, antialiasing, external IP, or raster UI dependencies.
7. Core economy and Agent observations remain independent from Pyxel art.
