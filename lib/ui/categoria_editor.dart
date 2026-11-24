import 'package:flutter/material.dart';

import '../core/catalog_repository.dart';
import 'common.dart';

/// Colores listos para elegir al crear o editar una categoría.
const _coloresRapidos = <Color>[
  Color(0xFFE53935), // Rojo
  Color(0xFFD81B60), // Rosa
  Color(0xFF8E24AA), // Morado
  Color(0xFF5E35B1), // Violeta
  Color(0xFF3949AB), // Índigo
  Color(0xFF1E88E5), // Azul
  Color(0xFF039BE5), // Celeste
  Color(0xFF00ACC1), // Turquesa
  Color(0xFF00897B), // Verde azulado
  Color(0xFF43A047), // Verde
  Color(0xFF7CB342), // Verde claro
  Color(0xFFC0CA33), // Lima
  Color(0xFFFDD835), // Amarillo
  Color(0xFFFFB300), // Ámbar
  Color(0xFFFB8C00), // Naranja
  Color(0xFFF4511E), // Naranja oscuro
  Color(0xFFEA580C), // Naranja quemado
  Color(0xFFD84315), // Ladrillo
  Color(0xFF795548), // Café
  Color(0xFF70452D), // Nogal
  Color(0xFFC18A55), // Caramelo
  Color(0xFFE8C995), // Dorado
  Color(0xFF2563EB), // Azul sistema
  Color(0xFF16A34A), // Verde sistema
  Color(0xFF9333EA), // Púrpura sistema
  Color(0xFF546E7A), // Gris pizarra
  Color(0xFF212121), // Negro
];

/// Color inicial de una categoría nueva (Nogal, el color de la marca).
const _colorPorDefecto = 0xFF70452D;

String _hexDe(int color) =>
    '#${color.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

/// Abre el diálogo para crear o editar una categoría y la guarda en la base.
/// Devuelve el id de la categoría guardada, o `null` si se canceló o falló.
Future<int?> showCategoriaEditor({
  required BuildContext context,
  required CatalogRepository repository,
  required List<CategoriaProducto> categorias,
  CategoriaProducto? categoria,
}) async {
  final resultado = await showDialog<_ResultadoEditor>(
    context: context,
    builder: (context) =>
        _CategoriaEditorDialog(categoria: categoria, categorias: categorias),
  );
  if (resultado == null) return null;
  try {
    return await repository.saveCategoria(
      CategoriaProducto(
        id: categoria?.id,
        nombre: resultado.nombre,
        color: resultado.color,
        siempreDisponible: categoria?.siempreDisponible ?? false,
        orden: categoria?.orden ?? categorias.length,
        activo: categoria?.activo ?? true,
      ),
    );
  } catch (error) {
    if (context.mounted) {
      showAppMessage(
        context,
        'No se pudo guardar la categoría: $error',
        error: true,
      );
    }
    return null;
  }
}

class _ResultadoEditor {
  const _ResultadoEditor({required this.nombre, required this.color});

  final String nombre;
  final int color;
}

/// Campo con menú desplegable para elegir y gestionar categorías.
class CategoriaPickerField extends StatefulWidget {
  const CategoriaPickerField({
    super.key,
    required this.repository,
    required this.categorias,
    required this.value,
    required this.onChanged,
    required this.onCategoriasChanged,
    this.label = 'Categoría',
    this.errorText,
    this.incluirTodas = false,
  });

  final CatalogRepository repository;
  final List<CategoriaProducto> categorias;
  final int? value;
  final ValueChanged<int?> onChanged;
  final ValueChanged<List<CategoriaProducto>> onCategoriasChanged;
  final String label;
  final String? errorText;

  /// Muestra el elemento "Todas" para quitar el filtro de categoría.
  final bool incluirTodas;

  @override
  State<CategoriaPickerField> createState() => _CategoriaPickerFieldState();
}

class _CategoriaPickerFieldState extends State<CategoriaPickerField> {
  final _menuController = MenuController();
  late List<CategoriaProducto> _categorias;

  @override
  void initState() {
    super.initState();
    _categorias = List.of(widget.categorias);
  }

  @override
  void didUpdateWidget(CategoriaPickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categorias != widget.categorias) {
      _categorias = List.of(widget.categorias);
    }
  }

  Future<void> _refrescar() async {
    final actualizadas = await widget.repository.getCategorias();
    if (!mounted) return;
    setState(() => _categorias = actualizadas);
    widget.onCategoriasChanged(actualizadas);
    if (widget.value != null &&
        !actualizadas.any((c) => c.id == widget.value)) {
      widget.onChanged(null);
    }
  }

  Future<void> _editar(CategoriaProducto categoria) async {
    final id = await showCategoriaEditor(
      context: context,
      repository: widget.repository,
      categorias: _categorias,
      categoria: categoria,
    );
    if (id != null) await _refrescar();
  }

  Future<void> _eliminar(CategoriaProducto categoria) async {
    final enUso = await widget.repository.countProductosCategoria(
      categoria.id!,
    );
    if (!mounted) return;
    if (enUso == 0) {
      final ok = await confirmAction(
        context,
        title: 'Eliminar categoría',
        message: '¿Eliminar la categoría "${categoria.nombre}"?',
        confirmLabel: 'Eliminar',
        destructive: true,
      );
      if (!ok) return;
    } else {
      final destinoId = await showDialog<int?>(
        context: context,
        builder: (context) => _MoverYEliminarDialog(
          categoria: categoria,
          productos: enUso,
          destinos: _categorias
              .where((c) => c.id != null && c.id != categoria.id)
              .toList(),
        ),
      );
      if (destinoId == null) return;
      try {
        await widget.repository.moverProductosCategoria(
          desdeId: categoria.id!,
          hastaId: destinoId,
        );
      } catch (error) {
        if (mounted) {
          showAppMessage(
            context,
            'No se pudieron mover los productos: $error',
            error: true,
          );
        }
        return;
      }
    }
    try {
      await widget.repository.deleteCategoria(categoria.id!);
    } catch (error) {
      if (mounted) {
        showAppMessage(context, 'No se pudo eliminar: $error', error: true);
      }
      return;
    }
    await _refrescar();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final menuWidth = screenSize.width > 464
        ? 440.0
        : (screenSize.width - 24).clamp(220.0, 440.0).toDouble();
    CategoriaProducto? seleccionada;
    for (final categoria in _categorias) {
      if (categoria.id == widget.value) {
        seleccionada = categoria;
        break;
      }
    }
    final texto =
        seleccionada?.nombre ??
        (widget.incluirTodas ? 'Todas' : 'Selecciona una categoría');
    return MenuAnchor(
      controller: _menuController,
      menuChildren: [
        SizedBox(
          width: menuWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: screenSize.height * 0.65,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      'Categorías',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (widget.incluirTodas)
                    ListTile(
                      dense: true,
                      selected: widget.value == null,
                      leading: Icon(
                        Icons.select_all,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: const Text('Todas'),
                      onTap: () {
                        _menuController.close();
                        widget.onChanged(null);
                      },
                    ),
                  const Divider(height: 1),
                  for (final categoria in _categorias)
                    ListTile(
                      dense: true,
                      selected: categoria.id == widget.value,
                      onTap: () {
                        _menuController.close();
                        widget.onChanged(categoria.id);
                      },
                      leading: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Color(categoria.color),
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Text(categoria.nombre),
                      subtitle:
                          CatalogRepository.esCategoriaProtegida(
                            categoria.nombre,
                          )
                          ? const Text('Categoría del sistema')
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            tooltip:
                                CatalogRepository.esCategoriaProtegida(
                                  categoria.nombre,
                                )
                                ? 'Categoría del sistema: solo se puede cambiar el color'
                                : 'Editar',
                            onPressed: () => _editar(categoria),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.delete_outline, size: 20),
                            tooltip:
                                CatalogRepository.esCategoriaProtegida(
                                  categoria.nombre,
                                )
                                ? 'No se puede eliminar una categoría del sistema'
                                : 'Eliminar',
                            onPressed:
                                CatalogRepository.esCategoriaProtegida(
                                  categoria.nombre,
                                )
                                ? null
                                : () => _eliminar(categoria),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
      builder: (context, controller, child) => InkWell(
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: appInput(
            label: widget.label,
            suffix: Icon(
              controller.isOpen ? Icons.expand_less : Icons.expand_more,
            ),
          ).copyWith(errorText: widget.errorText),
          child: Row(
            children: [
              if (seleccionada != null) ...[
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Color(seleccionada.color),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  texto,
                  overflow: TextOverflow.ellipsis,
                  style: seleccionada == null && !widget.incluirTodas
                      ? TextStyle(color: Theme.of(context).hintColor)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Diálogo para mover los productos de una categoría antes de eliminarla.
/// Devuelve el id de la categoría destino elegida.
class _MoverYEliminarDialog extends StatefulWidget {
  const _MoverYEliminarDialog({
    required this.categoria,
    required this.productos,
    required this.destinos,
  });

  final CategoriaProducto categoria;
  final int productos;
  final List<CategoriaProducto> destinos;

  @override
  State<_MoverYEliminarDialog> createState() => _MoverYEliminarDialogState();
}

class _MoverYEliminarDialogState extends State<_MoverYEliminarDialog> {
  int? _destinoId;

  @override
  void initState() {
    super.initState();
    _destinoId = widget.destinos.isEmpty ? null : widget.destinos.first.id;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      title: const Text('Mover productos y eliminar'),
      content: DialogSurface(
        maxWidth: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Hay ${widget.productos} producto(s) en la categoría '
              '"${widget.categoria.nombre}".',
            ),
            const SizedBox(height: 12),
            if (widget.destinos.isEmpty)
              const Text(
                'No hay otra categoría donde moverlos. '
                'Crea otra categoría primero.',
              )
            else
              DropdownButtonFormField<int>(
                initialValue: _destinoId,
                isExpanded: true,
                decoration: appInput(label: 'Mover los productos a'),
                items: widget.destinos
                    .map(
                      (categoria) => DropdownMenuItem(
                        value: categoria.id,
                        child: Text(
                          categoria.nombre,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _destinoId = value),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        if (widget.destinos.isNotEmpty)
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, _destinoId),
            child: const Text('Mover y eliminar'),
          ),
      ],
    );
  }
}

/// Diálogo para crear o editar una categoría con nombre y color.
class _CategoriaEditorDialog extends StatefulWidget {
  const _CategoriaEditorDialog({this.categoria, required this.categorias});

  final CategoriaProducto? categoria;
  final List<CategoriaProducto> categorias;

  @override
  State<_CategoriaEditorDialog> createState() => _CategoriaEditorDialogState();
}

class _CategoriaEditorDialogState extends State<_CategoriaEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombre;
  late final bool _protegida;
  late int _color;

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: widget.categoria?.nombre ?? '');
    _protegida =
        widget.categoria != null &&
        CatalogRepository.esCategoriaProtegida(widget.categoria!.nombre);
    _color = widget.categoria?.color ?? _colorPorDefecto;
  }

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _ResultadoEditor(
        nombre: _protegida ? widget.categoria!.nombre : _nombre.text.trim(),
        color: _color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      title: Text(
        widget.categoria == null ? 'Nueva categoría' : 'Editar categoría',
      ),
      content: DialogSurface(
        maxWidth: 380,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nombre,
                  autofocus: !_protegida,
                  enabled: !_protegida,
                  textCapitalization: TextCapitalization.characters,
                  decoration: appInput(
                    label: 'Nombre',
                    hint: 'Ej. SOPAS, REFRESCOS, POSTRES',
                  ),
                  onChanged: (value) {
                    final upper = value.toUpperCase();
                    if (upper == value) return;
                    _nombre.value = TextEditingValue(
                      text: upper,
                      selection: TextSelection.collapsed(offset: upper.length),
                    );
                  },
                  validator: (value) {
                    final texto = (value ?? '').trim();
                    if (texto.isEmpty) return 'Ingresa un nombre';
                    for (final otra in widget.categorias) {
                      if (otra.id == widget.categoria?.id) continue;
                      if (otra.nombre.toUpperCase() == texto.toUpperCase()) {
                        return 'Ya existe una categoría con ese nombre';
                      }
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _guardar(),
                ),
                if (_protegida) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Categoría del sistema: solo se puede cambiar el color.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _ColorSelector(
                  color: _color,
                  onChanged: (color) => setState(() => _color = color),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardar,
          child: Text(widget.categoria == null ? 'Crear' : 'Guardar'),
        ),
      ],
    );
  }
}

/// Paleta de colores listos + deslizadores de matiz, saturación y brillo para
/// llegar a cualquier color personalizado.
class _ColorSelector extends StatelessWidget {
  const _ColorSelector({required this.color, required this.onChanged});

  final int color;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hsv = HSVColor.fromColor(Color(color));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Color', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final opcion in _coloresRapidos)
              _MuestraColor(
                color: opcion.toARGB32(),
                seleccionado: opcion.toARGB32() == color,
                onTap: () => onChanged(opcion.toARGB32()),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Color personalizado',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Color(color),
                shape: BoxShape.circle,
                border: Border.all(color: scheme.outlineVariant),
              ),
            ),
            const SizedBox(width: 10),
            Text(_hexDe(color)),
          ],
        ),
        _Deslizador(
          etiqueta: 'Matiz',
          valor: hsv.hue,
          maximo: 360,
          texto: '${hsv.hue.round()}°',
          colorActivo: Color(color),
          onChanged: (valor) =>
              onChanged(hsv.withHue(valor).toColor().toARGB32()),
        ),
        _Deslizador(
          etiqueta: 'Saturación',
          valor: hsv.saturation,
          maximo: 1,
          texto: '${(hsv.saturation * 100).round()}%',
          colorActivo: Color(color),
          onChanged: (valor) =>
              onChanged(hsv.withSaturation(valor).toColor().toARGB32()),
        ),
        _Deslizador(
          etiqueta: 'Brillo',
          valor: hsv.value,
          maximo: 1,
          texto: '${(hsv.value * 100).round()}%',
          colorActivo: Color(color),
          onChanged: (valor) =>
              onChanged(hsv.withValue(valor).toColor().toARGB32()),
        ),
      ],
    );
  }
}

class _Deslizador extends StatelessWidget {
  const _Deslizador({
    required this.etiqueta,
    required this.valor,
    required this.maximo,
    required this.texto,
    required this.colorActivo,
    required this.onChanged,
  });

  final String etiqueta;
  final double valor;
  final double maximo;
  final String texto;
  final Color colorActivo;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 90, child: Text(etiqueta)),
        Expanded(
          child: Slider(
            value: valor.clamp(0, maximo),
            min: 0,
            max: maximo,
            activeColor: colorActivo,
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 48, child: Text(texto, textAlign: TextAlign.end)),
      ],
    );
  }
}

class _MuestraColor extends StatelessWidget {
  const _MuestraColor({
    required this.color,
    required this.seleccionado,
    required this.onTap,
  });

  final int color;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final claro = Color(color).computeLuminance() > 0.55;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Color(color),
          shape: BoxShape.circle,
          border: Border.all(
            color: seleccionado
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: seleccionado
            ? Icon(
                Icons.check,
                size: 18,
                color: claro ? Colors.black87 : Colors.white,
              )
            : null,
      ),
    );
  }
}
