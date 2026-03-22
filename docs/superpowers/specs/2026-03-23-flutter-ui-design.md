# Mise en Place — Flutter UI/UX Design Spec

## Design Philosophy

**Apple TV for Cooking** — cinematic, media-rich, dark-first interface where food photography is the hero. Premium feel with minimal chrome. Two distinct modes: casual browsing (touch-heavy) and cooking mode (arm's length, voice-driven).

## Design System

### Color Palette (Adaptive)

**Dark mode (default):**
- Background: #0A0A0A (near-black)
- Surface: #141414 (cards, panels)
- Border: rgba(255,255,255,0.04-0.08)
- Text primary: #FFFFFF
- Text secondary: rgba(255,255,255,0.45)
- Text tertiary: rgba(255,255,255,0.25)

**Light mode:**
- Background: #FAF7F2 (warm cream)
- Surface: #FFFFFF
- Accent colors remain the same

**Accent colors:**
- Primary: #FF9F0A (amber) — timers, active states, amounts, CTAs
- Success: #30D158 (green) — completed steps, voice listening indicator
- Multi-recipe dish tags: green (#30D158), amber (#FF9F0A), blue (#6382FF), purple — one per recipe

### Typography

System font (SF Pro on iOS, Roboto on Android). Specific sizes:
- Cooking mode step text: 32px, semibold, -0.6 tracking
- Cooking mode detail: 15px, regular, rgba(255,255,255,0.4)
- Card titles: 13-15px, semibold
- Labels/metadata: 11-12px, uppercase tracking 1.2px
- Section headers: 11px, uppercase, tracking 1.2px, rgba(255,255,255,0.25)

### Frosted Glass

Used for: ingredient panels, timer pills, back buttons on hero images.
- `background: rgba(0,0,0,0.5)` + `backdrop-filter: blur(24-28px)`
- `border: 1px solid rgba(255,255,255,0.07)`
- `border-radius: 16px`

### Ingredient Emojis

Every ingredient gets an emoji mapped by the LLM during recipe ingestion/creation. Stored alongside the ingredient text. Common mappings:

| Category | Examples |
|----------|----------|
| Proteins | 🥚 eggs, 🍗 chicken, 🥩 beef, 🦐 prawns, 🐟 fish/fish sauce |
| Vegetables | 🧅 onion, 🧄 garlic, 🥕 carrot, 🥦 broccoli, 🫑 pepper, 🌶️ chili, 🍅 tomato |
| Fruits | 🍋 lemon/lime, 🥭 mango, 🥥 coconut |
| Grains | 🍜 noodles, 🍚 rice, 🍞 bread |
| Dairy | 🧈 butter, 🧀 cheese, 🥛 milk |
| Sauces | 🫙 paste/sauce (tamarind, curry paste), 🍯 honey |
| Herbs/Spices | 🌿 herbs, 🧂 salt/seasoning, 🫚 ginger |
| Oils | 🥜 nut oil/vegetable oil, 🫒 olive oil |
| Misc | 🌱 sprouts/greens |

Fallback: 🧂 for any unmatched seasoning, 🫙 for any sauce/paste, 🥘 for generic.

### Motion

Apple-level restraint:
- Step transitions: fade + subtle slide
- Timer dot: pulse animation (2s cycle)
- Voice waveform: gentle wave animation (1.4s cycle)
- Voice orb: breathing glow (3s cycle)
- Card hover: scale(1.02)
- No flashy transitions or page animations

### Spacing & Touch Targets

- Minimum touch target: 44pt
- Generous whitespace throughout
- Cooking mode text readable from 2-3 feet away

---

## Screen: Cooking Mode (iPad)

### Layout: Hybrid Cinematic/Structured

Split layout — cinematic image left, structured content right.

**Left panel (45% width):**
- Full-bleed food photo (step illustration or recipe hero)
- Image crossfades between steps
- Gradient overlay: `linear-gradient(to right, transparent 55%, #0a0a0a 100%)` for blending into the right panel
- Subtle vignette top/bottom

**Frosted ingredient panel** — anchored bottom-left of image:
- No title/header — just the ingredient list
- Vertical list: emoji (16px) + amount (13px, amber, semibold) + name (13px, rgba white 0.6)
- Frosted glass background
- Grows vertically to fit ingredients (typically 2-5 per step)
- `max-width: 200px`

**Right panel (55% width):**
- Top bar: recipe name (small caps, dimmed) + step dots (numbered circles — done ✓ green / active amber / upcoming dimmed)
- Center (vertically centered):
  - "STEP N" label (12px, amber, uppercase)
  - Step text (32px, semibold)
  - Detail text (15px, dimmed)
  - Timer chips: frosted pills with pulsing dot + time (amber) + label
- Bottom: voice bar

**Voice bar:**
- Frosted strip with green listening orb (breathing animation) + waveform bars + "Listening..." status
- When agent speaks: text bubble appears above voice bar (agent avatar + response text). Voice bar turns amber, status says "Speaking..."

### States

1. **Listening** — default. Green orb breathes, waveform animates gently.
2. **User speaking** — waveform reacts to audio levels.
3. **Agent speaking** — amber orb, text bubble visible with response, waveform in amber.
4. **Idle** — orb dim, waveform static. Tap to re-engage.

### Multi-Recipe Session

- Top bar: color-coded dish tag pills instead of recipe name (e.g., green "Pad Thai", amber "Green Curry", blue "Sticky Rice")
- Current step shows colored dot + dish label (e.g., "🟠 Green Curry — Step 2")
- Multiple timer chips with dish-colored dots
- Step count shows total across all dishes (e.g., "5 of 12")

---

## Screen: Cooking Mode (Phone)

- Full-screen single column, dark background
- Step text large and centered
- Ingredient panel as collapsible row at top (tap to expand, emoji pills)
- Timer chips below step text
- Voice bar fixed at bottom
- No image panel (too narrow)
- Swipe left/right for manual step navigation

---

## Screen: Recipe Browsing (iPad)

### Full Library (12+ recipes)

4-column Pinterest masonry grid.

**Top bar:** "mise **en** place" logo left, search bar center, avatar right.

**Filter chips:** All (active, amber), cuisine flags (🇹🇭 Thai, 🇲🇽 Mexican, 🇮🇹 Italian, etc.), 🥬 Vegan, ⭐ Favorites, 📱 Imported.

**Recipe cards:**
- Variable height (image aspect ratio varies)
- Food photo fills card top
- Card body: title (13px semibold), metadata row (cuisine tag pill + cook time or source badge)
- Source badge on imported recipes: platform icon + @creator
- Cards: #141414 background, subtle border, 14px radius, scale on hover

**FAB:** Bottom-right, amber, "+" icon, 52px, rounded square (15px radius), shadow.

### Sparse Library (2-3 recipes)

Switches from masonry to horizontal card row:
- Recipe cards in a row (max-width 280px each)
- Dashed "Import a recipe" card with "+" icon
- Below: "Quick Start" section with 3 action cards — Import from TikTok, Import from YouTube, Write Your Own

### Empty State (New User)

- Centered vertically
- Large emoji (🍳)
- "Your kitchen awaits" title
- Description text
- Amber CTA button: "📱 Import your first recipe"
- Secondary link: "or create one from scratch →"

---

## Screen: Recipe Browsing (Phone)

- 2-column masonry grid
- Compact cards (smaller text, shorter bodies)
- Bottom tab bar: Browse (📖), Favorites (⭐), Cook (🍳), Profile (👤)
- Active tab in amber
- Same filter chips (horizontally scrollable)

---

## Screen: Recipe Detail

**Hero image** at top (~40% of screen), parallax scroll effect.
- Back button (frosted circle, top-left)
- Edit button (pencil, frosted circle, top-right)
- Gradient overlay fading into content area

**Content area:**
- Title (30px, bold) — overlaps hero slightly (negative margin)
- Tags row: cuisine tag pill, cook time, serves count, changelog pill ("📝 3 edits")
- Source row (if imported): platform icon + "Imported from @creator on TikTok"
- Description text (15px, dimmed)
- **Ingredients section:** label "INGREDIENTS" (section header style) + vertical list with emoji + amount (amber) + name. Separator lines between items.
- **Steps section:** label "STEPS" + numbered circles + step text per row. Separator lines.
- **Start Cooking button:** fixed bottom, full-width amber bar, "🍳 Start Cooking", 16px padding, 14px radius, shadow

---

## Screen: Recipe Edit

- Inline editing of title, description
- Ingredient rows: editable text, emoji auto-suggested
- Steps: drag to reorder, tap to edit, swipe to delete
- Save: creates changelog entry (auto-diff + optional user note)
- Cancel discards

---

## Screen: Recipe Changelog

- Accessible from detail screen via "📝 N edits" pill
- Timeline of changes, newest first
- Each entry: timestamp, description of what changed
- Example: "Mar 15 — Changed fish sauce from 3 tbsp to 2 tbsp. Added lime juice. Note: 'reduced salt for the kids'"

---

## Screen: Import (URL Ingestion)

- URL text field (pre-filled if shared from another app)
- Platform detection: shows TikTok/YouTube icon once URL is recognized
- "Import Recipe" button (amber)
- Progress states: "Downloading video..." → "Transcribing audio..." → "Extracting recipe..." → "Generating images..."
- On complete: transitions to recipe edit screen with parsed data pre-filled
- User reviews and saves

---

## Screen: Cook Session Setup

- Multi-recipe selection: toggle recipes on/off from library
- Selected recipes shown as cards with checkmarks
- "Start Cooking" button shows count: "🍳 Cook 3 recipes"
- If multi-recipe: loading state "Merging recipes into one session..." (3-5 seconds)
- Transitions to cooking mode

---

## Responsive Strategy

Single Flutter app, responsive:
- **iPad landscape:** Full experience — masonry browse, split cooking mode, side panels
- **iPad portrait:** 3-column masonry, same cooking mode (slightly narrower panels)
- **Phone:** Single column browse, full-screen cooking mode (text + voice, no image panel)
- Breakpoints: phone < 600px, tablet 600-1024px, large tablet > 1024px

---

## Mockup References

HTML mockups in `backend/mockups/`:
- `cooking-mode-hybrid.html` — Cooking mode with all three states (listening, agent speaking, multi-recipe)
- `ingredients-v2.html` — Frosted ingredient panel options
- `browse-v2.html` — Recipe browsing (full grid, sparse, empty states)
- `recipe-browse.html` — Recipe detail + phone layout
