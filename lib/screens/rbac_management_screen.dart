import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RbacManagementScreen extends StatefulWidget {
  const RbacManagementScreen({Key? key}) : super(key: key);

  @override
  _RbacManagementScreenState createState() => _RbacManagementScreenState();
}

class _RbacManagementScreenState extends State<RbacManagementScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  int _currentTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF001F3F),
      appBar: AppBar(
        title: const Text('RBAC & Core Config', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTab('Escalación', 0),
                _buildTab('Catálogos (Push)', 1),
                _buildTab('Monitor FCM', 2),
                _buildTab('Remote Config', 3),
                _buildTab('Broadcast', 4),
              ],
            ),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildTab(String title, int index) {
    final isSelected = _currentTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _currentTabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: isSelected ? Colors.cyanAccent : Colors.transparent, width: 3)),
        ),
        child: Text(title, style: TextStyle(color: isSelected ? Colors.cyanAccent : Colors.white70, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildBody() {
    switch (_currentTabIndex) {
      case 0: return _buildRoleEscalationPanel();
      case 1: return _buildCatalogEditor();
      case 2: return _buildFcmMonitor();
      case 3: return _buildRemoteConfigPanel();
      case 4: return _buildBroadcastPanel();
      default: return const SizedBox.shrink();
    }
  }

  // 1. Panel de Escalación (RBAC)
  Widget _buildRoleEscalationPanel() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final users = snapshot.data!.docs;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final data = users[index].data() as Map<String, dynamic>;
            final role = data['role'] ?? 'user';
            final email = data['email'] ?? 'Sin correo';
            return Card(
              color: Colors.white.withOpacity(0.05),
              child: ListTile(
                title: Text(email, style: const TextStyle(color: Colors.white)),
                subtitle: Text('Rol: $role', style: const TextStyle(color: Colors.white70)),
                trailing: DropdownButton<String>(
                  value: ['admin', 'coach', 'parent', 'user'].contains(role) ? role : 'user',
                  dropdownColor: const Color(0xFF003F87),
                  style: const TextStyle(color: Colors.cyanAccent),
                  items: ['admin', 'coach', 'parent', 'user'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (newRole) {
                    if (newRole != null) {
                      _db.collection('users').doc(users[index].id).update({'role': newRole});
                    }
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 2. Editor de Catálogos (Plantillas Push)
  Widget _buildCatalogEditor() {
    return FutureBuilder<DocumentSnapshot>(
      future: _db.collection('app_config').doc('notification_templates').get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (!snapshot.data!.exists) return const Center(child: Text('Plantillas no inicializadas', style: TextStyle(color: Colors.white)));
        
        final data = snapshot.data!.data() as Map<String, dynamic>;
        
        return ListView(
          padding: const EdgeInsets.all(16),
          children: data.entries.map((e) {
            final controller = TextEditingController(text: e.value.toString());
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: TextField(
                controller: controller,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: e.key.toUpperCase(),
                  labelStyle: const TextStyle(color: Colors.cyanAccent),
                  enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent)),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.save, color: Colors.cyanAccent),
                    onPressed: () {
                      _db.collection('app_config').doc('notification_templates').update({e.key: controller.text});
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plantilla actualizada')));
                    },
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // 3. Monitor de Dispositivos (FCM Tokens)
  Widget _buildFcmMonitor() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('users').where('fcmToken', isNull: false).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final users = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data.containsKey('fcmToken') && data['fcmToken'].toString().isNotEmpty;
        }).toList();
        
        if (users.isEmpty) return const Center(child: Text('Ningún dispositivo registrado con FCM', style: TextStyle(color: Colors.white70)));

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final data = users[index].data() as Map<String, dynamic>;
            final email = data['email'] ?? 'Usuario Desconocido';
            final token = data['fcmToken'];
            return Card(
              color: Colors.white.withOpacity(0.05),
              child: ListTile(
                leading: const Icon(Icons.phone_android, color: Colors.greenAccent),
                title: Text(email, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('FCM: ${token.toString().substring(0, 15)}...', style: const TextStyle(color: Colors.white54)),
                trailing: const Icon(Icons.check_circle, color: Colors.greenAccent),
              ),
            );
          },
        );
      },
    );
  }

  // 4. Remote Config (Maintenance Mode & QR TTL)
  Widget _buildRemoteConfigPanel() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('app_config').doc('global_settings').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final data = snapshot.data!.exists ? snapshot.data!.data() as Map<String, dynamic> : {};
        final bool isMaintenance = data['maintenance_mode'] ?? false;
        final int qrTtl = data['qr_rotation_time'] ?? 45;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SwitchListTile(
              title: const Text('Maintenance Mode (Global)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text('Bloquea el acceso a todos los usuarios excepto admins.', style: TextStyle(color: Colors.white54)),
              value: isMaintenance,
              activeColor: Colors.redAccent,
              onChanged: (val) {
                _db.collection('app_config').doc('global_settings').set({'maintenance_mode': val}, SetOptions(merge: true));
              },
            ),
            const Divider(color: Colors.white24),
            ListTile(
              title: const Text('QR Rotation TTL (segundos)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text('Actual: ${qrTtl}s', style: const TextStyle(color: Colors.white54)),
              trailing: DropdownButton<int>(
                value: [15, 30, 45, 60].contains(qrTtl) ? qrTtl : 45,
                dropdownColor: const Color(0xFF003F87),
                style: const TextStyle(color: Colors.cyanAccent),
                items: [15, 30, 45, 60].map((int value) {
                  return DropdownMenuItem<int>(
                    value: value,
                    child: Text('${value}s'),
                  );
                }).toList(),
                onChanged: (newTtl) {
                  if (newTtl != null) {
                    _db.collection('app_config').doc('global_settings').set({'qr_rotation_time': newTtl}, SetOptions(merge: true));
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // 5. Emergency Broadcast — con rate-limit cliente + servidor + doble confirmación
  final TextEditingController _broadcastController = TextEditingController();
  final TextEditingController _broadcastTitleController =
      TextEditingController(text: 'Aviso Importante');
  bool  _isBroadcasting    = false;
  bool  _broadcastCooling  = false;   // cliente: bloquea el botón durante el cooldown
  int   _cooldownRemaining = 0;       // segundos restantes mostrados en el botón
  Timer? _cooldownTimer;

  static const int _clientCooldownSecs = 300; // 5 min — espejo del servidor

  /// Limpia texto antes de enviarlo como payload de notificación push.
  /// Espejo del sanitizeForPush() del backend — protección en capas.
  String _sanitizeForPush(String raw, {int maxLen = 500}) {
    return raw
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
        .replaceAll(RegExp('[​‌‍⁠﻿]'), '')
        .replaceAll(RegExp(r'<[^>]{0,500}>'), '')
        .replaceAll(RegExp(r'javascript\s*:', caseSensitive: false), '')
        .replaceAll(RegExp(r'data\s*:[^,]{0,100},', caseSensitive: false), '')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .trim()
        .substring(0, raw.trim().length.clamp(0, maxLen));
  }

  void _startClientCooldown() {
    setState(() {
      _broadcastCooling  = true;
      _cooldownRemaining = _clientCooldownSecs;
    });
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _cooldownRemaining--;
        if (_cooldownRemaining <= 0) {
          _broadcastCooling = false;
          t.cancel();
        }
      });
    });
  }

  Future<void> _emitBroadcast() async {
    // Verificación de rol en cliente fue delegada a AuthGateway y re-validada en servidor.
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final message = _sanitizeForPush(_broadcastController.text, maxLen: 500);
    final title   = _sanitizeForPush(_broadcastTitleController.text, maxLen: 100);
    if (message.isEmpty) return;

    // Doble confirmación — previene tap accidental.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF001F3F),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Text('¿Confirmar alerta masiva?', style: TextStyle(color: Colors.white)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Se enviará a TODOS los representantes registrados:', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
            child: Text('"$message"', style: const TextStyle(color: Colors.orangeAccent, fontStyle: FontStyle.italic)),
          ),
          const SizedBox(height: 12),
          const Text('Esta acción no se puede deshacer.', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SÍ, EMITIR'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isBroadcasting = true);
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('broadcastEmergencyPush');
      final result = await fn.call({'message': message, 'title': title});
      final data = result.data as Map<String, dynamic>;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Alerta enviada: ${data['sent']} exitosos, ${data['failed']} fallidos.'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ));
        _broadcastController.clear();
        _startClientCooldown();
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message ?? 'Error al emitir alerta.'),
          backgroundColor: Colors.redAccent,
        ));
      }
    } finally {
      if (mounted) setState(() => _isBroadcasting = false);
    }
  }

  Widget _buildBroadcastPanel() {
    final coolMins = _cooldownRemaining ~/ 60;
    final coolSecs = _cooldownRemaining  % 60;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.campaign, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Emergency Broadcast',
                style: TextStyle(color: Colors.redAccent, fontSize: 20, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 6),
          const Text(
            'Envía una notificación Push masiva a todos los representantes. '
            'Límite: 1 broadcast cada 5 minutos por institución.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _broadcastTitleController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Título',
              labelStyle: TextStyle(color: Colors.orange),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.orange)),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _broadcastController,
            maxLines: 4,
            maxLength: 500,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Mensaje de Emergencia',
              labelStyle: TextStyle(color: Colors.orange),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.orange)),
              counterStyle: TextStyle(color: Colors.white38),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: ElevatedButton.icon(
              onPressed: (_isBroadcasting || _broadcastCooling) ? null : _emitBroadcast,
              icon: _isBroadcasting
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.campaign),
              label: Text(
                _isBroadcasting
                    ? 'Enviando...'
                    : _broadcastCooling
                        ? 'Cooldown ${coolMins}m ${coolSecs.toString().padLeft(2, '0')}s'
                        : 'EMITIR ALERTA MASIVA',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _broadcastCooling ? Colors.grey[700] : Colors.redAccent,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ),
          if (_broadcastCooling) ...[
            const SizedBox(height: 12),
            Center(
              child: Text(
                'Próximo broadcast disponible en ${coolMins}m ${coolSecs.toString().padLeft(2, '0')}s',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _broadcastController.dispose();
    _broadcastTitleController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }
}
