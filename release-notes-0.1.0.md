# Dysnow 0.1.0

The first build: text in, speech out, with Kokoro's natural voices.

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
