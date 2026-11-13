import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'core/auth_repository.dart';
import 'core/session.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/auth/presentation/onboarding_admin_page.dart';
import 'features/shell/presentation/app_shell.dart';

void main() {
  runApp(const RestaurantApp());
}

/// Permite arrastrar el contenido con el dedo, el lápiz o el mouse.
/// Sin esto, en web/escritorio solo se puede usar la rueda del mouse.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
  };
}

class RestaurantApp extends StatelessWidget {
  const RestaurantApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFFC18A55);
    return MaterialApp(
      title: 'Conwich',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const AppScrollBehavior(),
      theme: ThemeData(
        useMaterial3: true,
        // Identidad visual ConWich: Espresso, Nogal, Caramelo, Dorado, Crema
        // y Blanco cálido. Los colores semánticos se mantienen distinguibles.
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFF70452D), // Nogal
          onPrimary: const Color(0xFFFFF9F0), // Blanco cálido
          primaryContainer: const Color(0xFFE8C995), // Dorado
          onPrimaryContainer: const Color(0xFF2B1A12), // Texto oscuro
          secondary: const Color(0xFF574537), // Texto
          onSecondary: const Color(0xFFFFF9F0), // Blanco cálido
          secondaryContainer: const Color(0xFFE8C995), // Dorado
          onSecondaryContainer: const Color(0xFF2B1A12), // Texto oscuro
          tertiary: const Color(0xFF3D2419), // Espresso
          onTertiary: const Color(0xFFF3E9D9), // Crema
          tertiaryContainer: const Color(0xFFE8C995), // Dorado
          onTertiaryContainer: const Color(0xFF2B1A12), // Texto oscuro
          error: const Color(0xFFA9442F), // Terracota apagado
          onError: const Color(0xFFFFF9F0), // Blanco cálido
          errorContainer: const Color(0xFFF3DAD3), // Terracota suave
          onErrorContainer: const Color(0xFF3B120C), // Error oscuro
          surface: const Color(0xFFFFF9F0), // Blanco cálido
          onSurface: const Color(0xFF2B1A12), // Texto oscuro
          onSurfaceVariant: const Color(0xFF574537), // Texto
          surfaceDim: const Color(0xFFF3E9D9), // Crema
          surfaceBright: const Color(0xFFFFF9F0), // Blanco cálido
          surfaceContainerLowest: const Color(0xFFFFF9F0), // Blanco cálido
          surfaceContainerLow: const Color(0xFFFFF9F0), // Blanco cálido
          surfaceContainer: const Color(0xFFF3E9D9), // Crema
          surfaceContainerHigh: const Color(0xFFF3E9D9), // Crema
          surfaceContainerHighest: const Color(0xFFF3E9D9), // Crema
          outline: const Color(0xFF70452D), // Nogal
          outlineVariant: const Color(0xFFE8C995), // Dorado
          inverseSurface: const Color(0xFF3D2419), // Espresso
          onInverseSurface: const Color(0xFFF3E9D9), // Crema
          inversePrimary: const Color(0xFFC18A55), // Caramelo
          shadow: const Color(0xFF3D2419), // Espresso
          scrim: const Color(0xFF3D2419), // Espresso
          surfaceTint: const Color(0xFFC18A55), // Caramelo
        ),
        scaffoldBackgroundColor: const Color(0xFFFFF9F0), // Blanco cálido
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF3D2419), // Espresso
          surfaceTintColor: Color(0xFF3D2419),
          foregroundColor: Color(0xFFF3E9D9), // Crema
          iconTheme: IconThemeData(color: Color(0xFFF3E9D9)),
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: Color(0xFF3D2419), // Espresso
          surfaceTintColor: Color(0xFF3D2419),
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFFF3E9D9), // Crema
          surfaceTintColor: Colors.transparent,
          margin: EdgeInsets.zero,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFFFFF9F0), // Blanco cálido
          surfaceTintColor: Colors.transparent,
        ),
        popupMenuTheme: const PopupMenuThemeData(
          color: Color(0xFFFFF9F0), // Blanco cálido
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFFFF9F0), // Blanco cálido
          prefixIconColor: const Color(0xFF70452D), // Nogal
          suffixIconColor: const Color(0xFF70452D), // Nogal
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE8C995)), // Dorado
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: seed, width: 1.6),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFC18A55), // Caramelo
            foregroundColor: const Color(0xFF2B1A12), // Texto oscuro
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF70452D), // Nogal
            side: const BorderSide(color: Color(0xFFE8C995)), // Dorado
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF70452D), // Nogal
          ),
        ),
        navigationRailTheme: const NavigationRailThemeData(
          labelType: NavigationRailLabelType.none,
          groupAlignment: -0.9,
          backgroundColor: Color(0xFF3D2419), // Espresso
          indicatorColor: Color(0xFFC18A55), // Caramelo
          selectedIconTheme: IconThemeData(color: Color(0xFFF3E9D9)),
          unselectedIconTheme: IconThemeData(color: Color(0xFFE8C995)),
        ),
        chipTheme: const ChipThemeData(
          backgroundColor: Color(0x55E8C995), // Dorado translúcido
          selectedColor: Color(0xFFE8C995), // Dorado
          secondarySelectedColor: Color(0xFFC18A55), // Caramelo
          disabledColor: Color(0x33E8C995), // Dorado tenue
          side: BorderSide(color: Color(0xFFE8C995)), // Dorado
          checkmarkColor: Color(0xFF2B1A12), // Texto oscuro
          deleteIconColor: Color(0xFF70452D), // Nogal
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Color(0xFF70452D), // Nogal
          unselectedLabelColor: Color(0xFF574537), // Texto
          indicatorColor: Color(0xFFC18A55), // Caramelo
          dividerColor: Color(0xFFE8C995), // Dorado
          overlayColor: WidgetStatePropertyAll(Color(0x1FC18A55)),
        ),
        dataTableTheme: const DataTableThemeData(
          headingRowColor: WidgetStatePropertyAll(Color(0xFFE8C995)),
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: Color(0xFF70452D), // Nogal
          textColor: Color(0xFF2B1A12), // Texto oscuro
          selectedColor: Color(0xFFC18A55), // Caramelo
          selectedTileColor: Color(0x33E8C995), // Dorado suave
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFFC18A55); // Caramelo
            }
            return const Color(0xFFE8C995); // Dorado
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFFE8C995); // Dorado
            }
            return const Color(0xFFF3E9D9); // Crema
          }),
          trackOutlineColor: const WidgetStatePropertyAll(
            Color(0xFFE8C995), // Dorado
          ),
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: Color(0xFFC18A55), // Caramelo
          selectionColor: Color(0x55E8C995), // Dorado translúcido
          selectionHandleColor: Color(0xFFC18A55), // Caramelo
        ),
        scrollbarTheme: const ScrollbarThemeData(
          thumbColor: WidgetStatePropertyAll(Color(0x8070452D)),
        ),
        dividerTheme: const DividerThemeData(
          space: 1,
          color: Color(0xFFE8C995), // Dorado
        ),
      ),
      home: const StartupGate(),
    );
  }
}

class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  final _repository = AuthRepository();
  bool _loading = true;
  String? _error;
  Usuario? _usuario;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final usuario = await _repository.restaurarSesion().timeout(
        const Duration(seconds: 30),
      );
      if (!mounted) return;
      setState(() {
        _usuario = usuario;
        if (usuario != null) Sesion.instance.iniciar(usuario);
        _loading = false;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error = 'La base de datos tardó demasiado en abrir. Cierra la app y vuelve a intentar.';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo abrir la base de datos: $error';
        _loading = false;
      });
    }
  }

  Future<void> _login(Usuario usuario) async {
    Sesion.instance.iniciar(usuario);
    await _repository.guardarSesion(usuario.id);
    if (!mounted) return;
    setState(() => _usuario = usuario);
  }

  Future<void> _logout() async {
    await _repository.cerrarSesion();
    Sesion.instance.cerrar();
    if (!mounted) return;
    setState(() => _usuario = null);
  }

  Future<void> _cambiarUsuario(Usuario usuario) async {
    Sesion.instance.iniciar(usuario);
    await _repository.guardarSesion(usuario.id);
    if (!mounted) return;
    setState(() => _usuario = usuario);
  }

  /// El primer acceso obligatorio terminó: se continúa sin volver a pedir
  /// credenciales.
  void _completarPrimerAcceso(Usuario usuario) {
    Sesion.instance.iniciar(usuario);
    setState(() => _usuario = usuario);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storage_outlined, size: 48),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _check,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_usuario != null) {
      final usuario = _usuario!;
      if (usuario.debeCambiarPassword) {
        return OnboardingAdminPage(
          usuario: usuario,
          onCompletado: _completarPrimerAcceso,
          onLogout: _logout,
        );
      }
      return AppShell(
        usuario: usuario,
        onLogout: _logout,
        onUsuarioCambiado: _cambiarUsuario,
      );
    }
    return LoginPage(onLogin: _login);
  }
}
