import 'package:flutter/material.dart';

// ── Farben ────────────────────────────────────────────────────────────────────

const _kbBg       = Color(0xFF273849);
const _keyBg      = Color(0xFF3A4F62);
const _keyBgDark  = Color(0xFF1E2E3B);
const _keyFg      = Colors.white;
const _keySpecial = Color(0xFF2D5FA8);   // Blau für Space / Enter
const _keyShadow  = Color(0xFF111A24);

// ── Tastatur-Layout ───────────────────────────────────────────────────────────

/// Deutsche QWERTZ-Tastatur als Widget – kein System-Keyboard nötig.
///
/// Manipuliert direkt den [TextEditingController].
/// [textFocusNode]: Nach jedem Tastendruck wird der Fokus zurück an das
/// Textfeld gegeben, damit USB-Tastatureingabe weiterhin funktioniert.
///
/// Verwendet [Expanded] mit Flex-Werten statt fixer Pixel-Breiten, um
/// Gleitkomma-Overflow in allen Zeilen zu vermeiden.
class NasiraKeyboard extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback? onEnter;
  final FocusNode? textFocusNode;

  const NasiraKeyboard({
    super.key,
    required this.controller,
    this.onEnter,
    this.textFocusNode,
  });

  @override
  State<NasiraKeyboard> createState() => _NasiraKeyboardState();
}

class _NasiraKeyboardState extends State<NasiraKeyboard> {
  bool _caps  = false;
  bool _shift = false;

  // ── Eingabe-Logik ─────────────────────────────────────────────────────────

  void _type(String raw) {
    final upper = _caps ^ _shift;   // XOR: genau einer aktiv → uppercase
    final char = upper ? raw.toUpperCase() : raw.toLowerCase();
    final ctrl = widget.controller;
    final text = ctrl.text;
    final sel  = ctrl.selection;
    final start = (sel.isValid && sel.start >= 0) ? sel.start : text.length;
    final end   = (sel.isValid && sel.end   >= 0) ? sel.end   : text.length;
    final newText = text.replaceRange(start, end, char);
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + char.length),
    );
    if (_shift) setState(() => _shift = false);
    widget.textFocusNode?.requestFocus();
  }

  void _backspace() {
    final ctrl = widget.controller;
    final text = ctrl.text;
    if (text.isEmpty) return;
    ctrl.value = TextEditingValue(
      text: text.substring(0, text.length - 1),
      selection: TextSelection.collapsed(offset: text.length - 1),
    );
    widget.textFocusNode?.requestFocus();
  }

  void _deleteWord() {
    final ctrl = widget.controller;
    final text = ctrl.text;
    final trimmed = text.trimRight();
    final lastSpace = trimmed.lastIndexOf(' ');
    final newText = lastSpace == -1 ? '' : trimmed.substring(0, lastSpace + 1);
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
    widget.textFocusNode?.requestFocus();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _kbBg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildRow1(),   // QWERTZUIOPÜ + ⌫
            const SizedBox(height: 4),
            _buildRow2(),   // ⇪ ASDFGHJKLÖ + ↵
            const SizedBox(height: 4),
            _buildRow3(),   // ⇧ YXCVBNM,.? + ↵
            const SizedBox(height: 4),
            _buildRow4(),   // Ä ß ! ( )  ␣  - : @
          ],
        ),
      ),
    );
  }

  // ── Zeile 1: Q W E R T Z U I O P Ü ⌫  (flex: 2×11 + 3 = 25) ─────────────

  Widget _buildRow1() {
    return Row(children: [
      Expanded(flex: 2, child: _let('Q')),
      Expanded(flex: 2, child: _let('W')),
      Expanded(flex: 2, child: _let('E')),
      Expanded(flex: 2, child: _let('R')),
      Expanded(flex: 2, child: _let('T')),
      Expanded(flex: 2, child: _let('Z')),
      Expanded(flex: 2, child: _let('U')),
      Expanded(flex: 2, child: _let('I')),
      Expanded(flex: 2, child: _let('O')),
      Expanded(flex: 2, child: _let('P')),
      Expanded(flex: 2, child: _let('Ü')),
      Expanded(flex: 3, child: _action(
        icon: Icons.backspace_outlined,
        onTap: _backspace,
        onLongPress: _deleteWord,
      )),
    ]);
  }

  // ── Zeile 2: ⇪ A S D F G H J K L Ö ↵  (flex: 2×12 + 3 = 25) ─────────────

  Widget _buildRow2() {
    return Row(children: [
      Expanded(flex: 2, child: _toggle(
        icon: Icons.keyboard_capslock_rounded,
        active: _caps,
        onTap: () => setState(() => _caps = !_caps),
      )),
      Expanded(flex: 2, child: _let('A')),
      Expanded(flex: 2, child: _let('S')),
      Expanded(flex: 2, child: _let('D')),
      Expanded(flex: 2, child: _let('F')),
      Expanded(flex: 2, child: _let('G')),
      Expanded(flex: 2, child: _let('H')),
      Expanded(flex: 2, child: _let('J')),
      Expanded(flex: 2, child: _let('K')),
      Expanded(flex: 2, child: _let('L')),
      Expanded(flex: 2, child: _let('Ö')),
      Expanded(flex: 3, child: _action(
        icon: Icons.keyboard_return_rounded,
        color: _keySpecial,
        onTap: () {
          if (widget.onEnter != null) {
            widget.onEnter!();
          } else {
            _type('\n');
          }
        },
      )),
    ]);
  }

  // ── Zeile 3: ⇧ Y X C V B N M , . ? ↵  (flex: 2×12 + 3 = 25) ─────────────

  Widget _buildRow3() {
    return Row(children: [
      Expanded(flex: 2, child: _toggle(
        icon: Icons.keyboard_arrow_up_rounded,
        active: _shift,
        onTap: () => setState(() => _shift = !_shift),
      )),
      Expanded(flex: 2, child: _let('Y')),
      Expanded(flex: 2, child: _let('X')),
      Expanded(flex: 2, child: _let('C')),
      Expanded(flex: 2, child: _let('V')),
      Expanded(flex: 2, child: _let('B')),
      Expanded(flex: 2, child: _let('N')),
      Expanded(flex: 2, child: _let('M')),
      Expanded(flex: 2, child: _let(',')),
      Expanded(flex: 2, child: _let('.')),
      Expanded(flex: 2, child: _let('?')),
      Expanded(flex: 3, child: _action(
        icon: Icons.keyboard_return_rounded,
        color: _keySpecial,
        onTap: () {
          if (widget.onEnter != null) {
            widget.onEnter!();
          } else {
            _type('\n');
          }
        },
      )),
    ]);
  }

  // ── Zeile 4: Ä ß ! ( )  ␣  - : @  (flex: 5×2 + 9 + 3×2 = 25) ────────────

  Widget _buildRow4() {
    return Row(children: [
      Expanded(flex: 2, child: _let('Ä')),
      Expanded(flex: 2, child: _let('ß')),
      Expanded(flex: 2, child: _let('!')),
      Expanded(flex: 2, child: _let('(')),
      Expanded(flex: 2, child: _let(')')),
      Expanded(flex: 9, child: _spaceBar()),
      Expanded(flex: 2, child: _let('-')),
      Expanded(flex: 2, child: _let(':')),
      Expanded(flex: 2, child: _let('@')),
    ]);
  }

  // ── Hilfsmethoden für Tasten ──────────────────────────────────────────────

  Widget _let(String label) {
    final upper = _caps ^ _shift;
    final display = upper ? label.toUpperCase() : label.toLowerCase();
    return _KeyButton(
      label: display,
      color: _keyBg,
      onTap: () => _type(label),
    );
  }

  Widget _action({
    required IconData icon,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    Color color = _keyBgDark,
  }) {
    return _KeyButton(
      icon: icon,
      color: color,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  Widget _toggle({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return _KeyButton(
      icon: icon,
      color: active ? _keySpecial : _keyBgDark,
      onTap: onTap,
    );
  }

  Widget _spaceBar() {
    return _KeyButton(
      label: '␣',
      labelStyle: const TextStyle(
        fontSize: 16, color: Colors.white70, fontWeight: FontWeight.w300),
      color: _keySpecial,
      onTap: () => _type(' '),
    );
  }
}

// ── _KeyButton ────────────────────────────────────────────────────────────────

class _KeyButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final TextStyle? labelStyle;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _KeyButton({
    this.label,
    this.icon,
    this.labelStyle,
    required this.color,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        height: 44,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(7),
          shadowColor: _keyShadow,
          elevation: 2,
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: onTap,
            onLongPress: onLongPress,
            child: Center(
              child: icon != null
                  ? Icon(icon, size: 20, color: _keyFg)
                  : Text(
                      label ?? '',
                      style: labelStyle ??
                          const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: _keyFg,
                          ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
