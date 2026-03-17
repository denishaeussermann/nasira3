import 'core/text_normalizer.dart';

/// Kontextsensitiver Vorschlagsdienst für Nasira.
class NasiraContextService {

  // ── Partizip II: unregelmäßige Formen → Grundform ───────────────────────

  static const Map<String, String> _irregularPartizips = {
    'gehabt':         'haben',
    'gewesen':        'sein',
    'geworden':       'werden',
    'gegangen':       'gehen',
    'gekommen':       'kommen',
    'gefahren':       'fahren',
    'geschlafen':     'schlafen',
    'gegessen':       'essen',
    'getrunken':      'trinken',
    'gelesen':        'lesen',
    'geschrieben':    'schreiben',
    'gesehen':        'sehen',
    'gehoert':        'hoeren',
    'gesprochen':     'sprechen',
    'genommen':       'nehmen',
    'gegeben':        'geben',
    'gefunden':       'finden',
    'verstanden':     'verstehen',
    'gedacht':        'denken',
    'gewusst':        'wissen',
    'gebracht':       'bringen',
    'geholfen':       'helfen',
    'getragen':       'tragen',
    'geschnitten':    'schneiden',
    'gerufen':        'rufen',
    'gelaufen':       'laufen',
    'gesessen':       'sitzen',
    'gestanden':      'stehen',
    'gelegen':        'liegen',
    'geflogen':       'fliegen',
    'geschwommen':    'schwimmen',
    'gesprungen':     'springen',
    'geklettert':     'klettern',
    'gesungen':       'singen',
    'getreten':       'treten',
    'geworfen':       'werfen',
    'gezogen':        'ziehen',
    'geschlagen':     'schlagen',
    'gestohlen':      'stehlen',
    'gebrochen':      'brechen',
    'gelogen':        'luegen',
    'gelitten':       'leiden',
    'geschienen':     'scheinen',
    'gebissen':       'beissen',
    'gefroren':       'frieren',
    'gemolken':       'melken',
    'getrieben':      'treiben',
    'gemocht':        'moegen',
    'gekonnt':        'koennen',
    'gemusst':        'muessen',
    'gewollt':        'wollen',
    'gesollt':        'sollen',
    'gedurft':        'duerfen',
    'geliebt':        'lieben',
    'getroffen':      'treffen',
    'gehalten':       'halten',
    'gelassen':       'lassen',
    'gestorben':      'sterben',
    'gewachsen':      'wachsen',
    'geblieben':      'bleiben',
    'geliehen':       'leihen',
    'geritten':       'reiten',
    'gestiegen':      'steigen',
    'geschwiegen':    'schweigen',
    'geflossen':      'fliessen',
    'gelungen':       'gelingen',
    'geschlossen':    'schliessen',
    'vergessen':      'vergessen',
    'verloren':       'verlieren',
    'gewonnen':       'gewinnen',
    'begonnen':       'beginnen',
    'getan':          'tun',
    'getanzt':        'tanzen',
    'gespielt':       'spielen',
    'gemacht':        'machen',
    'gesagt':         'sagen',
    'gearbeitet':     'arbeiten',
    'gekauft':        'kaufen',
    'gezeigt':        'zeigen',
    'gelernt':        'lernen',
    'gefragt':        'fragen',
    'gelacht':        'lachen',
    'geweint':        'weinen',
    'gemalt':         'malen',
    'gebastelt':      'basteln',
    'gekocht':        'kochen',
    'gebacken':       'backen',
    'geputzt':        'putzen',
    'geraeumt':       'raeumen',
    'gewaschen':      'waschen',
    'geduscht':       'duschen',
    'gebadet':        'baaden',
    'gezahlt':        'zahlen',
    'bezahlt':        'bezahlen',
    'gewartet':       'warten',
    'gewuenscht':     'wuenschen',
    'gefreut':        'freuen',
    'geaergert':      'aergern',
    'geschrien':      'schreien',
    'geschaut':       'schauen',
    'gestellt':       'stellen',
    'geklebt':        'kleben',
    'geschraubt':     'schrauben',
    // ── Trennbare Verben (häufigste, explizit) ──────────────────
    'aufgewacht':     'aufwachen',
    'eingeschlafen':  'einschlafen',
    'aufgestanden':   'aufstehen',
    'ausgegangen':    'ausgehen',
    'angekommen':     'ankommen',
    'abgefahren':     'abfahren',
    'eingekauft':     'einkaufen',
    'aufgeraeumt':    'aufraeumen',
    'angemacht':      'anmachen',
    'ausgemacht':     'ausmachen',
    'eingeschaltet':  'einschalten',
    'ausgeschaltet':  'ausschalten',
    'umgeschaltet':   'umschalten',
    'angerufen':      'anrufen',
    'abgewaschen':    'abwaschen',
    'angezogen':      'anziehen',
    'ausgezogen':     'ausziehen',
    'hingesetzt':     'hinsetzen',
    'hingelegt':      'hinlegen',
    'aufgehoert':     'aufhoeren',
    'angefangen':     'anfangen',
    'mitgemacht':     'mitmachen',
    'mitgekommen':    'mitkommen',
    'mitgebracht':    'mitbringen',
    'mitgenommen':    'mitnehmen',
    'zugemacht':      'zumachen',
    'aufgemacht':     'aufmachen',
    'reingemacht':    'reinmachen',
  };

  /// Trennbare Verbpräfixe, sortiert nach Länge (längste zuerst),
  /// damit "zurück" vor "zu" geprüft wird.
  static const _trennbarePrefixe = [
    'zurueck', 'heraus', 'hinaus', 'herum', 'herein', 'weiter',
    'hinein', 'heran', 'daran', 'drauf', 'raus', 'rein',
    'fest', 'nach', 'raus', 'heim', 'dran',
    'auf', 'aus', 'ein', 'los', 'mit', 'vor', 'weg', 'hin',
    'her', 'rum', 'um',
    'an', 'ab', 'zu',
  ];

  static String? partizipToBase(String word) {
    final w = _norm(word);
    if (w.length < 4) return null;

    // Stufe 1: unregelmäßige Formen (inkl. bekannte trennbare)
    final irregular = _irregularPartizips[w];
    if (irregular != null) return irregular;

    // Stufe 2: einfache ge-Partizipien (ge + Stamm + Endung)
    if (w.startsWith('ge')) {
      final result = _resolveGeForm(w.substring(2));
      if (result != null) return result;
    }

    // Stufe 3: trennbare Verben (Präfix + ge + Stamm + Endung)
    //
    // Beispiele:
    //   angeklebt  → an + ge + klebt  → an + kleben  = ankleben
    //   weggestellt → weg + ge + stellt → weg + stellen = wegstellen
    //   zugemacht  → zu + ge + macht  → zu + machen  = zumachen
    //   angesehen  → an + ge + sehen  → an + sehen   = ansehen
    for (final prefix in _trennbarePrefixe) {
      if (w.length <= prefix.length + 2) continue; // zu kurz
      if (!w.startsWith(prefix)) continue;

      final afterPrefix = w.substring(prefix.length);
      if (!afterPrefix.startsWith('ge')) continue;

      final innerStem = afterPrefix.substring(2); // nach "ge"

      // Erst prüfen: ist "ge + innerStem" eine bekannte irreguläre Form?
      final irregularInner = _irregularPartizips['ge$innerStem'];
      if (irregularInner != null) return '$prefix$irregularInner';

      // Dann regulär auflösen
      final innerBase = _resolveGeForm(innerStem);
      if (innerBase != null) return '$prefix$innerBase';
    }

    return null;
  }

  /// Löst den Teil nach "ge" auf: Stamm + Endung → Infinitiv.
  ///
  /// Beispiele:
  ///   "macht"   → "machen"   (Stamm + t → Stamm + en)
  ///   "arbeitet" → "arbeiten" (Stamm + et → Stamm + en)
  ///   "sehen"   → "sehen"    (Stamm + en → Stamm + en)
  static String? _resolveGeForm(String stem) {
    if (stem.length < 3) return null;

    // Stamm + t → Stamm + en  (macht → machen)
    if (stem.endsWith('t') && !stem.endsWith('et')) {
      final base = stem.substring(0, stem.length - 1);
      if (base.length < 2) return null;
      if (base.endsWith('e')) return '${base}n';
      return '${base}en';
    }

    // Stamm + et → Stamm + en  (arbeitet → arbeiten)
    if (stem.endsWith('et') && stem.length >= 4) {
      final base = stem.substring(0, stem.length - 2);
      return '${base}en';
    }

    // Stamm + en → bleibt  (sehen → sehen)
    if (stem.endsWith('en') && stem.length >= 4) {
      return stem;
    }

    return null;
  }

  static bool isPartizip(String word) => partizipToBase(word) != null;

  // ── Satzmuster-Vorschläge ────────────────────────────────────────────────

  static List<String> contextSuggestions(
    List<String> tokens,
    String currentPartial,
  ) {
    if (tokens.isEmpty) return [];

    final nt = tokens.map(_norm).toList();
    final partial = _norm(currentPartial);

    // Nur die letzten 4 Tokens betrachten — verhindert dass alte
    // Hilfsverben am Satzanfang weiter Partizip-Vorschläge auslösen
    final window = nt.length > 4 ? nt.sublist(nt.length - 4) : nt;

    // Muster 1: haben-Form im Fenster → Partizip II
    // Nur wenn das letzte Token eine haben-Form ist UND
    // noch kein Partizip im Fenster folgt
    if (_endsWithAny(window, _habenForms) && !_containsPartizip(window)) {
      return _filter(_partizipsForHaben, partial);
    }

    // Muster 2: sein-Form im Fenster → Partizip II (Bewegungsverben)
    // Nur wenn das letzte Token eine sein-Form ist UND
    // noch kein Partizip im Fenster folgt
    if (_endsWithAny(window, _seinForms) && !_containsPartizip(window)) {
      return _filter(_partizipsForSein, partial);
    }

    // Muster 3: Modalverb im Fenster → Infinitiv
    // Nur wenn noch kein Infinitiv im Fenster folgt
    if (_endsWithAny(window, _modalForms) && !_containsInfinitiv(window)) {
      return _filter(_commonInfinitives, partial);
    }

    // Muster 4: Körper/Toilette-Kontext
    if (_containsAny(window, _koerperTokens)) {
      return _filter(
        ['gemacht', 'gepinkelt', 'gepupst', 'nass', 'voll'],
        partial,
      );
    }

    // Muster 5: Schmerz-Kontext
    if (_containsAny(window, _schmerzTokens)) {
      return _filter([
        'weh', 'schlimm', 'stark', 'geblutet', 'geschwollen',
        'kopf', 'bauch', 'bein', 'arm',
      ], partial);
    }

    // Muster 6: Pronomen alleine → häufige Verben
    if (nt.length == 1 &&
        _containsAny(nt, ['ich', 'du', 'er', 'sie', 'wir'])) {
      return _filter(_commonVerbsAfterPronoun, partial);
    }

    return [];
  }

  static List<String> phraseCompletions(List<String> tokens) {
    if (tokens.isEmpty) return [];

    for (int len = tokens.length.clamp(0, 5); len >= 1; len--) {
      final slice = tokens.sublist(tokens.length - len);
      final key = slice.map(_norm).join(' ');
      final match = _phrasePatterns[key];
      if (match != null) return match;
    }

    return [];
  }

  // ── Private Hilfsmethoden ────────────────────────────────────────────────

  static String _norm(String s) => TextNormalizer.normalize(s);

  static bool _containsAny(List<String> tokens, List<String> targets) =>
      tokens.any((t) => targets.contains(t));

  static bool _endsWithAny(List<String> tokens, List<String> targets) =>
      tokens.isNotEmpty && targets.contains(tokens.last);

  static bool _containsPartizip(List<String> tokens) =>
      tokens.any((t) => partizipToBase(t) != null);

  static bool _containsInfinitiv(List<String> tokens) =>
      tokens.any((t) => t.endsWith('en') && t.length > 3);

  static List<String> _filter(List<String> words, String partial) {
    if (partial.isEmpty) return words;
    return words.where((w) => _norm(w).startsWith(partial)).toList();
  }

  // ── Wortlisten ───────────────────────────────────────────────────────────

  static const _habenForms = [
    'habe', 'hast', 'hat', 'haben', 'habt',
    'hatte', 'hattest', 'hatten', 'hattet',
  ];

  static const _seinForms = [
    'bin', 'bist', 'ist', 'sind', 'seid',
    'war', 'warst', 'waren', 'wart',
  ];

  static const _modalForms = [
    'moechte', 'moechtest', 'will', 'willst', 'wollen',
    'kann', 'kannst', 'koennen', 'muss', 'musst', 'muessen',
    'soll', 'sollst', 'sollen', 'darf', 'darfst', 'duerfen',
    'mag', 'magst', 'moegen',
  ];

  static const _koerperTokens = [
    'hose', 'unterhose', 'windel', 'toilette', 'klo',
    'bett', 'badezimmer', 'boden',
  ];

  static const _schmerzTokens = [
    'weh', 'schmerz', 'schmerzen', 'aua',
    'kopfweh', 'bauchschmerzen',
  ];

  // Partizip II nach haben — häufige Alltagsverben
  static const _partizipsForHaben = [
    'gemacht', 'gehabt', 'gespielt', 'gegessen', 'getrunken',
    'gekauft', 'gesagt', 'gesehen', 'gehoert', 'gearbeitet',
    'gelernt', 'geschlafen', 'geschrieben', 'gelesen', 'gedacht',
    'gefunden', 'gebracht', 'geholt', 'gelacht', 'geweint',
    'getanzt', 'gesungen', 'gemalt', 'gebastelt', 'gekocht',
    'gebacken', 'geputzt', 'geraeumt', 'gewaschen', 'bezahlt',
    'gewartet', 'geholfen', 'gewusst', 'gefragt', 'gezeigt',
    'geliebt', 'geaergert', 'gefreut', 'gewuenscht', 'geduscht',
    'angemacht', 'ausgemacht', 'eingeschaltet', 'ausgeschaltet',
    'angerufen', 'eingekauft', 'aufgeraeumt', 'mitgemacht',
  ];

  // Partizip II nach sein — Bewegung/Zustandsänderung
  static const _partizipsForSein = [
    'gewesen', 'gegangen', 'gekommen', 'gefahren', 'gelaufen',
    'geflogen', 'geklettert', 'gesprungen', 'geschwommen',
    'aufgestanden', 'eingeschlafen', 'aufgewacht',
    'ausgegangen', 'angekommen', 'abgefahren',
    'geblieben', 'gestorben', 'gewachsen',
  ];

  // Infinitive nach Modalverben
  static const _commonInfinitives = [
    'essen', 'trinken', 'spielen', 'schlafen', 'gehen',
    'fahren', 'kaufen', 'lesen', 'tanzen', 'helfen',
    'arbeiten', 'lernen', 'kochen', 'malen', 'basteln',
    'schwimmen', 'laufen', 'singen', 'hoeren', 'sehen',
    'machen', 'bringen', 'holen', 'waschen', 'putzen',
    'duschen', 'anziehen', 'ausziehen', 'aufraeumen',
  ];

  // Verben direkt nach Pronomen
  static const _commonVerbsAfterPronoun = [
    'moechte', 'habe', 'bin', 'kann', 'will', 'muss',
    'gehe', 'esse', 'trinke', 'spiele', 'schlafe',
    'brauche', 'fuehle', 'mag', 'weiss', 'denke',
    'lerne', 'arbeite', 'fahre', 'lese', 'hoere',
  ];

  // ── Redewendungen / Satzmuster ───────────────────────────────────────────

  static const Map<String, List<String>> _phrasePatterns = {
    // Körperpflege
    'in die hose':            ['gemacht', 'gepinkelt', 'gepupst'],
    'in die windel':          ['gemacht', 'gepinkelt', 'gepupst'],
    'in die unterhose':       ['gemacht', 'gepinkelt', 'gepupst'],
    'auf die toilette':       ['muessen', 'gehen', 'wollen', 'gegangen'],
    'auf das klo':            ['muessen', 'gehen', 'wollen'],
    'ins bett':               ['gehen', 'muessen', 'wollen', 'gelegt'],
    'ins bett gegangen':      ['schlafen', 'eingeschlafen'],
    'aufgestanden und':       ['gegangen', 'gegessen', 'geduscht', 'angezogen'],

    // Essen & Trinken
    'ich habe hunger':        ['moechte', 'essen', 'bitte'],
    'ich habe durst':         ['moechte', 'trinken', 'bitte'],
    'ich moechte':            ['essen', 'trinken', 'spielen', 'schlafen', 'gehen', 'helfen'],
    'ich moechte essen':      ['bitte', 'jetzt', 'noch', 'mehr'],
    'ich moechte trinken':    ['bitte', 'wasser', 'saft', 'milch'],
    'ich habe gegessen':      ['bitte', 'danke', 'fertig', 'mehr'],
    'ich habe getrunken':     ['danke', 'fertig', 'mehr'],

    // Befinden
    'mir ist':                ['schlecht', 'kalt', 'warm', 'langweilig', 'schwindelig', 'uebel'],
    'ich bin':                ['muede', 'krank', 'traurig', 'froh', 'fertig', 'wach', 'hungrig'],
    'ich habe':               ['schmerzen', 'hunger', 'durst', 'langeweile', 'angst', 'kopfweh'],
    'ich fuehle mich':        ['schlecht', 'gut', 'muede', 'krank', 'wohl'],

    // Schmerz
    'mir tut':                ['weh', 'der kopf weh', 'der bauch weh'],
    'ich habe schmerzen':     ['im bauch', 'im kopf', 'im ruecken', 'im bein', 'im arm'],
    'es tut weh':             ['hier', 'sehr', 'stark'],

    // Hilfe
    'ich brauche':            ['hilfe', 'mehr', 'zeit', 'pause', 'dich', 'bitte'],
    'kannst du':              ['mir', 'bitte', 'helfen', 'kommen', 'das'],
    'kannst du mir':          ['helfen', 'bitte', 'sagen', 'zeigen', 'geben'],
    'bitte hilf':             ['mir', 'ihm', 'ihr', 'uns'],
    'ich brauche hilfe':      ['bitte', 'jetzt', 'sofort'],

    // Wunsch & Wille
    'ich wuensche':           ['mir', 'dir', 'euch', 'uns', 'allen'],
    'ich wuensche mir':       ['ein', 'eine', 'mehr', 'dass', 'zu'],
    'ich will':               ['nicht', 'das', 'mehr', 'jetzt', 'gehen', 'spielen'],
    'ich will nicht':         ['das', 'mehr', 'gehen', 'essen', 'schlafen'],
    'ich will mehr':          ['bitte', 'davon', 'trinken', 'essen', 'spielen'],

    // Ablehnung & Zustimmung
    'ich mag':                ['das', 'dich', 'es', 'ihn', 'sie'],
    'ich mag das':            ['nicht', 'sehr', 'gerne'],
    'ich mag das nicht':      ['bitte', 'aufhoeren', 'weggehen'],
    'das gefaellt':           ['mir', 'mir nicht', 'mir sehr gut'],

    // Tagesablauf
    'ich bin aufgewacht':     ['und', 'heute', 'frueh', 'spaet'],
    'ich bin muede':          ['moechte', 'schlafen', 'ins bett'],
    'guten morgen':           ['ich', 'heute', 'wie geht'],
    'guten abend':            ['ich', 'heute', 'wir'],
    'gute nacht':             ['schlaf', 'bis', 'ich'],

    // Kommunikation
    'ich verstehe':           ['das', 'das nicht', 'dich', 'nicht', 'jetzt'],
    'ich verstehe nicht':     ['bitte', 'nochmal', 'langsamer', 'zeigen'],
    'bitte nochmal':          ['sagen', 'zeigen', 'langsamer', 'warten'],
    'ich weiss nicht':        ['was', 'wie', 'ob', 'warum', 'wo'],

    // Zeitangaben
    'gestern war':            ['ich', 'er', 'sie', 'gut', 'schoen'],
    'heute ist':              ['schoen', 'toll', 'langweilig', 'schwer'],
    'morgen moechte':         ['ich', 'er', 'sie', 'wir'],
    'heute habe ich':         ['gemacht', 'gespielt', 'gegessen', 'gelernt'],

    // Schule & Therapie
    'ich habe gelernt':       ['zu', 'das', 'heute', 'viel'],
    'wir haben gespielt':     ['und', 'mit', 'heute', 'draussen'],
    'ich war in der':         ['schule', 'therapie', 'arztpraxis', 'klinik'],
    'ich gehe in die':        ['schule', 'therapie', 'pause', 'klinik'],
  };
}