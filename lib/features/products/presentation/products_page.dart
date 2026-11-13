import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/catalog_repository.dart';
import '../../../core/date_utils.dart';
import '../../../core/session.dart';
import '../../../ui/common.dart';

const _paleta = <int>[
  0xFF70452D, // Nogal
  0xFF3D2419, // Espresso
  0xFFC18A55, // Caramelo
  0xFFE8C995, // Dorado
  0xFF574537, // Texto
  0xFF2B1A12, // Texto oscuro
  0xFF70452D, // Nogal
  0xFFC18A55, // Caramelo
];

class _ProductsData {
  const _ProductsData({
    required this.productos,
    required this.categorias,
    required this.insumos,
    required this.unidades,
  });

  final List<Producto> productos;
  final List<CategoriaProducto> categorias;
  final List<Insumo> insumos;
  final List<UnidadMedida> unidades;
}

class ProductsPage extends StatefulWidget {
  const ProductsPage({
    super.key,
    required this.usuario,
    required this.refreshToken,
  });

  final Usuario usuario;
  final int refreshToken;

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final _repository = CatalogRepository();
  late Future<_ProductsData> _future;
  String _search = '';
  int? _categoriaId;
  bool _soloActivos = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(ProductsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _reload();
  }

  // Debe devolver void: si devolviera el Future, setState lanzaría error y la
  // pantalla no se refrescaría.
  void _reload() {
    _future = _load();
  }

  Future<_ProductsData> _load() async {
    final productos = await _repository.getProductos();
    final categorias = await _repository.getCategorias();
    final insumos = await _repository.getInsumos(soloActivos: true);
    final unidades = await _repository.getUnidades();
    return _ProductsData(
      productos: productos,
      categorias: categorias,
      insumos: insumos,
      unidades: unidades,
    );
  }

  Future<void> _openForm([Producto? producto]) async {
    final data = await _future;
    if (!mounted) return;
    final saved = await showDialog<int>(
      context: context,
      builder: (_) => _ProductDialog(
        repository: _repository,
        producto: producto,
        categorias: data.categorias,
        usuarioId: widget.usuario.id,
      ),
    );
    if (saved != null && mounted) {
      setState(_reload);
      showAppMessage(context, 'Producto guardado correctamente.');
    }
  }

  Future<void> _openRecipe(Producto producto) async {
    final data = await _future;
    final receta = await _repository.getReceta(producto.id!);
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RecipeDialog(
        repository: _repository,
        producto: producto,
        insumos: data.insumos,
        unidades: data.unidades,
        receta: receta,
      ),
    );
    if (saved == true && mounted) {
      setState(_reload);
      showAppMessage(context, 'Receta actualizada.');
    }
  }

  Future<void> _toggle(Producto producto, bool activo) async {
    await _repository.setProductoActivo(producto.id!, activo);
    if (!mounted) return;
    setState(_reload);
  }

  Set<int> _categoriaIdsIncluidos(List<CategoriaProducto> categorias) {
    return {_categoriaId!};
  }

  Future<void> _ajustarStock(Producto producto) async {
    final nuevo = await showDialog<double>(
      context: context,
      builder: (_) => _StockDialog(
        titulo: 'Ajustar stock de ${producto.nombre}',
        stockActual: producto.stock,
      ),
    );
    if (nuevo == null) return;
    try {
      await _repository.ajustarStockProducto(
        productoId: producto.id!,
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
    return FutureBuilder<_ProductsData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final productos = data?.productos ?? [];
        final categorias = data?.categorias ?? [];
        final categoriaIds = _categoriaId == null
            ? null
            : _categoriaIdsIncluidos(categorias);
        final filtrados = productos.where((producto) {
          if (_soloActivos && !producto.activo) return false;
          if (categoriaIds != null &&
              !categoriaIds.contains(producto.categoriaId)) {
            return false;
          }
          final term = _search.trim().toLowerCase();
          if (term.isEmpty) return true;
          return producto.nombre.toLowerCase().contains(term);
        }).toList();

        return SingleChildScrollView(
          padding: EdgeInsets.all(
            esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: 'Productos',
                subtitle: 'Platos y bebidas. La receta es opcional: si la configuras, descuenta insumos; si no, el producto se vende independiente. Los precios solo se cambian aquí y las categorías se crean desde esta misma pantalla.',
                actions: [
                  FilledButton.icon(
                    onPressed: snapshot.hasData ? () => _openForm() : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Nuevo producto'),
                  ),
                ],
              ),
              AppCard(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 280,
                      child: TextField(
                        decoration: appInput(
                          label: 'Buscar producto',
                          icon: Icons.search,
                        ),
                        onChanged: (value) => setState(() => _search = value),
                      ),
                    ),
                    SizedBox(
                      width: 230,
                      child: DropdownButtonFormField<int?>(
                        initialValue: _categoriaId,
                        isExpanded: true,
                        decoration: appInput(label: 'Categoría'),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Todas'),
                          ),
                          ...categorias.map(
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
                            setState(() => _categoriaId = value),
                      ),
                    ),
                    FilterChip(
                      label: const Text('Solo activos'),
                      selected: _soloActivos,
                      onSelected: (value) =>
                          setState(() => _soloActivos = value),
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
                  icon: Icons.lunch_dining_outlined,
                  title: 'No hay productos que coincidan',
                  message: 'Crea un producto o ajusta los filtros.',
                  action: FilledButton.icon(
                    onPressed: () => _openForm(),
                    icon: const Icon(Icons.add),
                    label: const Text('Nuevo producto'),
                  ),
                )
              else
                ...filtrados.map(
                  (producto) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ProductRow(
                      producto: producto,
                      onEdit: () => _openForm(producto),
                      onRecipe:
                          producto.esVentaDirecta || producto.esCompuesto
                          ? null
                          : () => _openRecipe(producto),
                      onAjustarStock: producto.esDirecto
                          ? () => _ajustarStock(producto)
                          : null,
                      onToggle: (value) => _toggle(producto, value),
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

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.producto,
    required this.onEdit,
    required this.onRecipe,
    required this.onAjustarStock,
    required this.onToggle,
  });

  final Producto producto;
  final VoidCallback onEdit;
  final VoidCallback? onRecipe;
  final VoidCallback? onAjustarStock;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icono = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Color(producto.categoriaColor).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        image: producto.imagen != null
            ? DecorationImage(
                image: MemoryImage(producto.imagen!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: producto.imagen == null
          ? Icon(
              producto.esDirecto
                  ? Icons.inventory_2_outlined
                  : Icons.restaurant,
              color: Color(producto.categoriaColor),
            )
          : null,
    );
    final etiqueta = producto.esVentaDirecta
        ? 'Venta directa'
        : producto.esCompuesto
        ? 'Almuerzo o combo armado'
        : producto.esDirecto
        ? 'Directo (legado)'
        : 'Preparado · receta opcional';
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              producto.nombre,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (producto.esVentaDirecta)
              Chip(
                label: const Text('Venta directa'),
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
                backgroundColor: scheme.primaryContainer,
                labelStyle: Theme.of(context).textTheme.labelSmall,
              ),
            if (producto.esCompuesto)
              Chip(
                label: const Text('Compuesto'),
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
                backgroundColor: scheme.tertiaryContainer,
                labelStyle: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${producto.categoriaNombre} · $etiqueta',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        if (producto.descripcion != null)
          Text(
            producto.descripcion!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
      ],
    );
    final precio = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatMoney(producto.precio),
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          producto.esDirecto
              ? 'Stock: ${formatQty(producto.stock)}'
              : producto.esVentaDirecta
              ? 'Receta fija: 1 unidad'
              : 'Receta opcional',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: producto.esDirecto && producto.stock <= producto.stockMinimo
                ? scheme.error
                : scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    final acciones = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (onRecipe != null)
          OutlinedButton.icon(
            onPressed: onRecipe,
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: const Text('Receta'),
          ),
        if (onAjustarStock != null)
          OutlinedButton.icon(
            onPressed: onAjustarStock,
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Ajustar stock'),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(value: producto.activo, onChanged: onToggle),
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
          if (!esAngosto(constraints.maxWidth, limite: 720)) {
            return Row(
              children: [
                icono,
                const SizedBox(width: 14),
                Expanded(flex: 3, child: info),
                Expanded(flex: 2, child: precio),
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
              precio,
              const SizedBox(height: 6),
              acciones,
            ],
          );
        },
      ),
    );
  }
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({
    required this.repository,
    required this.categorias,
    required this.usuarioId,
    this.producto,
  });

  final CatalogRepository repository;
  final List<CategoriaProducto> categorias;
  final int usuarioId;
  final Producto? producto;

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final TextEditingController _nombre;
  late final TextEditingController _descripcion;
  late final TextEditingController _precio;
  late final TextEditingController _stockMinimo;
  late final TextEditingController _stockActual;
  late final TextEditingController _costo;
  late List<CategoriaProducto> _categorias;
  late int? _categoriaId;
  late String _tipo;
  late bool _activo;
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
    final producto = widget.producto;
    _nombre = TextEditingController(text: producto?.nombre ?? '');
    _descripcion = TextEditingController(text: producto?.descripcion ?? '');
    _precio = TextEditingController(
      text: producto == null ? '' : producto.precio.toStringAsFixed(2),
    );
    _stockMinimo = TextEditingController(
      text: producto == null ? '0' : formatQty(producto.stockMinimo),
    );
    _stockActual = TextEditingController(
      text: producto == null ? '0' : formatQty(producto.stock),
    );
    _costo = TextEditingController(
      text: producto == null ? '0' : producto.costoUnitario.toStringAsFixed(2),
    );
    _categorias = List.of(widget.categorias);
    // Sin categoría por defecto: el usuario siempre elige la categoría.
    _categoriaId = producto?.categoriaId;
    _tipo = producto?.tipo ?? 'PREPARADO';
    _activo = producto?.activo ?? true;
    _imagen = producto?.imagen;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    _precio.dispose();
    _stockMinimo.dispose();
    _stockActual.dispose();
    _costo.dispose();
    super.dispose();
  }

  Future<void> _crearCategoria() async {
    final input = await showDialog<_NuevaCategoriaInput>(
      context: context,
      builder: (context) => const _NuevaCategoriaDialog(),
    );
    if (input == null || input.nombre.trim().isEmpty) return;
    try {
      final nombre = input.nombre.trim().toUpperCase();
      await widget.repository.saveCategoria(
        CategoriaProducto(
          nombre: nombre,
          color: _paleta[_categorias.length % _paleta.length],
          siempreDisponible: false,
          orden: _categorias.length,
          activo: true,
        ),
      );
      final categorias = await widget.repository.getCategorias();
      final creada = categorias.firstWhere(
        (categoria) => categoria.nombre.toUpperCase() == nombre,
      );
      if (!mounted) return;
      setState(() {
        _categorias = categorias;
        _categoriaId = creada.id;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo crear la categoría: $error');
    }
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoriaId == null) {
      setState(() => _error = 'Crea o selecciona una categoría.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final categoria = _categorias.firstWhere(
        (item) => item.id == _categoriaId,
      );
      final id = await widget.repository.saveProducto(
        Producto(
          id: widget.producto?.id,
          nombre: _nombre.text,
          categoriaId: _categoriaId!,
          categoriaNombre: categoria.nombre,
          categoriaColor: categoria.color,
          descripcion: _descripcion.text,
          precio: parseAmount(_precio.text),
          tipo: _tipo,
          esCompuesto: widget.producto?.esCompuesto ?? false,
          imagen: _imagen,
          stockMinimo: _tipo == 'DIRECTO' ? parseAmount(_stockMinimo.text) : 0,
          costoUnitario: _tipo == 'DIRECTO' ? parseAmount(_costo.text) : 0,
          activo: _activo,
          stock: widget.producto?.stock ?? 0,
        ),
      );
      if (_tipo == 'DIRECTO') {
        await widget.repository.ajustarStockProducto(
          productoId: id,
          nuevoStock: parseAmount(_stockActual.text),
          usuarioId: widget.usuarioId,
          motivo: 'Carga inicial',
        );
      }
      if (!mounted) return;
      Navigator.pop(context, id);
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
    final directo = _tipo == 'DIRECTO';
    final angosto = esAngosto(MediaQuery.sizeOf(context).width, limite: 430);
    final vistaPrevia = Container(
      height: 130,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9F0), // Blanco cálido
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: _imagen == null
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.image_outlined,
                  size: 30,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 6),
                Text(
                  'Sin imagen',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            )
          : Image.memory(_imagen!, fit: BoxFit.cover, gaplessPlayback: true),
    );
    final botonesImagen = Wrap(
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
    );
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      title: Text(
        widget.producto == null ? 'Nuevo producto' : 'Editar producto',
      ),
      content: DialogSurface(
        maxWidth: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nombre,
                  decoration: appInput(label: 'Nombre del producto'),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Ingresa un nombre'
                      : null,
                ),
                const SizedBox(height: 12),
                if (angosto)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      vistaPrevia,
                      const SizedBox(height: 8),
                      botonesImagen,
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: vistaPrevia),
                      const SizedBox(width: 12),
                      botonesImagen,
                    ],
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: ValueKey(_categorias.length),
                        initialValue: _categoriaId,
                        isExpanded: true,
                        decoration: appInput(label: 'Categoría'),
                        items: _categorias
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
                        onChanged: (value) =>
                            setState(() => _categoriaId = value),
                        validator: (value) =>
                            value == null ? 'Selecciona una categoría' : null,
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
                if (directo)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiaryContainer
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Producto directo heredado. Se mantiene con stock propio; '
                      'los productos nuevos usan receta de insumos.',
                    ),
                  ),
                if (directo) const SizedBox(height: 12),
                TextFormField(
                  controller: _descripcion,
                  maxLines: 2,
                  decoration: appInput(label: 'Descripción (opcional)'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _precio,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: appInput(
                          label: 'Precio de venta (Bs)',
                          icon: Icons.sell_outlined,
                        ),
                        validator: (value) {
                          if (parseAmount(value ?? '') < 0) {
                            return 'Precio inválido';
                          }
                          return null;
                        },
                      ),
                    ),
                    if (directo) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _stockMinimo,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: appInput(
                            label: 'Stock mínimo',
                            icon: Icons.warning_amber_outlined,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (directo) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _stockActual,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: appInput(
                            label: 'Stock actual',
                            icon: Icons.inventory_2_outlined,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _costo,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: appInput(
                            label: 'Costo unitario (Bs)',
                            icon: Icons.price_check,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Producto activo'),
                  subtitle: Text(
                    directo
                        ? 'Los productos inactivos no se venden ni aparecen en el menú.'
                        : 'La receta es opcional: configúrala desde la lista de productos y sirve para descontar insumos automáticamente.',
                  ),
                  value: _activo,
                  onChanged: (value) => setState(() => _activo = value),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
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

class _NuevaCategoriaInput {
  const _NuevaCategoriaInput({required this.nombre});

  final String nombre;
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

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _NuevaCategoriaInput(nombre: _controller.text.trim().toUpperCase()),
    );
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: appInput(
                  label: 'Nombre',
                  hint: 'Ej. SOPAS, REFRESCOS, POSTRES',
                ),
                onChanged: (value) {
                  final upper = value.toUpperCase();
                  if (upper == value) return;
                  _controller.value = TextEditingValue(
                    text: upper,
                    selection: TextSelection.collapsed(offset: upper.length),
                  );
                },
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Ingresa un nombre'
                    : null,
                onFieldSubmitted: (_) => _guardar(),
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
        FilledButton(onPressed: _guardar, child: const Text('Crear')),
      ],
    );
  }
}

class _StockDialog extends StatefulWidget {
  const _StockDialog({required this.titulo, required this.stockActual});

  final String titulo;
  final double stockActual;

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
                'Stock del sistema: ${formatQty(widget.stockActual)}',
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

class _RecipeDialog extends StatefulWidget {
  const _RecipeDialog({
    required this.repository,
    required this.producto,
    required this.insumos,
    required this.unidades,
    required this.receta,
  });

  final CatalogRepository repository;
  final Producto producto;
  final List<Insumo> insumos;
  final List<UnidadMedida> unidades;
  final List<RecetaLinea> receta;

  @override
  State<_RecipeDialog> createState() => _RecipeDialogState();
}

class _RecipeDialogState extends State<_RecipeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _cantidades = <int, TextEditingController>{};
  final _unidadesElegidas = <int, int>{};
  final _seleccionados = <int>{};
  String _search = '';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final insumo in widget.insumos) {
      _cantidades[insumo.id!] = TextEditingController();
      _unidadesElegidas[insumo.id!] = insumo.unidadId;
    }
    for (final linea in widget.receta) {
      if (!_cantidades.containsKey(linea.insumoId)) continue;
      _seleccionados.add(linea.insumoId);
      _cantidades[linea.insumoId]?.text = formatQty(linea.cantidad);
    }
  }

  @override
  void dispose() {
    for (final controller in _cantidades.values) {
      controller.dispose();
    }
    super.dispose();
  }

  UnidadMedida _unidadBase(Insumo insumo) {
    for (final unidad in widget.unidades) {
      if (unidad.id == insumo.unidadId) return unidad;
    }
    return UnidadMedida(
      id: insumo.unidadId,
      nombre: insumo.unidadNombre,
      abreviatura: insumo.unidadAbreviatura,
      familia: insumo.unidadFamilia,
      factorBase: insumo.unidadFactorBase,
    );
  }

  UnidadMedida _unidadElegida(Insumo insumo) {
    final id = _unidadesElegidas[insumo.id] ?? insumo.unidadId;
    for (final unidad in widget.unidades) {
      if (unidad.id == id) return unidad;
    }
    return _unidadBase(insumo);
  }

  List<UnidadMedida> _unidadesCompatibles(Insumo insumo) {
    final base = _unidadBase(insumo);
    if (!base.esConvertible) return [base];
    final lista =
        widget.unidades
            .where((unidad) => unidad.familia == base.familia)
            .toList()
          ..sort((a, b) => b.factorBase.compareTo(a.factorBase));
    return lista.isEmpty ? [base] : lista;
  }

  double _cantidadEnBase(Insumo insumo) {
    final elegida = _unidadElegida(insumo);
    final base = _unidadBase(insumo);
    final ingresada = parseAmount(_cantidades[insumo.id]?.text ?? '');
    return ingresada * elegida.factorBase / base.factorBase;
  }

  /// Texto de equivalencia en la unidad base del insumo.
  String _equivalencia(Insumo insumo) {
    final elegida = _unidadElegida(insumo);
    final base = _unidadBase(insumo);
    final enBase = _cantidadEnBase(insumo);
    if (enBase <= 0) return '';
    if (elegida.id != base.id) {
      return '= ${formatQty(enBase)} ${base.abreviatura}';
    }
    if (!base.esConvertible) return '';
    final compatible = _unidadesCompatibles(insumo)
        .where((unidad) => unidad.id != base.id)
        .toList();
    if (compatible.isEmpty) return '';
    final chica = compatible.last;
    final enChica = enBase * base.factorBase / chica.factorBase;
    return '= ${formatQty(enChica)} ${chica.abreviatura}';
  }

  void _aplicarRapido(Insumo insumo, String texto) {
    final elegida = _unidadElegida(insumo);
    final base = _unidadBase(insumo);
    final cantidadBase = parseAmount(texto);
    final enElegida = cantidadBase * base.factorBase / elegida.factorBase;
    setState(() {
      _seleccionados.add(insumo.id!);
      _cantidades[insumo.id]!.text = formatQty(enElegida);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveRecetaCantidades(widget.producto.id!, {
        for (final id in _seleccionados)
          id: _cantidadEnBase(
            widget.insumos.firstWhere((insumo) => insumo.id == id),
          ),
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo guardar la receta: $error';
        _saving = false;
      });
    }
  }

  Widget _filaInsumo(Insumo insumo) {
    final id = insumo.id!;
    final seleccionado = _seleccionados.contains(id);
    final elegida = _unidadElegida(insumo);
    final compatibles = _unidadesCompatibles(insumo);
    final equivalencia = _equivalencia(insumo);
    final enBase = _cantidadEnBase(insumo);
    final alcanza = enBase > 0 ? (insumo.stock / enBase).floor() : null;
    final costo = enBase * insumo.costoPromedio;
    final scheme = Theme.of(context).colorScheme;
    final angosto = esAngosto(MediaQuery.sizeOf(context).width, limite: 430);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: seleccionado
              ? scheme.primary.withValues(alpha: 0.5)
              : scheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: seleccionado,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _seleccionados.add(id);
                    } else {
                      _seleccionados.remove(id);
                    }
                  });
                },
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      insumo.nombre,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'stock ${formatQty(insumo.stock)} ${insumo.unidadAbreviatura}',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (seleccionado && equivalencia.isNotEmpty)
                      Text(
                        equivalencia,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (seleccionado) ...[
            const SizedBox(height: 6),
            Builder(
              builder: (context) {
                final campo = TextFormField(
                  controller: _cantidades[id],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: appInput(
                    label: 'Cantidad por 1 vendido',
                    hint: '0',
                    suffixText: elegida.abreviatura,
                  ),
                  validator: (value) {
                    if (!_seleccionados.contains(id)) return null;
                    return parseAmount(value ?? '') <= 0 ? 'Mayor a 0' : null;
                  },
                );
                final selector = compatibles.length <= 1
                    ? null
                    : DropdownButtonFormField<int>(
                        initialValue: elegida.id,
                        isExpanded: true,
                        decoration: appInput(label: 'Unidad'),
                        items: compatibles
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
                        onChanged: (nuevoId) {
                          if (nuevoId == null) return;
                          final anterior = _unidadElegida(insumo);
                          final nueva = compatibles.firstWhere(
                            (unidad) => unidad.id == nuevoId,
                          );
                          final actual = parseAmount(_cantidades[id]!.text);
                          if (actual > 0) {
                            _cantidades[id]!.text = formatQty(
                              actual * anterior.factorBase / nueva.factorBase,
                            );
                          }
                          setState(() => _unidadesElegidas[id] = nuevoId);
                        },
                      );
                if (angosto) {
                  return Column(
                    children: [
                      campo,
                      if (selector != null) ...[
                        const SizedBox(height: 8),
                        selector,
                      ],
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(flex: 2, child: campo),
                    if (selector != null) ...[
                      const SizedBox(width: 8),
                      Expanded(flex: 2, child: selector),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final rapido in const ['1/4', '1/2', '1', '2'])
                  ActionChip(
                    label: Text(rapido),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _aplicarRapido(insumo, rapido),
                  ),
                if (alcanza != null)
                  Text(
                    'Alcanza para $alcanza porción(es)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: alcanza > 0
                          ? scheme.onSurfaceVariant
                          : scheme.error,
                    ),
                  ),
                if (costo > 0)
                  Text(
                    'Costo ${formatMoney(costo)}',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final term = _search.trim().toLowerCase();
    final filtrados = widget.insumos
        .where(
          (insumo) =>
              term.isEmpty || insumo.nombre.toLowerCase().contains(term),
        )
        .toList();
    final costoTotal = _seleccionados.fold<double>(0, (suma, id) {
      final insumo = widget.insumos.firstWhere((item) => item.id == id);
      return suma + _cantidadEnBase(insumo) * insumo.costoPromedio;
    });

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      title: Text('Receta · ${widget.producto.nombre}'),
      content: DialogSurface(
        maxWidth: 620,
        maxHeightFactor: 0.85,
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Text(
                'Indica cuánto de cada insumo consume una porción vendida. '
                'Puedes usar la unidad del insumo o una equivalente (por ejemplo 250 ml de leche). '
                'Es opcional: si no eliges insumos, el producto no descuenta stock.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: appInput(
                  label: 'Buscar insumo',
                  icon: Icons.search,
                ),
                onChanged: (value) => setState(() => _search = value),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: widget.insumos.isEmpty
                    ? const EmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: 'No hay insumos activos',
                        message: 'Crea insumos en la sección Insumos para poder armar la receta.',
                      )
                    : filtrados.isEmpty
                    ? const EmptyState(
                        icon: Icons.search_off,
                        title: 'Sin resultados',
                        message:
                            'No hay insumos que coincidan con la búsqueda.',
                      )
                    : ListView.separated(
                        itemCount: filtrados.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _filaInsumo(filtrados[index]),
                      ),
              ),
              if (costoTotal > 0) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Costo estimado de la receta: ${formatMoney(costoTotal)}',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
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
          child: Text(_saving ? 'Guardando…' : 'Guardar receta'),
        ),
      ],
    );
  }
}
