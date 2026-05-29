import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../services/rbac_service.dart';

/// ============================================================
/// AdminMobileDashboardScreen
/// Pantalla simplificada de administración para dispositivos móviles.
/// Proporciona acceso rápido a las operaciones más críticas del admin
/// sin la complejidad del AdminDashboardScreen web completo.
/// ============================================================
class AdminMobileDashboardScreen extends StatefulWidget {
  const AdminMobileDashboardScreen({super.key});

  @override
  State<AdminMobileDashboardScreen> createState() => _AdminMobileDashboardScreenState();
}

class _AdminMobileDashboardScreenState extends State<AdminMobileDashboardScreen> {
  final _db   = FirebaseFirestore.instance;
  bool _isLoading = false;

  // ─── Estadísticas rápidas ─────────────────────────────────────
  Future<Map<String, int>> _fetchStats() async {
    final results = await Future.wait([
      _db.collection('users').get(),
      _db.collection('athletes').get(),
      _db.collection('users').where('role', isEqualTo: 'coach').get(),
      _db.collection('users').where('role', isEqualTo: 'parent').get(),
    ]);
    return {
      'usuarios':  results[0].size,
      'atletas':   results[1].size,
      'coaches':   results[2].size,
      'padres':    results[3].size,
    };
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _toggleMaintenanceMode(bool current) async {
    setState(() => _isLoading = true);
    try {
      await _db.collection('app_config').doc('global_settings')
          .set({'maintenance_mode': !current}, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(!current ? '🔒 Modo mantenimiento ACTIVADO' : '✅ Modo mantenimiento DESACTIVADO'),
          backgroundColor: !current ? Colors.orange : Colors.green,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Admin · OmniSport',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.power, color: Colors.redAccent),
            tooltip: 'Cerrar sesión',
            onPressed: _signOut,
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D0D1A), Color(0xFF001F3F), Color(0xFF003F87)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAdminHeader(),
                const SizedBox(height: 24),
                _buildStatsGrid(),
                const SizedBox(height: 24),
                _buildSectionLabel('CONTROL RÁPIDO'),
                const SizedBox(height: 12),
                _buildMaintenanceTile(),
                const SizedBox(height: 12),
                _buildQuickActions(),
                const SizedBox(height: 24),
                _buildSectionLabel('USUARIOS RECIENTES'),
                const SizedBox(height: 12),
                _buildRecentUsers(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdminHeader() {
    final user = FirebaseAuth.instance.currentUser;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFFFF6B35), Color(0xFFFF3D00)],
            ),
            boxShadow: [
              BoxShadow(color: const Color(0xFFFF6B35).withValues(alpha: 0.4), blurRadius: 16, spreadRadius: 2),
            ],
          ),
          child: const Icon(Icons.admin_panel_settings, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Panel de Administración',
                  style: TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 1)),
              Text(
                user?.email ?? 'Admin',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        RbacService.roleBadge(RbacService.roleAdmin),
      ],
    );
  }

  Widget _buildStatsGrid() {
    return FutureBuilder<Map<String, int>>(
      future: _fetchStats(),
      builder: (context, snap) {
        final stats = snap.data ?? {};
        final pairs = [
          {'label': 'Usuarios',  'value': stats['usuarios'] ?? 0, 'icon': Icons.people,           'color': const Color(0xFF00E5FF)},
          {'label': 'Atletas',   'value': stats['atletas']  ?? 0, 'icon': Icons.directions_run,   'color': const Color(0xFF69F0AE)},
          {'label': 'Coaches',   'value': stats['coaches']  ?? 0, 'icon': Icons.sports,           'color': const Color(0xFFFFD54F)},
          {'label': 'Padres',    'value': stats['padres']   ?? 0, 'icon': Icons.family_restroom,  'color': const Color(0xFFCE93D8)},
        ];
        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.6,
          children: pairs.map((p) => _buildStatCard(
            label: p['label'] as String,
            value: snap.hasData ? (p['value'] as int).toString() : '—',
            icon:  p['icon']  as IconData,
            color: p['color'] as Color,
          )).toList(),
        );
      },
    );
  }

  Widget _buildStatCard({required String label, required String value, required IconData icon, required Color color}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 24),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.bold)),
                  Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(label,
        style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2));
  }

  Widget _buildMaintenanceTile() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('app_config').doc('global_settings').snapshots(),
      builder: (context, snap) {
        final data         = snap.data?.data() as Map<String, dynamic>? ?? {};
        final isMaintenance = data['maintenance_mode'] ?? false;
        return _buildGlassCard(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              isMaintenance ? '🔒 Mantenimiento ACTIVO' : '✅ Sistema Operativo',
              style: TextStyle(
                color: isMaintenance ? Colors.orange : Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: const Text('Bloquea acceso a todos excepto admins.',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            value: isMaintenance,
            activeThumbColor: Colors.orange,
            inactiveThumbColor: const Color(0xFF00E5FF),
            inactiveTrackColor: const Color(0xFF00E5FF).withValues(alpha: 0.3),
            onChanged: _isLoading ? null : (val) => _toggleMaintenanceMode(isMaintenance),
          ),
        );
      },
    );
  }

  Widget _buildQuickActions() {
    final actions = [
      _QuickAction(
        icon: Icons.person_add,
        label: 'Crear Usuario',
        color: const Color(0xFF00E5FF),
        onTap: _showCreateUserSheet,
      ),
      _QuickAction(
        icon: Icons.link,
        label: 'Vincular Padre',
        color: const Color(0xFFCE93D8),
        onTap: _showLinkParentSheet,
      ),
      _QuickAction(
        icon: Icons.lock_reset,
        label: 'Reset Password',
        color: const Color(0xFFFFD54F),
        onTap: _showResetPasswordSheet,
      ),
      _QuickAction(
        icon: Icons.shield_outlined,
        label: 'Auditoría',
        color: const Color(0xFFFF6B35),
        onTap: _showAuditLogs,
      ),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 2.5,
      children: actions.map((a) => _buildActionButton(a)).toList(),
    );
  }

  Widget _buildActionButton(_QuickAction action) {
    return InkWell(
      onTap: action.onTap,
      borderRadius: BorderRadius.circular(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: action.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: action.color.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(action.icon, color: action.color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(action.label,
                      style: TextStyle(color: action.color, fontSize: 13, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentUsers() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('users').orderBy('createdAt', descending: true).limit(5).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
        if (snap.data!.docs.isEmpty) {
          return _buildGlassCard(
            child: const Center(child: Text('Sin usuarios aún.', style: TextStyle(color: Colors.white54))),
          );
        }
        return _buildGlassCard(
          child: Column(
            children: snap.data!.docs.map((doc) {
              final data  = doc.data() as Map<String, dynamic>;
              final role  = RbacService.normalize(data['role'] as String?);
              final name  = data['displayName'] ?? data['full_name'] ?? 'Sin nombre';
              final email = data['email'] ?? '';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: RbacService.getRoleColor(role).withValues(alpha: 0.2),
                      child: Icon(RbacService.getRoleIcon(role), color: RbacService.getRoleColor(role), size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              overflow: TextOverflow.ellipsis),
                          Text(email, style: const TextStyle(color: Colors.white54, fontSize: 11),
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    RbacService.roleBadge(role),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: child,
        ),
      ),
    );
  }

  // ─── Acciones rápidas (bottom sheets) ────────────────────────

  void _showCreateUserSheet() {
    final nameCtrl  = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl  = TextEditingController();
    String role = RbacService.roleCoach;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => _buildSheet(
          title: 'Crear Usuario',
          child: Column(
            children: [
              _sheetField(nameCtrl,  'Nombre Completo',   Icons.person),
              const SizedBox(height: 12),
              _sheetField(emailCtrl, 'Correo Electrónico', Icons.email),
              const SizedBox(height: 12),
              _sheetField(passCtrl,  'Contraseña temporal', Icons.lock, obscure: true),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: role,
                dropdownColor: const Color(0xFF001F3F),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Rol',
                  labelStyle: TextStyle(color: Colors.white54),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                ),
                items: [
                  RbacService.roleAdmin,
                  RbacService.roleCoach,
                  RbacService.roleAthlete,
                  RbacService.roleParent,
                ].map((r) => DropdownMenuItem(
                  value: r,
                  child: Row(children: [
                    Icon(RbacService.getRoleIcon(r), color: RbacService.getRoleColor(r), size: 18),
                    const SizedBox(width: 8),
                    Text(RbacService.getRoleLabel(r)),
                  ]),
                )).toList(),
                onChanged: (v) => setS(() => role = v ?? role),
              ),
              const SizedBox(height: 24),
              _sheetButton('Crear Usuario', const Color(0xFF00E5FF), () async {
                Navigator.pop(ctx);
                // Delega al RBAC management screen completo en web
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Para crear usuarios completos usa el backoffice web.'), backgroundColor: Colors.orange),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _showLinkParentSheet() {
    final parentEmailCtrl  = TextEditingController();
    final athleteEmailCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildSheet(
        title: 'Vincular Padre → Atleta',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ingresa los correos para vincular un padre con su tutorado.',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 16),
            _sheetField(parentEmailCtrl,  'Email del Padre',  Icons.family_restroom),
            const SizedBox(height: 12),
            _sheetField(athleteEmailCtrl, 'Email del Atleta', Icons.directions_run),
            const SizedBox(height: 24),
            _sheetButton('Vincular', const Color(0xFFCE93D8), () async {
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              try {
                // Buscar parentUid por email
                final parentSnap = await _db.collection('users')
                    .where('email', isEqualTo: parentEmailCtrl.text.trim()).limit(1).get();
                final athleteSnap = await _db.collection('users')
                    .where('email', isEqualTo: athleteEmailCtrl.text.trim()).limit(1).get();

                if (parentSnap.docs.isEmpty || athleteSnap.docs.isEmpty) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Usuario no encontrado.'), backgroundColor: Colors.red),
                  );
                  return;
                }

                final parentUid  = parentSnap.docs.first.id;
                final athleteId  = athleteSnap.docs.first.id;

                await FirebaseFunctions.instance
                    .httpsCallable('linkParentToAthlete')
                    .call({'parentUid': parentUid, 'athleteId': athleteId});

                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✅ Vinculación exitosa'), backgroundColor: Colors.green),
                );
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                );
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            }),
          ],
        ),
      ),
    );
  }

  void _showResetPasswordSheet() {
    final emailCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildSheet(
        title: 'Restablecer Contraseña',
        child: Column(
          children: [
            _sheetField(emailCtrl, 'Correo Electrónico', Icons.email),
            const SizedBox(height: 24),
            _sheetButton('Enviar Correo', const Color(0xFFFFD54F), () async {
              Navigator.pop(ctx);
              try {
                await FirebaseAuth.instance.sendPasswordResetEmail(email: emailCtrl.text.trim());
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('✅ Correo enviado a ${emailCtrl.text.trim()}'), backgroundColor: Colors.green),
                );
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                );
              }
            }),
          ],
        ),
      ),
    );
  }

  void _showAuditLogs() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (_, controller) => _buildSheet(
          title: 'Últimos Eventos de Auditoría',
          scrollController: controller,
          child: StreamBuilder<QuerySnapshot>(
            stream: _db.collection('audit_logs').orderBy('timestamp', descending: true).limit(20).snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B35)));
              return Column(
                children: snap.data!.docs.map((doc) {
                  final data   = doc.data() as Map<String, dynamic>;
                  final action = data['action'] ?? '?';
                  final by     = data['performedBy'] ?? '?';
                  final ts     = data['timestamp'];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.shield, color: Color(0xFFFF6B35), size: 18),
                    title: Text(action, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    subtitle: Text('Por: $by', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    trailing: ts != null
                        ? Text(
                            '${(ts as dynamic).toDate().hour.toString().padLeft(2, '0')}:${(ts).toDate().minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(color: Colors.white38, fontSize: 10),
                          )
                        : null,
                  );
                }).toList(),
              );
            },
          ),
        ),
      ),
    );
  }

  // ─── Helpers de UI para bottom sheets ────────────────────────

  Widget _buildSheet({required String title, required Widget child, ScrollController? scrollController}) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
            top: 16, left: 24, right: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF001F3F).withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetField(TextEditingController ctrl, String label, IconData icon, {bool obscure = false}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
      ),
    );
  }

  Widget _sheetButton(String label, Color color, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      ),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String   label;
  final Color    color;
  final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.color, required this.onTap});
}
