import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../nasira_app_state.dart';
import '../theme/nasira_colors.dart';
import '../widgets/nasira_grid_cell.dart';
import '../widgets/nasira_module_header.dart';
import 'freies_schreiben_screen.dart';

// ── Hilfsfunktion: Hauptwort für Symbol-Lookup ────────────────────────────────

/// Extrahiert das wichtigste Substantiv aus einem deutschen Satz.
/// Bevorzugt das letzte großgeschriebene Wort (= Nomen), das kein Stoppwort ist.
String _keyWord(String sentence) {
  const skip = {
    'ich', 'du', 'er', 'sie', 'es', 'wir', 'ihr',
    'mir', 'mich', 'dir', 'dich', 'ihn', 'uns', 'euch',
    'habe', 'haben', 'hat', 'hatte', 'bin', 'ist', 'war', 'sind', 'waren',
    'ein', 'eine', 'einen', 'einem', 'einer',
    'der', 'die', 'das', 'den', 'dem', 'des',
    'für', 'mit', 'von', 'zu', 'zum', 'zur', 'in', 'im', 'am', 'an', 'auf', 'bei',
    'und', 'oder', 'aber', 'nicht', 'auch', 'sehr', 'viel',
    'mein', 'meine', 'meinen', 'meinem', 'dein', 'deinen', 'deiner',
    'schon', 'noch', 'mal', 'immer', 'bald', 'wieder', 'lang', 'lange',
    'letzten', 'letzte', 'letzter',
  };

  final words = sentence
      .replaceAll(RegExp(r'[.!?,;]'), '')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();

  if (words.isEmpty) return sentence;

  final nouns = words.length > 1
      ? words
          .skip(1)
          .where((w) =>
              w.length >= 3 &&
              w[0] == w[0].toUpperCase() &&
              !skip.contains(w.toLowerCase()))
          .toList()
      : <String>[];

  if (nouns.isNotEmpty) return nouns.last;

  final content = words
      .where((w) => w.length >= 3 && !skip.contains(w.toLowerCase()))
      .toList();
  return content.isEmpty ? words.last : content.last;
}

// ── Datenmodelle ──────────────────────────────────────────────────────────────

class BriefWortItem {
  final String text;
  final String? symbolWord;   // expliziter Lookup-Override für Mehrwort-Einträge
  const BriefWortItem(this.text, {this.symbolWord});
}

class BriefPhraseButton {
  final String label;
  final String insertText;
  const BriefPhraseButton(this.label, this.insertText);
}

class BriefThemaConfig {
  final String name;
  final String leitfrage;
  final List<BriefWortItem> woerter;
  final List<BriefPhraseButton> phraseButtons;

  const BriefThemaConfig({
    required this.name,
    required this.leitfrage,
    required this.woerter,
    required this.phraseButtons,
  });
}

// ── Thema-Inhalte (aus den Grid-XMLs) ─────────────────────────────────────────

const _themenGefuehle = BriefThemaConfig(
  name: 'Gefühle',
  leitfrage: 'Wie hast du dich gefühlt?',
  woerter: [
    BriefWortItem('glücklich'), BriefWortItem('traurig'),
    BriefWortItem('wütend'),   BriefWortItem('ruhig'),
    BriefWortItem('super'),    BriefWortItem('verliebt'),
    BriefWortItem('mutig'),    BriefWortItem('genervt'),
    BriefWortItem('einsam'),   BriefWortItem('ängstlich'),
    BriefWortItem('stolz'),    BriefWortItem('enttäuscht'),
    BriefWortItem('schüchtern'), BriefWortItem('verlegen'),
    BriefWortItem('besorgt'),  BriefWortItem('ok'),
    BriefWortItem('krank'),    BriefWortItem('schlecht gelaunt', symbolWord: 'schlecht'),
  ],
  phraseButtons: [
    BriefPhraseButton('Ich bin', 'Ich bin'),
    BriefPhraseButton('Ich war', 'Ich war'),
    BriefPhraseButton('Bist du', 'Bist du'),
    BriefPhraseButton('Warst du', 'Warst du'),
  ],
);

const _themenEssen = BriefThemaConfig(
  name: 'Essen',
  leitfrage: 'Was hast du gegessen?',
  woerter: [
    BriefWortItem('Pizza'),      BriefWortItem('Burger'),
    BriefWortItem('Nudeln'),     BriefWortItem('Reis'),
    BriefWortItem('Salat'),      BriefWortItem('Suppe'),
    BriefWortItem('Kuchen'),     BriefWortItem('Eis'),
    BriefWortItem('Schokolade'), BriefWortItem('Fisch'),
    BriefWortItem('Gemüse'),     BriefWortItem('Kartoffeln'),
    BriefWortItem('Pfannkuchen'),BriefWortItem('Joghurt'),
    BriefWortItem('Obst'),       BriefWortItem('Süßigkeiten'),
  ],
  phraseButtons: [
    BriefPhraseButton('Ich mag', 'Ich mag'),
    BriefPhraseButton('Heute gibt es', 'Heute gibt es'),
    BriefPhraseButton('Magst du', 'Magst du'),
  ],
);

const _themenTrinken = BriefThemaConfig(
  name: 'Trinken',
  leitfrage: 'Was trinkst du gerne?',
  woerter: [
    BriefWortItem('Tee'),
    BriefWortItem('Kaffee'),
    BriefWortItem('Kakao'),
    BriefWortItem('Wasser'),
    BriefWortItem('Apfelsaft',    symbolWord: 'Apfel'),
    BriefWortItem('Orangensaft',  symbolWord: 'Orange'),
    BriefWortItem('Saft'),
    BriefWortItem('Milch'),
    BriefWortItem('Cola'),
    BriefWortItem('Eistee',       symbolWord: 'Tee'),
  ],
  phraseButtons: [
    BriefPhraseButton('Heute gibt es', 'Heute gibt es'),
    BriefPhraseButton('Ich mag', 'Ich mag'),
    BriefPhraseButton('Magst du', 'Magst du'),
  ],
);

const _themenSchule = BriefThemaConfig(
  name: 'Schule',
  leitfrage: 'Wie war die Schule?',
  woerter: [
    BriefWortItem('spannend'),
    BriefWortItem('langweilig'),
    BriefWortItem('super'),
    BriefWortItem('toll'),
    BriefWortItem('wie immer', symbolWord: 'immer'),
  ],
  phraseButtons: [
    BriefPhraseButton('In der Schule', 'In der Schule'),
    BriefPhraseButton('Wie war es in der Schule?', 'Wie war es in der Schule?'),
    BriefPhraseButton('war es', 'war es'),
    BriefPhraseButton('ist es', 'ist es'),
  ],
);

const _themenWetter = BriefThemaConfig(
  name: 'Wetter',
  leitfrage: 'Wie war das Wetter?',
  woerter: [
    BriefWortItem('scheint die Sonne',   symbolWord: 'Sonne'),
    BriefWortItem('regnet es',           symbolWord: 'Regen'),
    BriefWortItem('ist ein Gewitter',    symbolWord: 'Gewitter'),
    BriefWortItem('stürmt es',           symbolWord: 'Sturm'),
    BriefWortItem('schneit es',          symbolWord: 'Schnee'),
    BriefWortItem('hat es viel Schnee',  symbolWord: 'Schnee'),
    BriefWortItem('hagelt es',           symbolWord: 'Hagel'),
    BriefWortItem('hat es Frost',        symbolWord: 'Frost'),
  ],
  phraseButtons: [
    BriefPhraseButton('Bei uns', 'Bei uns'),
    BriefPhraseButton('Das Wetter soll', 'Das Wetter soll'),
    BriefPhraseButton('Wie ist das Wetter bei euch?', 'Wie ist das Wetter bei euch?'),
    BriefPhraseButton('war es', 'war es'),
  ],
);

const _themenHaustiere = BriefThemaConfig(
  name: 'Haustiere',
  leitfrage: 'Was hast du mit deinem Haustier gemacht?',
  woerter: [
    BriefWortItem('einen Hund',           symbolWord: 'Hund'),
    BriefWortItem('eine Katze',           symbolWord: 'Katze'),
    BriefWortItem('einen Hasen',          symbolWord: 'Hase'),
    BriefWortItem('einen Hamster',        symbolWord: 'Hamster'),
    BriefWortItem('ein Meerschweinchen',  symbolWord: 'Meerschweinchen'),
    BriefWortItem('einen Vogel',          symbolWord: 'Vogel'),
    BriefWortItem('einen Papagei',        symbolWord: 'Papagei'),
    BriefWortItem('einen Fisch',          symbolWord: 'Fisch'),
    BriefWortItem('ein Pferd',            symbolWord: 'Pferd'),
    BriefWortItem('ein Huhn',             symbolWord: 'Huhn'),
    BriefWortItem('eine Maus',            symbolWord: 'Maus'),
  ],
  phraseButtons: [
    BriefPhraseButton('Ich habe', 'Ich habe'),
    BriefPhraseButton('Wir haben', 'Wir haben'),
  ],
);

const _themenBeschreiben = BriefThemaConfig(
  name: 'Beschreibungen',
  leitfrage: 'Wie war es?',
  woerter: [
    BriefWortItem('super'),       BriefWortItem('gut'),
    BriefWortItem('toll'),        BriefWortItem('wunderbar'),
    BriefWortItem('schlecht'),    BriefWortItem('schrecklich'),
    BriefWortItem('nervig'),      BriefWortItem('kalt'),
    BriefWortItem('heiß'),        BriefWortItem('krank'),
    BriefWortItem('furchtbar'),   BriefWortItem('unbequem'),
  ],
  phraseButtons: [
    BriefPhraseButton('Das ist', 'Das ist'),
    BriefPhraseButton('Der ist', 'Der ist'),
    BriefPhraseButton('Die ist', 'Die ist'),
    BriefPhraseButton('Das war', 'Das war'),
  ],
);

const _themenHobby = BriefThemaConfig(
  name: 'Hobby',
  leitfrage: 'Was machst du gerne in deiner Freizeit?',
  woerter: [
    BriefWortItem('fernsehen'),
    BriefWortItem('Musik hören',        symbolWord: 'Musik'),
    BriefWortItem('ins Kino gehen',     symbolWord: 'Kino'),
    BriefWortItem('Filme anschauen',    symbolWord: 'Film'),
    BriefWortItem('ins Konzert gehen',  symbolWord: 'Konzert'),
    BriefWortItem('ein Buch anschauen', symbolWord: 'Buch'),
    BriefWortItem('kochen'),
    BriefWortItem('Karten spielen',     symbolWord: 'Karten'),
    BriefWortItem('ins Theater gehen',  symbolWord: 'Theater'),
    BriefWortItem('im Garten arbeiten', symbolWord: 'Garten'),
    BriefWortItem('Spazieren gehen',    symbolWord: 'spazieren'),
    BriefWortItem('wandern'),
    BriefWortItem('tanzen'),
    BriefWortItem('in die Disco',       symbolWord: 'Disco'),
    BriefWortItem('spielen'),
    BriefWortItem('fotografieren'),
    BriefWortItem('schwimmen'),
    BriefWortItem('in den Zoo gehen',   symbolWord: 'Zoo'),
    BriefWortItem('shoppen gehen',      symbolWord: 'shoppen'),
    BriefWortItem('Basketball'),
    BriefWortItem('Handball'),
    BriefWortItem('Fahrrad fahren',     symbolWord: 'Fahrrad'),
    BriefWortItem('Yoga'),
    BriefWortItem('Musik machen',       symbolWord: 'Musik'),
    BriefWortItem('Lesen'),
    BriefWortItem('Hörbücher anhören',  symbolWord: 'Buch'),
    BriefWortItem('malen'),
    BriefWortItem('Lego bauen',         symbolWord: 'Lego'),
    BriefWortItem('Autos'),
    BriefWortItem('Tiere'),
    BriefWortItem('Ohrringe'),
    BriefWortItem('Parfüm'),
    BriefWortItem('Lidschatten'),
    BriefWortItem('Lippenstift'),
    BriefWortItem('Nagellack'),
  ],
  phraseButtons: [
    BriefPhraseButton('Ich mag', 'Ich mag'),
    BriefPhraseButton('Magst du', 'Magst du'),
    BriefPhraseButton('Ich mache gerne', 'Ich mache gerne'),
  ],
);

const _themenKleidung = BriefThemaConfig(
  name: 'Kleidung',
  leitfrage: 'Was trägst du gerne?',
  woerter: [
    BriefWortItem('Hose'),
    BriefWortItem('Rock'),
    BriefWortItem('Kleid'),
    BriefWortItem('Shirt'),
    BriefWortItem('Pulli'),
    BriefWortItem('Jacke'),
    BriefWortItem('Mantel'),
    BriefWortItem('Schuhe'),
    BriefWortItem('Socken'),
    BriefWortItem('Schlafanzug'),
    BriefWortItem('Mütze'),
    BriefWortItem('Schal'),
    BriefWortItem('Handschuhe'),
    BriefWortItem('Sportkleidung', symbolWord: 'Sport'),
    BriefWortItem('Badeanzug',     symbolWord: 'schwimmen'),
    BriefWortItem('Rucksack'),
  ],
  phraseButtons: [
    BriefPhraseButton('Ich trage', 'Ich trage'),
    BriefPhraseButton('Ich mag', 'Ich mag'),
    BriefPhraseButton('Hast du', 'Hast du'),
  ],
);

const _themenBedanken = BriefThemaConfig(
  name: 'Bedanken',
  leitfrage: 'Wofür möchtest du dich bedanken?',
  woerter: [
    BriefWortItem('für das Geschenk',       symbolWord: 'Geschenk'),
    BriefWortItem('für die Geschenke',      symbolWord: 'Geschenk'),
    BriefWortItem('für deinen Brief',       symbolWord: 'Brief'),
    BriefWortItem('für deinen Besuch',      symbolWord: 'Besuch'),
    BriefWortItem('für den tollen Ausflug', symbolWord: 'Ausflug'),
    BriefWortItem('für die Einladung',      symbolWord: 'einladen'),
    BriefWortItem('für die Wünsche',        symbolWord: 'wünschen'),
  ],
  phraseButtons: [
    BriefPhraseButton('Danke', 'Danke'),
    BriefPhraseButton('Vielen Dank', 'Vielen Dank'),
  ],
);

const _themenWuenschen = BriefThemaConfig(
  name: 'Wünschen',
  leitfrage: 'Was möchtest du wünschen?',
  woerter: [
    BriefWortItem('frohe Ostern',          symbolWord: 'Ostern'),
    BriefWortItem('ein gutes neues Jahr',  symbolWord: 'Neujahr'),
    BriefWortItem('frohe Weihnachten',     symbolWord: 'Weihnachten'),
    BriefWortItem('alles Gute',            symbolWord: 'gut'),
    BriefWortItem('viel Glück',            symbolWord: 'Glück'),
    BriefWortItem('gute Besserung',        symbolWord: 'krank'),
    BriefWortItem('Gesundheit'),
    BriefWortItem('viele Geschenke',       symbolWord: 'Geschenk'),
    BriefWortItem('viele Freunde',         symbolWord: 'Freund'),
    BriefWortItem('alles Liebe',           symbolWord: 'lieben'),
    BriefWortItem('viel Freude',           symbolWord: 'glücklich'),
  ],
  phraseButtons: [
    BriefPhraseButton('Ich wünsche dir', 'Ich wünsche dir'),
  ],
);

const _themenVerabredenWann = BriefThemaConfig(
  name: 'Wann',
  leitfrage: 'Wann kannst du?',
  woerter: [
    BriefWortItem('am Montag',              symbolWord: 'Montag'),
    BriefWortItem('am Dienstag',            symbolWord: 'Dienstag'),
    BriefWortItem('am Mittwoch',            symbolWord: 'Mittwoch'),
    BriefWortItem('am Donnerstag',          symbolWord: 'Donnerstag'),
    BriefWortItem('am Freitag',             symbolWord: 'Freitag'),
    BriefWortItem('am Samstag',             symbolWord: 'Samstag'),
    BriefWortItem('am Sonntag',             symbolWord: 'Sonntag'),
    BriefWortItem('in der Frühstückspause', symbolWord: 'Frühstück'),
    BriefWortItem('in der Mittagspause',    symbolWord: 'Mittagessen'),
    BriefWortItem('heute Mittag',           symbolWord: 'Mittag'),
    BriefWortItem('heute Abend',            symbolWord: 'Abend'),
  ],
  phraseButtons: [],
);

const _themenVerabredenWas = BriefThemaConfig(
  name: 'Was',
  leitfrage: 'Was wollt ihr machen?',
  woerter: [
    BriefWortItem('fernsehen'),
    BriefWortItem('Musik hören',          symbolWord: 'Musik'),
    BriefWortItem('ins Kino',             symbolWord: 'Kino'),
    BriefWortItem('einen Film anschauen', symbolWord: 'Film'),
    BriefWortItem('ins Konzert',          symbolWord: 'Konzert'),
    BriefWortItem('ein Buch anschauen',   symbolWord: 'Buch'),
    BriefWortItem('kochen'),
    BriefWortItem('Karten spielen',       symbolWord: 'Karten'),
    BriefWortItem('ins Theater',          symbolWord: 'Theater'),
    BriefWortItem('im Garten arbeiten',   symbolWord: 'Garten'),
    BriefWortItem('Spazieren gehen',      symbolWord: 'spazieren'),
    BriefWortItem('wandern'),
    BriefWortItem('tanzen'),
    BriefWortItem('in die Disco',         symbolWord: 'Disco'),
    BriefWortItem('spielen'),
    BriefWortItem('fotografieren'),
    BriefWortItem('ins Schwimmbad gehen', symbolWord: 'schwimmen'),
    BriefWortItem('in den Zoo gehen',     symbolWord: 'Zoo'),
    BriefWortItem('shoppen gehen',        symbolWord: 'shoppen'),
    BriefWortItem('Tischkicker spielen',  symbolWord: 'Kicker'),
    BriefWortItem('Kettcar fahren',       symbolWord: 'Kettcar'),
  ],
  phraseButtons: [
    BriefPhraseButton('Wir könnten', 'Wir könnten'),
    BriefPhraseButton('Wollen wir', 'Wollen wir'),
  ],
);

const _themenVerabredenWo = BriefThemaConfig(
  name: 'Wo',
  leitfrage: 'Wo wollt ihr euch treffen?',
  woerter: [
    BriefWortItem('in der Schülerbücherei', symbolWord: 'Bücherei'),
    BriefWortItem('auf dem Pausenhof',      symbolWord: 'Pausenhof'),
    BriefWortItem('in der Pausenecke',      symbolWord: 'Pause'),
    BriefWortItem('in der Pausenhalle',     symbolWord: 'Halle'),
    BriefWortItem('beim Tischkicker',       symbolWord: 'Kicker'),
    BriefWortItem('im Cafe',                symbolWord: 'Cafe'),
    BriefWortItem('bei mir zu Hause',       symbolWord: 'Haus'),
    BriefWortItem('bei dir zu Hause',       symbolWord: 'Haus'),
    BriefWortItem('im Kino',                symbolWord: 'Kino'),
    BriefWortItem('in der Stadt',           symbolWord: 'Stadt'),
  ],
  phraseButtons: [
    BriefPhraseButton('Wir treffen uns', 'Wir treffen uns'),
  ],
);

// ── Schritte ──────────────────────────────────────────────────────────────────

enum _BriefSchritt {
  begruessung,
  personen,
  einleitung,
  inhaltsuebersicht,
  // Haupt-Hubs
  verabreden,
  uberDichUndMich,
  wuenscheUndDanken,
  sonstiges,
  gefuehle,
  beschreibungen,
  // Verabreden Sub-Seiten
  verabredenWann,
  verabredenWas,
  verabredenWo,
  // Über dich und mich Sub-Seiten
  uberDich,
  uberMich,
  trinken,
  kleidung,
  hobby,
  essen,
  haustiere,
  // Wünsche und Danken Sub-Seiten
  wuenschen,
  bedanken,
  // Sonstiges Sub-Seiten
  wetter,
  schule,
  gesundheit,
  // Abschluss
  ende,
  endeGruesse,
}

// ── Hauptscreen ───────────────────────────────────────────────────────────────

class BriefScreen extends StatefulWidget {
  const BriefScreen({super.key});

  @override
  State<BriefScreen> createState() => _BriefScreenState();
}

class _BriefScreenState extends State<BriefScreen> {
  _BriefSchritt _schritt = _BriefSchritt.begruessung;
  final List<_BriefSchritt> _history = [];

  // ── Navigation ──────────────────────────────────────────────────────────

  static const _mainSeq = [
    _BriefSchritt.begruessung,
    _BriefSchritt.personen,
    _BriefSchritt.einleitung,
    _BriefSchritt.inhaltsuebersicht,
    _BriefSchritt.ende,
    _BriefSchritt.endeGruesse,
  ];

  void _navigateTo(_BriefSchritt step) {
    setState(() {
      _history.add(_schritt);
      _schritt = step;
    });
  }

  void _vorwaerts() {
    final idx = _mainSeq.indexOf(_schritt);
    if (idx >= 0 && idx < _mainSeq.length - 1) {
      _navigateTo(_mainSeq[idx + 1]);
    }
  }

  void _zurueck() {
    if (_history.isNotEmpty) {
      setState(() => _schritt = _history.removeLast());
    } else {
      Navigator.pop(context);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NasiraAppState>();
    return Scaffold(
      backgroundColor: NasiraColors.briefBg,
      body: SafeArea(
        child: Column(
          children: [
            NasiraModuleHeader(
              controller: state.textController,
              accentColor: NasiraColors.navGreen,
              onBack: _zurueck,
              onForward: _vorwaerts,
            ),
            Expanded(child: _buildStepContent(state)),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent(NasiraAppState state) {
    return switch (_schritt) {
      _BriefSchritt.begruessung       => _buildBegruessung(state),
      _BriefSchritt.personen          => _buildPersonen(state),
      _BriefSchritt.einleitung        => _buildEinleitung(state),
      _BriefSchritt.inhaltsuebersicht => _buildInhaltsuebersicht(state),
      // Verabreden
      _BriefSchritt.verabreden        => _buildVerabreden(state),
      _BriefSchritt.verabredenWann    => _buildThemaPage(state, _themenVerabredenWann),
      _BriefSchritt.verabredenWas     => _buildThemaPage(state, _themenVerabredenWas),
      _BriefSchritt.verabredenWo      => _buildThemaPage(state, _themenVerabredenWo),
      // Über dich und mich
      _BriefSchritt.uberDichUndMich   => _buildUberDichUndMich(state),
      _BriefSchritt.uberDich          => _buildUberDich(state),
      _BriefSchritt.uberMich          => _buildUberMich(state),
      _BriefSchritt.trinken           => _buildThemaPage(state, _themenTrinken),
      _BriefSchritt.kleidung          => _buildThemaPage(state, _themenKleidung),
      _BriefSchritt.hobby             => _buildThemaPage(state, _themenHobby),
      _BriefSchritt.essen             => _buildThemaPage(state, _themenEssen),
      _BriefSchritt.haustiere         => _buildThemaPage(state, _themenHaustiere),
      // Wünsche und Danken
      _BriefSchritt.wuenscheUndDanken => _buildWuenscheUndDanken(state),
      _BriefSchritt.wuenschen         => _buildThemaPage(state, _themenWuenschen),
      _BriefSchritt.bedanken          => _buildThemaPage(state, _themenBedanken),
      // Sonstiges
      _BriefSchritt.sonstiges         => _buildSonstiges(state),
      _BriefSchritt.wetter            => _buildThemaPage(state, _themenWetter),
      _BriefSchritt.schule            => _buildThemaPage(state, _themenSchule),
      _BriefSchritt.gesundheit        => _buildGesundheit(state),
      // Direkte Themen
      _BriefSchritt.gefuehle          => _buildThemaPage(state, _themenGefuehle),
      _BriefSchritt.beschreibungen    => _buildThemaPage(state, _themenBeschreiben),
      // Abschluss
      _BriefSchritt.ende              => _buildEnde(state),
      _BriefSchritt.endeGruesse       => _buildEndeGruesse(state),
    };
  }

  // ── Begrüßung ────────────────────────────────────────────────────────────

  Widget _buildBegruessung(NasiraAppState state) {
    const items = ['Hallo', 'Liebe', 'Lieber'];
    return Column(children: [
      Expanded(child: _buildGrid(
        itemCount: items.length,
        builder: (i) => NasiraGridCell(
          caption: items[i],
          symbolWord: items[i],
          backgroundColor: NasiraColors.briefTopic,
          onTap: () => state.insertPhrase(items[i]),
        ),
      )),
      _buildLeitfragenStrip(state, ['Wie möchtest du den Brief beginnen?']),
    ]);
  }

  // ── Personen ─────────────────────────────────────────────────────────────

  Widget _buildPersonen(NasiraAppState state) {
    const items = ['Mama', 'Papa', 'Opa', 'Oma', 'Onkel', 'Tante'];
    return Column(children: [
      Expanded(child: _buildGrid(
        itemCount: items.length,
        builder: (i) => NasiraGridCell(
          caption: items[i],
          symbolWord: items[i],
          backgroundColor: NasiraColors.briefTopic,
          onTap: () => state.insertPhrase(items[i]),
        ),
      )),
      _buildLeitfragenStrip(state, ['An wen schreibst du?']),
    ]);
  }

  // ── Einleitung ───────────────────────────────────────────────────────────

  Widget _buildEinleitung(NasiraAppState state) {
    final sentences = [
      ...state.customSentences.forModule('brief').map((s) => s.sentence),
      'Wie geht es dir?',
      'Mir geht es gut.',
      'Mir geht es nicht gut.',
      'Ich vermisse dich.',
      'Ich denk an dich!',
      'Ich mag dich.',
      'Ich hab dich lieb.',
      'Ich liebe dich.',
      'Vielen Dank für deinen letzten Brief.',
      'Ich habe mich sehr darüber gefreut.',
      'Vielen Dank für die letzte E-Mail.',
      'Wir haben immer viel Spaß zusammen.',
      'Wir haben lange nichts mehr voneinander gehört.',
    ];

    return Column(children: [
      Expanded(child: _buildGrid(
        itemCount: sentences.length,
        builder: (i) {
          final text = sentences[i];
          final isQuestion = text.endsWith('?');
          return NasiraGridCell(
            caption: text,
            symbolWord: _keyWord(text),
            backgroundColor: isQuestion
                ? NasiraColors.briefQuestion
                : NasiraColors.briefSentence,
            onTap: () => state.insertPhrase(text),
          );
        },
      )),
      _buildLeitfragenStrip(state, [
        'Was schreibst du zur Einleitung?',
        'Was hast du gemacht?',
      ]),
    ]);
  }

  // ── Inhaltsübersicht ─────────────────────────────────────────────────────

  Widget _buildInhaltsuebersicht(NasiraAppState state) {
    final cells = <Widget>[
      NasiraGridCell(
        caption: 'Verabreden',
        symbolWord: 'treffen',
        backgroundColor: NasiraColors.briefTopic,
        onTap: () => _navigateTo(_BriefSchritt.verabreden),
      ),
      NasiraGridCell(
        caption: 'Über dich und mich',
        symbolWord: 'sprechen',
        backgroundColor: NasiraColors.briefTopic,
        onTap: () => _navigateTo(_BriefSchritt.uberDichUndMich),
      ),
      NasiraGridCell(
        caption: 'Wünsche und Danken',
        symbolWord: 'wünschen',
        backgroundColor: NasiraColors.briefTopic,
        onTap: () => _navigateTo(_BriefSchritt.wuenscheUndDanken),
      ),
      NasiraGridCell(
        caption: 'Sonstiges',
        symbolWord: 'mehr',
        backgroundColor: NasiraColors.briefTopic,
        onTap: () => _navigateTo(_BriefSchritt.sonstiges),
      ),
      NasiraGridCell(
        caption: 'Gefühle',
        symbolWord: 'glücklich',
        backgroundColor: NasiraColors.briefTopic,
        onTap: () => _navigateTo(_BriefSchritt.gefuehle),
      ),
      NasiraGridCell(
        caption: 'Beschreibungen',
        symbolWord: 'gut',
        backgroundColor: NasiraColors.briefTopic,
        onTap: () => _navigateTo(_BriefSchritt.beschreibungen),
      ),
      NasiraGridCell(
        caption: 'Freies Schreiben',
        icon: Icons.edit_outlined,
        backgroundColor: NasiraColors.moduleDarkGreen,
        textColor: Colors.white,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FreiesSchreibenScreen()),
        ),
      ),
    ];

    return Column(children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: GridView.builder(
            itemCount: cells.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 0.85,
            ),
            itemBuilder: (_, i) => cells[i],
          ),
        ),
      ),
      _buildLeitfragenStrip(state, ['Über was möchtest du schreiben?']),
    ]);
  }

  // ── Verabreden ───────────────────────────────────────────────────────────

  Widget _buildVerabreden(NasiraAppState state) {
    const mainPhrases = [
      'Ich möchte dich gerne mal besuchen.',
      'Kannst du mich mal besuchen?',
      'Ich möchte dich gerne mal treffen.',
      'Können wir uns mal treffen?',
      'Wann können wir uns mal treffen?',
    ];

    final cells = <Widget>[
      for (final phrase in mainPhrases)
        NasiraGridCell(
          caption: phrase,
          symbolWord: _keyWord(phrase),
          backgroundColor: phrase.endsWith('?')
              ? NasiraColors.briefQuestion
              : NasiraColors.briefSentence,
          onTap: () => state.insertPhrase(phrase),
        ),
      NasiraGridCell(
        caption: 'Wann',
        symbolWord: 'Montag',
        backgroundColor: NasiraColors.briefTopic,
        onTap: () => _navigateTo(_BriefSchritt.verabredenWann),
      ),
      NasiraGridCell(
        caption: 'Was',
        symbolWord: 'spielen',
        backgroundColor: NasiraColors.briefTopic,
        onTap: () => _navigateTo(_BriefSchritt.verabredenWas),
      ),
      NasiraGridCell(
        caption: 'Wo',
        symbolWord: 'Haus',
        backgroundColor: NasiraColors.briefTopic,
        onTap: () => _navigateTo(_BriefSchritt.verabredenWo),
      ),
    ];

    return Column(children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: GridView.builder(
            itemCount: cells.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 0.85,
            ),
            itemBuilder: (_, i) => cells[i],
          ),
        ),
      ),
      _buildLeitfragenStrip(state, ['Verabreden']),
    ]);
  }

  // ── Über dich und mich ───────────────────────────────────────────────────

  Widget _buildUberDichUndMich(NasiraAppState state) {
    const subPages = [
      ('Über dich',  _BriefSchritt.uberDich,   'du'),
      ('Über mich',  _BriefSchritt.uberMich,    'ich'),
      ('Trinken',    _BriefSchritt.trinken,      'trinken'),
      ('Kleidung',   _BriefSchritt.kleidung,     'Kleidung'),
      ('Hobby',      _BriefSchritt.hobby,         'spielen'),
      ('Essen',      _BriefSchritt.essen,         'Essen'),
      ('Haustiere',  _BriefSchritt.haustiere,     'Hund'),
    ];

    return Column(children: [
      Expanded(child: _buildGrid(
        itemCount: subPages.length,
        builder: (i) => NasiraGridCell(
          caption: subPages[i].$1,
          symbolWord: subPages[i].$3,
          backgroundColor: NasiraColors.briefTopic,
          onTap: () => _navigateTo(subPages[i].$2),
        ),
      )),
      _buildLeitfragenStrip(state, ['Über dich und mich']),
    ]);
  }

  Widget _buildUberDich(NasiraAppState state) {
    const fragen = [
      'Wie alt bist du?',
      'Wann hast du Geburtstag?',
      'Wo wohnst du?',
      'Wo gehst du zur Schule?',
      'Wo arbeitest du?',
      'Was arbeitest du?',
      'Hast du Geschwister?',
      'Hast du ein Haustier?',
      'Welche Musik hörst du gerne?',
      'Was ist deine Lieblingsfarbe?',
      'Was ist deine Lieblingssendung?',
      'Was ist dein Lieblingsessen?',
      'Was ist dein Lieblingsfach?',
    ];
    return Column(children: [
      Expanded(child: _buildGrid(
        itemCount: fragen.length,
        builder: (i) => NasiraGridCell(
          caption: fragen[i],
          symbolWord: _keyWord(fragen[i]),
          backgroundColor: NasiraColors.briefQuestion,
          onTap: () => state.insertPhrase(fragen[i]),
        ),
      )),
      _buildLeitfragenStrip(state, ['Fragen über die andere Person']),
    ]);
  }

  Widget _buildUberMich(NasiraAppState state) {
    const saetze = [
      ('Ich bin xx Jahre alt',                  'Jahr'),
      ('Ich habe am xx Geburtstag',             'Geburtstag'),
      ('Ich wohne in xx',                       'wohnen'),
      ('Ich gehe in xx zur Schule',             'Schule'),
      ('Ich habe xx Schwestern und xx Brüder',  'Geschwister'),
      ('Sie heißen xx / Er heißt xx',           'Name'),
      ('Ich habe ein xx (Haustier)',             'Haustier'),
      ('Meine Lieblingsfarbe ist xxx',          'Farbe'),
      ('Meine Lieblingssendung ist xx',         'fernsehen'),
      ('Mein Lieblingsessen ist xx',            'Essen'),
      ('Meine Lieblingsmusik ist xxx',          'Musik'),
      ('Mein Lieblingsfach ist xxx',            'Schule'),
      ('Mein Hobby ist xx',                     'spielen'),
    ];
    return Column(children: [
      Expanded(child: _buildGrid(
        itemCount: saetze.length,
        builder: (i) => NasiraGridCell(
          caption: saetze[i].$1,
          symbolWord: saetze[i].$2,
          backgroundColor: NasiraColors.briefSentence,
          onTap: () => state.insertPhrase(saetze[i].$1),
        ),
      )),
      _buildLeitfragenStrip(state, ['Über dich selbst']),
    ]);
  }

  // ── Wünsche und Danken ───────────────────────────────────────────────────

  Widget _buildWuenscheUndDanken(NasiraAppState state) {
    const subPages = [
      ('Wünschen', _BriefSchritt.wuenschen, 'wünschen'),
      ('Bedanken', _BriefSchritt.bedanken,  'danke'),
    ];
    return Column(children: [
      Expanded(child: _buildGrid(
        itemCount: subPages.length,
        builder: (i) => NasiraGridCell(
          caption: subPages[i].$1,
          symbolWord: subPages[i].$3,
          backgroundColor: NasiraColors.briefTopic,
          onTap: () => _navigateTo(subPages[i].$2),
        ),
      )),
      _buildLeitfragenStrip(state, ['Wünsche und Danken']),
    ]);
  }

  // ── Sonstiges ────────────────────────────────────────────────────────────

  Widget _buildSonstiges(NasiraAppState state) {
    const subPages = [
      ('Wetter',     _BriefSchritt.wetter,     'Wetter'),
      ('Schule',     _BriefSchritt.schule,     'Schule'),
      ('Gesundheit', _BriefSchritt.gesundheit, 'krank'),
    ];
    return Column(children: [
      Expanded(child: _buildGrid(
        itemCount: subPages.length,
        builder: (i) => NasiraGridCell(
          caption: subPages[i].$1,
          symbolWord: subPages[i].$3,
          backgroundColor: NasiraColors.briefTopic,
          onTap: () => _navigateTo(subPages[i].$2),
        ),
      )),
      _buildLeitfragenStrip(state, ['Sonstiges Themen']),
    ]);
  }

  // ── Gesundheit ───────────────────────────────────────────────────────────

  Widget _buildGesundheit(NasiraAppState state) {
    const sentences = [
      'Mir geht es besser.',
      'Mir geht es nicht besser.',
      'Ich bin wieder gesund.',
      'Geht es dir besser?',
      'Geht es dir noch nicht besser?',
      'Bist du wieder gesund?',
    ];
    return Column(children: [
      Expanded(child: _buildGrid(
        itemCount: sentences.length,
        builder: (i) => NasiraGridCell(
          caption: sentences[i],
          symbolWord: _keyWord(sentences[i]),
          backgroundColor: sentences[i].endsWith('?')
              ? NasiraColors.briefQuestion
              : NasiraColors.briefSentence,
          onTap: () => state.insertPhrase(sentences[i]),
        ),
      )),
      _buildLeitfragenStrip(state, ['Wie geht es dir gesundheitlich?']),
    ]);
  }

  // ── Thema-Seite (generisch) ───────────────────────────────────────────────

  Widget _buildThemaPage(NasiraAppState state, BriefThemaConfig config) {
    final List<Widget> cells = [];

    for (final pb in config.phraseButtons) {
      final isQuestion = pb.label.endsWith('?');
      cells.add(NasiraGridCell(
        caption: pb.label,
        symbolWord: _keyWord(pb.label),
        backgroundColor: isQuestion
            ? NasiraColors.briefQuestion
            : NasiraColors.briefSentence,
        onTap: () => state.insertPhrase(pb.insertText),
      ));
    }

    if (config.phraseButtons.isNotEmpty) {
      cells.add(NasiraGridCell(
        caption: 'und',
        symbolWord: 'und',
        backgroundColor: NasiraColors.briefNeutral,
        textColor: NasiraColors.textDark,
        onTap: () => state.insertPhrase('und'),
      ));
      cells.add(NasiraGridCell(
        caption: 'nicht',
        symbolWord: 'nicht',
        backgroundColor: NasiraColors.briefNeutral,
        textColor: NasiraColors.textDark,
        onTap: () => state.insertPhrase('nicht'),
      ));
    }

    for (final wort in config.woerter) {
      cells.add(NasiraGridCell(
        caption: wort.text,
        symbolWord: wort.symbolWord ?? wort.text,
        backgroundColor: NasiraColors.briefTopic,
        onTap: () => state.insertPhrase(wort.text),
      ));
    }

    return Column(children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: GridView.builder(
            itemCount: cells.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 0.85,
            ),
            itemBuilder: (_, i) => cells[i],
          ),
        ),
      ),
      _buildLeitfragenStrip(state, [config.leitfrage]),
    ]);
  }

  // ── Ende ─────────────────────────────────────────────────────────────────

  Widget _buildEnde(NasiraAppState state) {
    const phrases = [
      'Ich hoffe, wir sehen uns bald wieder.',
      'Lass mal wieder von dir hören.',
      'Ich freue mich schon auf deine Antwort!',
      'Schreib bald zurück!',
      'Lass es dir gut gehen!',
      'So, ich muss jetzt aufhören.',
      'Alles Gute.',
      'Bis bald.',
      'Ich umarme dich herzlich.',
    ];
    return Column(children: [
      Expanded(child: _buildGrid(
        itemCount: phrases.length,
        builder: (i) => NasiraGridCell(
          caption: phrases[i],
          symbolWord: _keyWord(phrases[i]),
          backgroundColor: NasiraColors.briefSentence,
          onTap: () => state.insertPhrase(phrases[i]),
        ),
      )),
      _buildLeitfragenStrip(state, ['Wie möchtest du den Brief beenden?']),
    ]);
  }

  // ── Ende Grüße ───────────────────────────────────────────────────────────

  Widget _buildEndeGruesse(NasiraAppState state) {
    const gruesse = [
      ('Liebe Grüße',     'Liebe'),
      ('Herzliche Grüße', 'herzlich'),
      ('Viele Grüße',     'viel'),
      ('Bis bald',        'bald'),
      ('Deine Nasira',    'Nasira'),
    ];
    return Column(children: [
      Expanded(child: _buildGrid(
        itemCount: gruesse.length,
        builder: (i) => NasiraGridCell(
          caption: gruesse[i].$1,
          symbolWord: gruesse[i].$2,
          backgroundColor: NasiraColors.briefTopic,
          onTap: () => state.insertPhrase('\n${gruesse[i].$1},\n'),
        ),
      )),
      _buildLeitfragenStrip(state, ['Mit welchem Gruß möchtest du schließen?']),
    ]);
  }

  // ── Leitfragen-Streifen ──────────────────────────────────────────────────

  Widget _buildLeitfragenStrip(NasiraAppState state, List<String> fragen) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            for (int i = 0; i < fragen.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: NasiraGridCell(
                  caption: fragen[i],
                  backgroundColor: NasiraColors.briefQuestion,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Shared grid helper ───────────────────────────────────────────────────

  Widget _buildGrid({
    required int itemCount,
    required Widget Function(int index) builder,
  }) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GridView.builder(
        itemCount: itemCount,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 140,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: 0.85,
        ),
        itemBuilder: (_, i) => builder(i),
      ),
    );
  }
}
