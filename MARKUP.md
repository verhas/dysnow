# Speech markup

Dysnow reads text as Markdown, and three tags in it set how parts of the text
are read. They are HTML comments, so a Markdown viewer shows nothing of them:
the document reads the same with or without them.

```markdown
We were two goals down. <!-- tts:mood value="excited" -->Then we scored three!<!-- /tts:mood -->

<!-- tts:speaker value="Fable" -->
"Well played," said the coach.
<!-- /tts:speaker -->

<!-- tts:speed value="0.8" -->Slowly, the crowd went home.<!-- /tts:speed -->
```

## The tags

| Tag | Value | Effect |
|---|---|---|
| `<!-- tts:mood value="…" -->` … `<!-- /tts:mood -->` | a mood: `excited`, `sad`, … | the mood it is read in |
| `<!-- tts:speaker value="…" -->` … `<!-- /tts:speaker -->` | a speaker's name, `Fable`, or id, `bm_fable` | the voice it is read in |
| `<!-- tts:speed value="…" -->` … `<!-- /tts:speed -->` | a factor: `1.2`, `1,2` or `120%` | faster or slower than the speed set in the app |

- A tag may wrap a few words in a sentence, or many paragraphs.
- Tags nest. The innermost mood and speaker count, and speeds multiply:
  `0.5` inside `1.2` is 0.6 times the app's speed.
- The value is in double or single quotes.
- Tags in code blocks are ignored, as the code is.
- Playing from the cursor, or a selection, takes the tags open at that point
  into account.

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
