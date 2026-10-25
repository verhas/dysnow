# Dysnow 0.1.0

The first build: text in, speech out, with Kokoro's natural voices,
Piper's for Hungarian, and Qwen3-TTS, which reads in the mood it is told.

- Open a text file, or type or paste text into the editor.
- The text is read as Markdown: headings, lists, links and emphasis without
  their symbols, code blocks skipped, and a pause between paragraphs.
- Choose the language, then a woman's or a man's voice, then the speaker,
  who says hello when picked.
- Play the text, the selection, or from the cursor.
- Markup in HTML comments sets the mood, the speaker and the speed of parts
  of the text: see MARKUP.md.
- Save the speech as M4A, WAV, AIFF or FLAC. Files are made one after the
  other in a queue, with a notification when a long one is done.
- Kokoro's voice model is downloaded once, to `~/.dysnow/voices` or another
  folder, or an existing copy is used.
- Hungarian, with Piper's voices Anna, Berta and Imre: each downloaded on
  its own when first chosen, about 64 MB, and managed in Settings.
- Qwen3-TTS on Macs with Apple silicon: nine speakers in ten languages,
  German, Russian and Korean among them, told the mood of `tts:mood` tags in
  words. Its model, 1.9 or 2.9 GB, is downloaded once.
