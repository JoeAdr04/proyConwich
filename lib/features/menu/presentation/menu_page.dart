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
    required this.productos,
    required this.categorias,
    required this.cajaAbierta,
  });

  final MenuDia? menu;
  final List<MenuItem> items;
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
    final menu = await _repository.getMenu(_fecha, _tipo);
    final items = menu == null
        ? <MenuItem>[]
        : await _repository.getItems(menu.id);
    final productos = await _catalog.getProductos(soloActivos: true);
    final categorias = await _catalog.getCategorias();
    final caja = await _cash.getCajaAbierta();
    return _MenuData(
      menu: menu,
      items: items,
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
    await _repository.reemplazarItems(menu.id, []);
    if (!mounted) return;
    setState(_reload);
    showAppMessage(context, 'Menú limpiado. Elige los platos del día.');
  }

  Future<void> _toggleProducto(_MenuData data, Producto producto) async {
    if (!_esAdmin || producto.id == null || _guardando) return;
    if (data.menu?.cerrado == true) {
      showAppMessage(
        context,
        'El menú está cerrado. Usa "Reabrir menú" para editarlo.',
        error: true,
      );
      return;
    }
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
    if (data.items.isEmpty) {
      showAppMessage(
        context,
        'Agrega al menos un plato antes de habilitar.',
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

  Future<void> _cerrar(_MenuData data) async {
    final menu = data.menu;
    if (menu == null) return;
    final confirmado = await confirmAction(
      context,
      title: 'Cerrar menú',
      message: 'El menú quedará cerrado y no se podrán registrar más ventas de estos platos.',
      confirmLabel: 'Cerrar menú',
      destructive: true,
    );
    if (!confirmado) return;
    await _repository.cerrar(menu.id);
    if (!mounted) return;
    setState(_reload);
    showAppMessage(context, 'Menú cerrado.');
  }

  /// Reabre un menú cerrado: vuelve a estar habilitado para editar y vender.
  Future<void> _reabrir(_MenuData data) async {
    final menu = data.menu;
    if (menu == null) return;
    await _repository.habilitar(menu.id);
    if (!mounted) return;
    setState(_reload);
    showAppMessage(context, 'Menú reabierto. Ya se puede editar y vender.');
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
      relevantes.add(producto.categoriaId);
      if (producto.categoriaParentId != null) {
        relevantes.add(producto.categoriaParentId!);
      }
    }
    final categorias = data.categorias
        .where(
          (categoria) => categoria.id != null && relevantes.contains(categoria.id),
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
    final cerrado = menu?.cerrado == true;
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
            ],
          ),
          const SizedBox(height: 10),
          Text(
            cerrado
                ? 'Menú cerrado. Pulsa "Reabrir menú" para editarlo o seguir vendiendo.'
                : _editando
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
                if (menu != null && !cerrado)
                  FilledButton.tonalIcon(
                    onPressed: () => _agregarAlmuerzoCompleto(data),
                    icon: const Icon(Icons.dinner_dining),
                    label: const Text('Agregar almuerzo completo'),
                  ),
                if (menu != null && !cerrado && !_editando)
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _editando = true),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar'),
                  ),
                if (habilitado && _editando)
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _editando = false),
                    icon: const Icon(Icons.done_all_outlined),
                    label: const Text('Listo'),
                  ),
                if (_editando && !cerrado && data.items.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _limpiar(data),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Limpiar'),
                  ),
                if (habilitado)
                  OutlinedButton.icon(
                    onPressed: () => _cerrar(data),
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Cerrar menú'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _catalogo(BuildContext context, _MenuData data) {
    final term = _search.trim().toLowerCase();
    final filtrados = data.productos
        .where((producto) {
          if (_categoriaId != null &&
              producto.categoriaId != _categoriaId &&
              producto.categoriaParentId != _categoriaId) {
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

    final grupos = <String, Map<String, List<Producto>>>{};
    for (final producto in menu) {
      final padre = (producto.categoriaParentNombre ?? producto.categoriaNombre)
          .toUpperCase();
      final sub = producto.categoriaParentNombre == null
          ? ''
          : producto.categoriaNombre.toUpperCase();
      grupos
          .putIfAbsent(padre, () => {})
          .putIfAbsent(sub, () => [])
          .add(producto);
    }
    final padres = grupos.keys.toList()..sort();

    final children = <Widget>[];
    for (final padre in padres) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            padre,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
      final subcategorias = grupos[padre]!.keys.toList()..sort();
      for (final sub in subcategorias) {
        if (sub.isNotEmpty && sub != padre) {
          children.add(
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Text(
                sub,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }
        final productos = grupos[padre]![sub]!..sort(_compararProductos);
        children.add(_gridProductos(context, data, productos));
        children.add(const SizedBox(height: 16));
      }
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
    final cerrado = menu?.cerrado == true;
    final borrador = menu == null || menu.estado == 'BORRADOR';
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
                '${data.items.length}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (data.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Aún no has elegido platos.\nToca un plato o usa "Agregar almuerzo completo".',
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
          const SizedBox(height: 12),
          if (menu == null)
            FilledButton.icon(
              onPressed: () => _crearMenu(),
              icon: const Icon(Icons.history),
              label: const Text('Crear menú con los platos de ayer'),
            )
          else if (borrador)
            FilledButton.icon(
              onPressed: () => _habilitar(data),
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('Abrir menú'),
            )
          else if (habilitado)
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
            )
          else if (cerrado)
            FilledButton.icon(
              onPressed: () => _reabrir(data),
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('Reabrir menú'),
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
  Future<void> _agregarAlmuerzoCompleto(_MenuData data) async {
    int? categoriaId(String nombre) {
      for (final categoria in data.categorias) {
        if (categoria.nombre.trim().toUpperCase() == nombre) {
          return categoria.id;
        }
      }
      return null;
    }

    final sopaId = categoriaId('SOPA');
    final segundoId = categoriaId('SEGUNDO');
    if (sopaId == null && segundoId == null) {
      showAppMessage(
        context,
        'Crea las categorías SOPA y SEGUNDO en el módulo de Productos.',
        error: true,
      );
      return;
    }
    final enMenu = data.items.map((item) => item.productoId).toSet();
    final sopas = data.productos
        .where(
          (producto) =>
              producto.categoriaId == sopaId &&
              !enMenu.contains(producto.id),
        )
        .toList()
      ..sort(_compararProductos);
    final segundos = data.productos
        .where(
          (producto) =>
              producto.categoriaId == segundoId &&
              !enMenu.contains(producto.id),
        )
        .toList()
      ..sort(_compararProductos);
    final seleccion = await showDialog<List<int>>(
      context: context,
      builder: (_) => _AlmuerzoCompletoDialog(sopas: sopas, segundos: segundos),
    );
    if (seleccion == null || seleccion.isEmpty) return;
    try {
      final menu = data.menu ?? await _crearConAnterior();
      for (final productoId in seleccion) {
        await _repository.agregarProducto(menu.id, productoId);
      }
      if (!mounted) return;
      setState(_reload);
      showAppMessage(
        context,
        '${seleccion.length} plato(s) agregado(s) al menú de hoy.',
      );
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, 'No se pudo agregar: $error', error: true);
    }
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
    final cerrado = data.menu?.cerrado == true;
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
      } else if (cerrado) {
        onTap = () => showAppMessage(
          context,
          'El menú está cerrado. Usa "Reabrir menú" para editarlo.',
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
      accion: item != null && !directo && _esAdmin && !cerrado
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

/// Popup para elegir el almuerzo del día: una sopa y/o un segundo.
class _AlmuerzoCompletoDialog extends StatefulWidget {
  const _AlmuerzoCompletoDialog({required this.sopas, required this.segundos});

  final List<Producto> sopas;
  final List<Producto> segundos;

  @override
  State<_AlmuerzoCompletoDialog> createState() =>
      _AlmuerzoCompletoDialogState();
}

class _AlmuerzoCompletoDialogState extends State<_AlmuerzoCompletoDialog> {
  final _seleccionados = <int>{};
  String _buscarSopa = '';
  String _buscarSegundo = '';

  void _alternar(Producto producto) {
    setState(() {
      if (!_seleccionados.remove(producto.id)) {
        _seleccionados.add(producto.id!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Agregar almuerzo completo'),
      content: SizedBox(
        width: 560,
        height: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _seccion(
                context,
                titulo: 'SOPA',
                hint: 'Buscar sopa',
                vacio: 'No hay sopas disponibles para agregar.',
                productos: widget.sopas,
                busqueda: _buscarSopa,
                onBuscar: (valor) => setState(() => _buscarSopa = valor),
              ),
              const SizedBox(height: 18),
              _seccion(
                context,
                titulo: 'SEGUNDO',
                hint: 'Buscar segundo suelto',
                vacio: 'No hay segundos disponibles para agregar.',
                productos: widget.segundos,
                busqueda: _buscarSegundo,
                onBuscar: (valor) => setState(() => _buscarSegundo = valor),
              ),
              const SizedBox(height: 8),
              Text(
                'Toca un plato para elegirlo y pulsa "Listo".',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
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
          onPressed: _seleccionados.isEmpty
              ? null
              : () => Navigator.pop(context, _seleccionados.toList()),
          child: Text('Listo (${_seleccionados.length})'),
        ),
      ],
    );
  }

  Widget _seccion(
    BuildContext context, {
    required String titulo,
    required String hint,
    required String vacio,
    required List<Producto> productos,
    required String busqueda,
    required ValueChanged<String> onBuscar,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final termino = busqueda.trim().toLowerCase();
    final filtrados = productos
        .where(
          (producto) =>
              termino.isEmpty ||
              producto.nombre.toLowerCase().contains(termino),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: appInput(label: hint, icon: Icons.search),
          onChanged: onBuscar,
        ),
        const SizedBox(height: 8),
        if (filtrados.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(vacio, style: TextStyle(color: scheme.onSurfaceVariant)),
          )
        else
          for (final producto in filtrados) _fila(context, producto),
      ],
    );
  }

  Widget _fila(BuildContext context, Producto producto) {
    final scheme = Theme.of(context).colorScheme;
    final seleccionado = _seleccionados.contains(producto.id);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _alternar(producto),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 42,
                height: 42,
                child: producto.imagen != null
                    ? Image.memory(
                        producto.imagen!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
                    : Container(
                        color: Color(
                          producto.categoriaColor,
                        ).withValues(alpha: 0.15),
                        child: Icon(
                          Icons.restaurant,
                          size: 20,
                          color: Color(producto.categoriaColor),
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
                    producto.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    formatMoney(producto.precio),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              seleccionado ? Icons.check_circle : Icons.add_circle_outline,
              color: seleccionado ? Colors.green.shade700 : scheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
