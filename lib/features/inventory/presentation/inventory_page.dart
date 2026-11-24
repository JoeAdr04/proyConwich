import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/catalog_repository.dart';
import '../../../core/compras_repository.dart';
import '../../../core/date_utils.dart';
import '../../../core/session.dart';
import '../../../ui/categoria_editor.dart';
import '../../../ui/common.dart';

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
  final _compras = ComprasRepository();
  late Future<_InsumosData> _future;
  String _search = '';
  bool _soloActivos = false;
  bool _soloAlertas = false;
  bool _soloNoConsumibles = false;

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

  Future<void> _registrarCompra() async {
    final data = await _future;
    if (!mounted) return;
    final resultado = await showDialog<_CompraResultado>(
      context: context,
      builder: (_) => _RegistrarCompraDialog(
        unidades: data.unidades,
        categorias: data.categorias,
      ),
    );
    if (resultado == null || !mounted) return;
    try {
      // Buscar insumo existente por nombre o crear uno nuevo.
      final existente = await _repository.getInsumoByNombre(resultado.nombre);
      final int insumoId;
      if (existente != null) {
        insumoId = existente.id!;
      } else {
        final und = data.unidades.firstWhere(
          (u) => u.id == resultado.unidadId,
          orElse: () => data.unidades.first,
        );
        insumoId = await _repository.saveInsumo(
          Insumo(
            nombre: resultado.nombre,
            unidadId: und.id,
            unidadAbreviatura: und.abreviatura,
            stockMinimo: 0,
            costoPromedio: resultado.costoUnitario,
            activo: true,
            stock: 0,
          ),
        );
      }
      await _compras.registrarCompraInsumo(
        insumoId: insumoId,
        cantidad: resultado.cantidad,
        costoUnitario: resultado.costoUnitario,
        usuarioId: widget.usuario.id,
      );
      if (!mounted) return;
      setState(_reload);
      if (resultado.loVendeDirecto) {
        final insumo = await _repository.getInsumo(insumoId);
        if (insumo != null && mounted) {
          await _crearProductoDesdeCompra(insumo, data);
        }
      } else {
        showAppMessage(context, 'Compra registrada: ${resultado.nombre}.');
      }
    } catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        'No se pudo registrar la compra: $error',
        error: true,
      );
    }
  }

  Future<void> _crearProductoDesdeCompra(
    Insumo insumo,
    _InsumosData data,
  ) async {
    final resultado = await showDialog<_ProductoDesdeCompra>(
      context: context,
      builder: (_) => _CrearProductoDesdeCompraDialog(
        insumo: insumo,
        categorias: data.categorias,
      ),
    );
    if (resultado == null || !mounted) return;
    try {
      await _repository.saveInsumo(
        Insumo(
          id: insumo.id,
          nombre: insumo.nombre,
          unidadId: insumo.unidadId,
          unidadAbreviatura: insumo.unidadAbreviatura,
          stockMinimo: insumo.stockMinimo,
          costoPromedio: insumo.costoPromedio,
          activo: resultado.activo,
          stock: insumo.stock,
          ventaDirecta: true,
          precioVenta: resultado.precioVenta,
          productoId: insumo.productoId,
          categoriaVentaDirectaId: resultado.categoriaId,
          imagen: resultado.imagen,
          consumible: insumo.consumible,
        ),
      );
      if (!mounted) return;
      setState(_reload);
      showAppMessage(
        context,
        'Producto "${insumo.nombre}" creado correctamente.',
      );
    } catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        'No se pudo crear el producto: $error',
        error: true,
      );
    }
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

  Future<void> _agregarCantidad(Insumo insumo) async {
    final resultado = await showDialog<_CompraInput>(
      context: context,
      builder: (_) => _AgregarCantidadDialog(insumo: insumo),
    );
    if (resultado == null) return;
    try {
      await _compras.registrarCompraInsumo(
        insumoId: insumo.id!,
        cantidad: resultado.cantidad,
        costoUnitario: resultado.costo,
        usuarioId: widget.usuario.id,
      );
      if (!mounted) return;
      setState(_reload);
      showAppMessage(context, 'Se agregó cantidad a ${insumo.nombre}.');
    } catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        'No se pudo registrar la compra: $error',
        error: true,
      );
    }
  }

  Future<void> _registrarPerdida(Insumo insumo) async {
    final resultado = await showDialog<_PerdidaInput>(
      context: context,
      builder: (_) => _RegistrarPerdidaDialog(insumo: insumo),
    );
    if (resultado == null) return;
    try {
      await _compras.registrarPerdida(
        insumoId: insumo.id!,
        cantidad: resultado.cantidad,
        usuarioId: widget.usuario.id,
        motivo: resultado.motivo,
      );
      if (!mounted) return;
      setState(_reload);
      showAppMessage(context, 'Pérdida registrada de ${insumo.nombre}.');
    } catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        'No se pudo registrar la pérdida: $error',
        error: true,
      );
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
          if (_soloNoConsumibles && insumo.consumible) return false;
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
                title: 'Compras de insumos',
                subtitle: 'Registra lo que compras para llevar el control de stock y costos.',
                actions: [
                  FilledButton.icon(
                    onPressed: snapshot.hasData ? _registrarCompra : null,
                    icon: const Icon(Icons.shopping_cart_outlined),
                    label: const Text('Registrar compra'),
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
                    FilterChip(
                      label: const Text('No consumibles'),
                      selected: _soloNoConsumibles,
                      onSelected: (value) =>
                          setState(() => _soloNoConsumibles = value),
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
                      ? 'Registra tu primera compra para controlar el inventario.'
                      : 'Ajusta la búsqueda o los filtros.',
                  action: insumos.isEmpty
                      ? FilledButton.icon(
                          onPressed: _registrarCompra,
                          icon: const Icon(Icons.shopping_cart_outlined),
                          label: const Text('Registrar compra'),
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
                      onAgregarCantidad: () => _agregarCantidad(insumo),
                      onRegistrarPerdida: () => _registrarPerdida(insumo),
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
    required this.onAgregarCantidad,
    required this.onRegistrarPerdida,
    required this.onToggleActivo,
  });

  final Insumo insumo;
  final VoidCallback onEdit;
  final VoidCallback onAjustarStock;
  final VoidCallback onAgregarCantidad;
  final VoidCallback onRegistrarPerdida;
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
            if (!insumo.consumible)
              Chip(
                label: const Text('No consumible'),
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
                backgroundColor: scheme.tertiaryContainer,
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
          'Stock: ${formatQty(insumo.stock)} ${insumo.unidadAbreviatura}',
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
          onPressed: onAgregarCantidad,
          icon: const Icon(Icons.add_circle_outline, size: 18),
          label: const Text('Agregar cantidad'),
        ),
        OutlinedButton.icon(
          onPressed: onRegistrarPerdida,
          icon: const Icon(Icons.remove_circle_outline, size: 18),
          label: const Text('Registrar pérdida'),
        ),
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
  late final TextEditingController _costo;
  late final TextEditingController _precioVenta;
  late List<CategoriaProducto> _categorias;
  late int? _unidadId;
  late int? _categoriaVentaId;
  late bool _activo;
  late bool _ventaDirecta;
  late bool _consumible;
  Uint8List? _imagen;
  bool _saving = false;
  String? _error;

  bool get _hayCamara {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();
    final insumo = widget.insumo;
    _categorias = List.of(widget.categorias);
    _nombre = TextEditingController(text: insumo?.nombre ?? '');
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
    _consumible = insumo?.consumible ?? true;
    _imagen = insumo?.imagen;
  }

  @override
  void dispose() {
    _nombre.dispose();
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
    final id = await showCategoriaEditor(
      context: context,
      repository: widget.repository,
      categorias: _categorias,
    );
    if (id == null || !mounted) return;
    final categorias = await widget.repository.getCategorias();
    if (!mounted) return;
    setState(() {
      _categorias = categorias;
      _categoriaVentaId = id;
      _error = null;
    });
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
      await widget.repository.saveInsumo(
        Insumo(
          id: widget.insumo?.id,
          nombre: _nombre.text,
          unidadId: _unidadId!,
          unidadAbreviatura: unidad.abreviatura,
          unidadNombre: unidad.nombre,
          unidadFamilia: unidad.familia,
          unidadFactorBase: unidad.factorBase,
          stockMinimo: 0,
          costoPromedio: parseAmount(_costo.text),
          activo: _activo,
          stock: widget.insumo?.stock ?? 0,
          ventaDirecta: _ventaDirecta,
          precioVenta: _ventaDirecta ? precio : 0,
          productoId: widget.insumo?.productoId,
          categoriaVentaDirectaId: _categoriaVentaId,
          imagen: _imagen,
          consumible: _consumible,
        ),
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
                const SizedBox(height: 12),
                TextFormField(
                  controller: _costo,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: appInput(
                    label: 'Costo (Bs)',
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
                  title: const Text('No consumible (activo fijo)'),
                  subtitle: const Text(
                    'Cucharas, platos, vasos y otros que no se descuentan con '
                    'recetas. Se controlan igual pero en su propia lista.',
                  ),
                  value: !_consumible,
                  onChanged: (value) => setState(() => _consumible = !value),
                ),
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

class _CompraInput {
  const _CompraInput({required this.cantidad, required this.costo});

  final double cantidad;
  final double costo;
}

class _AgregarCantidadDialog extends StatefulWidget {
  const _AgregarCantidadDialog({required this.insumo});

  final Insumo insumo;

  @override
  State<_AgregarCantidadDialog> createState() => _AgregarCantidadDialogState();
}

class _AgregarCantidadDialogState extends State<_AgregarCantidadDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _cantidad;
  late final TextEditingController _costo;

  @override
  void initState() {
    super.initState();
    _cantidad = TextEditingController();
    _costo = TextEditingController(
      text: widget.insumo.costoPromedio.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _cantidad.dispose();
    _costo.dispose();
    super.dispose();
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _CompraInput(
        cantidad: parseAmount(_cantidad.text),
        costo: parseAmount(_costo.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final insumo = widget.insumo;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      title: Text('Agregar cantidad · ${insumo.nombre}'),
      content: DialogSurface(
        maxWidth: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Unidad ${insumo.unidadAbreviatura} · stock actual '
                '${formatQty(insumo.stock)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cantidad,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [decimalAmountInputFormatter],
                decoration: appInput(
                  label: 'Cantidad a agregar',
                  icon: Icons.add_circle_outline,
                ),
                validator: (value) => validateDecimalAmount(
                  value,
                  allowZero: false,
                  label: 'La cantidad',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _costo,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [decimalAmountInputFormatter],
                decoration: appInput(
                  label: 'Costo de esta compra (Bs)',
                  hint: 'Vacío = mantener costo promedio',
                  icon: Icons.price_check,
                ),
                validator: (value) {
                  final texto = (value ?? '').trim();
                  if (texto.isEmpty) return null;
                  if (parseAmount(texto) < 0) {
                    return 'El costo no puede ser negativo.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Si el costo cambia, se recalcula el costo promedio ponderado.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
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
        FilledButton(onPressed: _guardar, child: const Text('Agregar')),
      ],
    );
  }
}

class _PerdidaInput {
  const _PerdidaInput({required this.cantidad, this.motivo});

  final double cantidad;
  final String? motivo;
}

class _RegistrarPerdidaDialog extends StatefulWidget {
  const _RegistrarPerdidaDialog({required this.insumo});

  final Insumo insumo;

  @override
  State<_RegistrarPerdidaDialog> createState() =>
      _RegistrarPerdidaDialogState();
}

class _RegistrarPerdidaDialogState extends State<_RegistrarPerdidaDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _cantidad;
  late final TextEditingController _motivo;

  @override
  void initState() {
    super.initState();
    _cantidad = TextEditingController();
    _motivo = TextEditingController();
  }

  @override
  void dispose() {
    _cantidad.dispose();
    _motivo.dispose();
    super.dispose();
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _PerdidaInput(
        cantidad: parseAmount(_cantidad.text),
        motivo: _motivo.text.trim().isEmpty ? null : _motivo.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final insumo = widget.insumo;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      title: Text('Registrar pérdida · ${insumo.nombre}'),
      content: DialogSurface(
        maxWidth: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Unidad ${insumo.unidadAbreviatura} · stock actual '
                '${formatQty(insumo.stock)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cantidad,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [decimalAmountInputFormatter],
                decoration: appInput(
                  label: 'Cantidad perdida',
                  icon: Icons.remove_circle_outline,
                ),
                validator: (value) => validateDecimalAmount(
                  value,
                  allowZero: false,
                  label: 'La cantidad',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _motivo,
                decoration: appInput(
                  label: 'Motivo (opcional)',
                  hint: 'Ej. se echó a perder, rotura',
                  icon: Icons.notes,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Solo baja el stock; no cambia precios ni el costo promedio.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
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
        FilledButton(onPressed: _guardar, child: const Text('Registrar')),
      ],
    );
  }
}

// --- Nuevos diálogos de compra rápida ---

class _CompraResultado {
  const _CompraResultado({
    required this.nombre,
    required this.cantidad,
    required this.costoUnitario,
    required this.unidadId,
    this.loVendeDirecto = false,
  });

  final String nombre;
  final double cantidad;
  final double costoUnitario;
  final int unidadId;
  final bool loVendeDirecto;
}

class _RegistrarCompraDialog extends StatefulWidget {
  const _RegistrarCompraDialog({
    required this.unidades,
    required this.categorias,
  });

  final List<UnidadMedida> unidades;
  final List<CategoriaProducto> categorias;

  @override
  State<_RegistrarCompraDialog> createState() => _RegistrarCompraDialogState();
}

class _RegistrarCompraDialogState extends State<_RegistrarCompraDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _cantidad = TextEditingController();
  final _costoTotal = TextEditingController();
  int? _unidadId;
  bool _loVendeDirecto = false;

  @override
  void initState() {
    super.initState();
    _unidadId = widget.unidades.isNotEmpty ? widget.unidades.first.id : null;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _cantidad.dispose();
    _costoTotal.dispose();
    super.dispose();
  }

  double get _costoUnitario {
    final cantidad = parseAmount(_cantidad.text);
    final costo = parseAmount(_costoTotal.text);
    if (cantidad <= 0) return 0;
    return costo / cantidad;
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _CompraResultado(
        nombre: _nombre.text.trim(),
        cantidad: parseAmount(_cantidad.text),
        costoUnitario: _costoUnitario,
        unidadId: _unidadId!,
        loVendeDirecto: _loVendeDirecto,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      title: const Text('Registrar compra'),
      content: DialogSurface(
        maxWidth: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nombre,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: appInput(
                    label: '¿Qué compraste?',
                    hint: 'Ej. Carne, Leche, Coca-Cola',
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Escribe qué compraste'
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _cantidad,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [decimalAmountInputFormatter],
                        decoration: appInput(label: '¿Cuánto?'),
                        validator: (value) => validateDecimalAmount(
                          value,
                          allowZero: false,
                          label: 'La cantidad',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<int>(
                        initialValue: _unidadId,
                        decoration: appInput(label: 'Unidad'),
                        items: widget.unidades
                            .map(
                              (u) => DropdownMenuItem(
                                value: u.id,
                                child: Text(u.abreviatura),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() => _unidadId = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _costoTotal,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [decimalAmountInputFormatter],
                  decoration: appInput(
                    label: '¿Cuánto costó? (Bs total)',
                    icon: Icons.payments_outlined,
                  ),
                  validator: (value) => validateDecimalAmount(
                    value,
                    allowZero: false,
                    label: 'El costo',
                  ),
                ),
                if (_costoUnitario > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Costo unitario: ${formatMoney(_costoUnitario)} / '
                    '${widget.unidades.firstWhere((u) => u.id == _unidadId, orElse: () => widget.unidades.first).abreviatura}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('¿Lo vendes directo?'),
                  subtitle: const Text(
                    'Se creará un producto en el catálogo para venderlo.',
                  ),
                  value: _loVendeDirecto,
                  onChanged: (value) => setState(() => _loVendeDirecto = value),
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
        FilledButton(onPressed: _guardar, child: const Text('Registrar')),
      ],
    );
  }
}

class _ProductoDesdeCompra {
  const _ProductoDesdeCompra({
    required this.categoriaId,
    required this.categoriaNombre,
    required this.categoriaColor,
    required this.precioVenta,
    this.imagen,
    this.activo = true,
  });

  final int categoriaId;
  final String categoriaNombre;
  final int categoriaColor;
  final double precioVenta;
  final Uint8List? imagen;
  final bool activo;
}

class _CrearProductoDesdeCompraDialog extends StatefulWidget {
  const _CrearProductoDesdeCompraDialog({
    required this.insumo,
    required this.categorias,
  });

  final Insumo insumo;
  final List<CategoriaProducto> categorias;

  @override
  State<_CrearProductoDesdeCompraDialog> createState() =>
      _CrearProductoDesdeCompraDialogState();
}

class _CrearProductoDesdeCompraDialogState
    extends State<_CrearProductoDesdeCompraDialog> {
  final _formKey = GlobalKey<FormState>();
  final _precio = TextEditingController();
  int? _categoriaId;
  Uint8List? _imagen;
  bool _activo = true;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _imagen = widget.insumo.imagen;
  }

  @override
  void dispose() {
    _precio.dispose();
    super.dispose();
  }

  Future<void> _cargarImagen() async {
    try {
      final archivo = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );
      if (archivo == null) return;
      final bytes = await archivo.readAsBytes();
      if (mounted) setState(() => _imagen = bytes);
    } catch (error) {
      if (mounted) {
        showAppMessage(
          context,
          'No se pudo cargar la imagen: $error',
          error: true,
        );
      }
    }
  }

  void _crear() {
    if (!_formKey.currentState!.validate()) return;
    if (_categoriaId == null) {
      showAppMessage(context, 'Elige una categoría.', error: true);
      return;
    }
    final cat = widget.categorias.firstWhere((c) => c.id == _categoriaId);
    Navigator.pop(
      context,
      _ProductoDesdeCompra(
        categoriaId: _categoriaId!,
        categoriaNombre: cat.nombre,
        categoriaColor: cat.color,
        precioVenta: parseAmount(_precio.text),
        imagen: _imagen,
        activo: _activo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      title: Text('Crear producto desde "${widget.insumo.nombre}"'),
      content: DialogSurface(
        maxWidth: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_imagen != null)
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _imagen!,
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Center(
                  child: OutlinedButton.icon(
                    onPressed: _cargarImagen,
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: Text(
                      _imagen == null
                          ? 'Subir foto (opcional)'
                          : 'Cambiar foto',
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '¿En qué categoría lo vendes?',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: _categoriaId,
                  isExpanded: true,
                  decoration: appInput(
                    label: 'Categoría',
                    hint: 'Elige una categoría',
                  ),
                  items: widget.categorias
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.nombre),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _categoriaId = value),
                  validator: (value) =>
                      value == null ? 'Elige una categoría' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _precio,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [decimalAmountInputFormatter],
                  decoration: appInput(
                    label: 'Precio de venta (Bs)',
                    icon: Icons.sell_outlined,
                  ),
                  validator: (value) => validateDecimalAmount(
                    value,
                    allowZero: false,
                    label: 'El precio de venta',
                  ),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Producto activo'),
                  subtitle: const Text(
                    'Si está activo se puede vender de inmediato.',
                  ),
                  value: _activo,
                  onChanged: (value) => setState(() => _activo = value),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nombre: ${widget.insumo.nombre}',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
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
        FilledButton(onPressed: _crear, child: const Text('Crear producto')),
      ],
    );
  }
}
