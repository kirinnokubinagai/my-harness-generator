$imagegen Generate ONE high-quality PNG image for the "<SCREEN_NAME>" screen of <PROJECT_NAME> on <PLATFORM>. Read the attached spec files first to understand what this screen does, then design with full creative freedom — visual style, palette, layout patterns, icon language are all your call.

The image is divided into 2 stacked sections, separated by a thin horizontal divider line:

SECTION A — FULL PAGE MOCK (top 65 % of the image, occupies y = 0 to y ≈ 0.65 × HEIGHT)
- A complete <PLATFORM> mock of the "<SCREEN_NAME>" screen at its native aspect ratio.
- Realistic content — not Lorem Ipsum, not "Title goes here" placeholders. Use plausible copy for this project's domain.
- Every UI component visible and at correct visual hierarchy.
- All states visible where natural (e.g., a list with one selected row, a button in default state visible alongside a disabled one if both exist in the screen).

SECTION B — PARTS GRID (bottom 35 % of the image, occupies y ≈ 0.65 × HEIGHT to y = HEIGHT)
- Identify every distinct UI component used in Section A and lay them out as an isolated catalog.
- Layout: exactly 4 columns wide, as many rows as needed to fit every component + every state variant separately.
- Each cell is uniform size: cell_width = (image_width / 4), cell_height = (section_B_height / number_of_rows). All cells identical.
- Components MUST NOT overlap. Components MUST NOT touch the cell edges (16 px padding minimum inside each cell).
- Background of Section B is solid white (#FFFFFF) so cropping is unambiguous against the components.
- Below each component, write its name in plain readable text (e.g., "Primary Button", "Primary Button — Hover", "Primary Button — Disabled", "Search Bar", "Avatar", "Nav Item — active"). Use simple sans-serif at a readable size.
- Each state variant (Hover, Active, Disabled, Selected, Focus) is its own cell.

Image specs (these are technical, not aesthetic):
- Format: PNG (RGB; no alpha channel needed).
- Aim for the highest resolution your tool supports — at least 2048 × 2880, or whatever your highest "hd" / "high quality" setting produces. Quality matters more than file size.
- Section A occupies y = 0 to y ≈ 0.65 × HEIGHT; Section B occupies the rest.
- One image_gen call total. Do NOT produce multiple image files for this prompt.

Save to: <root>/dev/docs/design/page-<PLATFORM>-<SCREEN_SLUG>.png
