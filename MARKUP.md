# Speech markup

Dysnow reads text as Markdown or as plain text, as chosen in the toolbar
(opening a `.md` or a `.txt` file chooses it too). Five tags in it set how
parts of the text are read. In Markdown they are HTML comments, so a
Markdown viewer shows nothing of them: the document reads the same with or
without them.

```markdown
We were two goals down. <!-- tts:mood value="excited" -->Then we scored three!<!-- /tts:mood -->

<!-- tts:speaker value="Fable" -->
"Well played," said the coach.
<!-- /tts:speaker -->

<!-- tts:speed value="0.8" -->Slowly, the crowd went home.<!-- /tts:speed -->

<!-- tts:language value="German" -->Auf Wiedersehen!<!-- /tts:language -->
```

Plain text has no comments, so there the tags are in brackets:

```text
We were two goals down. [tts:mood value="excited"]Then we scored three![/tts:mood]
```

In plain text nothing else is markup: `# Title` is read as "Title", and a
line starting with `-` is not a list item. Symbols are still not read out,
and empty lines still separate paragraphs.

## The tags

| Tag | Value | Effect |
|---|---|---|
| `<!-- tts:mood value="…" -->` … `<!-- /tts:mood -->` | a mood: `excited`, `sad`, … | the mood it is read in |
| `<!-- tts:speaker value="…" -->` … `<!-- /tts:speaker -->` | a speaker's name, `Fable`, or id, `bm_fable` | the voice it is read in |
| `<!-- tts:speed value="…" -->` … `<!-- /tts:speed -->` | a factor: `1.2`, `1,2` or `120%` | faster or slower than the speed set in the app |
| `<!-- tts:language value="…" -->` … `<!-- /tts:language -->` | a language's name, `German`, or id, `de` | the language it is read in |
| `<!-- tts:set language="…" model="…" speaker="…" speed="…" mood="…" -->` | any of these, each optional | changes them all from there on |

- A tag may wrap a few words in a sentence, or many paragraphs.
- Tags nest. The innermost mood, speaker and language count, and speeds multiply:
  `0.5` inside `1.2` is 0.6 times the app's speed.
- The value is in double or single quotes.
- Tags in code blocks are ignored, as the code is.
- Playing from the cursor, or a selection, takes the tags open at that point
  into account.

## Changing several things at once: `tts:set`

`tts:set` changes what its attributes say, from where it is on, until the
next `tts:set` changes it again. It needs no closing tag; a
`<!-- /tts:set -->` ends it, and what was before comes back. An attribute
left out, or empty, changes nothing. The attributes are best spaced, but
need not be: `language="Hungarian"speaker="Imre"` is read as two.

```markdown
Good morning, this part is English.

<!-- tts:set language="Hungarian" -->
Jó reggelt, ez a rész magyar.

<!-- tts:set language="en-gb" model="Kokoro" speaker="Fable" speed="0.9" -->
And English again, a little slower.
```

- `language`: by name or id. A language the chosen model does not speak is
  read by the first model that has a voice for it downloaded: Hungarian by
  Piper, while the rest is Kokoro's. This is how languages with no model in
  common are mixed.
- `model`: by name or id, `Piper`, `qwen3`, or the start of a name, `qwen`.
  Named, the model reads the text; a language it does not speak is then not
  looked for elsewhere.
- `speaker`: looked for in that model. Without one, the chosen speaker reads
  if the model is the chosen one, else the model's first voice there, a
  woman's or a man's as the chosen speaker is.
- `speed`: a factor on the app's speed, as `tts:speed`, but it replaces the
  one before rather than multiplying it.
- `mood`: as `tts:mood`.

Models make speech at different rates (Kokoro 24 kHz, Piper 22 kHz); Dysnow
converts each part to the rate of the first, so playing and saved files are
one piece. What cannot be followed -- a model, a language, a speaker there
is none of -- is read as chosen in the app, and the status bar says so.

## Writing tags: Control-Space

Control-Space in the editor (also Speech > Complete Markup, and
Option-Escape) helps write the tags, in the format chosen:

- Outside a tag it offers the kinds: speed, speaker, mood, language, set.
  The one picked is put around the selection, or at the cursor, with the
  cursor in its empty value, and the values are offered at once. `set` gets
  no closing tag unless it is put around a selection; its attributes are
  offered first, then their values.
- Outside a tag, when tags are open there, it first offers to close them,
  the innermost first: `Close /tts:mood`, `Close /tts:mood /tts:speed`, and
  so on, above the kinds. The one picked is closed with every tag opened
  inside it.
- In a `set` tag it offers the attributes not written yet. One put in right
  before another is spaced from it. The speakers it
  offers are those of the model and language written in the same tag.
- The values: the moods; the speakers of the model chosen that are there
  to speak (downloaded), in the language read at that point, which a
  `tts:language` tag before it may have changed; the model's languages.
  For a speed, `120%` is put in with `120` selected, to be typed over.
- In a tag written halfway it offers only what is missing: the rest of the
  kind, `value=""`, the value, the end of the tag. What is typed narrows the
  offer; when only one thing fits, it is put in without asking.
- After a value is picked, the cursor goes past the tag, to the text.

macOS uses Control-Space to switch between keyboard input sources when there
is more than one. It then never reaches Dysnow: switch that shortcut off in
System Settings, Keyboard, Keyboard Shortcuts, Input Sources, or use
Option-Escape.

## Languages

A language is looked for among those of the model chosen, by id or name,
ignoring case; `English` is its first English. A language the model does not
speak is read in the language chosen, and the status bar says so. With no
`tts:speaker` the voice stays the chosen one, speaking the other language
with its own accent.

## Speakers

A speaker is looked for among the voices of the current model, those of the
chosen language first: "Alex" is a Spanish and a Portuguese voice, and the
one of the language being read is taken. The id (`em_alex`, `pm_alex`)
picks one exactly. The language the text is read in stays the chosen one: a
French voice reading English text reads it with a French accent.

A speaker that is not found is read in the chosen voice, and the status bar
says so.

## Moods

Kokoro cannot be told a mood, so Dysnow shows it in the pace and the pauses:

| Mood | Pace | Pauses |
|---|---|---|
| `excited`, `enthusiastic`, `thrilled` | 12% faster | shorter |
| `happy`, `cheerful`, `joyful`, `glad` | 6% faster | a bit shorter |
| `angry`, `annoyed`, `furious` | 8% faster | shorter |
| `fearful`, `nervous`, `anxious`, `scared` | 10% faster | shorter, a breath after sentences |
| `sad`, `melancholic`, `sorrowful` | 15% slower | longer, after sentences too |
| `calm`, `gentle`, `tender`, `relaxed`, `soothing` | 8% slower | longer |
| `serious`, `solemn`, `formal` | 6% slower | a bit longer |
| `tired`, `sleepy`, `bored` | 18% slower | much longer |

Any other mood is read as written, with no change. The punctuation still
counts: Kokoro lifts its voice a little at "!" and rises at "?".

Qwen3-TTS can be told the mood itself. It gets it as an instruction:
`excited` becomes "very excited and energetic", `sad` "sad and slow, with a
heavy heart", another single word "in a … way", and a phrase is passed on
as written. So `value="whispering"` or `value="like a sports commentator"`
can be tried too. Its pace and pauses
are then left as they are. See [ENGINES.md](ENGINES.md).

ZipVoice and Pocket TTS are shown a mood by example: a voice of your own
may have a recording of how it sounds in a mood (Settings, My Voices, Add
a Mood). A `tts:mood` with such a recording is read the way it sounds;
another mood is shown in pace and pauses as for Kokoro.
