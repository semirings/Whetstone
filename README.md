# Whetstone

A HyperCard-like recipe store for Blender. A **recipe** is a card: some text fields, buttons with scripts, and (later) the Blender API calls that do the job plus a screen capture of the result. You find, read and run recipes the way you would work a HyperCard stack.

Whetstone is a macOS app (Flutter) with a small Python backend that stores the cards. Cards are scripted in **Speakeasy**, a HyperTalk-inspired language that lives in its own package.

## How it fits together

| Part | Where | What it is |
|------|-------|------------|
| Whetstone app | `lib/` | Flutter macOS app: card list, card view, message box, menu bar |
| Backend | `backend/` | FastAPI service on port **8402** that stores the cards |
| Speakeasy | `../Speakeasy` | The scripting language (lexer, parser, interpreter), a separate Dart package |
| Storage | `storage/` | `cards.parquet` is the store; `cards.tsv` is a readable mirror that is never read back |
| ForgeTools | `../ForgeTools` | Shared scripts: `run.sh` machinery and the app-icon generator |

Ports: DoubleNaught 8400, SegForge 8401, Whetstone 8402.

## Running it

    ./run.sh up        # backend under launchd, app in the background
    ./run.sh status    # what is running, ports, health
    ./run.sh dn        # stop the app and the backend
    ./run.sh re        # stop, then up (after changing code)
    ./run.sh logs be|fe

Foreground, for development: `./run.sh FE` (hot reload), `./run.sh BE` (backend with auto-reload; `--clear-storage` empties the card store), `./run.sh all` (both). `up --with-dn` also starts DoubleNaught's and SegForge's backends. Override the port with `WHETSTONE_PORT`.

The first run creates `.venv` and installs the backend. `run.sh` is only Whetstone's settings; the runner itself is `../ForgeTools/forge-run.zsh`, which needs the `ForgeTools` folder beside this one.

## Using it

- **One card fills the window**, as in HyperCard: its title, buttons and fields. A thin strip underneath shows where you are ("3 of 12"), steps with the arrows, and shows the last message or error.
- **Find** (Go > Find, ⌘F) looks for text in any field and shows the hits as "Results"; "All cards" in the strip returns to the whole stack.
- **The message box** is hidden until you ask (View > Message Box, ⌘M). It runs a Speakeasy line, for example `find cards where field "symptom" contains "render"`.
- **The card list** is hidden too (View > Card List, ⌘L); open it to browse by title.
- **Menu bar** (at the top of the screen): File (New Card ⌘N, Save ⌘S, Delete Card), Go (First to Last on ⌘1 to ⌘4, Find, All Cards), Objects (New Field, New Button, edit scripts, rename, delete, mark fields required), View (message box, card list, light or dark theme; dark is the default).
- **Saving** is explicit: ⌘S or `save` in a script. Structural changes made from the Objects menu save at once. The standard fields (symptom and the others) can't be renamed or deleted.

## Storing cards

The app talks to the backend over HTTP (`/health`, `/cards`, `/cards/{id}`). If the backend isn't reachable the app shows sample cards with a warning and nothing is saved. On a first run with an empty store, the sample cards are saved.

`cards.parquet` holds `(row, col, val)` string triples, one row per card id, with columns `kind`, `name`, `stack`, `script`, `field|<name>`, `button|<name>` and `required|<name>`. Unknown columns are ignored, so a newer file can be read by an older app. A corrupt file is refused and never overwritten.

## Tests

    flutter analyze; flutter test                        # the app
    cd backend && pytest                                 # the backend (in the venv)
    cd ../Speakeasy && dart analyze; dart test           # the language

## App icon

Put a square PNG at `img/logo.png`, then `../ForgeTools/app-icon.sh --project .` and `./run.sh re`. If the Dock keeps the old icon, add `--refresh`.

## Not built yet

Autosave; the D4M and Blender extensions of Speakeasy; the Blender add-on and log reader; recording a recipe and translating it to a script. See `doc/design.md` (parts of it, notably storage, predate the Parquet backend).

## Talking to Blender

Open Blender (with its MCP extension running), show the message box (View > Message Box, ⌘M) and type Speakeasy:

    create sphere "Eye" at 0, 0, 1
    move "Eye" by 1, 0, 0
    rotate "Eye" to 0, 0, 90      -- degrees
    scale "Eye" by 2
    delete object "Eye"
    render to "frame.png"

Shapes: cube, sphere, plane, cylinder, cone, camera, light. Names go in quotes. Each line is sent to the backend (`POST /blender/ops`), which runs it in Blender on `127.0.0.1:9876` (override with `WHETSTONE_BLENDER_HOST` / `WHETSTONE_BLENDER_PORT`). `the result` holds a short summary; an error shows in the status strip. `move`, `rotate`, `scale` and `render` are now reserved words.

## Starting up

Whetstone shows `img/splash.png` while it reaches the backend and loads the cards, at least 1.2 seconds (`splashMinimum` in `lib/main.dart`), then opens on the **Home** card. There are no sample cards any more: an empty store gives an empty `Recipes` stack. If the backend can't be reached, Home still opens, with a warning in the status line, and nothing is saved. **Go > Home** (⇧⌘H) returns to Home. The Home card is built in: it is never stored and can't be edited or deleted. Its tiles are buttons with `go to` scripts; tiles for the templates will be added as their master cards are made.

`img/splash.png` is declared as an asset in `pubspec.yaml`, so the file must exist for the app to build.
