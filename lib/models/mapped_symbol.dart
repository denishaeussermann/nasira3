import 'word_entry.dart';
import 'symbol_entry.dart';

/// Ein aufgelöstes Paar aus Wort und zugehörigem Symbol.
///
/// Entsteht durch Auflösung eines [WordSymbolMapping] gegen die
/// tatsächlichen [WordEntry]- und [SymbolEntry]-Listen.
class MappedSymbol {
  final WordEntry word;
  final SymbolEntry symbol;

  const MappedSymbol({
    required this.word,
    required this.symbol,
  });

  @override
  String toString() =>
      'MappedSymbol("${word.text}" → "${symbol.fileName}")';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MappedSymbol &&
          other.word.id == word.id &&
          other.symbol.id == symbol.id;

  @override
  int get hashCode => Object.hash(word.id, symbol.id);
}
