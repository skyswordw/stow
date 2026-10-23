# Sample archive credits

"Harbor Rebrand Handoff" is the archive Try the Sample opens, and the one in Stow's screenshots and
video. Harbor is a made-up ferry app; any likeness to a real company is unintended. The files in
`Harbor Rebrand Handoff/` give the sample's previews something real to show. This file lists where
each one comes from and its license.

## Photos (CC0 1.0)

Bernard Spragg released all five photos into the public domain under
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). Each Commons file page shows the
dedication. We downloaded Wikimedia Commons' 1600 px rendition of each, then downscaled it to
1440 px and re-encoded it with `sips`. We made no other changes.

| File | Source | Author | License |
| --- | --- | --- | --- |
| `Photos/Pier at Dawn.jpg` | [Dawn New Brighton Pier. NZ (33736189201).jpg](https://commons.wikimedia.org/wiki/File:Dawn_New_Brighton_Pier._NZ_(33736189201).jpg) (from [Flickr](https://www.flickr.com/photos/volvob12b/33736189201/)) | Bernard Spragg | CC0 1.0 |
| `Photos/Lighthouse.jpg` | [Historic Akaroa Lighthouse. (31392380543).jpg](https://commons.wikimedia.org/wiki/File:Historic_Akaroa_Lighthouse._(31392380543).jpg) (from [Flickr](https://www.flickr.com/photos/volvob12b/31392380543/)) | Bernard Spragg | CC0 1.0 |
| `Photos/Rope Detail.jpg` | [The mooring rope. (16291085142).jpg](https://commons.wikimedia.org/wiki/File:The_mooring_rope._(16291085142).jpg) (from [Flickr](https://www.flickr.com/photos/volvob12b/16291085142)) | Bernard Spragg | CC0 1.0 |
| `Photos/Old Jetty.heic` | [Boat harbour Oamaru. FZ200 (16422032120).jpg](https://commons.wikimedia.org/wiki/File:Boat_harbour_Oamaru._FZ200_(16422032120).jpg) (from [Flickr](https://www.flickr.com/photos/volvob12b/16422032120/)) | Bernard Spragg | CC0 1.0 |
| `Photos/Harbor at Night.jpg` | [Moorings Akaroa. NZ (48304313346).jpg](https://commons.wikimedia.org/wiki/File:Moorings_Akaroa._NZ_(48304313346).jpg) (from [Flickr](https://www.flickr.com/photos/volvob12b/48304313346/)) | Bernard Spragg | CC0 1.0 |

The screens, the brand guidelines PDF and the guidelines' photography page show these same photos.

## Fonts (SIL Open Font License 1.1)

We copied the font files unmodified from the [Google Fonts repository](https://github.com/google/fonts)
at commit `45e3d5269e4a17d823f6d84470bc084dc5ae46f6`. We renamed the files only, so their names
read well in the sample. Neither license reserves a font name. The full license texts are in
`Licenses/`. The generated screens and PDFs use these fonts, and the PDFs embed them, which the OFL
allows.

| File | Font | Copyright | License |
| --- | --- | --- | --- |
| `Fonts/Atkinson Hyperlegible Regular.ttf` | [Atkinson Hyperlegible](https://github.com/googlefonts/atkinson-hyperlegible) Regular (`ofl/atkinsonhyperlegible/AtkinsonHyperlegible-Regular.ttf`) | Copyright 2020 Braille Institute of America, Inc. | OFL 1.1 |
| `Fonts/Atkinson Hyperlegible Bold.ttf` | Atkinson Hyperlegible Bold (`ofl/atkinsonhyperlegible/AtkinsonHyperlegible-Bold.ttf`) | Copyright 2020 Braille Institute of America, Inc. | OFL 1.1 |
| `Fonts/Instrument Serif Italic.ttf` | [Instrument Serif](https://github.com/Instrument/instrument-serif) Italic (`ofl/instrumentserif/InstrumentSerif-Italic.ttf`) | Copyright 2022 The Instrument Serif Project Authors | OFL 1.1 |

## Made for Stow

We wrote or drew everything else ourselves, and it's under Stow's license (GPL-3.0). The text files
are `README.md`, `Specs/Color Tokens.json`, `Specs/Motion Notes.txt` and
`Earlier Rounds/Old Explorations/Notes.txt`. Their names, places and prices are invented.

The rest come from `scripts/make-sample-content.swift`, which renders them from the photos and fonts
above:

- `Logo/Harbor Mark.svg`, `Logo/Harbor Wordmark.svg`, `Logo/Harbor Mark@2x.png`. The lighthouse
  matches the sample app's icon (`Design/DemoAppIcon.svg`). The wordmark's letters are outlines of
  Instrument Serif Italic.
- `Screens/*.png` and `Screens/Dark/*.png`: mock iOS screens. Their icons are SF Symbols, used as
  Apple allows in mock-ups of apps for its platforms.
- `Specs/Brand Guidelines.pdf`
- `Video/Logo Reveal.jpg`: the poster frame for `Video/Logo Reveal.mov`, which has no file of its own.
- `Earlier Rounds/Old Explorations/Round 1/Wordmark Ideas.pdf`, `Round 2/Wordmark Draft.svg`,
  `Round 2/Mark Sketches.png`

The sample's other entries have no files here. `Prototype/Harbor Prototype.app` shows the lighthouse
icon from the app's asset catalog (`Design/DemoAppIcon.svg`). The installer, the audio and the inner
7Z archive show their system icons, as real ones would.

## Website hover-demo thumbnails

The thumbnails under `website/assets/demo/` are crops of the same CC0 photos listed above and
the first page of `Specs/Brand Guidelines.pdf`. They introduce no new licenses.
