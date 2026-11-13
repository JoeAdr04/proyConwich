import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/date_utils.dart';

/// Tarjeta de producto compartida por Ventas y Menú del día.
class ProductoCatalogoCard extends StatelessWidget {
  const ProductoCatalogoCard({
    super.key,
    required this.nombre,
    required this.categoria,
    required this.precio,
    required this.color,
    required this.mensaje,
    this.advertencia,
    this.imagen,
    this.onTap,
    this.habilitado = true,
    this.seleccionado = false,
    this.agotado = false,
    this.esDirecto = false,
    this.stock,
    this.accion,
  });

  final Uint8List? imagen;
  final String nombre;
  final String categoria;
  final double precio;
  final int color;
  final String mensaje;

  /// Aviso no bloqueante (por ejemplo, insumos insuficientes en la receta).
  final String? advertencia;
  final VoidCallback? onTap;
  final bool habilitado;

  /// En el Menú: el producto está elegido para el menú de hoy
  /// (borde verde + check).
  final bool seleccionado;

  /// En el Menú: producto agotado (borde rojo + badge, bloqueado).
  final bool agotado;
  final bool esDirecto;
  final double? stock;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final verde = Colors.green.shade700;
    final texto = habilitado && !agotado
        ? scheme.onSurface
        : scheme.onSurfaceVariant;
    final borde = agotado
        ? scheme.error
        : seleccionado
        ? verde
        : scheme.outlineVariant.withValues(alpha: 0.6);
    final colorMensaje = agotado
        ? scheme.error
        : habilitado
        ? (seleccionado ? verde : scheme.primary)
        : scheme.onSurfaceVariant;
    final iconoMensaje = agotado
        ? Icons.block
        : seleccionado
        ? Icons.remove_circle_outline
        : habilitado
        ? Icons.add_circle_outline
        : Icons.info_outline;
    return Opacity(
      opacity: habilitado ? 1 : 0.55,
      child: Material(
        color: agotado
            ? scheme.errorContainer.withValues(alpha: 0.25)
            : scheme.surfaceContainer, // Crema
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: borde,
                width: seleccionado || agotado ? 2 : 1,
              ),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          height: 92,
                          width: double.infinity,
                          child: imagen != null
                              ? Image.memory(
                                  imagen!,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                )
                              : Container(
                                  color: Color(color).withValues(alpha: 0.10),
                                  child: Icon(
                                    esDirecto
                                        ? Icons.local_drink_outlined
                                        : Icons.restaurant,
                                    size: 34,
                                    color: agotado
                                        ? scheme.onSurfaceVariant
                                        : Color(color),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: agotado
                                  ? scheme.onSurfaceVariant
                                  : Color(color),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              categoria,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                          ?accion,
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        nombre,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700, color: texto),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatMoney(precio),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: agotado
                              ? scheme.onSurfaceVariant
                              : habilitado
                              ? scheme.primary
                              : texto,
                        ),
                      ),
                      if (stock != null && esDirecto)
                        Text(
                          'Stock: ${_formatQty(stock!)}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: habilitado
                                    ? scheme.onSurfaceVariant
                                    : texto,
                              ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            iconoMensaje,
                            size: 18,
                            color: colorMensaje,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              mensaje,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorMensaje,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      if (advertencia != null && advertencia!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 18,
                              color: Colors.orange.shade800,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                advertencia!,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Colors.orange.shade900,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (agotado)
                  Positioned(
                    top: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.error,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.block,
                            size: 12,
                            color: Color(0xFFFFF9F0), // Blanco cálido
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Agotado',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Color(0xFFFFF9F0), // Blanco cálido
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (seleccionado)
                  Positioned(
                    top: 20,
                    right: 20,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: verde,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Color(0xFFFFF9F0), // Blanco cálido
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 16,
                        color: Color(0xFFFFF9F0), // Blanco cálido
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatQty(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    final dos = value.toStringAsFixed(2);
    if ((double.parse(dos) - value).abs() < 0.0000001) return dos;
    return value
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
