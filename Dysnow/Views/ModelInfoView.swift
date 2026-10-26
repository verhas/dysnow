import SwiftUI

/// What there is to know about a model before choosing it: what it is good
/// and bad at, what it costs in disk and time, and its licence.
struct ModelInfo {
    static let windowID = "model-info"

    let id: String
    let name: String
    let summary: String
    let languages: String
    let size: String
    let strengths: [String]
    let weaknesses: [String]
    let licence: [String]
    let source: URL

    static func of(_ id: String) -> ModelInfo? {
        all.first { $0.id == id }
    }

    static let all: [ModelInfo] = [
        ModelInfo(
            id: "kokoro", name: "Kokoro",
            summary: "A small, natural-sounding model with 53 voices, run on the processor through sherpa-onnx. "
                + "The one to start with.",
            languages: "English (US and UK), Spanish, French, Hindi, Italian, Japanese, Portuguese (Brazil), Chinese.",
            size: "One download of about 350 MB, for every voice and language.",
            strengths: [
                "Natural, clear speech, quicker than real time on any recent Mac, Intel ones too.",
                "Many voices, women's and men's, in each of its main languages.",
                "Follows the speed setting itself.",
            ],
            weaknesses: [
                "Cannot be told a mood: Dysnow shows moods in its pace and pauses only.",
                "No German, Hungarian, Russian or Korean; its non-English voices are fewer and plainer.",
                "Reads what it is given: abbreviations and signs are best written out first.",
            ],
            licence: [
                "The model: Apache License 2.0, by hexgrad. Commercial use is allowed.",
                "Its words are turned into sounds by eSpeak NG, GPL 3.0, built into sherpa-onnx.",
            ],
            source: URL(string: "https://huggingface.co/hexgrad/Kokoro-82M")!),
        ModelInfo(
            id: "piper", name: "Piper",
            summary: "Very small, very fast models of a voice or a few each, run through sherpa-onnx: 205 "
                + "voices in 47 languages, each downloaded on its own in the Settings.",
            languages: "47, from Arabic to Vietnamese, Hungarian, Polish, Czech, Russian and Ukrainian among them. A "
                + "language is offered in the main window once one of its voices is downloaded; Hungarian always.",
            size: "From 26 MB (x-low quality) to about 130 MB a download; most are 67 MB.",
            strengths: [
                "Speaks at many times real time, with little memory.",
                "Languages the larger models lack, Hungarian, Polish and Czech among them.",
                "Follows the speed setting itself.",
            ],
            weaknesses: [
                "Flatter and less natural than Kokoro or Qwen3-TTS; the x-low and low quality voices more so.",
                "Cannot be told a mood: shown in pace and pauses only.",
                "Of the models of many speakers, only those whose speakers are known are offered by name; of "
                    + "the large ones (LibriTTS, VCTK, ARCTIC) only the first speaker.",
            ],
            licence: [
                "Piper itself: MIT License. eSpeak NG, which turns the words into sounds, GPL 3.0.",
                "Each voice has a licence of its own, shown beside it in the Settings with a link to its model "
                    + "card. Many are free to use (CC0, public domain, CC BY); some are for non-commercial use "
                    + "only (CC BY-NC-SA, among them the Miro and Dii voices); some say nothing.",
            ],
            source: URL(string: "https://github.com/rhasspy/piper")!),
        ModelInfo(
            id: "qwen3", name: "Qwen3-TTS",
            summary: "A large model by Alibaba's Qwen team, run on the Mac's graphics processor through MLX. It "
                + "can be told in words how to speak.",
            languages: "English, German, Spanish, French, Italian, Portuguese, Russian, Japanese, Korean, Chinese.",
            size: "1.9 GB (0.6B, faster) or 2.9 GB (1.7B, follows moods better).",
            strengths: [
                "Lively, expressive speech; told the mood, \u{201C}excited\u{201D} or \u{201C}like a sports "
                    + "commentator\u{201D}, it speaks so.",
                "Nine speakers, each speaking all ten languages.",
            ],
            weaknesses: [
                "Apple silicon only.",
                "Large downloads; takes about ten seconds to load, and needs an optimised build to keep up with "
                    + "playback.",
                "Each reading comes out a little different. It can stumble on digits, which Dysnow writes out "
                    + "in words for it.",
                "Has no speed setting of its own: its speech is stretched in time.",
            ],
            licence: ["Apache License 2.0. Commercial use is allowed."],
            source: URL(string: "https://github.com/QwenLM/Qwen3-TTS")!),
        ModelInfo(
            id: "zipvoice", name: "ZipVoice",
            summary: "A voice-cloning model by the k2-fsa team, run through sherpa-onnx. It has no voices of "
                + "its own: it speaks in the voice of a recording, one of your own voices.",
            languages: "English and Chinese.",
            size: "About 156 MB: the model, and its vocoder, downloaded with it.",
            strengths: [
                "Any voice, from ten seconds of recording.",
                "Moods by example: a recording of the voice in a mood makes it speak in that mood.",
                "Quicker than real time on the processor.",
            ],
            weaknesses: [
                "Needs the words said in the recording, exactly.",
                "As good as the recording: noise, music or echo come through.",
                "Garbles words when asked for another speed: its speech is stretched in time instead.",
                "Only use voices whose owners have agreed to it.",
            ],
            licence: [
                "The code and the model: Apache License 2.0.",
                "It is trained on the Emilia speech collection, part of which may be used for non-commercial "
                    + "purposes only: check before using its speech commercially.",
            ],
            source: URL(string: "https://github.com/k2-fsa/ZipVoice")!),
        ModelInfo(
            id: "pocket", name: "Pocket TTS",
            summary: "A small voice-cloning model by Kyutai, run through sherpa-onnx. Like ZipVoice it speaks in "
                + "the voice of a recording, one of your own voices.",
            languages: "English.",
            size: "About 94 MB.",
            strengths: [
                "Small and quick: several times faster than real time on the processor.",
                "Does not need the words of the recording.",
                "Moods by example, as ZipVoice.",
            ],
            weaknesses: [
                "English only.",
                "Ignores the speed setting: its speech is stretched in time.",
                "Only use voices whose owners have agreed to it.",
            ],
            licence: [
                "The download's licence file is Creative Commons Attribution 4.0, but the notes of the converted "
                    + "model sherpa-onnx publishes say it is for non-commercial use: treat it as non-commercial.",
            ],
            source: URL(string: "https://github.com/kyutai-labs/pocket-tts")!),
        ModelInfo(
            id: "xtts", name: "XTTS v2",
            summary: "Coqui's multilingual voice-cloning model, run in Python 3.11 on the processor. Dysnow finds "
                + "Python on the Mac, sets up its libraries, and talks to it in the background.",
            languages: "English, Spanish, French, German, Italian, Portuguese, Polish, Turkish, Russian, Dutch, "
                + "Czech, Arabic, Chinese, Hungarian, Korean, Japanese, Hindi.",
            size: "The model 1.9 GB; its Python libraries about 2 GB more, in ~/.dysnow/xtts.",
            strengths: [
                "Natural, lively speech in 17 languages, Hungarian among them.",
                "58 speakers of its own, each speaking every language, and any voice from a recording of a few "
                    + "seconds: your own voices, with their moods.",
                "Follows the speed setting itself.",
            ],
            weaknesses: [
                "Needs Python 3.11, not newer, installed on the Mac; and some minutes to set up its libraries.",
                "Slower than real time on the processor: a sentence takes some seconds. The model takes ten "
                    + "seconds or more to load.",
                "Each reading comes out a little different; now and then it repeats or swallows a word.",
                "Only use voices whose owners have agreed to it.",
            ],
            licence: [
                "The model: Coqui Public Model License 1.0.0, for non-commercial use only. Coqui, the company, "
                    + "closed in 2024: a commercial licence can no longer be bought.",
                "The Coqui TTS library: Mozilla Public License 2.0.",
            ],
            source: URL(string: "https://huggingface.co/coqui/XTTS-v2")!),
    ]
}

/// The window telling about a model.
struct ModelInfoView: View {
    let engineID: String

    var body: some View {
        if let info = ModelInfo.of(engineID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(info.name).font(.largeTitle).bold()
                    Text(info.summary)
                    section("Languages") { Text(info.languages) }
                    section("Download") { Text(info.size) }
                    section("Good at") { bullets(info.strengths, symbol: "plus.circle.fill", color: .green) }
                    section("Not so good at") { bullets(info.weaknesses, symbol: "minus.circle.fill", color: .orange) }
                    section("Licence") {
                        Text("What is written here is for information only: it is not authoritative and not "
                            + "legally binding. Dysnow does not, by itself, grant you any right to the model, "
                            + "its voices or the speech made with them; check the licences at their source.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        bullets(info.licence, symbol: "doc.text", color: .secondary)
                    }
                    Link("More at \(info.source.host() ?? "its home page")", destination: info.source)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 520, height: 560)
        } else {
            Text("There is nothing to say about this model.").padding(40)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }

    private func bullets(_ lines: [String], symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines, id: \.self) { line in
                Label {
                    Text(line).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: symbol).foregroundStyle(color)
                }
            }
        }
    }
}

/// The (?) beside a model's name, opening the window about it.
struct ModelInfoButton: View {
    let engineID: String
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About \(ModelInfo.of(engineID)?.name ?? "the Model")", systemImage: "questionmark.circle") {
            openWindow(id: ModelInfo.windowID, value: engineID)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .help("What this model is good and bad at, and its licence")
    }
}

/// A Settings section's title, with the (?) beside it.
struct ModelSectionHeader: View {
    let title: String
    let engineID: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            ModelInfoButton(engineID: engineID)
        }
    }
}
