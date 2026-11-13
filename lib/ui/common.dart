import 'package:flutter/material.dart';

import '../core/date_utils.dart';

void showAppMessage(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirmar',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                )
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Acepta decimales con coma o punto y fracciones como `1/4` o `3/2`.
double parseAmount(String value) {
  final normalized = value.replaceAll(',', '.').replaceAll(' ', '');
  if (normalized.contains('/')) {
    final partes = normalized.split('/');
    if (partes.length == 2) {
      final numerador = double.tryParse(partes[0]);
      final denominador = double.tryParse(partes[1]);
      if (numerador != null && denominador != null && denominador != 0) {
        return numerador / denominador;
      }
    }
    return 0;
  }
  return double.tryParse(normalized) ?? 0;
}

String formatQty(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  final dos = value.toStringAsFixed(2);
  if ((double.parse(dos) - value).abs() < 0.0000001) return dos;
  return value
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// `true` cuando el ancho disponible corresponde a un teléfono.
bool esAngosto(double ancho, {double limite = 700}) => ancho < limite;

/// Diálogo que se adapta al tamaño de la pantalla sin desbordarse.
class DialogSurface extends StatelessWidget {
  const DialogSurface({
    super.key,
    required this.child,
    this.maxWidth = 520,
    this.maxHeightFactor = 0.8,
  });

  final Widget child;
  final double maxWidth;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final alto = MediaQuery.sizeOf(context).height * maxHeightFactor;
    // El ancho debe ser "tight": AlertDialog usa IntrinsicWidth y un ancho
    // máximo (ConstrainedBox) lo obliga a pedir intrínsecos a ListView, que no
    // los soporta. El diálogo recorta este ancho al espacio disponible.
    return SizedBox(
      width: maxWidth,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: alto),
        child: child,
      ),
    );
  }
}

/// Fila que se convierte en columna cuando el ancho es reducido.
class AdaptiveRow extends StatelessWidget {
  const AdaptiveRow({
    super.key,
    required this.children,
    this.spacing = 12,
    this.runSpacing = 10,
    this.limite = 700,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.mainAxisAlignment = MainAxisAlignment.start,
  });

  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final double limite;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisAlignment mainAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!esAngosto(constraints.maxWidth, limite: limite)) {
          return Row(
            crossAxisAlignment: crossAxisAlignment,
            mainAxisAlignment: mainAxisAlignment,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(width: spacing),
                children[i],
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(height: runSpacing),
              children[i],
            ],
          ],
        );
      },
    );
  }
}

/// Tabla o contenido ancho que se puede recorrer con el dedo o el mouse.
class HorizontalScrollArea extends StatelessWidget {
  const HorizontalScrollArea({
    super.key,
    required this.child,
    this.minWidth,
  });

  final Widget child;
  final double? minWidth;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      thumbVisibility: false,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: minWidth == null
            ? child
            : ConstrainedBox(
                constraints: BoxConstraints(minWidth: minWidth!),
                child: child,
              ),
      ),
    );
  }
}

String formatPercent(double value) =>
    '${(value * 100).toStringAsFixed(1)}%';

String formatDateTimeText(String value) {
  final parsed = parseSqlDateTime(value);
  return parsed == null ? value : formatDateTimeShort(parsed);
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final angosto = esAngosto(constraints.maxWidth);
        final titulo = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        );
        final botones = actions.isEmpty
            ? null
            : Wrap(spacing: 8, runSpacing: 8, children: actions);
        return Padding(
          padding: EdgeInsets.only(bottom: angosto ? 14 : 20),
          child: angosto
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titulo,
                    if (botones != null) ...[
                      const SizedBox(height: 12),
                      Align(alignment: Alignment.centerLeft, child: botones),
                    ],
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: titulo),
                    if (botones != null) ...[
                      const SizedBox(width: 12),
                      botones,
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(
            alpha: 0.6,
          ),
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.color,
    this.width = 230,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  final Color? color;
  final double width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    return SizedBox(
      width: width,
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null)
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
            if (icon != null) const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                  if (caption != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      caption!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children, this.width = 230});

  final List<Widget> children;
  final double width;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth >= 1100
            ? (constraints.maxWidth - 36) / 4
            : constraints.maxWidth >= 700
            ? (constraints.maxWidth - 24) / 3
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: children
              .map((child) => SizedBox(width: cardWidth, child: child))
              .toList(),
        );
      },
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: scheme.primary),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()));
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline,
      title: 'No se pudo cargar la información',
      message: message,
      action: onRetry == null
          ? null
          : OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
    );
  }
}

class LabelValue extends StatelessWidget {
  const LabelValue({
    super.key,
    required this.label,
    required this.value,
    this.strong = false,
    this.color,
  });

  final String label;
  final String value;
  final bool strong;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class MoneyText extends StatelessWidget {
  const MoneyText(
    this.value, {
    super.key,
    this.style,
    this.color,
    this.strong = false,
  });

  final double value;
  final TextStyle? style;
  final Color? color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Text(
      formatMoney(value),
      style: (style ?? Theme.of(context).textTheme.bodyMedium)?.copyWith(
        color: color,
        fontWeight: strong ? FontWeight.w700 : null,
      ),
    );
  }
}

InputDecoration appInput({
  required String label,
  String? hint,
  IconData? icon,
  Widget? suffix,
  String? suffixText,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: icon == null ? null : Icon(icon),
    suffixIcon: suffix,
    suffixText: suffixText,
    filled: true,
    fillColor: const Color(0xFFFFF9F0), // Blanco cálido
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );
}

class ChoiceChipRow<T> extends StatelessWidget {
  const ChoiceChipRow({
    super.key,
    required this.values,
    required this.labelBuilder,
    required this.selected,
    required this.onSelected,
  });

  final List<T> values;
  final String Function(T value) labelBuilder;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values
          .map(
            (value) => ChoiceChip(
              label: Text(labelBuilder(value)),
              selected: value == selected,
              onSelected: (_) => onSelected(value),
            ),
          )
          .toList(),
    );
  }
}
