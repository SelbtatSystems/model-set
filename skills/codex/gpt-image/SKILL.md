---
name: gpt-image
description: Generate or edit images with OpenAI's latest image model (GPT Image 2) via the sogni-agent CLI — text-to-image, multi-reference editing with up to 16 context images, and best-in-class text/typography rendering inside images. Use when the user wants OpenAI/GPT image generation, images containing readable text (logos, posters, UI mockups, signage), or precise instruction-following edits.
---

# GPT Image 2 (OpenAI) via Sogni

OpenAI's newest image model, `gpt-image-2`, is reachable through the same **`sogni-agent`** CLI and Sogni account used for Seedance video (see [[seedance-video]]) — no OpenAI API key. Auth: `~/.config/sogni/credentials` or `SOGNI_API_KEY`. It is a **Premium Spark vendor model** (from ~14 Spark ≈ $0.07 per image, scaling with pixel count); it is never covered by SOGNI tokens or an Unlimited subscription.

**No preflight.** Go straight to the generate command — it validates credentials and balance itself. `sogni-agent doctor` is only for install/upgrade verification or after a real error.

## Core commands

```bash
# Text-to-image (always set -w/-h — see sizing rules below)
sogni-agent -q -m gpt-image-2 -w 1024 -h 1024 -o ./image.png "prompt"

# Edit / compose with context images (repeatable -c, up to 16)
sogni-agent -q -m gpt-image-2 -c ./base.png -c ./logo.png -o ./edited.png "Place the logo from Image 2 onto the storefront in Image 1, matching perspective and lighting"

# Variations: one call, not serial renders
sogni-agent -q -m gpt-image-2 -w 1024 -h 1024 -n 3 -o ./v.png "a {watercolor|line-art|isometric} farm dashboard illustration"

# Output format (gpt-image-2 also supports webp)
sogni-agent -q -m gpt-image-2 -w 1536 -h 1024 --output-format webp -o ./hero.webp "prompt"
```

## Sizing rules (gpt-image-2 specific)

- Up to **3840 px on either edge**, max **3:1** aspect ratio, total pixels between **655,360 and 8,294,400**; the API snaps dimensions to multiples of 16.
- The CLI's global default of 512×512 is **below this model's pixel minimum** — always pass explicit `-w`/`-h` (1024×1024 is a safe floor; 3840×2160 works for 16:9 wallpapers/heroes).

## Prompting and editing

- In prompts, refer to context images as `Image 1`, `Image 2` … (attachment order) — **not** the `@Image1` form (that grammar is Seedance-only).
- For edits, write a concise delta instruction describing the change and what to preserve ("keep the layout and palette of Image 1, replace only the headline text with 'HARVEST 2026'") rather than re-describing the whole picture. No negative prompts.
- Its standout strengths: rendering readable text/typography, following layout instructions, and composing many references — pick it over Sogni-native models for those; for identity-preserving people edits prefer `krea2_identity_edit_v1_2` (1–2 refs), for cheap generic edits `qwen_image_edit_2511_fp8_lightning` (≤3 refs), for non-vendor quality art `-Q pro`.

## Output and cost rules

- Save to the working directory (`-o ./name.png`), never `/tmp`. Hosted result URLs expire after 24 h — `-o` downloads automatically.
- "Debit Error: Insufficient funds" means the user must top up **Spark** at https://dashboard.sogni.ai — there is no token fallback; report it, don't retry.
- Natural follow-up: animate the result into video with `sogni-agent --video --ref ./image.png …` per the [[seedance-video]] skill.
- Full flags: `sogni-agent --help`; model catalog: `sogni-agent --list-models`.
