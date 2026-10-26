import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Sentences to read aloud for a recording, in the language recorded in,
/// each written to be said in its mood.
enum ReadingText {
    /// About ten seconds of everyday speech, by language.
    static func neutral(_ languageID: String) -> String {
        switch languageID.prefix(2) {
        case "ar": "كان الطقس جميلاً، فمشينا على ضفة النهر حتى الطاحونة القديمة ثم عدنا. استغرق ذلك معظم فترة بعد "
            + "الظهر، لكن أحداً لم يمانع."
        case "cs": "Bylo hezky, a tak jsme šli podél řeky ke starému mlýnu a zpátky. Trvalo to skoro celé odpoledne, "
            + "ale nikomu to nevadilo."
        case "de": "Das Wetter war schön, also gingen wir am Fluss entlang bis zur alten Mühle und zurück. Es dauerte "
            + "fast den ganzen Nachmittag, aber das störte niemanden."
        case "es": "Hacía buen tiempo, así que caminamos junto al río hasta el viejo molino y volvimos. Nos llevó "
            + "casi toda la tarde, pero a nadie le importó."
        case "fr": "Il faisait beau, alors nous avons marché le long de la rivière jusqu'au vieux moulin, puis nous "
            + "sommes revenus. Cela a pris presque tout l'après-midi, mais personne ne s'en est plaint."
        case "hi": "मौसम अच्छा था, इसलिए हम नदी के किनारे-किनारे पुरानी चक्की तक गए और लौट आए। इसमें लगभग पूरी "
            + "दोपहर लग गई, पर किसी को बुरा नहीं लगा।"
        case "hu": "Az idő jó volt, ezért lesétáltunk a folyó mentén az öreg malomig és vissza. Az egész délután "
            + "ráment, de senki sem bánta."
        case "it": "Il tempo era bello, così abbiamo camminato lungo il fiume fino al vecchio mulino e ritorno. Ci è "
            + "voluto quasi tutto il pomeriggio, ma a nessuno è dispiaciuto."
        case "ja": "天気が良かったので、川沿いを古い水車小屋まで歩いて戻ってきました。午後のほとんどがかかりましたが、"
            + "誰も気にしませんでした。"
        case "ko": "날씨가 좋아서 우리는 강을 따라 오래된 방앗간까지 걸어갔다가 돌아왔어요. 오후 내내 걸렸지만 아무도 "
            + "개의치 않았어요."
        case "nl": "Het was mooi weer, dus liepen we langs de rivier naar de oude molen en terug. Het kostte bijna de "
            + "hele middag, maar niemand vond dat erg."
        case "pl": "Pogoda była ładna, więc poszliśmy wzdłuż rzeki do starego młyna i z powrotem. Zajęło nam to "
            + "prawie całe popołudnie, ale nikomu to nie przeszkadzało."
        case "pt": "O tempo estava bom, então caminhamos ao longo do rio até o velho moinho e voltamos. Levou quase a "
            + "tarde toda, mas ninguém se importou."
        case "ru": "Погода была хорошая, и мы прошлись вдоль реки до старой мельницы и обратно. На это ушла почти "
            + "вся вторая половина дня, но никто не возражал."
        case "tr": "Hava güzeldi, bu yüzden nehir boyunca eski değirmene kadar yürüyüp geri döndük. Neredeyse bütün "
            + "öğleden sonramızı aldı ama kimse aldırmadı."
        case "zh": "天气很好，所以我们沿着河边走到老磨坊，又走了回来。这几乎花了整个下午，但没有人介意。"
        default: "The weather was fine, so we walked along the river to the old mill and back. It took most of the "
            + "afternoon, but nobody minded."
        }
    }

    /// A sentence to say in the mood; in a language with none written for
    /// the mood, the everyday one, to be said in the mood.
    static func forMood(_ mood: String, languageID: String) -> String {
        let group = SpeechMarkup.prosodyGroup(of: mood.lowercased())
        switch languageID.prefix(2) {
        case "en":
            switch group {
            case "excited": return "We did it! I can't believe it, we actually won the whole thing!"
            case "happy": return "What a lovely morning! The sun is out, and everyone is smiling."
            case "angry": return "This is the third time you have broken your promise, and I am done waiting."
            case "fearful": return "Did you hear that? Something is moving in the dark, behind the door."
            case "sad": return "I waited for hours, but she never came back, and the house felt so empty."
            case "calm": return "Take a slow breath, let your shoulders drop, and listen to the rain outside."
            case "serious": return "The results are in, and they leave us with a difficult decision to make."
            case "tired": return "It has been such a long day. I think I will just close my eyes for a while."
            default: break
            }
        case "hu":
            switch group {
            case "excited": return "Sikerült! El sem hiszem, tényleg megnyertük az egészet!"
            case "happy": return "Milyen gyönyörű reggel! Süt a nap, és mindenki mosolyog."
            case "angry": return "Már harmadszor szeged meg az ígéretedet, és elegem van a várakozásból."
            case "fearful": return "Hallottad ezt? Valami mozog a sötétben, az ajtó mögött."
            case "sad": return "Órákig vártam, de nem jött vissza, és a ház olyan üresnek tűnt."
            case "calm": return "Vegyél egy lassú, mély levegőt, engedd le a vállad, és hallgasd a kinti esőt."
            case "serious": return "Megvannak az eredmények, és nehéz döntés elé állítanak minket."
            case "tired": return "Olyan hosszú nap volt. Azt hiszem, lehunyom egy kicsit a szemem."
            default: break
            }
        default:
            break
        }
        return neutral(languageID)
    }
}

/// Makes a voice of a recording, or records how a voice sounds in a mood:
/// recorded here, or taken from a sound file, with the words said in it.
struct VoiceRecordingSheet: View {
    let purpose: VoiceSheet
    let store: MyVoiceStore
    /// The model the voice is made for, which says what it needs; nil when
    /// made in the Settings.
    var engineID: String?
    /// Called with the voice made or changed.
    let done: (String) -> Void

    /// `languageID` is the one first offered to record in: the text's.
    init(purpose: VoiceSheet, store: MyVoiceStore, languageID: String, engineID: String? = nil,
         done: @escaping (String) -> Void) {
        self.purpose = purpose
        self.store = store
        self.engineID = engineID
        self.done = done
        _languageID = State(initialValue: languageID)
        _transcript = State(initialValue: ReadingText.neutral(languageID))
    }

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var gender = SpeechGender.female
    @State private var mood = ""
    @State private var fromFile = false
    @State private var transcript: String
    /// The language recorded in: the words to read, and the one they are
    /// written down in from a file.
    @State private var languageID: String
    @State private var audio: SynthesizedAudio?
    @State private var fileName: String?
    @State private var problem: String?
    @State private var transcribing = false
    @State private var recorder = VoiceRecorder()
    @State private var player = AudioPlayer()

    private var moodVoice: MyVoice? {
        if case .mood(let id) = purpose { store.voices.first { $0.id == id } } else { nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(moodVoice.map { "How \($0.name) Sounds in a Mood" } ?? "New Voice").font(.title2).bold()
            Form {
                if let voice = moodVoice {
                    TextField("Mood", text: $mood, prompt: Text("excited"))
                        .onChange(of: mood) {
                            if !fromFile && audio == nil {
                                transcript = ReadingText.forMood(mood, languageID: languageID)
                            }
                        }
                    Text("When text is to be read in this mood, \(voice.name) speaks the way this recording sounds.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    TextField("Name", text: $name, prompt: Text("The voice's name"))
                    Picker("Gender", selection: $gender) {
                        ForEach(SpeechGender.allCases) { Text($0.title).tag($0) }
                    }
                }
                Picker("Language", selection: $languageID) {
                    ForEach(Self.languages) { Text($0.name).tag($0.id) }
                }
                .onChange(of: languageID) {
                    if !fromFile && audio == nil {
                        transcript = moodVoice == nil ? ReadingText.neutral(languageID)
                            : ReadingText.forMood(mood, languageID: languageID)
                    }
                }
                Picker("Recording", selection: $fromFile) {
                    Text("Record Now").tag(false)
                    Text("From a Sound File").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: fromFile) {
                    audio = nil
                    fileName = nil
                }
                if fromFile {
                    fileRow
                } else {
                    recordRow
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(fromFile ? "What is said in it" : "Read this aloud, as it is written").font(.callout)
                    TextEditor(text: $transcript)
                        .font(.body)
                        .frame(height: 64)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
                    if fromFile {
                        Button(transcribing ? "Listening…" : "Write It Down from the Recording") { transcribe() }
                            .disabled(audio == nil || transcribing)
                    }
                    Text(wordsNote).font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            if let problem {
                Text(problem).foregroundStyle(.red).font(.callout)
            }
            if let missing = whyNotSaving {
                Text(missing).foregroundStyle(.secondary).font(.callout)
            }
            Text("Only use your own voice, or the voice of someone who has agreed to it.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    stopEverything()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            if let voice = moodVoice {
                gender = voice.gender
                mood = ""
            }
        }
        .onDisappear(perform: stopEverything)
    }

    private var recordRow: some View {
        HStack(spacing: 10) {
            if recorder.isRecording {
                Button("Stop", systemImage: "stop.circle.fill") { stopRecording() }
                    .foregroundStyle(.red)
                ProgressView(value: Double(recorder.level)).frame(width: 120)
                Text(Self.seconds(recorder.duration)).monospacedDigit()
            } else {
                Button(audio == nil ? "Record" : "Record Again", systemImage: "record.circle") { startRecording() }
                if let audio {
                    playButton
                    Text(Self.seconds(audio.duration)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var fileRow: some View {
        HStack(spacing: 10) {
            Button("Choose File…", action: chooseFile)
            if let fileName {
                Text(fileName).lineLimit(1).truncationMode(.middle)
            }
            if let audio {
                playButton
                Text(Self.seconds(audio.duration)).monospacedDigit().foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var playButton: some View {
        Button("Play", systemImage: "play.fill") {
            guard let audio else { return }
            try? player.start(sampleRate: audio.sampleRate)
            player.enqueue(audio.samples)
        }
        .labelStyle(.iconOnly)
    }

    private var canSave: Bool { whyNotSaving == nil }

    /// What is still missing before the voice can be saved.
    private var whyNotSaving: String? {
        if recorder.isRecording {
            if recorder.duration < 1 { return "Read the text aloud; Save stops the recording." }
        } else if let audio {
            if audio.duration < 1 { return "The recording is too short: read the whole text." }
        } else {
            return fromFile ? "Choose a sound file of the voice." : "Press Record, and read the text aloud."
        }
        if moodVoice != nil {
            return mood.trimmingCharacters(in: .whitespaces).isEmpty ? "Write the mood: excited, calm…" : nil
        }
        return name.trimmingCharacters(in: .whitespaces).isEmpty ? "Give the voice a name." : nil
    }

    /// What the words in the box are for, for the model the voice is for.
    private var wordsNote: String {
        switch engineID {
        case "zipvoice": "ZipVoice needs these words to be exactly what is said in the recording."
        case "pocket": "Pocket TTS needs only the recording: the words are kept, for ZipVoice."
        case "xtts": "XTTS v2 needs only the recording: the words are kept, for ZipVoice."
        default: "ZipVoice needs these words to be exactly what is said; XTTS v2 and Pocket TTS need only the "
            + "recording."
        }
    }

    /// Every language a model of the app speaks.
    private static let languages: [SpeechLanguage] = {
        var seen = Set<String>()
        return SpeechEngines.all.flatMap(\.languages).filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()

    private static func seconds(_ duration: TimeInterval) -> String {
        duration.formatted(.number.precision(.fractionLength(1))) + " s"
    }

    private func startRecording() {
        problem = nil
        player.stop()
        Task {
            do {
                try await recorder.start()
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    private func stopRecording() {
        do {
            let recorded = try recorder.stop()
            audio = recorded
            problem = recorded.duration < 3 ? "That is short: five to fifteen seconds make a better voice." : nil
        } catch {
            problem = error.localizedDescription
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.message = "Choose a recording of the voice: five to fifteen seconds of speech, without music."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let read = AudioImporter.trimmed(try AudioImporter.read(url))
            audio = read
            fileName = url.lastPathComponent
            transcript = ""
            problem = read.duration < 3 ? "That is short: five to fifteen seconds make a better voice." : nil
            transcribe()
        } catch {
            problem = "\(url.lastPathComponent) could not be read: \(error.localizedDescription)"
        }
    }

    private func transcribe() {
        guard let audio else { return }
        transcribing = true
        Task {
            defer { transcribing = false }
            do {
                transcript = try await Transcriber.transcribe(audio, languageID: languageID)
            } catch {
                problem = "The words could not be written down: \(error.localizedDescription) "
                    + "They can be typed in instead."
            }
        }
    }

    private func save() {
        if recorder.isRecording { stopRecording() }
        guard let audio, audio.duration >= 1 else { return }
        let words = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let voice = moodVoice {
                try store.addMood(mood, to: voice.id, audio: audio, transcript: words)
                done(voice.id)
            } else {
                let voice = try store.add(name: name.trimmingCharacters(in: .whitespaces), gender: gender,
                                          audio: audio, transcript: words)
                done(voice.id)
            }
            stopEverything()
            dismiss()
        } catch {
            problem = "The voice could not be saved: \(error.localizedDescription)"
        }
    }

    private func stopEverything() {
        if recorder.isRecording { _ = try? recorder.stop() }
        player.stop()
    }
}

/// The Settings window's list of the user's voices.
struct MyVoicesSettings: View {
    let store: MyVoiceStore
    @State private var sheet: VoiceSheet?
    @State private var deleting: MyVoice?
    @State private var player = AudioPlayer()
    @State private var problem: String?

    var body: some View {
        Form {
            Section {
                if store.voices.isEmpty {
                    Text("No voices yet. A voice is made of a recording of ten seconds or so; ZipVoice and "
                        + "Pocket TTS then read text in it.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.voices) { voice in
                    VoiceRow(voice: voice, store: store, play: { play(voice, mood: $0) },
                             addMood: { sheet = .mood(voiceID: voice.id) }, delete: { deleting = voice })
                }
            } header: {
                HStack {
                    Text("My voices")
                    Spacer()
                    Button("Add a Voice…", systemImage: "plus") { sheet = .newVoice }
                }
            } footer: {
                Text("Kept in \(store.library.directory.abbreviatedPath). A recording of a mood makes the voice "
                    + "speak in that mood where the text says so with a mood tag.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let problem {
                Text(problem).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $sheet) { sheet in
            VoiceRecordingSheet(purpose: sheet, store: store,
                                languageID: UserDefaults.standard.string(forKey: "speech.language") ?? "en-us") { _ in }
        }
        .confirmationDialog("Delete \(deleting?.name ?? "")'s voice?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                guard let voice = deleting else { return }
                do { try store.remove(voice.id) } catch { problem = error.localizedDescription }
            }
        } message: {
            Text("Its recordings are deleted from the disk.")
        }
    }

    private func play(_ voice: MyVoice, mood: String?) {
        do {
            let audio = try store.library.reference(for: voice.id, mood: mood).audio
            try player.start(sampleRate: audio.sampleRate)
            player.enqueue(audio.samples)
        } catch {
            problem = error.localizedDescription
        }
    }
}

private struct VoiceRow: View {
    let voice: MyVoice
    let store: MyVoiceStore
    let play: (String?) -> Void
    let addMood: () -> Void
    let delete: () -> Void
    @State private var name = ""
    @State private var transcript = ""

    var body: some View {
        DisclosureGroup {
            TextField("Name", text: $name)
                .onSubmit { change { $0.name = name.trimmingCharacters(in: .whitespaces) } }
            Picker("Gender", selection: Binding(get: { voice.gender }, set: { gender in change { $0.gender = gender } })) {
                ForEach(SpeechGender.allCases) { Text($0.title).tag($0) }
            }
            TextField("What is said", text: $transcript, axis: .vertical)
                .lineLimit(2...4)
                .onSubmit { change { $0.sample.transcript = transcript } }
            LabeledContent("Moods") {
                HStack {
                    ForEach(voice.moods.keys.sorted(), id: \.self) { mood in
                        HStack(spacing: 2) {
                            Button(mood) { play(mood) }
                                .buttonStyle(.borderless)
                                .help("Play the recording of \(mood)")
                            Button("Delete \(mood)", systemImage: "xmark.circle.fill") {
                                try? store.removeMood(mood, from: voice.id)
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                    }
                    Button("Add a Mood…", action: addMood)
                }
            }
        } label: {
            HStack {
                Text(voice.name).bold()
                Text(voice.gender.title).foregroundStyle(.secondary)
                if !voice.moods.isEmpty {
                    Text(voice.moods.keys.sorted().joined(separator: ", ")).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Play", systemImage: "play.fill") { play(nil) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                Button("Delete", systemImage: "trash", action: delete)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
        }
        .onAppear {
            name = voice.name
            transcript = voice.sample.transcript
        }
    }

    private func change(_ edit: (inout MyVoice) -> Void) {
        var changed = voice
        edit(&changed)
        guard changed != voice, !changed.name.isEmpty else { return }
        try? store.update(changed)
    }
}
