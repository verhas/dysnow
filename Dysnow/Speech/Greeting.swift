/// What a voice says when it is picked: its name, in its own language.
enum Greeting {
    static func text(languageID: String, name: String) -> String {
        switch languageID.prefix(2) {
        case "es": "Hola, soy \(name). Así es como sueno."
        case "fr": "Bonjour, je suis \(name). Voici ma voix."
        case "hi": "नमस्ते, मैं \(name) हूँ। मेरी आवाज़ ऐसी है।"
        case "it": "Ciao, sono \(name). Ecco come suona la mia voce."
        case "ja": "こんにちは、\(name)です。私の声はこんな感じです。"
        case "pt": "Olá, eu sou \(name). Esta é a minha voz."
        case "zh": "你好，我是\(name)。这就是我的声音。"
        default: "Hi, I am \(name). This is how I sound."
        }
    }
}
