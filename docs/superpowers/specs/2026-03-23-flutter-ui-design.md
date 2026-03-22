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
- Border: rgba(0,0,0,0.06-0.10)
- Text primary: #1A1A1A
- Text secondary: rgba(0,0,0,0.5)
- Text tertiary: rgba(0,0,0,0.3)
- Frosted glass: `rgba(255,255,255,0.7)` + `backdrop-filter: blur(24px)` + `border: 1px solid rgba(0,0,0,0.06)`
- Accent colors remain the same

**Accent colors:**
- Primary: #FF9F0A (amber) — timers, active states, amounts, CTAs
- Success: #30D158 (green) — completed steps, voice listening indicator
- Multi-recipe dish tags: green (#30D158), amber (#FF9F0A), blue (#6382FF), purple (#BF5AF2) — one per recipe. If 5+ dishes, cycle from green.

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
- Top bar: recipe name (small caps, dimmed) + step dots (26px circles, 6px gap — done ✓ green / active amber / upcoming dimmed). If 10+ steps, show scrollable horizontal row with active dot centered. Number inside each dot (11px, semibold).
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
- Ingredient panel as collapsible row at top: **collapsed** shows a single row of emoji circles (just the emojis, 28px each, horizontally scrollable). **Tap to expand:** slides down to show full ingredient list (emoji + amount + name per row, max height 40% of screen, scrollable). Pushes step text down (not overlay).
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

Full-screen route (not overlay). Same layout as detail screen but all fields become editable.

- **Title:** large editable text field at top
- **Description:** multi-line editable below title
- **Ingredients:** each row has emoji (auto-suggested as user types ingredient name) + editable text. Swipe row to delete. "Add ingredient" button at bottom.
- **Steps:** numbered cards, each with editable text area. Drag handle on left for reorder. Swipe to delete. "Add step" button at bottom.
- **Keyboard avoidance:** scroll to keep active field above keyboard
- **Top bar:** "Cancel" (left, text button) + "Save" (right, amber button)
- **Save behavior:** auto-diffs changes, creates changelog entry. Optional note sheet slides up: "What did you change?" with text field + "Save" button. Skip to save without note.
- **Cancel:** if changes exist, confirm sheet: "Discard changes?"

---

## Screen: Recipe Changelog

Bottom sheet, slides up from detail screen when "📝 N edits" pill is tapped.

- **Header:** "Edit History" + close button (×)
- **Timeline:** vertical list, newest first. Each entry:
  - Amber dot on left edge (timeline line connecting dots)
  - Date (13px, dimmed)
  - Change description (14px) — auto-generated diff text
  - User note in italics if present (13px, dimmed)
- Example entry: "**Mar 15** — Changed fish sauce from 3 tbsp to 2 tbsp. Added lime juice. *'reduced salt for the kids'*"
- Max height: 70% of screen. Scrollable.

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

Bottom sheet slides up from recipe detail's "Start Cooking" button.

- **Header:** "What are you cooking?"
- **Selected recipe** shown as a compact card with checkmark
- **"Add another recipe" button** — opens recipe picker (mini browse grid as a modal). Tap to toggle selection. Selected recipes show checkmarks.
- **Selected recipes list:** horizontal scroll of compact cards with "×" to remove
- **Servings adjuster:** stepper control (- 2 +) per recipe (LLM handles scaling conversationally)
- **"Start Cooking" button:** full-width amber, shows count: "🍳 Cook 3 recipes"
- **Loading state (multi-recipe):** full-screen dark overlay with centered spinner + "Merging your recipes..." text. Subtle food emoji rotating (🍳→🥘→🍜). Takes 3-5 seconds, then transitions to cooking mode.

## Screen: Import (URL Ingestion)

Bottom sheet or full-screen route depending on entry point.

- **URL field:** large, auto-focused. Pre-filled if shared from another app.
- **Platform detection:** once URL is recognized, shows icon + "TikTok recipe detected" or "YouTube video detected" in green.
- **"Import Recipe" button:** amber, below URL field
- **Progress:** vertical step list (not a bar). Each step has a circle indicator:
  - ⏳ Downloading video...
  - ⏳ Transcribing audio...
  - ⏳ Extracting recipe...
  - ⏳ Generating step images...
  - Steps turn ✅ as they complete
- **Auto-transitions** to recipe edit screen on completion (no tap needed). User reviews parsed data and saves.

---

## Responsive Strategy

Single Flutter app, responsive:
- **iPad landscape:** Full experience — 4-col masonry browse, split cooking mode (45/55)
- **iPad portrait:** 3-col masonry browse. Cooking mode keeps split layout but image panel shrinks to 35% width. If width < 700px, collapse to phone cooking layout.
- **Phone:** 2-col masonry browse with bottom tab bar. Full-screen cooking mode (text + voice, no image panel). FAB sits above tab bar (bottom-right, 16px above tab bar top edge).
- Breakpoints: phone < 600px, tablet 600-1024px, large tablet > 1024px

**Timer interaction:** Tap timer chip to expand into a control row: time display + pause/resume button + cancel (×) button. Tap elsewhere to collapse back to chip. Long-press to cancel with confirmation.

---

## Mockup References

HTML mockups in `backend/mockups/`:
- `cooking-mode-hybrid.html` — Cooking mode with all three states (listening, agent speaking, multi-recipe)
- `ingredients-v2.html` — Frosted ingredient panel options
- `browse-v2.html` — Recipe browsing (full grid, sparse, empty states)
- `recipe-browse.html` — Recipe detail + phone layout
