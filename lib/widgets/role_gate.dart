import 'package:flutter/material.dart';
import '../services/rbac_service.dart';

/// ============================================================
/// RoleGate — Widget de Control de Políticas RBAC
///
/// Renderiza [child] SOLO si el [currentRole] está en [allowedRoles].
/// Si el rol no tiene acceso:
///   - Retorna [orElse] si se provee (contenido alternativo).
///   - Retorna SizedBox.shrink() por defecto → cero memoria consumida,
///     cero excepciones 403, cero botones que no deberían existir.
///
/// USO:
/// ```dart
/// RoleGate(
///   currentRole: userRole,
///   allowedRoles: [RbacService.roleCoach, RbacService.roleAdmin],
///   child: _buildZeroTrustButton(),
/// )
/// ```
///
/// IMPORTANTE: Esta es defensa en profundidad a nivel de UI.
/// La autorización real e inalterable vive en Firestore Security Rules
/// y en los guards de Cloud Functions (assertAdmin, assertAuthenticated).
/// ============================================================
class RoleGate extends StatelessWidget {
  /// El rol actual del usuario autenticado.
  final String currentRole;

  /// Lista de roles que tienen permiso para ver [child].
  final List<String> allowedRoles;

  /// Widget a renderizar si el rol tiene acceso.
  final Widget child;

  /// Widget alternativo a renderizar si el rol NO tiene acceso.
  /// Por defecto: SizedBox.shrink() (invisible, sin espacio).
  final Widget? orElse;

  const RoleGate({
    super.key,
    required this.currentRole,
    required this.allowedRoles,
    required this.child,
    this.orElse,
  });

  @override
  Widget build(BuildContext context) {
    if (allowedRoles.contains(RbacService.normalize(currentRole))) {
      return child;
    }
    return orElse ?? const SizedBox.shrink();
  }
}

/// ============================================================
/// RoleGateAsync — Versión asíncrona que carga el rol desde Firestore
/// directamente, para usarse en widgets que no tienen el rol disponible
/// en su árbol de contexto.
///
/// USO:
/// ```dart
/// RoleGateAsync(
///   allowedRoles: [RbacService.roleAdmin],
///   child: _buildAdminButton(),
/// )
/// ```
/// ============================================================
class RoleGateAsync extends StatelessWidget {
  final List<String> allowedRoles;
  final Widget child;
  final Widget? orElse;
  final Stream<String?> roleStream;

  const RoleGateAsync({
    super.key,
    required this.allowedRoles,
    required this.child,
    required this.roleStream,
    this.orElse,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String?>(
      stream: roleStream,
      builder: (context, snap) {
        final role = RbacService.normalize(snap.data);
        if (allowedRoles.contains(role)) return child;
        return orElse ?? const SizedBox.shrink();
      },
    );
  }
}
