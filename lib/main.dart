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
        // y Blanco cálido. Los colores semánticos (error, etc.) se conservan.
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFFC18A55), // Caramelo
          onPrimary: const Color(0xFF2B1A12), // Texto oscuro
          secondary: const Color(0xFF70452D), // Nogal
          onSecondary: const Color(0xFFFFF9F0), // Blanco cálido
          tertiary: const Color(0xFFC18A55), // Caramelo
          onTertiary: const Color(0xFF2B1A12), // Texto oscuro
          surface: const Color(0xFFFFF9F0), // Blanco cálido
          onSurface: const Color(0xFF2B1A12), // Texto oscuro
          onSurfaceVariant: const Color(0xFF574537), // Texto
          outline: const Color(0xFF70452D), // Nogal
          outlineVariant: const Color(0xFFE8C995), // Dorado
          inverseSurface: const Color(0xFF3D2419), // Espresso
          onInverseSurface: const Color(0xFFF3E9D9), // Crema
        ),
        scaffoldBackgroundColor: const Color(0xFFF3E9D9), // Crema
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
          color: Color(0xFFFFF9F0), // Blanco cálido
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFFFF9F0), // Blanco cálido
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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
        dividerTheme: const DividerThemeData(space: 1),
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
