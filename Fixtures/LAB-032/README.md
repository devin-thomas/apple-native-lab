# LAB-032 Render That Survives fixtures

Original, synthetic render recipes written for this project and distributed under the repository's MIT License. A recipe is numbers only: the render draws every frame from them, so there is no source media, and nothing here came from a person, a camera, or an import.

The valid recipes live with their module, because the app bundles them: [`Packages/LabFeatures/Sources/RenderThatSurvives/Resources/recipes.json`](../../Packages/LabFeatures/Sources/RenderThatSurvives/Resources/recipes.json).

| Recipe | Frames | Segments | Pacing | Output |
|---|---|---|---|---|
| `short-bars` | 48 at 160×90, 24 fps (2.0 s) | 4 of 12 frames | as fast as possible | `short-bars.mov`, a few tens of KB |
| `long-bars` | 576 at 320×180, 24 fps (24.0 s) | 8 of 72 frames | real time, one second of video per second | `long-bars.mov`, under 2 MB |

Each frame is a stack of rectangles: a background whose color changes every second, a strip with one cell per segment and the frame's own segment lit, a progress bar, and a moving square. `FrameTests` pins the SHA-256 of the CPU painter's pixels for known frames, and checks that the GPU painter draws the same bytes.

Rendered movies are not stored here. The app writes them to its own container, and tests write them to a temporary folder that they remove.

The files here are hostile. Each is refused before anything is started or stored (`RecipeTests.hostileRecipesAreRefused`).

| File | What it tries | Expected result |
|---|---|---|
| `duplicate-keys.json` | `id` twice | `malformed` (strict JSON refuses a repeated key) |
| `unknown-field.json` | A `sourceURL` field | `unknownField`; a recipe never means more than this build reads |
| `traversal-id.json` | An `id` of `../escape`, which names the output file | `invalid(id)` |
| `oversized-frames.json` | 100,000 frames | `invalid(frameCount)` |
| `odd-width.json` | A width of 161; H.264 needs even sizes | `invalid(width)` |
| `malformed.json` | A trailing comma | `malformed` |
