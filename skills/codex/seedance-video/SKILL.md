---
name: seedance-video
description: Generate cinematic video (up to native 4K) with ByteDance Seedance 2.0 and LTX-2.3 via the sogni-agent CLI — text-to-video, animating photos/images into video, two-keyframe transitions, and reference-guided multimodal clips. Use when the user wants to create a video, animate an image or photo, make a 4K/UHD clip, or mentions Seedance or Sogni.
---

# Seedance / Sogni video generation

The tool is the globally installed **`sogni-agent`** CLI (Sogni Supernet; ByteDance Seedance 2.0 is the 4K vendor model). Auth comes from `~/.config/sogni/credentials` (`SOGNI_API_KEY=...`, chmod 600) or the `SOGNI_API_KEY` env var — one global location, works from any repo or worktree.

**Do not run `sogni-agent doctor` as a preflight.** Go straight to the generate command — it validates credentials, ffmpeg, and balance itself. Use `doctor` only after an install/upgrade or when a command actually errors.

## Model routing

| Ask | Command core |
|---|---|
| 4K / UHD, native audio, or multimodal refs | `-m seedance2 --target-resolution 2160` |
| Cheap Seedance iteration (720p cap) | `-m seedance2-fast` (or `seedance2-mini`) |
| Non-vendor HD 1080p text-to-video | `-m ltx23-22b-fp8_t2v_distilled -w 1920 -h 1088` |
| Non-vendor HD 1080p image-to-video | `-m ltx23-22b-fp8_i2v_distilled -w 1920 -h 1088` |

- Never use `seedance2-mini`/`-fast` for 4K — both are hard-capped at 720p.
- Seedance: 4–15 s duration, fixed 24 fps. `seedance2` runs on paid **Premium Spark** only (roughly $1 per clip at 1080p, more at 4K — cost scales with pixels × seconds); it never falls back to SOGNI tokens or an Unlimited plan.
- Workflow: iterate drafts on `seedance2-fast` at 720p, then re-render the winning prompt once at 4K on `seedance2`.

## Image-to-video (animate photos)

```bash
# Single photo → 4K cinematic clip
sogni-agent -q --video --ref ./photo.png -m seedance2 --target-resolution 2160 --duration 8 -o ./clip.mp4 "<prose paragraph>"

# Two keyframes: animate image A into image B
sogni-agent -q --video --ref ./A.png --ref-end ./B.png -o ./transition.mp4 "<prose paragraph>"

# Extra Seedance references (images/video/audio mixed)
sogni-agent -q --video -m seedance2 --ref ./product.png --ref ./detail.png --duration 8 -o ./spot.mp4 "<prose using @Image1, @Image2>"
```

- In Seedance prompts, address attachments as `@Image1`, `@Video1`, `@Audio1` — numbered per modality in attachment order.
- Give every reference an explicit role in the prompt: product/person identity, motion timing, camera path, edit rhythm, background music, speech.
- Use **positive preservation language**: "maintain the exact face, hair, and jacket from @Image1" — never "don't change the face". Seedance ignores negative prompts.
- Limits: ≤9 image, ≤3 video, ≤3 audio references, ≤12 assets total. Audio references require at least one image or video reference alongside (text+audio alone is rejected).

## Writing prompts that produce beautiful footage

Never pass a short slogan-style request through unchanged. Rewrite it into one cinematic prose paragraph:

- One single paragraph, 4–8 flowing present-tense sentences, one continuous shot — no bullets, headers, negative clauses, or on-screen-text requests.
- Open with shot scale + the scene's visual identity, then environment, time of day, atmosphere, textures, and **named light sources** ("violet neon reflecting off wet pavement", not "moody lighting").
- One action thread start-to-finish, joined with *as / while / then*. Describe motion literally and chronologically: what moves, where it moves, what it contacts, what happens next.
- Vague filler is banned — "beautiful", "nice", "stunning" do nothing; concrete nouns, materials, and light do the work.
- Translate loose camera talk: zoom in → *slow push-in* · zoom out → *slow pull-back* · orbit → *slow arc left/right* · follow → *tracking follow* · pan → *smooth pan left/right*.
- Native audio is part of the scene: write foley, ambience, and music into the prose; dialogue verbatim in double quotes with speaker and delivery, budgeted ~3 words/second.
- Pace beats to duration: 1–4 s → one action; 5–8 s → two; 9–12 s → three. Don't cram a montage into a short clip.
- Orientation: "vertical/portrait/reel/tiktok" → `-w 1088 -h 1920` on LTX models; on Seedance prefer `--target-resolution` and let the CLI infer aspect from phrases like "720p 9:16".

## Output and cost rules

- Always save to the working directory: `-o ./name.mp4`. Never `/tmp`. Hosted result URLs expire after 24 h — `-o` downloads automatically.
- For several prompt-only takes with identical settings, use one call with `-n <count>` (and `{a|b|c}` prompt variations) instead of serial renders.
- "Debit Error: Insufficient funds" on a `seedance2*` model means the user must top up **Spark** at https://dashboard.sogni.ai — there is no token fallback; say so instead of retrying.
- Full flag reference: `sogni-agent --help`. Deep guides: https://github.com/Sogni-AI/sogni-creative-agent-skill/tree/main/references (video-prompting.md, video-editing.md).

## Repo-local fallback (AgCore)

`tools/seedance/generate.mjs` in the AgCore repo is a standalone SDK script (HTTPS-URL references only, no local files). Prefer `sogni-agent`; use the script only when a repo-pinned, dependency-light path is explicitly wanted.
