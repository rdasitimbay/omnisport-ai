import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../services/rbac_service.dart';

class RbacManagementScreen extends StatefulWidget {
  const RbacManagementScreen({Key? key}) : super(key: key);

  @override
  _RbacManagementScreenState createState() => _RbacManagementScreenState();
}

class _RbacManagementScreenState extends State<RbacManagementScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  int _currentTabIndex = 0;

  // Catalog controllers are cached to avoid leaks from FutureBuilder rebuilds
  final Map<String, TextEditingController> _catalogControllers = {};

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
                _buildTab('Vinculación Padre', 5),
              ],
            ),
          ),
        ),
      ),
      body: _buildBody(),
      floatingActionButton: _currentTabIndex == 0
          ? FloatingActionButton(
              onPressed: _showCreateUserDialog,
              backgroundColor: const Color(0xFF00E5FF),
              child: const Icon(Icons.person_add, color: Colors.black),
              tooltip: 'Crear Usuario',
            )
          : null,
    );
  }

  Future<void> _showCreateUserDialog() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String selectedRole = 'coach';
    String selectedDiscipline = 'voleibol';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateModal) {
          return AlertDialog(
            backgroundColor: const Color(0xFF003F87),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Crear Nuevo Usuario', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Nombre Completo', labelStyle: TextStyle(color: Colors.cyanAccent), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent))),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Correo Electrónico', labelStyle: TextStyle(color: Colors.cyanAccent), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent))),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passCtrl,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Contraseña temporal', labelStyle: TextStyle(color: Colors.cyanAccent), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent))),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedRole,
                    dropdownColor: const Color(0xFF003F87),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Rol Inicial', labelStyle: TextStyle(color: Colors.cyanAccent), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent))),
                    items: const [
                      DropdownMenuItem(value: 'coach',   child: Text('COACH')),
                      DropdownMenuItem(value: 'athlete', child: Text('ATHLETE')),
                      DropdownMenuItem(value: 'parent',  child: Text('PARENT')),
                      DropdownMenuItem(value: 'admin',   child: Text('ADMIN')),
                    ],
                    onChanged: (v) { 
                      if (v != null) setStateModal(() => selectedRole = v); 
                    },
                  ),
                  if (selectedRole == 'coach' || selectedRole == 'athlete') ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedDiscipline,
                      dropdownColor: const Color(0xFF003F87),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Disciplina Deportiva', labelStyle: TextStyle(color: Colors.cyanAccent), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent))),
                      items: const [
                        DropdownMenuItem(value: 'voleibol', child: Text('Voleibol 🏐')),
                        DropdownMenuItem(value: 'basquetbol', child: Text('Básquetbol 🏀')),
                        DropdownMenuItem(value: 'futbol', child: Text('Fútbol ⚽')),
                      ],
                      onChanged: (v) { 
                        if (v != null) setStateModal(() => selectedDiscipline = v); 
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Crear', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold))),
            ],
          );
        }
      ),
    );

    if (result == true) {
      final name = nameCtrl.text.trim();
      final email = emailCtrl.text.trim();
      final pass = passCtrl.text.trim();
      if (name.isEmpty || email.isEmpty || pass.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor completa todos los campos')));
        return;
      }

      showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.cyanAccent)));

      try {
        final appName = 'SecondaryApp_${DateTime.now().millisecondsSinceEpoch}';
        FirebaseApp secondaryApp = await Firebase.initializeApp(
          name: appName,
          options: Firebase.app().options,
        );
        UserCredential credential = await FirebaseAuth.instanceFor(app: secondaryApp).createUserWithEmailAndPassword(
          email: email,
          password: pass,
        );

        final uid = credential.user!.uid;

        // Guardar metadata en users
        await _db.collection('users').doc(uid).set({
          'email': email,
          'displayName': name,
          'role': selectedRole,
          'disciplina': (selectedRole == 'coach' || selectedRole == 'athlete') ? selectedDiscipline : null,
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
          'institutionId': 'inst_piloto_stresstest', 
        });

        // Crear registro en athletes si aplica
        if (selectedRole == 'athlete') {
          final athleteRef = _db.collection('athletes').doc(uid);
          await athleteRef.set({
            'full_name': name,
            'ownerInstitutionId': 'inst_piloto_stresstest',
            'teamOrCategory': 'General',
            'paymentStatus': 'Pago Pendiente',
            'status': 'Activo',
            'photoUrl': '',
            'disciplina': selectedDiscipline,
            'consent_timestamp': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
          });
          await athleteRef.collection('sport_details').doc(selectedDiscipline).set({
            'sport_type': selectedDiscipline,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        await secondaryApp.delete();
        if (mounted) {
          Navigator.pop(context); 
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Usuario $name creado exitosamente'), backgroundColor: Colors.green));
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); 
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al crear usuario: $e'), backgroundColor: Colors.red));
        }
      }
    }
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
      case 5: return _buildParentLinkingPanel();
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
            final role = RbacService.normalize(data['role'] as String?);
            final email = data['email'] ?? 'Sin correo';
            final isActive = data['isActive'] ?? true;
            final displayName = data['displayName'] ?? data['full_name'] ?? data['name'] ?? 'Sin nombre';
            
            return Card(
              color: Colors.white.withValues(alpha: 0.05),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: RbacService.getRoleColor(role).withValues(alpha: 0.15),
                  child: Icon(RbacService.getRoleIcon(role), color: RbacService.getRoleColor(role), size: 20),
                ),
                title: Row(
                  children: [
                    Expanded(child: Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 8),
                    RbacService.roleBadge(role),
                  ],
                ),
                subtitle: Text('$email | Estado: ${isActive ? "Activo" : "Inactivo"}', style: const TextStyle(color: Colors.white70)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: isActive,
                      activeColor: Colors.greenAccent,
                      inactiveThumbColor: Colors.redAccent,
                      inactiveTrackColor: Colors.redAccent.withValues(alpha: 0.3),
                      onChanged: (val) {
                        _db.collection('users').doc(users[index].id).update({'isActive': val});
                      },
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: [RbacService.roleAdmin, RbacService.roleCoach, RbacService.roleAthlete, RbacService.roleParent].contains(role) ? role : RbacService.roleAthlete,
                      dropdownColor: const Color(0xFF003F87),
                      style: const TextStyle(color: Colors.cyanAccent),
                      items: [RbacService.roleAdmin, RbacService.roleCoach, RbacService.roleAthlete, RbacService.roleParent].map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(RbacService.getRoleLabel(value).toUpperCase()),
                        );
                      }).toList(),
                      onChanged: (newRole) async {
                        if (newRole != null) {
                          final uid = users[index].id;
                          await _db.collection('users').doc(uid).update({'role': newRole});
                          
                          if (newRole == 'athlete') {
                            final athleteRef = _db.collection('athletes').doc(uid);
                            final athleteSnap = await athleteRef.get();
                            if (!athleteSnap.exists) {
                              await athleteRef.set({
                                'full_name': displayName == 'Sin nombre' ? 'Nuevo Atleta' : displayName,
                                'ownerInstitutionId': data['institutionId'] ?? 'inst_piloto_stresstest',
                                'teamOrCategory': 'General',
                                'paymentStatus': 'Pago Pendiente',
                                'status': 'Activo',
                                'photoUrl': '',
                                'disciplina': 'voleibol',
                                'consent_timestamp': FieldValue.serverTimestamp(),
                                'createdAt': FieldValue.serverTimestamp(),
                              });
                              // Also write to sport_details subcollection
                              final sportRef = athleteRef.collection('sport_details').doc('voleibol');
                              await sportRef.set({
                                'sport_type': 'voleibol',
                                'updatedAt': FieldValue.serverTimestamp(),
                              }, SetOptions(merge: true));
                            }
                          }
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.cyanAccent),
                      tooltip: 'Editar Datos',
                      onPressed: () async {
                        final nameCtrl = TextEditingController(text: displayName == 'Sin nombre' ? '' : displayName);
                        final emailCtrl = TextEditingController(text: email == 'Sin correo' ? '' : email);
                        final phoneCtrl = TextEditingController(text: data['phone'] ?? '');
                        String selectedDiscipline = data['disciplina'] ?? 'voleibol';

                        final updated = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: const Color(0xFF003F87),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            title: const Text('Editar Usuario', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            content: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                    controller: nameCtrl,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: const InputDecoration(
                                      labelText: 'Nombre Completo',
                                      labelStyle: TextStyle(color: Colors.cyanAccent),
                                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent)),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: emailCtrl,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: const InputDecoration(
                                      labelText: 'Correo Electrónico',
                                      labelStyle: TextStyle(color: Colors.cyanAccent),
                                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent)),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: phoneCtrl,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: const InputDecoration(
                                      labelText: 'Teléfono',
                                      labelStyle: TextStyle(color: Colors.cyanAccent),
                                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent)),
                                    ),
                                  ),
                                  if (role == 'athlete') ...[
                                    const SizedBox(height: 16),
                                    DropdownButtonFormField<String>(
                                      value: selectedDiscipline,
                                      dropdownColor: const Color(0xFF003F87),
                                      style: const TextStyle(color: Colors.white),
                                      decoration: const InputDecoration(
                                        labelText: 'Disciplina Deportiva Primaria',
                                        labelStyle: TextStyle(color: Colors.cyanAccent),
                                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent)),
                                      ),
                                      items: const [
                                        DropdownMenuItem(value: 'voleibol', child: Text('Voleibol 🏐')),
                                        DropdownMenuItem(value: 'basquetbol', child: Text('Básquetbol 🏀')),
                                        DropdownMenuItem(value: 'futbol', child: Text('Fútbol ⚽')),
                                      ],
                                      onChanged: (v) {
                                        if (v != null) selectedDiscipline = v;
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Guardar', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        );

                        if (updated == true) {
                          try {
                            final uid = users[index].id;
                            final newName = nameCtrl.text.trim();
                            final newEmail = emailCtrl.text.trim();
                            final newPhone = phoneCtrl.text.trim();

                            final Map<String, dynamic> updates = {
                              'displayName': newName,
                              'full_name': newName,
                              'email': newEmail,
                              'phone': newPhone,
                            };
                            if (role == 'athlete') {
                              updates['disciplina'] = selectedDiscipline;
                            }

                            await _db.collection('users').doc(uid).update(updates);

                            if (role == 'athlete') {
                              final athleteRef = _db.collection('athletes').doc(uid);
                              final athleteSnap = await athleteRef.get();
                              if (athleteSnap.exists) {
                                await athleteRef.update({
                                  'full_name': newName,
                                  'phone': newPhone,
                                  'disciplina': selectedDiscipline,
                                });
                              } else {
                                await athleteRef.set({
                                  'full_name': newName.isEmpty ? 'Nuevo Atleta' : newName,
                                  'ownerInstitutionId': data['institutionId'] ?? 'inst_piloto_stresstest',
                                  'teamOrCategory': 'General',
                                  'paymentStatus': 'Pago Pendiente',
                                  'status': 'Activo',
                                  'photoUrl': '',
                                  'disciplina': selectedDiscipline,
                                  'consent_timestamp': FieldValue.serverTimestamp(),
                                  'createdAt': FieldValue.serverTimestamp(),
                                });
                              }
                              // Also write to sport_details subcollection
                              final sportRef = athleteRef.collection('sport_details').doc(selectedDiscipline);
                              await sportRef.set({
                                'sport_type': selectedDiscipline,
                                'updatedAt': FieldValue.serverTimestamp(),
                              }, SetOptions(merge: true));
                            }

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Usuario actualizado correctamente'), backgroundColor: Colors.green),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error al actualizar: $e'), backgroundColor: Colors.redAccent),
                              );
                            }
                          }
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.lock_reset, color: Colors.orangeAccent),
                      tooltip: 'Restablecer Contraseña',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: const Color(0xFF003F87),
                            title: const Text('Restablecer Contraseña', style: TextStyle(color: Colors.white)),
                            content: Text('¿Enviar correo de restablecimiento a $email?', style: const TextStyle(color: Colors.white70)),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Enviar', style: TextStyle(color: Colors.orangeAccent)),
                              ),
                            ],
                          ),
                        );
                        
                        if (confirm == true) {
                          try {
                            await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Correo enviado a $email'), backgroundColor: Colors.green),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
                              );
                            }
                          }
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      tooltip: 'Eliminar Usuario',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: const Color(0xFF003F87),
                            title: const Text('Eliminar Usuario', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                            content: Text('¿Estás seguro de que deseas eliminar permanentemente a $email de la base de datos de Auth? Esta acción no se puede deshacer.', style: const TextStyle(color: Colors.white70)),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
                              ),
                            ],
                          ),
                        );
                        
                        if (confirm == true) {
                          try {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Eliminando...'), backgroundColor: Colors.orange),
                            );
                            await FirebaseFunctions.instance.httpsCallable('deleteUserAccount').call({
                              'uid': users[index].id,
                            });
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Usuario $email eliminado'), backgroundColor: Colors.green),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
                              );
                            }
                          }
                        }
                      },
                    ),
                  ],
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
            // Reuse cached controller or create new one — prevents leaks on rebuild
            final controller = _catalogControllers.putIfAbsent(
              e.key, () => TextEditingController(text: e.value.toString()),
            );
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
              color: Colors.white.withValues(alpha: 0.05),
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
      final result = await FirebaseFunctions.instance
          .httpsCallable('broadcastEmergencyPush')
          .call({'message': message, 'title': title});
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
    // Dispose all catalog controllers
    for (final c in _catalogControllers.values) { c.dispose(); }
    _catalogControllers.clear();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  // =========================================================================
  // 6. Panel de Vinculación Padre → Atleta (USR-ROL: parent)
  // Art. 26 LOPDP — Solo admins establecen la relación jurídica de tutela.
  // =========================================================================
  final TextEditingController _parentEmailCtrl  = TextEditingController();
  final TextEditingController _athleteEmailCtrl = TextEditingController();
  bool _isLinking = false;

  Widget _buildParentLinkingPanel() {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _db.collection('parent_children').snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Error al cargar vinculaciones:\n${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                );
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: Colors.cyanAccent));
              if (snap.data!.docs.isEmpty) {
                return const Center(
                  child: Text(
                    'No hay vinculaciones registradas.\nUsa el formulario de abajo para crear la primera.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ...snap.data!.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final List<dynamic> children = data['childrenIds'] ?? [];
                    return Card(
                      color: Colors.white.withValues(alpha: 0.05),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ExpansionTile(
                        leading: Icon(RbacService.getRoleIcon(RbacService.roleParent),
                            color: RbacService.getRoleColor(RbacService.roleParent)),
                        title: Text('Padre: ${doc.id.substring(0, 8)}...',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text('${children.length} tutorado(s)',
                            style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        iconColor: Colors.white54,
                        collapsedIconColor: Colors.white38,
                        children: [
                          ...children.map((id) => ListTile(
                            dense: true,
                            leading: Icon(RbacService.getRoleIcon(RbacService.roleAthlete),
                                color: RbacService.getRoleColor(RbacService.roleAthlete), size: 18),
                            title: Text(id.toString(),
                                style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            trailing: IconButton(
                              icon: const Icon(Icons.link_off, color: Colors.redAccent, size: 18),
                              tooltip: 'Desvincular',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: const Color(0xFF003F87),
                                    title: const Text('Desvincular', style: TextStyle(color: Colors.redAccent)),
                                    content: Text('\u00bfDesvincular atleta $id de este padre?',
                                        style: const TextStyle(color: Colors.white70)),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false),
                                          child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
                                      TextButton(onPressed: () => Navigator.pop(ctx, true),
                                          child: const Text('Desvincular', style: TextStyle(color: Colors.redAccent))),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await _db.collection('parent_children').doc(doc.id).update({
                                    'childrenIds': FieldValue.arrayRemove([id]),
                                  });
                                  await _db.collection('users').doc(doc.id).update({
                                    'childrenIds': FieldValue.arrayRemove([id]),
                                  });
                                }
                              },
                            ),
                          )),
                        ],
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        ),
        // Formulario de vinculación
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('NUEVA VINCULACIÓN',
                  style: TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _parentEmailCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Email del Padre',
                      labelStyle: TextStyle(color: Colors.white54, fontSize: 12),
                      prefixIcon: Icon(Icons.family_restroom, color: Colors.white38, size: 18),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _athleteEmailCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Email del Atleta',
                      labelStyle: TextStyle(color: Colors.white54, fontSize: 12),
                      prefixIcon: Icon(Icons.directions_run, color: Colors.white38, size: 18),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isLinking ? null : _linkParentToAthlete,
                  icon: _isLinking
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                      : const Icon(Icons.link, size: 16),
                  label: const Text('Vincular'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFCE93D8),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _linkParentToAthlete() async {
    final parentEmail  = _parentEmailCtrl.text.trim();
    final athleteEmail = _athleteEmailCtrl.text.trim();
    if (parentEmail.isEmpty || athleteEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa ambos campos de email.')),
      );
      return;
    }
    setState(() => _isLinking = true);
    try {
      // Buscar UIDs por email
      final parentSnap  = await _db.collection('users').where('email', isEqualTo: parentEmail).limit(1).get();
      final athleteSnap = await _db.collection('users').where('email', isEqualTo: athleteEmail).limit(1).get();

      if (parentSnap.docs.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Padre no encontrado: $parentEmail'), backgroundColor: Colors.red),
        );
        return;
      }
      if (athleteSnap.docs.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Atleta no encontrado: $athleteEmail'), backgroundColor: Colors.red),
        );
        return;
      }

      final parentUid = parentSnap.docs.first.id;
      final athleteId = athleteSnap.docs.first.id;

      // Llamar Cloud Function linkParentToAthlete (Admin SDK escribe en parent_children + users)
      await FirebaseFunctions.instance
          .httpsCallable('linkParentToAthlete')
          .call({'parentUid': parentUid, 'athleteId': athleteId});

      if (mounted) {
        _parentEmailCtrl.clear();
        _athleteEmailCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Vinculación registrada exitosamente'), backgroundColor: Colors.green),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.message}'), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLinking = false);
    }
  }
}
