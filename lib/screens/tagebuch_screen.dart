import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../nasira_app_state.dart';
import '../theme/nasira_colors.dart';
import '../widgets/nasira_grid_cell.dart';
import '../widgets/nasira_module_header.dart';

// ── Datenmodelle ──────────────────────────────────────────────────────────────

class TagebuchFachConfig {
  final String name;
  final String emoji;
  final List<String> sentences;

  const TagebuchFachConfig({
    required this.name,
    required this.emoji,
    required this.sentences,
  });
}

class TagebuchTagConfig {
  final String label;
  final String emoji;
  final Color color;
  final List<TagebuchFachConfig> faecher;

  const TagebuchTagConfig({
    required this.label,
    required this.emoji,
    required this.color,
    required this.faecher,
  });
}

// ── Fach-Inhalte ──────────────────────────────────────────────────────────────

const _fachMorgenkreis = TagebuchFachConfig(
  name: 'Morgenkreis',
  emoji: '🌅',
  sentences: [
    'habe ich gesungen',
    'haben wir gesungen',
    'haben wir den Stundenplan gemacht',
    'haben wir eine Geschichte gehört',
    'haben wir ein Spiel gespielt',
    'haben wir Kuchen gegessen',
    'habe ich vom Wochenende erzählt',
    'haben wir uns unterhalten',
    'habe ich von den Ferien erzählt',
    'haben wir Geburtstag gefeiert',
    'habe ich vom gestrigen Tag erzählt',
    'habe ich mit dem Talker erzählt',
    'wurde mein Mitteilungsbuch vorgelesen',
  ],
);

const _fachPause = TagebuchFachConfig(
  name: 'Pause',
  emoji: '🔔',
  sentences: [
    'war ich in der Pausenecke.',
    'war ich im Pausenhof.',
    'war ich in der Pausenhalle.',
    'war ich beim Tischkicker.',
    'habe ich mich ausgeruht.',
    'habe ich mich unterhalten.',
    'habe ich gefrühstückt.',
    'habe ich mit der Murmelbahn gespielt.',
    'war ich in der Schülerbücherei.',
  ],
);

const _fachMittagessen = TagebuchFachConfig(
  name: 'Mittagessen',
  emoji: '🍽️',
  sentences: [
    'Fleisch.',
    'Nudeln.',
    'Gemüse.',
    'Kartoffel.',
    'Reis.',
    'Salat.',
    'Süßes.',
    'Pommes.',
    'Maultaschen.',
    'Spaghetti Bolognese mit Käse.',
  ],
);

const _fachKochen = TagebuchFachConfig(
  name: 'Kochen',
  emoji: '👨‍🍳',
  sentences: [
    'haben wir Suppe gekocht.',
    'haben wir Kuchen gebacken.',
    'haben wir Pfannkuchen gemacht.',
    'haben wir Nudeln gekocht.',
    'haben wir etwas Leckeres zubereitet.',
    'habe ich mitgeholfen.',
    'war ich der Koch / die Köchin.',
  ],
);

const _fachMusik = TagebuchFachConfig(
  name: 'Musik',
  emoji: '🎵',
  sentences: [
    'haben wir gesungen.',
    'haben wir Instrumente gespielt.',
    'haben wir Trommeln gespielt.',
    'haben wir getanzt.',
    'haben wir ein neues Lied gelernt.',
    'war es sehr laut.',
    'hat mir das Singen Spaß gemacht.',
  ],
);

const _fachKunst = TagebuchFachConfig(
  name: 'Kunst',
  emoji: '🎨',
  sentences: [
    'haben wir gemalt.',
    'haben wir gebastelt.',
    'haben wir etwas geformt.',
    'habe ich etwas gebaut.',
    'war das Thema Farben.',
    'hat mir das Malen Spaß gemacht.',
  ],
);

const _fachMathe = TagebuchFachConfig(
  name: 'Mathe',
  emoji: '🔢',
  sentences: [
    'haben wir gerechnet.',
    'haben wir Zahlen geübt.',
    'war das Thema Addition.',
    'war das Thema Subtraktion.',
    'haben wir Aufgaben gelöst.',
    'war es schwer.',
    'war es leicht.',
  ],
);

const _fachSport = TagebuchFachConfig(
  name: 'Sport',
  emoji: '⚽',
  sentences: [
    'haben wir Fußball gespielt.',
    'haben wir Basketball gespielt.',
    'haben wir Tischtennis gespielt.',
    'haben wir getanzt.',
    'haben wir Yoga gemacht.',
    'bin ich gelaufen.',
    'hat mir Sport viel Spaß gemacht.',
  ],
);

const _fachReiten = TagebuchFachConfig(
  name: 'Reiten',
  emoji: '🐴',
  sentences: [
    'war ich auf dem Pferd.',
    'habe ich das Pferd gebürstet.',
    'haben wir im Schritt geritten.',
    'haben wir im Trab geritten.',
    'war mein Pferd brav.',
    'hatte ich keine Angst.',
    'hat mir das Reiten viel Spaß gemacht.',
  ],
);

const _fachSchwimmen = TagebuchFachConfig(
  name: 'Schwimmen',
  emoji: '🏊',
  sentences: [
    'bin ich geschwommen.',
    'war das Wasser kalt.',
    'war das Wasser warm.',
    'habe ich geübt.',
    'hat mir das Schwimmen Spaß gemacht.',
  ],
);

const _fachReligion = TagebuchFachConfig(
  name: 'Religion',
  emoji: '✝️',
  sentences: [
    'haben wir eine Geschichte gehört.',
    'haben wir über Gott gesprochen.',
    'haben wir gesungen.',
    'haben wir gebetet.',
    'war das Thema interessant.',
  ],
);

const _fachSprachtherapie = TagebuchFachConfig(
  name: 'Sprachtherapie',
  emoji: '🗣️',
  sentences: [
    'haben wir Übungen gemacht.',
    'habe ich mit dem Talker geübt.',
    'habe ich Laute geübt.',
    'war es anstrengend.',
    'hat mir die Übung gut gefallen.',
  ],
);

const _fachComputer = TagebuchFachConfig(
  name: 'Computer',
  emoji: '💻',
  sentences: [
    'habe ich gespielt.',
    'habe ich gemalt.',
    'habe ich etwas geschrieben.',
    'habe ich etwas gelernt.',
    'war das Programm toll.',
    'hat mir der Computer Spaß gemacht.',
  ],
);

const _alleFaecher = [
  _fachMorgenkreis,
  _fachPause,
  _fachMittagessen,
  _fachComputer,
  _fachKochen,
  _fachMusik,
  _fachKunst,
  _fachMathe,
  _fachSport,
  _fachReiten,
  _fachSchwimmen,
  _fachReligion,
  _fachSprachtherapie,
];

// ── Stundenplan pro Tag ───────────────────────────────────────────────────────

const _stundenplanMontag = [
  _fachMorgenkreis, _fachComputer, _fachPause, _fachMittagessen,
];
const _stundenplanDienstag = [
  _fachMorgenkreis, _fachMusik, _fachPause, _fachMittagessen,
];
const _stundenplanMittwoch = [
  _fachMorgenkreis, _fachKunst, _fachPause, _fachMittagessen,
];
const _stundenplanDonnerstag = [
  _fachMorgenkreis, _fachSport, _fachPause, _fachMittagessen,
];
const _stundenplanFreitag = [
  _fachMorgenkreis, _fachKochen, _fachPause, _fachMittagessen,
];
const _stundenplanWochenende = [
  _fachSport, _fachMusik, _fachKunst,
];

// ── Wochentage ────────────────────────────────────────────────────────────────

const _wochentage = [
  TagebuchTagConfig(
    label: 'Montag',
    emoji: '📅',
    color: NasiraColors.tagMontag,
    faecher: _stundenplanMontag,
  ),
  TagebuchTagConfig(
    label: 'Dienstag',
    emoji: '📅',
    color: NasiraColors.tagDienstag,
    faecher: _stundenplanDienstag,
  ),
  TagebuchTagConfig(
    label: 'Mittwoch',
    emoji: '📅',
    color: NasiraColors.tagMittwoch,
    faecher: _stundenplanMittwoch,
  ),
  TagebuchTagConfig(
    label: 'Donnerstag',
    emoji: '📅',
    color: NasiraColors.tagDonnerstag,
    faecher: _stundenplanDonnerstag,
  ),
  TagebuchTagConfig(
    label: 'Freitag',
    emoji: '📅',
    color: NasiraColors.tagFreitag,
    faecher: _stundenplanFreitag,
  ),
  TagebuchTagConfig(
    label: 'Samstag',
    emoji: '🌤️',
    color: NasiraColors.tagSamstag,
    faecher: _stundenplanWochenende,
  ),
  TagebuchTagConfig(
    label: 'Sonntag',
    emoji: '☀️',
    color: NasiraColors.tagSonntag,
    faecher: _stundenplanWochenende,
  ),
  TagebuchTagConfig(
    label: 'Am Wochenende',
    emoji: '🏖️',
    color: NasiraColors.tagWochenende,
    faecher: _stundenplanWochenende,
  ),
  TagebuchTagConfig(
    label: 'In den Ferien',
    emoji: '🌴',
    color: NasiraColors.tagFerien,
    faecher: _stundenplanWochenende,
  ),
];

// ── Hilfsfunktion: Inhaltswort für Symbol-Lookup ──────────────────────────────

/// Extrahiert das erste bedeutungstragende Wort aus einem Tagebuch-Satz.
/// Beispiel: "haben wir Fußball gespielt." → "Fußball"
String _keyWord(String sentence) {
  const skip = {
    'habe', 'haben', 'hatte', 'hatten', 'bin', 'ist', 'war', 'waren',
    'ich', 'wir', 'du', 'er', 'sie', 'es',
    'ein', 'eine', 'einen', 'einem', 'einer',
    'der', 'die', 'das', 'den', 'dem', 'des',
    'in', 'im', 'am', 'an', 'auf', 'bei', 'für', 'mit', 'von', 'zu', 'zum', 'zur',
    'und', 'oder', 'nicht', 'auch', 'mir', 'uns', 'mich', 'mein', 'meine',
    'sehr', 'viel', 'keine', 'kein', 'keinen',
  };
  final words = sentence
      .replaceAll(RegExp(r'[.!?,;]'), '')
      .split(' ')
      .where((w) => w.length >= 3 && !skip.contains(w.toLowerCase()))
      .toList();
  if (words.isEmpty) {
    final parts = sentence.trim().split(' ');
    return parts.last.replaceAll(RegExp(r'[.!?,;]'), '');
  }
  return words.first;
}

// ── Schritte ──────────────────────────────────────────────────────────────────

enum _TagebuchSchritt { wochentage, stundenplan, fach }

// ── Hauptscreen ───────────────────────────────────────────────────────────────

class TagebuchScreen extends StatefulWidget {
  const TagebuchScreen({super.key});

  @override
  State<TagebuchScreen> createState() => _TagebuchScreenState();
}

class _TagebuchScreenState extends State<TagebuchScreen> {
  _TagebuchSchritt _schritt = _TagebuchSchritt.wochentage;
  int? _selectedTag;
  int? _selectedFach;
  bool _alleFaecherAnzeigen = false;

  // ── Navigation ──────────────────────────────────────────────────────────

  void _zurueck() {
    switch (_schritt) {
      case _TagebuchSchritt.wochentage:
        Navigator.pop(context);
      case _TagebuchSchritt.stundenplan:
        setState(() {
          _schritt = _TagebuchSchritt.wochentage;
          _alleFaecherAnzeigen = false;
        });
      case _TagebuchSchritt.fach:
        setState(() => _schritt = _TagebuchSchritt.stundenplan);
    }
  }

  void _tagGewaehlt(int index) {
    final tag = _wochentage[index];
    context.read<NasiraAppState>().insertPhrase(tag.label);
    setState(() {
      _selectedTag = index;
      _schritt = _TagebuchSchritt.stundenplan;
    });
  }

  void _fachGewaehlt(int index, TagebuchFachConfig fach) {
    context.read<NasiraAppState>().insertPhrase(fach.name);
    setState(() {
      _selectedFach = index;
      _schritt = _TagebuchSchritt.fach;
    });
  }

  void _satzGewaehlt(String satz) {
    context.read<NasiraAppState>().insertPhrase(satz);
  }

  // ── Build ───────────────────────────────────────────────────────────────

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
            ),

            // Step content
            Expanded(child: _buildSchritt()),
          ],
        ),
      ),
    );
  }

  Widget _buildSchritt() {
    return switch (_schritt) {
      _TagebuchSchritt.wochentage => _buildWochentage(),
      _TagebuchSchritt.stundenplan => _buildStundenplan(),
      _TagebuchSchritt.fach => _buildFach(),
    };
  }

  // ── Schritt 1: Wochentage ──────────────────────────────────────────────

  Widget _buildWochentage() {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: GridView.builder(
        itemCount: _wochentage.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.0,
        ),
        itemBuilder: (context, i) {
          final tag = _wochentage[i];
          return NasiraGridCell(
            backgroundColor: tag.color,
            caption: tag.label,
            symbolWord: tag.label,
            onTap: () => _tagGewaehlt(i),
          );
        },
      ),
    );
  }

  // ── Schritt 2: Stundenplan ─────────────────────────────────────────────

  Widget _buildStundenplan() {
    final tag = _wochentage[_selectedTag!];
    final liste = _alleFaecherAnzeigen ? _alleFaecher : tag.faecher;

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Expanded(
            child: GridView.builder(
              itemCount: liste.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 140,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.9,
              ),
              itemBuilder: (context, i) {
                final fach = liste[i];
                return NasiraGridCell(
                  backgroundColor: NasiraColors.moduleGreen,
                  caption: '${fach.name} ${fach.emoji}',
                  symbolWord: fach.name,
                  onTap: () => _fachGewaehlt(i, fach),
                );
              },
            ),
          ),
          if (!_alleFaecherAnzeigen) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () =>
                    setState(() => _alleFaecherAnzeigen = true),
                icon: const Icon(Icons.apps),
                label: const Text('Alle Fächer anzeigen'),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  // ── Schritt 3: Fach (Sätze) ────────────────────────────────────────────

  Widget _buildFach() {
    final tag = _wochentage[_selectedTag!];
    final liste = _alleFaecherAnzeigen ? _alleFaecher : tag.faecher;
    final fach = liste[_selectedFach!];

    return Padding(
      padding: const EdgeInsets.all(10),
      child: GridView.builder(
        itemCount: fach.sentences.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 2.0,
        ),
        itemBuilder: (context, i) {
          final satz = fach.sentences[i];
          return NasiraGridCell(
            backgroundColor: NasiraColors.briefSentence,
            caption: satz,
            symbolWord: _keyWord(satz),
            onTap: () => _satzGewaehlt(satz),
          );
        },
      ),
    );
  }
}
