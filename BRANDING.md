# PortWatch Branding Guide

## Name

**PortWatch** — one word, capital P, capital W.

## Tagline Options

1. **dev ports at a glance**
2. **know what's running**
3. **localhost, watched**

## Color Palette

| Role       | Hex       | Usage                                      |
|------------|-----------|---------------------------------------------|
| Background | `#1A1A2E` | App chrome, icon background, dark surfaces  |
| Primary    | `#4FC3F7` | Active indicators, icon accents, highlights |
| Dimmed     | `#6B7B8D` | Inactive state, disabled elements           |
| Text       | `#E0E0E0` | Primary body text                           |
| Muted Text | `#8892A0` | Secondary labels, timestamps                |
| Danger     | `#FF6B6B` | Kill actions, error states                  |

## Typography

- **Primary:** SF Mono (macOS system monospaced)
- **Fallback:** Menlo, Monaco, monospace
- All UI text is monospaced. No proportional fonts anywhere.
- Prefer lowercase for labels and actions: `kill`, `quit`, `copy port`, `no active ports`
- Port numbers and PIDs displayed in regular weight. Labels in light or regular.

## Voice & Tone

- Terse. Technical. Lowercase.
- No exclamation marks. No emoji. No cleverness.
- Reads like terminal output, not marketing copy.
- The tool is quiet and competent. It shows what's running and lets you act on it.

### Examples

| Do                          | Don't                                    |
|-----------------------------|------------------------------------------|
| `no active ports`           | `Nothing running right now!`             |
| `3 ports active`            | `You have 3 active development servers`  |
| `kill`                      | `Stop Server`                            |
| `quit`                      | `Exit PortWatch`                         |
| `copied`                    | `Port number copied to clipboard!`       |

## Icon

Geometric radar/antenna motif on dark background. A vertical mast radiates concentric signal rings, with small dots representing active ports. Two small stacked squares suggest the colon in `localhost:3000`.

- Active state: `#4FC3F7` accent on `#1A1A2E`
- Dimmed state: `#6B7B8D` at reduced opacity on `#1A1A2E`
- No gradients. No rounded-friendly shapes. Clean geometry only.
- Scales from 16x16 (menu bar) to 512x512 (app icon) without detail loss.

## Personality

A quiet tool that stays out of the way. Not cute. Not clever. Just useful. The kind of utility a senior engineer keeps running and never thinks about until they need it — and then it's exactly where they left it, showing exactly what they need.
