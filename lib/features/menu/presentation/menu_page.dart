import 'package:flutter/material.dart';

import '../../../core/cash_repository.dart';
import '../../../core/catalog_repository.dart';
import '../../../core/date_utils.dart';
import '../../../core/menu_repository.dart';
import '../../../core/session.dart';
import '../../../ui/common.dart';
import '../../../ui/producto_catalogo_card.dart';

class _MenuData {
  const _MenuData({
    required this.menu,
    required this.items,
    required this.combos,
    required this.productos,
    required this.categorias,
    required this.cajaAbierta,
  });

  final MenuDia? menu;
  final List<MenuItem> items;
  final List<MenuCombo> combos;
  final List<Producto> productos;
  final List<CategoriaProducto> categorias;
  final bool cajaAbierta;
}

class MenuPage extends StatefulWidget {
  const MenuPage({
    super.key,
    required this.usuario,
    required this.refreshToken,
    this.onAbrirCaja,
    this.flujoInicioActivo = false,
    this.onFinalizarAtajo,
  });

  final Usuario usuario;
  final int refreshToken;

  /// Atajo hacia la pantalla de Caja (flujo "Empezar el día").
  final VoidCallback? onAbrirCaja;

  /// Solo cuando el usuario llegó con el botón "Empezar el día" del tablero.
  final bool flujoInicioActivo;
  final VoidCallback? onFinalizarAtajo;

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  final _repository = MenuRepository();
  final _catalog = CatalogRepository();
  final _cash = CashRepository();
  late DateTime _fecha;
  late String _tipo;
  late Future<_MenuData> _future;
  String _search = '';
  int? _categoriaId;
  bool _editando = false;
  bool _guardando = false;

  bool get _esAdmin => widget.usuario.puede(Permiso.menu);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fecha = DateTime(now.year, now.month, now.day);
    _tipo = MenuRepository.tipoMenu;
    _reload();
  }

  @override
  void didUpdateWidget(MenuPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _reload();
  }

  // Debe devolver void: si devolviera el Future, setState lanzaría error y la
  // pantalla no se refrescaría.
  void _reload() {
    _future = _load();
  }

  Future<_MenuData> _load() async {
    var menu = await _repository.getMenu(_fecha, _tipo);
    final hoy = DateTime.now();
    final inicioHoy = DateTime(hoy.year, hoy.month, hoy.day);
    final esFuturoOHoy = !_fecha.isBefore(inicioHoy);
    if (menu == null && esFuturoOHoy) {
      try {
        menu = await _repository.duplicarAnterior(
          _fecha,
          _tipo,
          widget.usuario.id,
        );
      } catch (_) {
        // Si no se puede copiar el menú anterior, la pantalla sigue vacía.
      }
    }
    // El menú ya no se cierra; si viene cerrado de una versión anterior se
    // vuelve a publicar para conservar la venta del día.
    if (menu != null && menu.cerrado && esFuturoOHoy) {
      await _repository.habilitar(menu.id);
      menu = await _repository.getMenu(_fecha, _tipo);
    }
    final items = menu == null
        ? <MenuItem>[]
        : await _repository.getItems(menu.id);
    final combos = menu == null
        ? <MenuCombo>[]
        : await _repository.getCombos(menu.id);
    final productos = await _catalog.getProductos(soloActivos: true);
    final categorias = await _catalog.getCategorias();
    final caja = await _cash.getCajaAbierta();
    return _MenuData(
      menu: menu,
      items: items,
      combos: combos,
      productos: productos,
      categorias: categorias,
      cajaAbierta: caja != null,
    );
  }

  MenuItem? _itemDe(List<MenuItem> items, int productoId) {
    for (final item in items) {
      if (item.productoId == productoId) return item;
    }
    return null;
  }

  /// Crea el menú del día empezando con los platos del menú anterior para que
  /// solo se ajuste lo que cambie. Si no hay menú anterior queda vacío.
  Future<MenuDia> _crearConAnterior() async {
    final desdeAnterior = await _repository.duplicarAnterior(
      _fecha,
      _tipo,
      widget.usuario.id,
    );
    return desdeAnterior ??
        await _repository.crearMenu(_fecha, _tipo, widget.usuario.id);
  }

  Future<void> _crearMenu() async {
    try {
      final previos = await _repository.getProductosMenuAnterior(
        _fecha,
        _tipo,
      );
      await _crearConAnterior();
      if (!mounted) return;
      setState(() {
        _editando = true;
        _reload();
      });
      showAppMessage(
        context,
        previos.isEmpty
            ? 'Menú creado vacío. Elige los platos del día.'
            : 'Menú creado con ${previos.length} plato(s) del día anterior. '
                  'Ajusta lo que haga falta o usa "Limpiar".',
      );
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, 'No se pudo crear el menú: $error', error: true);
    }
  }

  Future<void> _limpiar(_MenuData data) async {
    final menu = data.menu;
    if (menu == null) return;
    final confirmado = await confirmAction(
      context,
      title: 'Limpiar menú',
      message:
          'Se quitarán todos los platos del menú de hoy y podrás armarlo desde cero.',
      confirmLabel: 'Limpiar',
      destructive: true,
    );
    if (!confirmado) return;
    await _repository.limpiarMenu(menu.id);
    if (!mounted) return;
    setState(_reload);
    showAppMessage(context, 'Menú limpiado. Elige los platos del día.');
  }

  Future<void> _toggleProducto(_MenuData data, Producto producto) async {
    if (!_esAdmin || producto.id == null || _guardando) return;
    setState(() => _guardando = true);
    try {
      final menu = data.menu ?? await _crearConAnterior();
      // Se consulta el estado real en la BD para que un doble toque rápido no
      // deje el plato "pegado" en el menú.
      final items = await _repository.getItems(menu.id);
      final item = _itemDe(items, producto.id!);
      if (item != null) {
        await _repository.quitarItem(item.id);
        if (!mounted) return;
        setState(() {
          _guardando = false;
          _reload();
        });
        showAppMessage(
          context,
          '${producto.nombre} ya no está en el menú de hoy.',
        );
      } else {
        await _repository.agregarProducto(menu.id, producto.id!);
        if (!mounted) return;
        setState(() {
          _guardando = false;
          _reload();
        });
        showAppMessage(context, '${producto.nombre} agregado al menú de hoy.');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _guardando = false);
      showAppMessage(
        context,
        'No se pudo actualizar el menú: $error',
        error: true,
      );
    }
  }

  Future<void> _toggleDisponible(MenuItem item, bool disponible) async {
    await _repository.setDisponible(
      item.id,
      disponible,
      motivo: disponible ? null : 'Agotado',
    );
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _habilitar(_MenuData data) async {
    final menu = data.menu;
    if (menu == null) return;
    if (data.items.isEmpty && data.combos.isEmpty) {
      showAppMessage(
        context,
        'Agrega al menos un plato o almuerzo antes de publicar.',
        error: true,
      );
      return;
    }
    await _repository.habilitar(menu.id);
    if (!mounted) return;
    setState(() {
      _editando = false;
      _reload();
    });
    showAppMessage(context, 'Menú abierto. Ya se puede vender.');
  }

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (elegida == null) return;
    setState(() {
      _fecha = DateTime(elegida.year, elegida.month, elegida.day);
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now();
    final esHoy =
        _fecha.year == hoy.year &&
        _fecha.month == hoy.month &&
        _fecha.day == hoy.day;
    return FutureBuilder<_MenuData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return SingleChildScrollView(
          padding: EdgeInsets.all(
            esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: 'Menú del día',
                subtitle:
                    'Pulsa "Editar" para elegir los platos del menú de hoy con un toque.',
                actions: [
                  if (_esAdmin)
                    OutlinedButton.icon(
                      onPressed: _elegirFecha,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(
                        esHoy
                            ? 'Hoy · ${formatDateShort(_fecha)}'
                            : formatDateShort(_fecha),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => setState(_reload),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar'),
                  ),
                ],
              ),
              if (snapshot.connectionState == ConnectionState.waiting)
                const LoadingView()
              else if (snapshot.hasError)
                ErrorView(
                  message: '${snapshot.error}',
                  onRetry: () => setState(_reload),
                )
              else if (data == null)
                const SizedBox.shrink()
              else ...[
                if (widget.flujoInicioActivo && !data.cajaAbierta) ...[
                  _atajoCaja(context),
                  const SizedBox(height: 16),
                ],
                _estadoCard(context, data),
                const SizedBox(height: 16),
                _combosSection(context, data),
                const SizedBox(height: 16),
                _filtros(context, data),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final catalogo = _catalogo(context, data);
                    final panel = _menuLateral(context, data);
                    if (constraints.maxWidth >= 1100) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: catalogo),
                          const SizedBox(width: 16),
                          SizedBox(width: 300, child: panel),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [catalogo, const SizedBox(height: 16), panel],
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Atajo del flujo "Empezar el día": solo aparece si se usó ese botón y la
  /// caja todavía no está abierta.
  Widget _atajoCaja(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final boton = FilledButton.icon(
      onPressed: widget.onAbrirCaja == null
          ? null
          : () {
              widget.onFinalizarAtajo?.call();
              widget.onAbrirCaja!();
            },
      icon: const Icon(Icons.arrow_forward),
      label: const Text('Abrir caja'),
    );
    return AppCard(
      color: scheme.primaryContainer.withValues(alpha: 0.45),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final icono = Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.flag_outlined, color: scheme.primary),
          );
          const texto = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paso 2: abre la caja para iniciar el día',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Text('Cuando el menú esté listo, sigue a Caja.'),
            ],
          );
          if (esAngosto(constraints.maxWidth, limite: 560)) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    icono,
                    const SizedBox(width: 14),
                    const Expanded(child: texto),
                  ],
                ),
                const SizedBox(height: 12),
                boton,
              ],
            );
          }
          return Row(
            children: [
              icono,
              const SizedBox(width: 14),
              const Expanded(child: texto),
              const SizedBox(width: 12),
              boton,
            ],
          );
        },
      ),
    );
  }

  String _estadoLabel(String? estado) {
    switch (estado) {
      case 'HABILITADO':
        return 'Habilitado';
      case 'CERRADO':
        return 'Cerrado';
      case 'BORRADOR':
        return 'Borrador';
      default:
        return 'Sin menú';
    }
  }

  /// Buscador + chips de categorías (con su color) para filtrar el catálogo.
  Widget _filtros(BuildContext context, _MenuData data) {
    final relevantes = <int>{};
    for (final producto in data.productos) {
      if (producto.esCompuesto) continue;
      relevantes.add(producto.categoriaId);
    }
    final categorias = data.categorias
        .where(
          (categoria) =>
              categoria.id != null && relevantes.contains(categoria.id),
        )
        .toList()
      ..sort((a, b) {
        if (a.orden != b.orden) return a.orden.compareTo(b.orden);
        return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      });
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            decoration: appInput(label: 'Buscar producto', icon: Icons.search),
            onChanged: (value) => setState(() => _search = value),
          ),
          if (categorias.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Todas'),
                  selected: _categoriaId == null,
                  onSelected: (_) => setState(() => _categoriaId = null),
                ),
                ...categorias.map(
                  (categoria) => ChoiceChip(
                    avatar: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Color(categoria.color),
                        shape: BoxShape.circle,
                      ),
                    ),
                    label: Text(categoria.nombre),
                    selected: _categoriaId == categoria.id,
                    onSelected: (_) =>
                        setState(() => _categoriaId = categoria.id),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _estadoCard(BuildContext context, _MenuData data) {
    final scheme = Theme.of(context).colorScheme;
    final menu = data.menu;
    final habilitado = menu?.habilitado == true;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Chip(
                avatar: Icon(Icons.restaurant, size: 18),
                label: Text('MENÚ DE ALMUERZO'),
                side: BorderSide.none,
              ),
              Chip(
                label: Text('Estado: ${_estadoLabel(menu?.estado)}'),
                side: BorderSide.none,
              ),
              Chip(
                label: Text('${data.items.length} plato(s)'),
                side: BorderSide.none,
              ),
              Chip(
                label: Text('${data.combos.length} combo(s)'),
                side: BorderSide.none,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _editando
                ? 'Modo edición: toca un plato para agregarlo o quitarlo del menú de hoy.'
                : 'Pulsa "Editar" para agregar o quitar platos. Los platos con check verde están en el menú de hoy; los rojos están agotados.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          if (_esAdmin) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (menu == null)
                  FilledButton.icon(
                    onPressed: _crearMenu,
                    icon: const Icon(Icons.history),
                    label: const Text('Crear menú con los platos de ayer'),
                  ),
                if (menu != null && !_editando)
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _editando = true),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar'),
                  ),
                if (menu != null && _editando)
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _editando = false),
                    icon: const Icon(Icons.done_all_outlined),
                    label: const Text('Listo'),
                  ),
                if (_editando &&
                    (data.items.isNotEmpty || data.combos.isNotEmpty))
                  OutlinedButton.icon(
                    onPressed: () => _limpiar(data),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Limpiar'),
                  ),
                if (menu != null && !habilitado)
                  FilledButton.icon(
                    onPressed: () => _habilitar(data),
                    icon: const Icon(Icons.lock_open_outlined),
                    label: const Text('Publicar menú'),
                  ),
                if (menu != null)
                  OutlinedButton.icon(
                    onPressed: () => _programarDias(data),
                    icon: const Icon(Icons.event_repeat_outlined),
                    label: const Text('Programar días'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _combosSection(BuildContext context, _MenuData data) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.dinner_dining, color: scheme.primary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Almuerzos y combos',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              if (_esAdmin)
                FilledButton.tonalIcon(
                  onPressed: () => _abrirConstructorCombo(data),
                  icon: const Icon(Icons.add),
                  label: const Text('Armar almuerzo'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Selecciona uno o más productos. El precio sugerido baja un 10% desde el segundo producto, pero puedes cambiarlo.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (data.combos.isEmpty)
            Text(
              'Todavía no hay almuerzos armados para este día.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final ancho = constraints.maxWidth < 300
                    ? constraints.maxWidth
                    : 300.0;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: data.combos
                      .map(
                        (combo) => _comboCard(
                          context,
                          data,
                          combo,
                          ancho: ancho,
                        ),
                      )
                      .toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _comboCard(
    BuildContext context,
    _MenuData data,
    MenuCombo combo, {
    required double ancho,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final disponible = combo.disponible;
    return Container(
      width: ancho,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: disponible
            ? Colors.green.shade700.withValues(alpha: 0.08)
            : scheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: disponible ? Colors.green.shade700 : scheme.error,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  combo.nombre,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(
                disponible ? Icons.check_circle : Icons.block,
                size: 18,
                color: disponible ? Colors.green.shade700 : scheme.error,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            combo.componentes
                .map((componente) => componente.nombre)
                .join(' + '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                formatMoney(combo.precio),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              if (combo.sumaComponentes > combo.precio)
                Flexible(
                  child: Text(
                    'antes ${formatMoney(combo.sumaComponentes)}',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ),
            ],
          ),
          if (_esAdmin)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: disponible ? 'Marcar agotado' : 'Marcar disponible',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _toggleComboDisponible(combo),
                  icon: Icon(
                    disponible ? Icons.block : Icons.check_circle_outline,
                    size: 18,
                  ),
                ),
                IconButton(
                  tooltip: 'Editar almuerzo',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _abrirConstructorCombo(data, combo: combo),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
                IconButton(
                  tooltip: 'Quitar del menú',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _quitarCombo(combo),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _catalogo(BuildContext context, _MenuData data) {
    final term = _search.trim().toLowerCase();
    final filtrados = data.productos
        .where((producto) {
          if (producto.esCompuesto) return false;
          if (_categoriaId != null && producto.categoriaId != _categoriaId) {
            return false;
          }
          return term.isEmpty || producto.nombre.toLowerCase().contains(term);
        })
        .toList();
    if (filtrados.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        title: 'Sin productos',
        message: 'No hay productos activos que coincidan con la búsqueda.',
      );
    }

    final directos =
        filtrados
            .where(
              (producto) =>
                  producto.categoriaSiempreDisponible ||
                  producto.esVentaDirecta,
            )
            .toList()
          ..sort(_compararProductos);
    final menu = filtrados
        .where(
          (producto) =>
              !producto.categoriaSiempreDisponible && !producto.esVentaDirecta,
        )
        .toList();

    final grupos = <String, List<Producto>>{};
    for (final producto in menu) {
      grupos.putIfAbsent(producto.categoriaNombre.toUpperCase(), () => []).add(
        producto,
      );
    }
    final ordenCategorias = {
      for (final categoria in data.categorias) categoria.nombre: categoria.orden,
    };
    final categorias = grupos.keys.toList()
      ..sort((a, b) {
        final ordenA = ordenCategorias[a] ?? 999;
        final ordenB = ordenCategorias[b] ?? 999;
        if (ordenA != ordenB) return ordenA.compareTo(ordenB);
        return a.compareTo(b);
      });

    final children = <Widget>[];
    for (final categoria in categorias) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            categoria,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
      final productos = grupos[categoria]!..sort(_compararProductos);
      children.add(_gridProductos(context, data, productos));
      children.add(const SizedBox(height: 16));
    }

    if (directos.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'SIEMPRE DISPONIBLES',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.tertiary,
            ),
          ),
        ),
      );
      children.add(_gridProductos(context, data, directos, directo: true));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  int _compararProductos(Producto a, Producto b) =>
      a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());

  /// Lista lateral con los platos elegidos hoy (foto · producto · precio) y el
  /// botón para abrir el menú.
  Widget _menuLateral(BuildContext context, _MenuData data) {
    final scheme = Theme.of(context).colorScheme;
    final menu = data.menu;
    final habilitado = menu?.habilitado == true;
    final productosPorId = {
      for (final producto in data.productos) producto.id: producto,
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'MENÚ DE HOY',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              Text(
                '${data.items.length + data.combos.length}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (data.items.isEmpty && data.combos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Aún no has elegido platos.\nToca un plato o arma un almuerzo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          else
            for (final item in data.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: _miniatura(productosPorId[item.productoId]),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (!item.disponible)
                            Text(
                              item.motivoAgotado ?? 'Agotado',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.error),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatMoney(item.precio),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          for (final combo in data.combos)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: combo.imagen != null
                          ? Image.memory(
                              combo.imagen!,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            )
                          : Container(
                              color: Color(
                                combo.categoriaColor,
                              ).withValues(alpha: 0.15),
                              child: Icon(
                                Icons.dinner_dining,
                                size: 20,
                                color: Color(combo.categoriaColor),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          combo.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          combo.componentes
                              .map((componente) => componente.nombre)
                              .join(' + '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        if (!combo.disponible)
                          Text(
                            'Agotado',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.error),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatMoney(combo.precio),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (menu == null)
            FilledButton.icon(
              onPressed: () => _crearMenu(),
              icon: const Icon(Icons.history),
              label: const Text('Crear menú con los platos de ayer'),
            )
          else if (!habilitado)
            FilledButton.icon(
              onPressed: () => _habilitar(data),
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('Publicar menú'),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.shade700.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'MENÚ ABIERTO',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniatura(Producto? producto) {
    if (producto == null) {
      return Container(
        color: const Color(0xFFF3E9D9), // Crema
        child: const Icon(Icons.restaurant, size: 20),
      );
    }
    if (producto.imagen != null) {
      return Image.memory(
        producto.imagen!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    return Container(
      color: Color(producto.categoriaColor).withValues(alpha: 0.15),
      child: Icon(
        producto.esDirecto ? Icons.local_drink_outlined : Icons.restaurant,
        size: 20,
        color: Color(producto.categoriaColor),
      ),
    );
  }

  /// Atajo para elegir el almuerzo del día: una sopa y/o un segundo.
  int? _categoriaParaCombo(_MenuData data) {
    for (final categoria in data.categorias) {
      if (categoria.nombre == 'PLATOS SUELTOS') return categoria.id;
    }
    for (final categoria in data.categorias) {
      if (categoria.id != null) return categoria.id;
    }
    return null;
  }

  Future<void> _abrirConstructorCombo(
    _MenuData data, {
    MenuCombo? combo,
  }) async {
    final categoriaId = _categoriaParaCombo(data);
    if (categoriaId == null) {
      showAppMessage(
        context,
        'Crea al menos una categoría en Productos antes de armar un almuerzo.',
        error: true,
      );
      return;
    }
    final disponibles = data.productos
        .where((producto) => producto.id != combo?.productoId)
        .toList();
    final resultado = await showDialog<_ComboInput>(
      context: context,
      builder: (_) => _ComboBuilderDialog(
        productos: disponibles,
        combo: combo,
      ),
    );
    if (resultado == null || resultado.componenteIds.isEmpty) return;
    try {
      final menu = data.menu ?? await _crearConAnterior();
      if (combo == null) {
        final productoId = await _catalog.crearProductoCompuesto(
          nombre: resultado.nombre,
          categoriaId: categoriaId,
          precio: resultado.precio,
          componenteIds: resultado.componenteIds,
        );
        await _repository.agregarCombo(
          menuDiaId: menu.id,
          productoId: productoId,
          nombre: resultado.nombre,
          precio: resultado.precio,
        );
      } else {
        await _catalog.actualizarProductoCompuesto(
          productoId: combo.productoId,
          nombre: resultado.nombre,
          precio: resultado.precio,
          componenteIds: resultado.componenteIds,
        );
        await _repository.actualizarCombo(
          combo.id,
          nombre: resultado.nombre,
          precio: resultado.precio,
        );
      }
      if (!mounted) return;
      setState(_reload);
      showAppMessage(
        context,
        combo == null ? 'Almuerzo agregado al menú.' : 'Almuerzo actualizado.',
      );
    } catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        'No se pudo guardar el almuerzo: $error',
        error: true,
      );
    }
  }

  Future<void> _toggleComboDisponible(MenuCombo combo) async {
    await _repository.setComboDisponible(combo.id, !combo.disponible);
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _quitarCombo(MenuCombo combo) async {
    final confirmado = await confirmAction(
      context,
      title: 'Quitar almuerzo',
      message: '${combo.nombre} ya no aparecerá en el menú de hoy.',
      confirmLabel: 'Quitar',
      destructive: true,
    );
    if (!confirmado) return;
    await _repository.quitarCombo(combo.id);
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _programarDias(_MenuData data) async {
    final menu = data.menu;
    if (menu == null) return;
    final dias = await showDialog<int>(
      context: context,
      builder: (context) {
        var dias = 3;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Programar menú'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Se copiará esta configuración a los siguientes días que '
                  'todavía no tengan un menú programado.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: dias,
                  decoration: appInput(label: 'Días a programar'),
                  items: [
                    for (var i = 1; i <= 7; i++)
                      DropdownMenuItem(value: i, child: Text('$i día(s)')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => dias = value ?? dias),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, dias),
                child: const Text('Programar'),
              ),
            ],
          ),
        );
      },
    );
    if (dias == null || dias <= 0) return;
    var programados = 0;
    for (var i = 1; i <= dias; i++) {
      final fecha = _fecha.add(Duration(days: i));
      final existente = await _repository.getMenu(fecha, _tipo);
      if (existente != null) continue;
      final nuevo = await _repository.duplicarAnterior(
        fecha,
        _tipo,
        widget.usuario.id,
      );
      if (nuevo != null) programados++;
    }
    if (!mounted) return;
    setState(_reload);
    showAppMessage(
      context,
      programados == 0
          ? 'Los días siguientes ya tenían menú programado.'
          : 'Menú programado para $programados día(s).',
    );
  }

  Widget _gridProductos(
    BuildContext context,
    _MenuData data,
    List<Producto> productos, {
    bool directo = false,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: productos
              .map(
                (producto) => SizedBox(
                  width: width,
                  child: _tarjeta(context, data, producto, directo: directo),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _tarjeta(
    BuildContext context,
    _MenuData data,
    Producto producto, {
    required bool directo,
  }) {
    final item = _itemDe(data.items, producto.id!);
    final agotado = item != null && !item.disponible;
    final seleccionado = item != null && !agotado;
    final mensaje = directo
        ? 'Siempre disponible'
        : item == null
        ? (_editando ? 'Toca para agregar' : 'No está en el menú de hoy')
        : agotado
        ? (item.motivoAgotado ?? 'Agotado')
        : _editando
        ? 'En el menú de hoy · toca para quitar'
        : 'En el menú de hoy';

    // Cada toque deja un mensaje claro; fuera de modo edición nada cambia.
    VoidCallback? onTap;
    if (_esAdmin && !directo) {
      if (agotado) {
        onTap = () => showAppMessage(
          context,
          '${producto.nombre} está agotado. Reactívalo con el control de la tarjeta.',
        );
      } else if (_editando) {
        onTap = () => _toggleProducto(data, producto);
      } else {
        onTap = () =>
            showAppMessage(context, 'Pulsa "Editar" para modificar el menú.');
      }
    }

    return ProductoCatalogoCard(
      nombre: producto.nombre,
      categoria: producto.categoriaEtiqueta,
      precio: producto.precio,
      color: producto.categoriaColor,
      imagen: producto.imagen,
      esDirecto: producto.esDirecto,
      stock: producto.stock,
      habilitado: true,
      seleccionado: seleccionado,
      agotado: agotado,
      mensaje: mensaje,
      onTap: onTap,
      accion: item != null && !directo && _esAdmin
          ? IconButton(
              tooltip: item.disponible ? 'Marcar agotado' : 'Marcar disponible',
              visualDensity: VisualDensity.compact,
              onPressed: () => _toggleDisponible(item, !item.disponible),
              icon: Icon(
                item.disponible ? Icons.block : Icons.check_circle_outline,
                size: 18,
              ),
            )
          : null,
    );
  }
}

class _ComboInput {
  const _ComboInput({
    required this.nombre,
    required this.precio,
    required this.componenteIds,
  });

  final String nombre;
  final double precio;
  final List<int> componenteIds;
}

class _ComboBuilderDialog extends StatefulWidget {
  const _ComboBuilderDialog({required this.productos, this.combo});

  final List<Producto> productos;
  final MenuCombo? combo;

  @override
  State<_ComboBuilderDialog> createState() => _ComboBuilderDialogState();
}

class _ComboBuilderDialogState extends State<_ComboBuilderDialog> {
  late final TextEditingController _nombre;
  late final TextEditingController _precio;
  final _buscar = TextEditingController();
  final _seleccionados = <int>{};
  bool _precioManual = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final combo = widget.combo;
    _nombre = TextEditingController(text: combo?.nombre ?? '');
    _precio = TextEditingController(
      text: combo == null ? '' : combo.precio.toStringAsFixed(2),
    );
    _precioManual = combo != null;
    if (combo != null) {
      _seleccionados.addAll(
        combo.componentes.map((componente) => componente.componenteId),
      );
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _precio.dispose();
    _buscar.dispose();
    super.dispose();
  }

  double get _base => widget.productos
      .where((producto) => _seleccionados.contains(producto.id))
      .fold<double>(0, (suma, producto) => suma + producto.precio);

  double get _sugerido => _seleccionados.length >= 2 ? _base * 0.9 : _base;

  void _alternar(Producto producto) {
    setState(() {
      if (!_seleccionados.remove(producto.id)) {
        _seleccionados.add(producto.id!);
      }
      if (!_precioManual) {
        _precio.text = _sugerido.toStringAsFixed(2);
      }
    });
  }

  void _usarSugerido() {
    setState(() {
      _precioManual = false;
      _precio.text = _sugerido.toStringAsFixed(2);
    });
  }

  void _guardar() {
    final nombre = _nombre.text.trim();
    final precio = parseAmount(_precio.text);
    if (nombre.isEmpty) {
      setState(() => _error = 'Ingresa un nombre para el almuerzo.');
      return;
    }
    if (_seleccionados.isEmpty) {
      setState(() => _error = 'Selecciona al menos un producto.');
      return;
    }
    if (precio < 0) {
      setState(() => _error = 'El precio no puede ser negativo.');
      return;
    }
    Navigator.pop(
      context,
      _ComboInput(
        nombre: nombre,
        precio: precio,
        componenteIds: _seleccionados.toList(),
      ),
    );
  }

  int _prioridad(Producto producto) {
    switch (producto.categoriaNombre.toUpperCase()) {
      case 'SOPAS':
        return 0;
      case 'PLATOS SUELTOS':
        return 1;
      default:
        return producto.esCompuesto ? 3 : 2;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final termino = _buscar.text.trim().toLowerCase();
    final productos = widget.productos
        .where(
          (producto) =>
              termino.isEmpty ||
              producto.nombre.toLowerCase().contains(termino),
        )
        .toList()
      ..sort((a, b) {
        final prioridad = _prioridad(a).compareTo(_prioridad(b));
        if (prioridad != 0) return prioridad;
        return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      });
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      title: Text(
        widget.combo == null ? 'Armar almuerzo o combo' : 'Editar almuerzo',
      ),
      content: DialogSurface(
        maxWidth: 620,
        child: SizedBox(
          height: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nombre,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: appInput(label: 'Nombre del almuerzo'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _precio,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: appInput(
                        label: 'Precio (Bs)',
                        icon: Icons.sell_outlined,
                      ),
                      onChanged: (_) => _precioManual = true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Suma: ${formatMoney(_base)} · '
                      'Sugerido: ${formatMoney(_sugerido)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _seleccionados.isEmpty ? null : _usarSugerido,
                    child: const Text('Usar precio sugerido'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _buscar,
                decoration: appInput(
                  label: 'Buscar producto',
                  icon: Icons.search,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: productos.isEmpty
                    ? Center(
                        child: Text(
                          'No hay productos disponibles.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        itemCount: productos.length,
                        itemBuilder: (context, index) {
                          final producto = productos[index];
                          final seleccionado = _seleccionados.contains(
                            producto.id,
                          );
                          return CheckboxListTile(
                            value: seleccionado,
                            onChanged: (_) => _alternar(producto),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            secondary: Icon(
                              producto.esCompuesto
                                  ? Icons.dinner_dining
                                  : producto.esDirecto
                                  ? Icons.local_drink_outlined
                                  : Icons.restaurant,
                              color: Color(producto.categoriaColor),
                            ),
                            title: Text(producto.nombre),
                            subtitle: Text(
                              '${producto.categoriaNombre} · '
                              '${formatMoney(producto.precio)}',
                            ),
                          );
                        },
                      ),
              ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error, style: TextStyle(color: scheme.error)),
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
          onPressed: _guardar,
          child: Text(widget.combo == null ? 'Agregar al menú' : 'Guardar'),
        ),
      ],
    );
  }
}
