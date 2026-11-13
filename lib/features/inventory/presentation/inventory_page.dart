import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/catalog_repository.dart';
import '../../../core/date_utils.dart';
import '../../../core/session.dart';
import '../../../ui/common.dart';

const _paletaCategorias = <int>[
  0xFF0F766E,
  0xFF2563EB,
  0xFF7C3AED,
  0xFFDB2777,
  0xFFEA580C,
  0xFFCA8A04,
  0xFF16A34A,
  0xFF475569,
];

class _InsumosData {
  const _InsumosData({
    required this.insumos,
    required this.unidades,
    required this.categorias,
  });

  final List<Insumo> insumos;
  final List<UnidadMedida> unidades;
  final List<CategoriaProducto> categorias;
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({
    super.key,
    required this.usuario,
    required this.refreshToken,
  });

  final Usuario usuario;
  final int refreshToken;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _repository = CatalogRepository();
  late Future<_InsumosData> _future;
  String _search = '';
  bool _soloActivos = false;
  bool _soloAlertas = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(InventoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _reload();
  }

  // Debe devolver void: si devolviera el Future, setState lanzaría error y la
  // pantalla no se refrescaría.
  void _reload() {
    _future = _load();
  }

  Future<_InsumosData> _load() async {
    final insumos = await _repository.getInsumos();
    final unidades = await _repository.getUnidades();
    final categorias = await _repository.getCategorias();
    return _InsumosData(
      insumos: insumos,
      unidades: unidades,
      categorias: categorias,
    );
  }

  Future<void> _openForm([Insumo? insumo]) async {
    final data = await _future;
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _InsumoDialog(
        repository: _repository,
        unidades: data.unidades,
        categorias: data.categorias,
        insumo: insumo,
        usuarioId: widget.usuario.id,
      ),
    );
    if (saved == true && mounted) {
      setState(_reload);
      showAppMessage(context, 'Insumo guardado correctamente.');
    }
  }

  Future<void> _toggleActivo(Insumo insumo, bool activo) async {
    await _repository.setInsumoActivo(insumo.id!, activo);
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _ajustarStock(Insumo insumo) async {
    final nuevo = await showDialog<double>(
      context: context,
      builder: (_) => _StockDialog(
        titulo: 'Ajustar stock de ${insumo.nombre}',
        stockActual: insumo.stock,
        unidad: insumo.unidadAbreviatura,
      ),
    );
    if (nuevo == null) return;
    try {
      await _repository.ajustarStockInsumo(
        insumoId: insumo.id!,
        nuevoStock: nuevo,
        usuarioId: widget.usuario.id,
        motivo: 'Ajuste manual',
      );
      if (!mounted) return;
      setState(_reload);
      showAppMessage(context, 'Stock actualizado.');
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, 'No se pudo ajustar: $error', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_InsumosData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final insumos = data?.insumos ?? [];
        final filtrados = insumos.where((insumo) {
          if (_soloActivos && !insumo.activo) return false;
          if (_soloAlertas && !insumo.bajoStock) return false;
          final term = _search.trim().toLowerCase();
          return term.isEmpty || insumo.nombre.toLowerCase().contains(term);
        }).toList();
        final alertas = insumos.where((insumo) => insumo.bajoStock).length;

        return SingleChildScrollView(
          padding: EdgeInsets.all(
            esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: 'Insumos',
                subtitle: 'Materias primas y su stock. Al vender un plato se descuentan sus insumos según la receta, si la tiene.',
                actions: [
                  FilledButton.icon(
                    onPressed: snapshot.hasData ? () => _openForm() : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Nuevo insumo'),
                  ),
                ],
              ),
              if (alertas > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: AppCard(
                    color: Theme.of(context).colorScheme.errorContainer
                        .withValues(alpha: 0.35),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '$alertas insumo(s) por debajo o en el stock mínimo.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              AppCard(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 300,
                      child: TextField(
                        decoration: appInput(
                          label: 'Buscar insumo',
                          icon: Icons.search,
                        ),
                        onChanged: (value) => setState(() => _search = value),
                      ),
                    ),
                    FilterChip(
                      label: const Text('Solo activos'),
                      selected: _soloActivos,
                      onSelected: (value) =>
                          setState(() => _soloActivos = value),
                    ),
                    FilterChip(
                      label: const Text('Solo alertas'),
                      selected: _soloAlertas,
                      onSelected: (value) =>
                          setState(() => _soloAlertas = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (snapshot.connectionState == ConnectionState.waiting)
                const LoadingView()
              else if (snapshot.hasError)
                ErrorView(
                  message: '${snapshot.error}',
                  onRetry: () => setState(_reload),
                )
              else if (filtrados.isEmpty)
                EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'No hay insumos que coincidan',
                  message: insumos.isEmpty
                      ? 'Crea el primer insumo para controlar el inventario.'
                      : 'Ajusta la búsqueda o los filtros.',
                  action: insumos.isEmpty
                      ? FilledButton.icon(
                          onPressed: () => _openForm(),
                          icon: const Icon(Icons.add),
                          label: const Text('Crear insumo'),
                        )
                      : null,
                )
              else
                ...filtrados.map(
                  (insumo) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _InsumoRow(
                      insumo: insumo,
                      onEdit: () => _openForm(insumo),
                      onAjustarStock: () => _ajustarStock(insumo),
                      onToggleActivo: (value) => _toggleActivo(insumo, value),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _InsumoRow extends StatelessWidget {
  const _InsumoRow({
    required this.insumo,
    required this.onEdit,
    required this.onAjustarStock,
    required this.onToggleActivo,
  });

  final Insumo insumo;
  final VoidCallback onEdit;
  final VoidCallback onAjustarStock;
  final ValueChanged<bool> onToggleActivo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final alerta = insumo.bajoStock;
    final icono = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: (alerta ? scheme.error : scheme.primary).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.inventory_2_outlined,
        color: alerta ? scheme.error : scheme.primary,
      ),
    );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              insumo.nombre,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (insumo.ventaDirecta)
              Chip(
                label: const Text('Venta directa'),
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
                backgroundColor: scheme.primaryContainer,
                labelStyle: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
        Text(
          '${insumo.unidadAbreviatura} · costo ${formatMoney(insumo.costoPromedio)}'
          '${insumo.ventaDirecta ? ' · se vende a ${formatMoney(insumo.precioVenta)}' : ''}',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
    final stock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Stock: ${formatQty(insumo.stock)} ${insumo.unidadAbreviatura}',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: alerta ? scheme.error : null,
          ),
        ),
        Text(
          'Mínimo: ${formatQty(insumo.stockMinimo)}',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
    final acciones = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: onAjustarStock,
          icon: const Icon(Icons.tune, size: 18),
          label: const Text('Ajustar stock'),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(value: insumo.activo, onChanged: onToggleActivo),
            IconButton(
              tooltip: 'Editar',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
      ],
    );

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!esAngosto(constraints.maxWidth, limite: 640)) {
            return Row(
              children: [
                icono,
                const SizedBox(width: 14),
                Expanded(flex: 3, child: info),
                Expanded(flex: 2, child: stock),
                const SizedBox(width: 8),
                acciones,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  icono,
                  const SizedBox(width: 12),
                  Expanded(child: info),
                ],
              ),
              const SizedBox(height: 8),
              stock,
              const SizedBox(height: 6),
              acciones,
            ],
          );
        },
      ),
    );
  }
}

class _InsumoDialog extends StatefulWidget {
  const _InsumoDialog({
    required this.repository,
    required this.unidades,
    required this.categorias,
    required this.usuarioId,
    this.insumo,
  });

  final CatalogRepository repository;
  final List<UnidadMedida> unidades;
  final List<CategoriaProducto> categorias;
  final int usuarioId;
  final Insumo? insumo;

  @override
  State<_InsumoDialog> createState() => _InsumoDialogState();
}

class _InsumoDialogState extends State<_InsumoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final TextEditingController _nombre;
  late final TextEditingController _stockMinimo;
  late final TextEditingController _stockActual;
  late final TextEditingController _costo;
  late final TextEditingController _precioVenta;
  late List<CategoriaProducto> _categorias;
  late int? _unidadId;
  late int? _categoriaVentaId;
  late bool _activo;
  late bool _ventaDirecta;
  Uint8List? _imagen;
  bool _saving = false;
  String? _error;

  bool get _hayCamara {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Aviso cuando el mínimo deja al insumo en alerta desde el primer momento.
  String? get _advertenciaStock {
    final actual = parseAmount(_stockActual.text);
    final minimo = parseAmount(_stockMinimo.text);
    if (minimo <= 0 || actual > minimo) return null;
    return 'El stock mínimo (${formatQty(minimo)}) es mayor o igual al stock '
        'actual (${formatQty(actual)}): el insumo quedará en alerta de stock.';
  }

  @override
  void initState() {
    super.initState();
    final insumo = widget.insumo;
    _categorias = List.of(widget.categorias);
    _nombre = TextEditingController(text: insumo?.nombre ?? '');
    _stockMinimo = TextEditingController(
      text: insumo == null ? '0' : formatQty(insumo.stockMinimo),
    );
    _stockActual = TextEditingController(
      text: insumo == null ? '0' : formatQty(insumo.stock),
    );
    _costo = TextEditingController(
      text: insumo == null ? '0' : insumo.costoPromedio.toStringAsFixed(2),
    );
    _precioVenta = TextEditingController(
      text: insumo == null ? '' : insumo.precioVenta.toStringAsFixed(2),
    );
    _unidadId =
        insumo?.unidadId ??
        (widget.unidades.isEmpty ? null : widget.unidades.first.id);
    if (!widget.unidades.any((unidad) => unidad.id == _unidadId)) {
      _unidadId = widget.unidades.isEmpty ? null : widget.unidades.first.id;
    }
    _categoriaVentaId = insumo?.categoriaVentaDirectaId;
    if (_categoriaVentaId == null) {
      for (final categoria in _categorias) {
        if (categoria.nombre.toLowerCase() == 'venta directa') {
          _categoriaVentaId = categoria.id;
          break;
        }
      }
    }
    _activo = insumo?.activo ?? true;
    _ventaDirecta = insumo?.ventaDirecta ?? false;
    _imagen = insumo?.imagen;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _stockMinimo.dispose();
    _stockActual.dispose();
    _costo.dispose();
    _precioVenta.dispose();
    super.dispose();
  }

  Future<void> _cargarImagen(ImageSource source) async {
    try {
      final archivo = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );
      if (archivo == null) return;
      final bytes = await archivo.readAsBytes();
      if (!mounted) return;
      setState(() => _imagen = bytes);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo cargar la imagen: $error');
    }
  }

  Future<void> _crearCategoria() async {
    final nombre = await showDialog<String>(
      context: context,
      builder: (_) => const _NuevaCategoriaDialog(),
    );
    if (nombre == null || nombre.trim().isEmpty) return;
    try {
      await widget.repository.saveCategoria(
        CategoriaProducto(
          nombre: nombre.trim(),
          color:
              _paletaCategorias[_categorias.length % _paletaCategorias.length],
          siempreDisponible: false,
          orden: _categorias.length,
          activo: true,
        ),
      );
      final categorias = await widget.repository.getCategorias();
      CategoriaProducto? creada;
      for (final categoria in categorias) {
        if (categoria.nombre == nombre.trim()) {
          creada = categoria;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _categorias = categorias;
        _categoriaVentaId = creada?.id ?? _categoriaVentaId;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo crear la categoría: $error');
    }
  }

  Widget _fotoProducto(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Foto para la venta directa',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Container(
          height: 130,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF9F0), // Blanco cálido
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: _imagen == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.image_outlined,
                      size: 30,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sin imagen',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                )
              : Image.memory(
                  _imagen!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_hayCamara)
              OutlinedButton.icon(
                onPressed: () => _cargarImagen(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Tomar foto'),
              ),
            OutlinedButton.icon(
              onPressed: () => _cargarImagen(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(_hayCamara ? 'Elegir imagen' : 'Buscar imagen'),
            ),
            if (_imagen != null)
              TextButton.icon(
                onPressed: () => setState(() => _imagen = null),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Quitar'),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_unidadId == null) {
      setState(() => _error = 'Selecciona una unidad de medida.');
      return;
    }
    final precio = parseAmount(_precioVenta.text);
    if (_ventaDirecta && precio <= 0) {
      setState(() => _error = 'Indica un precio de venta mayor a 0.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final unidad = widget.unidades.firstWhere((item) => item.id == _unidadId);
      final id = await widget.repository.saveInsumo(
        Insumo(
          id: widget.insumo?.id,
          nombre: _nombre.text,
          unidadId: _unidadId!,
          unidadAbreviatura: unidad.abreviatura,
          unidadNombre: unidad.nombre,
          unidadFamilia: unidad.familia,
          unidadFactorBase: unidad.factorBase,
          stockMinimo: parseAmount(_stockMinimo.text),
          costoPromedio: parseAmount(_costo.text),
          activo: _activo,
          stock: widget.insumo?.stock ?? 0,
          ventaDirecta: _ventaDirecta,
          precioVenta: _ventaDirecta ? precio : 0,
          productoId: widget.insumo?.productoId,
          categoriaVentaDirectaId: _categoriaVentaId,
          imagen: _imagen,
        ),
      );
      await widget.repository.ajustarStockInsumo(
        insumoId: id,
        nuevoStock: parseAmount(_stockActual.text),
        usuarioId: widget.usuarioId,
        motivo: 'Carga inicial',
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo guardar: $error';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unidad = widget.unidades.where((u) => u.id == _unidadId).isEmpty
        ? null
        : widget.unidades.firstWhere((u) => u.id == _unidadId);
    final categoriasActivas = _categorias
        .where(
          (categoria) => categoria.activo || categoria.id == _categoriaVentaId,
        )
        .toList();
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      title: Text(widget.insumo == null ? 'Nuevo insumo' : 'Editar insumo'),
      content: DialogSurface(
        maxWidth: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nombre,
                  decoration: appInput(label: 'Nombre del insumo'),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Ingresa un nombre'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _unidadId,
                  isExpanded: true,
                  decoration: appInput(label: 'Unidad de medida'),
                  items: widget.unidades
                      .map(
                        (unidad) => DropdownMenuItem(
                          value: unidad.id,
                          child: Text(
                            '${unidad.nombre} (${unidad.abreviatura})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _unidadId = value),
                  validator: (value) =>
                      value == null ? 'Selecciona una unidad' : null,
                ),
                const SizedBox(height: 6),
                Text(
                  'Registra el stock en la unidad elegida. Ej.: 30 botellas de '
                  '1 L se cargan como 30 L; en la receta puedes usar 250 ml.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Builder(
                  builder: (context) {
                    final angosto = esAngosto(
                      MediaQuery.sizeOf(context).width,
                      limite: 420,
                    );
                    final actual = TextFormField(
                      controller: _stockActual,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                      decoration: appInput(
                        label: 'Stock actual',
                        icon: Icons.inventory_2_outlined,
                      ),
                    );
                    final minimo = TextFormField(
                      controller: _stockMinimo,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                      decoration: appInput(
                        label: 'Stock mínimo',
                        icon: Icons.warning_amber_outlined,
                      ),
                    );
                    if (angosto) {
                      return Column(
                        children: [actual, const SizedBox(height: 12), minimo],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: actual),
                        const SizedBox(width: 12),
                        Expanded(child: minimo),
                      ],
                    );
                  },
                ),
                if (_advertenciaStock != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: scheme.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _advertenciaStock!,
                            style: TextStyle(color: scheme.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _costo,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: appInput(
                    label: 'Costo promedio (Bs)',
                    icon: Icons.price_check,
                  ),
                ),
                const Divider(height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Disponible para venta directa'),
                  subtitle: const Text(
                    'Se creará un producto en venta directa con receta de 1 unidad del insumo.',
                  ),
                  value: _ventaDirecta,
                  onChanged: (value) => setState(() => _ventaDirecta = value),
                ),
                if (_ventaDirecta) ...[
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: _precioVenta,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: appInput(
                      label: 'Precio de venta (Bs)',
                      icon: Icons.sell_outlined,
                    ),
                    validator: (value) {
                      if (!_ventaDirecta) return null;
                      return parseAmount(value ?? '') <= 0
                          ? 'Indica un precio mayor a 0'
                          : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int?>(
                          initialValue: _categoriaVentaId,
                          isExpanded: true,
                          decoration: appInput(label: 'Categoría en Productos'),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Venta directa (automática)'),
                            ),
                            ...categoriasActivas.map(
                              (categoria) => DropdownMenuItem<int?>(
                                value: categoria.id,
                                child: Text(
                                  categoria.nombre,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _categoriaVentaId = value),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _crearCategoria,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Nueva'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _fotoProducto(context),
                  const SizedBox(height: 8),
                  Text(
                    'Se venderá siempre, sin depender del menú del día. '
                    'La receta descuenta 1 ${unidad?.abreviatura ?? 'unidad'} '
                    'del insumo por cada venta.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Insumo activo'),
                  value: _activo,
                  onChanged: (value) => setState(() => _activo = value),
                ),
                if (_error != null)
                  Text(_error!, style: TextStyle(color: scheme.error)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Guardando…' : 'Guardar'),
        ),
      ],
    );
  }
}

class _NuevaCategoriaDialog extends StatefulWidget {
  const _NuevaCategoriaDialog();

  @override
  State<_NuevaCategoriaDialog> createState() => _NuevaCategoriaDialogState();
}

class _NuevaCategoriaDialogState extends State<_NuevaCategoriaDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      title: const Text('Nueva categoría'),
      content: DialogSurface(
        maxWidth: 380,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _controller,
            autofocus: true,
            decoration: appInput(
              label: 'Nombre',
              hint: 'Ej. Bebidas, Postres, Snacks',
            ),
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'Ingresa un nombre'
                : null,
            onFieldSubmitted: (_) {
              if (_formKey.currentState!.validate()) {
                Navigator.pop(context, _controller.text.trim());
              }
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, _controller.text.trim());
            }
          },
          child: const Text('Crear'),
        ),
      ],
    );
  }
}

class _StockDialog extends StatefulWidget {
  const _StockDialog({
    required this.titulo,
    required this.stockActual,
    required this.unidad,
  });

  final String titulo;
  final double stockActual;
  final String unidad;

  @override
  State<_StockDialog> createState() => _StockDialogState();
}

class _StockDialogState extends State<_StockDialog> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: formatQty(widget.stockActual));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      title: Text(widget.titulo),
      content: DialogSurface(
        maxWidth: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stock del sistema: ${formatQty(widget.stockActual)} ${widget.unidad}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: appInput(
                  label: 'Stock real',
                  icon: Icons.inventory_2_outlined,
                ),
                validator: (value) {
                  if (parseAmount(value ?? '') < 0) return 'Cantidad inválida';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, parseAmount(_controller.text));
            }
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
