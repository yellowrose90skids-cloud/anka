import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ANKA - multi-AI assistant. Users add their own FREE API keys in Settings.
late SharedPreferences prefs;

String pref(String k, [String d = '']) => prefs.getString(k) ?? d;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  prefs = await SharedPreferences.getInstance();
  runApp(const AnkaApp());
}

class AnkaApp extends StatelessWidget {
  const AnkaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ANKA',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF0E0B1F),
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF6C4DFF), brightness: Brightness.dark),
        ),
        home: const Home(),
      );
}

const ankaGradient = LinearGradient(
    colors: [Color(0xFF6C4DFF), Color(0xFF00BEFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight);

class AnkaLogo extends StatelessWidget {
  final double size;
  const AnkaLogo({super.key, this.size = 36});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            gradient: ankaGradient,
            borderRadius: BorderRadius.circular(size * .28)),
        alignment: Alignment.center,
        child: Text('A',
            style: TextStyle(
                color: Colors.white,
                fontSize: size * .62,
                fontWeight: FontWeight.w900)),
      );
}

class Msg {
  final bool user;
  final String text;
  final File? image;
  Msg(this.user, this.text, [this.image]);
}

// ---------- AI calls ----------
Future<String> askGemini(List<Msg> history) async {
  final key = pref('gk');
  if (key.isEmpty) return 'Add your free Gemini key in Settings first.';
  final contents = <Map<String, dynamic>>[];
  for (final m in history) {
    final parts = <Map<String, dynamic>>[
      {'text': m.text}
    ];
    if (m.image != null) {
      parts.add({
        'inline_data': {
          'mime_type': 'image/jpeg',
          'data': base64Encode(await m.image!.readAsBytes())
        }
      });
    }
    contents.add({'role': m.user ? 'user' : 'model', 'parts': parts});
  }
  final model = pref('gm', 'gemini-2.5-flash-lite');
  final r = await http.post(
    Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$key'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'contents': contents}),
  );
  final j = jsonDecode(r.body);
  if (r.statusCode != 200) {
    return 'Error ${r.statusCode}: ${j['error']?['message'] ?? r.body}';
  }
  return j['candidates'][0]['content']['parts'][0]['text'];
}

Future<String> askOpenRouter(List<Msg> history) async {
  final key = pref('ok');
  if (key.isEmpty) return 'Add your free OpenRouter key in Settings first.';
  final r = await http.post(
    Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $key'
    },
    body: jsonEncode({
      'model': pref('om', 'meta-llama/llama-3.3-70b-instruct:free'),
      'messages': [
        for (final m in history)
          {'role': m.user ? 'user' : 'assistant', 'content': m.text}
      ],
    }),
  );
  final j = jsonDecode(r.body);
  if (r.statusCode != 200) {
    return 'Error ${r.statusCode}: ${j['error']?['message'] ?? r.body}';
  }
  return j['choices'][0]['message']['content'];
}

// ---------- Home ----------
class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Row(children: [
            AnkaLogo(size: 32),
            SizedBox(width: 10),
            Text('ANKA',
                style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 3)),
          ]),
        ),
        body: IndexedStack(index: tab, children: const [
          ChatPage(),
          PhotoPage(),
          SettingsPage(),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.chat), label: 'Chat'),
            NavigationDestination(icon: Icon(Icons.tune), label: 'Photo'),
            NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      );
}

// ---------- Chat ----------
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final msgs = <Msg>[];
  final ctl = TextEditingController();
  String ai = 'Gemini';
  File? pic;
  bool busy = false;

  Future<void> pick() async {
    final x = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 1280);
    if (x != null) setState(() => pic = File(x.path));
  }

  Future<void> send() async {
    final t = ctl.text.trim();
    if ((t.isEmpty && pic == null) || busy) return;
    if (pic != null && ai != 'Gemini') {
      setState(() => msgs.add(Msg(false, 'Photos work with Gemini only.')));
      return;
    }
    setState(() {
      msgs.add(Msg(true, t.isEmpty ? 'Describe this photo.' : t, pic));
      busy = true;
      ctl.clear();
      pic = null;
    });
    String a;
    try {
      a = ai == 'Gemini' ? await askGemini(msgs) : await askOpenRouter(msgs);
    } catch (e) {
      a = 'Error: $e';
    }
    setState(() {
      msgs.add(Msg(false, a));
      busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'Gemini', label: Text('Gemini')),
            ButtonSegment(value: 'OpenRouter', label: Text('OpenRouter')),
          ],
          selected: {ai},
          onSelectionChanged: (s) => setState(() => ai = s.first),
        ),
      ),
      Expanded(
        child: msgs.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const AnkaLogo(size: 84),
                  const SizedBox(height: 16),
                  const Text("Hi, I'm ANKA",
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('Ask me anything, or add a photo'),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, children: [
                    for (final q in ['Explain something simply', 'Help me write a message', 'Business ideas'])
                      ActionChip(label: Text(q), onPressed: () { ctl.text = q; send(); }),
                  ]),
                ]),
              )
            : ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: msgs.length,
          itemBuilder: (_, i) {
            final m = msgs[i];
            return Align(
              alignment: m.user ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(12),
                constraints: const BoxConstraints(maxWidth: 320),
                decoration: BoxDecoration(
                  gradient: m.user ? ankaGradient : null,
                  color: m.user ? null : cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (m.image != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Image.file(m.image!, height: 120),
                    ),
                  SelectableText(m.text),
                ]),
              ),
            );
          },
        ),
      ),
      if (busy) const LinearProgressIndicator(),
      if (pic != null)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            Image.file(pic!, height: 56),
            IconButton(
                onPressed: () => setState(() => pic = null),
                icon: const Icon(Icons.close)),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          IconButton(onPressed: pick, icon: const Icon(Icons.image)),
          Expanded(
            child: TextField(
              controller: ctl,
              decoration: const InputDecoration(
                  hintText: 'Ask anything...', border: OutlineInputBorder()),
              onSubmitted: (_) => send(),
            ),
          ),
          IconButton(onPressed: send, icon: const Icon(Icons.send)),
        ]),
      ),
    ]);
  }
}

// ---------- Photo editor (free, on-device, no AI) ----------
class PhotoPage extends StatefulWidget {
  const PhotoPage({super.key});
  @override
  State<PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<PhotoPage> {
  File? img;
  double bri = 0, con = 1, sat = 1;
  int turns = 0;

  List<double> matrix() {
    const lr = .2126, lg = .7152, lb = .0722;
    final s = sat, c = con, t = 128 * (1 - c) + bri * 255;
    return [
      c * (lr * (1 - s) + s), c * lg * (1 - s), c * lb * (1 - s), 0, t,
      c * lr * (1 - s), c * (lg * (1 - s) + s), c * lb * (1 - s), 0, t,
      c * lr * (1 - s), c * lg * (1 - s), c * (lb * (1 - s) + s), 0, t,
      0, 0, 0, 1, 0,
    ];
  }

  Widget slider(String label, double v, double min, double max, ValueChanged<double> f) =>
      Row(children: [
        SizedBox(width: 90, child: Text(label)),
        Expanded(child: Slider(value: v, min: min, max: max, onChanged: f)),
      ]);

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(12), children: [
        FilledButton.icon(
          onPressed: () async {
            final x = await ImagePicker().pickImage(source: ImageSource.gallery);
            if (x != null) setState(() => img = File(x.path));
          },
          icon: const Icon(Icons.photo_library),
          label: const Text('Choose photo'),
        ),
        const SizedBox(height: 12),
        if (img != null) ...[
          SizedBox(
            height: 320,
            child: Center(
              child: RotatedBox(
                quarterTurns: turns,
                child: ColorFiltered(
                  colorFilter: ColorFilter.matrix(matrix()),
                  child: Image.file(img!),
                ),
              ),
            ),
          ),
          slider('Brightness', bri, -.5, .5, (v) => setState(() => bri = v)),
          slider('Contrast', con, .5, 1.8, (v) => setState(() => con = v)),
          slider('Saturation', sat, 0, 2, (v) => setState(() => sat = v)),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            OutlinedButton.icon(
                onPressed: () => setState(() => turns = (turns + 1) % 4),
                icon: const Icon(Icons.rotate_right),
                label: const Text('Rotate')),
            OutlinedButton(
                onPressed: () => setState(() {
                      bri = 0;
                      con = 1;
                      sat = 1;
                      turns = 0;
                    }),
                child: const Text('Reset')),
          ]),
        ],
      ]);
}

// ---------- Settings ----------
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Widget field(String label, String key, {String def = '', bool secret = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: TextEditingController(text: pref(key, def)),
          obscureText: secret,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          onChanged: (v) => prefs.setString(key, v.trim()),
        ),
      );

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Keys stay on this phone. Get free keys at aistudio.google.com and openrouter.ai.'),
        const SizedBox(height: 16),
        field('Gemini API key', 'gk', secret: true),
        field('Gemini model', 'gm', def: 'gemini-2.5-flash-lite'),
        field('OpenRouter API key', 'ok', secret: true),
        field('OpenRouter model (pick one ending in :free)', 'om',
            def: 'meta-llama/llama-3.3-70b-instruct:free'),
      ]);
}
