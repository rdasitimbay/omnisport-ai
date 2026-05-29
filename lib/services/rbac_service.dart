import 'package:flutter/material.dart';

/// ============================================================
/// RbacService — Matriz de Permisos Centralizada (Cliente)
/// USR-ROL: admin | coach | athlete | parent
///
/// IMPORTANTE: Esta capa solo es defensa en profundidad en UI.
/// La autorización real e inalterable vive en:
///   - Firestore Security Rules  (servidor, por colección)
///   - Cloud Functions Guards    (assertAdmin, assertAuthenticated)
/// Nunca confiar solo en este servicio para decisiones de seguridad.
/// ============================================================
class RbacService {
  // ─── Roles canónicos ─────────────────────────────────────────
  static const String roleAdmin   = 'admin';
  static const String roleCoach   = 'coach';
  static const String roleAthlete = 'athlete';
  static const String roleParent  = 'parent';

  // Normaliza variantes legadas ('user', null, '') → 'athlete'
  static String normalize(String? raw) {
    if (raw == null || raw.isEmpty || raw == 'user') return roleAthlete;
    return raw;
  }

  // ─── Comprobaciones de acceso ─────────────────────────────────

  /// Admin: acceso total al backoffice y dashboards de auditoría forense.
  static bool canAccessAdminFeatures(String role) => role == roleAdmin;

  /// Admin o Coach: pueden gestionar atletas (ver listas, asistencia, reportes).
  static bool canManageAthletes(String role) =>
      role == roleAdmin || role == roleCoach;

  /// Coach: solo sus atletas (filtro por coachId — la query Firestore se encarga).
  static bool isCoach(String role) => role == roleCoach;

  /// Padre: solo puede leer datos de sus tutorados (validado por childrenIds).
  static bool isParent(String role) => role == roleParent;

  /// Verifica si un padre tiene acceso legítimo a un atleta concreto.
  /// [childrenIds] proviene de users/{parentUid}.childrenIds en Firestore.
  static bool canParentViewAthlete(String role, List<String> childrenIds, String athleteId) {
    if (role != roleParent) return false;
    return childrenIds.contains(athleteId);
  }

  /// Atleta: solo puede ver su propio perfil y datos.
  static bool canAthleteViewProfile(String role, String currentUid, String targetId) {
    if (role == roleAdmin || role == roleCoach) return true;
    return currentUid == targetId;
  }

  /// ¿Puede este rol acceder al panel de escalación de roles del backoffice?
  static bool canAccessRbacManagement(String role) => role == roleAdmin;

  /// ¿Puede este rol ver logs de auditoría forense?
  static bool canViewAuditLogs(String role) => role == roleAdmin;

  /// ¿Puede este rol emitir broadcasts de emergencia?
  static bool canBroadcast(String role) => role == roleAdmin;

  // ─── Presentación visual ──────────────────────────────────────

  /// Color por rol para badges y UI diferenciada.
  static Color getRoleColor(String role) {
    switch (normalize(role)) {
      case roleAdmin:   return const Color(0xFFFF6B35); // Naranja Fuego
      case roleCoach:   return const Color(0xFF00E5FF); // Cyan
      case roleAthlete: return const Color(0xFF69F0AE); // Verde
      case roleParent:  return const Color(0xFFCE93D8); // Lavanda
      default:          return Colors.white54;
    }
  }

  /// Etiqueta legible en español.
  static String getRoleLabel(String role) {
    switch (normalize(role)) {
      case roleAdmin:   return 'Administrador';
      case roleCoach:   return 'Entrenador';
      case roleAthlete: return 'Atleta';
      case roleParent:  return 'Padre / Tutor';
      default:          return 'Desconocido';
    }
  }

  /// Ícono representativo del rol.
  static IconData getRoleIcon(String role) {
    switch (normalize(role)) {
      case roleAdmin:   return Icons.admin_panel_settings;
      case roleCoach:   return Icons.sports;
      case roleAthlete: return Icons.directions_run;
      case roleParent:  return Icons.family_restroom;
      default:          return Icons.person;
    }
  }

  /// Badge widget compacto para listas de usuarios.
  static Widget roleBadge(String role) {
    final color = getRoleColor(role);
    final label = getRoleLabel(role);
    final icon  = getRoleIcon(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
