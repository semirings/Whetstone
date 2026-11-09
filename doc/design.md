---
intent: Design
mode: Attended
status: DRAFT 2 (recipe redefined as calls + screen capture)
---

# Whetstone: design

## Subject
Whetstone is a Flutter app for capturing, finding and replaying "recipes": how-tos for tools like Blender that you worked out once and forget by the next time (camera pointing nowhere, grease pencil with no fill). It is inspired by HyperCard: a stack of cards you can script. Speakeasy is the scripting language.

**A recipe is a card that stores the set of Blender API calls you made, a screen capture of the same session, and Blender information about the session.** You record while you work it out; later you find the card and either watch it or replay it.

## Inspiration: HyperCard
Whetstone borrows HyperCard's shape and vocabulary. It does not copy it (see "Departures").

| HyperCard | Whetstone |
|---|---|
| Stack | A collection of cards, e.g. "Blender recipes" |
| Card | One recipe (or a note, or a query result) |
| Field | A named text slot on a card (symptom, calls, ...) |
| Button | A named action with a script (record, replay, search) |
| Message box | A one-line command prompt that runs Speakeasy |
| Script / handler | Speakeasy code attached to an object |
| Message passing | button, then card, then stack, then Whetstone |

Departures: cards are recipes with a fixed set of fields, not free-form; no card background or painting layer in v1; the command set is far smaller than HyperTalk's; scripts can query a D4M backend and drive Blender; search and recording are first-class features.
Grammar source: Jeanne A. E. DeVoto, *Formal Syntax of HyperTalk*, version 2.2. Whetstone and Speakeasy are not affiliated with Apple.

## Problem
Tool proficiency costs bandwidth, and Blender is the worst offender. When you finally work something out after hours of dead ends, you forget it by the next time. Tutorials are slow to scan. You need (1) quick capture while you work, (2) retrieval by *symptom*, because people (including you) describe the same problem in many ways, and (3) replay of what worked, as a series of calls that gives the same result.

## Object model (nouns Speakeasy will name)
- **Stack**: ordered cards; has a name; has an index for search.
- **Card**: has `id`, `name`, fields, buttons, a script, and a `kind` (recipe, note, result).
- **Field**: named text on a card; has `name` and `text`.
- **Button**: has `name`, `script`; click sends a message.
- **Whetstone** (top of the message path): the app itself: current stack, current card, message box.

Properties common to all: `id`, `name`, `script`. Everything else is per type.

## The recipe card
Symptom first, because that is how you will look for it. A symptom is what you observe that is wrong, in your own words, not the cause and not the fix.

| Field | Required | Meaning |
|---|---|---|
| title (card name) | yes | short name |
| symptom | yes | what you see that is wrong |
| expected | yes | what you wanted |
| observed | no | what actually happens, if different from the symptom |
| context | no | editor, mode, object type |
| summary | no | one or two lines on what fixed it, in words |
| narration | no | spoken explanation, transcribed |
| calls | yes | **raw captured calls, one per line: the source of truth** |
| steps | no | the calls translated to Speakeasy where possible (derived) |
| clip | no | path to the screen capture |
| blender_info | no | version, mode, scene summary at the start of recording |
| tool | yes | what the recipe is about: blender, d4m, julia, ... |
| version | yes | version of that tool it was verified on |
| applies_from / applies_until | no | version range |
| superseded_by | no | a newer card that replaces this one |
| keywords | no | free tags |
| status | yes | `stuck` (open problem) or `solved` |

### How calls and steps are stored
- `calls`: one line per captured call, `SECONDS<TAB>CALL`, where SECONDS counts from the start of recording and CALL is exactly what Blender logged (a `bpy.ops...` line). Never edited by the translator.
- `steps`: one line per call, same SECONDS, then either a Speakeasy command, or `!raw ` followed by the original call when the translator does not know that operator.
- Seconds are shared with the clip, so each step can be tied to a moment in the video.

## Core flows
1. **Record.** Press *Record*: Whetstone starts the screen capture and starts reading Blender's operation log, both stamped from the same clock. Press *Stop*: a card is created with `calls`, `clip` and `blender_info` filled in. (*Stuck* and *Solved* set `status`.)
2. **Find.** Type a symptom in the message box or search field. Results rank by text match, keywords and, later, similarity. Open a card.
3. **Watch.** Play the clip; the step list scrolls with it.
4. **Replay.** Run the card's `steps` against Blender. Translated steps run directly; any `!raw` step asks first.
5. **Curate.** Mark a card superseded; add the version range; merge duplicates; fix a step.

## Architecture
```
Whetstone (Flutter)
  recorder: screen capture (macOS) + log reader, one clock
  Speakeasy (Dart: lexer, parser, interpreter)
    host interface -> Whetstone objects
    D4M extension  -> operation tree -> FastAPI -> D4M.jl
    Blender ext    -> operation tree -> Blender add-on
  translator: raw call -> Speakeasy step (per Blender version)
Blender add-on: publishes the operation log (wm.reports) and runs steps
```
Speakeasy never imports Flutter. Whetstone implements Speakeasy's host interface.

## Milestones
1. **Store and find.** Cards, fields, message box, text search, and manual entry of every recipe field.
2. **Record.** Screen capture plus the Blender log reader, producing `calls`, `clip` and `blender_info`. Watch.
3. **Translate and replay.** Translator for the common operators, `steps`, replay with the Blender extension.
4. **Later.** Narration transcription and captions, similarity search, D4M indexing of the corpus.

## Decisions (defaults taken 2026-11-06 and 2026-11-09; overturn any)
- **1 Stored calls: both forms (option 3).** Raw lines are kept as the source of truth; Speakeasy steps are derived where the translator knows the operator and marked `!raw` otherwise. Replay asks before running anything raw.
- **2 Storage:** one markdown file per card, front matter for short fields, body sections for `calls`, `steps`, `narration`. Clips are separate files referenced by path.
- **3 Stacks:** one stack. A card belongs to one stack.
- **4 Scripts:** every object has a `script` property; messages pass button, card, stack, app.
- **5 Platform:** macOS only.
- **6 Message box:** always visible at the bottom of the window.
- **7 Script editing:** edit files in your own editor first; a built-in editor later.
- **8 Clock:** `SECONDS` is time since recording started, from one clock for both capture and log.

## Object model in code
`lib/model/model.dart` holds `WhetstoneApp`, `CardStack`, `RecipeCard`, `CardField` and `CardButton`.
They extend Speakeasy's `BaseHostObject` (`Speakeasy/lib/src/core/host.dart`), which is the only thing the language sees.
Fields on a recipe card come from `RecipeCard.fieldSpecs`; change that list to change the card.

## Still open
- **Screen capture on macOS.** Which API (ScreenCaptureKit, `screencapture`, ffmpeg), the permission prompt, and what happens to the clip's size on disk.
- **Log transport from Blender.** First idea: a small add-on that polls the operation log on a timer and appends JSON lines to a file Whetstone tails.
- **Translator coverage.** How many operators are worth translating at first, and how a translation is checked.
- **Versions.** How "5.2" vs "5.10" is compared, and how the translator picks a mapping per version.
- **Privacy.** A screen capture shows the whole screen. Capture only the Blender window?
- **Is `tool` needed?** If recipes are only ever Blender, drop it. Kept for now in case D4M recipes appear.
- What `Stuck` records automatically, and how search ranks results.
