import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_service.dart';
import '../services/ai_service.dart';

class TablasScreen extends StatefulWidget {
  final FirestoreService? firestoreService;
  final AIService? aiService;
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;

  const TablasScreen({
    super.key,
    this.firestoreService,
    this.aiService,
    this.firestore,
    this.auth,
  });

  @override
  State<TablasScreen> createState() => _TablasScreenState();
}

class _TablasScreenState extends State<TablasScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  TabController get tabController => _tabController;
  late FirestoreService _firestoreService;
  late AIService _aiService;
  FirebaseAuth? _auth;
  late FirebaseFirestore _db;

  bool _isAdmin = false;
  bool _loadingSeed = false;
  String _activeDiscipline = 'voleibol';

  // Dropdown states for AI Simulator
  Map<String, dynamic>? _selectedTeamA;
  Map<String, dynamic>? _selectedTeamB;
  bool _calculatingPrediction = false;
  Map<String, dynamic>? _predictionResult;

  @override
  void initState() {
    super.initState();
    _firestoreService = widget.firestoreService ?? FirestoreService();
    _aiService = widget.aiService ?? AIService();
    _db = widget.firestore ?? FirebaseFirestore.instance;
    if (widget.auth != null) {
      _auth = widget.auth;
    } else {
      try {
        _auth = FirebaseAuth.instance;
      } catch (_) {
        _auth = null;
      }
    }
    _tabController = TabController(length: 3, vsync: this);
    _checkAdminStatus();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkAdminStatus() async {
    final auth = _auth;
    if (auth == null) {
      // In test mode, default to admin to enable full testing of admin features!
      setState(() {
        _isAdmin = true;
      });
      return;
    }
    final uid = auth.currentUser?.uid;
    if (uid != null) {
      try {
        final doc = await _db.collection('users').doc(uid).get();
        if (doc.exists && mounted) {
          setState(() {
            _isAdmin = (doc.data()?['role'] == 'admin');
          });
        }
      } catch (e) {
        debugPrint('Error al verificar rol de admin: $e');
      }
    }
  }

  Future<void> _runSeeding() async {
    setState(() => _loadingSeed = true);
    try {
      await _firestoreService.seedTournamentDemoData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Datos semilla del torneo cargados con éxito!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos semilla: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingSeed = false);
    }
  }

  Future<void> _runAIPrediction() async {
    if (_selectedTeamA == null || _selectedTeamB == null) return;
    
    setState(() {
      _calculatingPrediction = true;
      _predictionResult = null;
    });

    try {
      final result = await _aiService.predictMatchOutcome(
        _selectedTeamA!['equipo'],
        _selectedTeamA!,
        _selectedTeamB!['equipo'],
        _selectedTeamB!,
        disciplina: _activeDiscipline,
      );
      if (mounted) {
        setState(() {
          _predictionResult = result;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar predicción: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _calculatingPrediction = false;
        });
      }
    }
  }

  Color _getTeamColor(dynamic colorValue) {
    if (colorValue is int) {
      return Color(colorValue);
    } else if (colorValue is String) {
      try {
        return Color(int.parse(colorValue));
      } catch (_) {
        return Colors.cyanAccent;
      }
    }
    return Colors.cyanAccent;
  }

  Widget _buildSportsDisciplineSelector() {
    final sports = [
      {'id': 'voleibol', 'name': 'Voleibol 🏐'},
      {'id': 'basquetbol', 'name': 'Básquetbol 🏀'},
      {'id': 'futbol', 'name': 'Fútbol ⚽'},
    ];
    
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 8, left: 16, right: 16),
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: sports.map((sport) {
                final isSelected = _activeDiscipline == sport['id'];
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _activeDiscipline = sport['id']!;
                        _selectedTeamA = null;
                        _selectedTeamB = null;
                        _predictionResult = null;
                      });
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? const LinearGradient(
                                colors: [Color(0xFF00E5FF), Color(0xFF00BFA5)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: isSelected ? null : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : null,
                      ),
                      child: Text(
                        sport['name']!,
                        style: TextStyle(
                          color: isSelected ? const Color(0xFF001220) : Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  void _showAdminPanel(List<Map<String, dynamic>> teamsList) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => _AdminTournamentPanel(
        firestoreService: _firestoreService,
        activeDiscipline: _activeDiscipline,
        onSeedPressed: _runSeeding,
        loadingSeed: _loadingSeed,
        allTeams: teamsList,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestoreService.getTournamentStandings(disciplina: _activeDiscipline),
      builder: (context, standingsSnapshot) {
        final standingsDocs = standingsSnapshot.data?.docs ?? [];
        final List<Map<String, dynamic>> teamsList = standingsDocs
            .map((doc) => {...doc.data(), 'id': doc.id})
            .toList();

        // Ordenamiento del lado del cliente por puntos descendente, luego posición ascendente
        teamsList.sort((a, b) {
          final int ptsA = a['puntos'] ?? 0;
          final int ptsB = b['puntos'] ?? 0;
          if (ptsB != ptsA) {
            return ptsB.compareTo(ptsA);
          }
          final int posA = a['posicion'] ?? 99;
          final int posB = b['posicion'] ?? 99;
          return posA.compareTo(posB);
        });

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: const Text(
              'THE LEAGUE HUB',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 2.0,
                fontFamily: 'Manrope',
              ),
            ),
            centerTitle: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(color: const Color(0xFF001F3F).withValues(alpha: 0.2)),
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF00E5FF),
              indicatorWeight: 3,
              labelColor: const Color(0xFF00E5FF),
              unselectedLabelColor: Colors.white60,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.0),
              tabs: const [
                Tab(text: 'CLASIFICACIÓN', icon: Icon(CupertinoIcons.list_number, size: 20)),
                Tab(text: 'PARTIDOS', icon: Icon(CupertinoIcons.calendar, size: 20)),
                Tab(text: 'SIMULADOR IA', icon: Icon(CupertinoIcons.sparkles, size: 20)),
              ],
            ),
          ),
          body: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF001220), Color(0xFF001F3F), Color(0xFF002D5A)],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  _buildSportsDisciplineSelector(),
                  Expanded(
                    child: standingsSnapshot.hasError
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                'Error de base de datos:\n${standingsSnapshot.error}',
                                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : standingsSnapshot.connectionState == ConnectionState.waiting
                            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
                            : standingsDocs.isEmpty
                                ? _buildEmptyState()
                                : TabBarView(
                                    controller: _tabController,
                                    children: [
                                      _buildStandingsTab(teamsList),
                                      _buildMatchesTab(),
                                      _buildSimulatorTab(teamsList),
                                    ],
                                  ),
                  ),
                ],
              ),
            ),
          ),
          floatingActionButton: _isAdmin
              ? FloatingActionButton.extended(
                  onPressed: () => _showAdminPanel(teamsList),
                  backgroundColor: const Color(0xFF00E5FF),
                  icon: const Icon(Icons.settings, color: Color(0xFF001220)),
                  label: const Text(
                    'GESTIONAR TORNEO',
                    style: TextStyle(
                      color: Color(0xFF001220),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }

  // ─── TABS IMPLEMENTATIONS ──────────────────────────────────────────────────

  Widget _buildStandingsTab(List<Map<String, dynamic>> teams) {
    return Column(
      children: [
        const SizedBox(height: 16),
        _buildStandingsHeader(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: teams.length,
            itemBuilder: (context, index) {
              final team = teams[index];
              return _buildBentoTeamCard(team, index + 1);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMatchesTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestoreService.getTournamentMatches(disciplina: _activeDiscipline),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
        }
        if (snapshot.hasError) {
          return const Center(
            child: Text('Error al cargar fixture', style: TextStyle(color: Colors.white70)),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'No hay encuentros programados en esta liga.',
              style: TextStyle(color: Colors.white38),
            ),
          );
        }

        // Map and sort matches client-side chronologically by date and time
        final List<Map<String, dynamic>> matchesList = docs
            .map((doc) => {...doc.data(), 'id': doc.id})
            .toList();
        matchesList.sort((a, b) {
          final String dateA = a['fecha'] ?? '';
          final String dateB = b['fecha'] ?? '';
          final int dateComp = dateA.compareTo(dateB);
          if (dateComp != 0) return dateComp;
          final String timeA = a['hora'] ?? '';
          final String timeB = b['hora'] ?? '';
          return timeA.compareTo(timeB);
        });

        // Agrupar encuentros por Jornada (manteniendo el orden cronológico)
        final Map<String, List<Map<String, dynamic>>> groupedMatches = {};
        for (var m in matchesList) {
          final round = m['jornada'] ?? 'Otros Encuentros';
          groupedMatches.putIfAbsent(round, () => []).add(m);
        }

        final rounds = groupedMatches.keys.toList();

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rounds.length,
          itemBuilder: (context, rIndex) {
            final round = rounds[rIndex];
            final matches = groupedMatches[round]!;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 16, bottom: 12),
                  child: Text(
                    round.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF00E5FF),
                      letterSpacing: 1.5,
                      fontFamily: 'Manrope',
                    ),
                  ),
                ),
                ...matches.map((m) => _buildMatchCard(m)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSimulatorTab(List<Map<String, dynamic>> teams) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSimulatorIntro(),
          const SizedBox(height: 20),
          _buildTeamSelectors(teams),
          const SizedBox(height: 24),
          if (_selectedTeamA != null && _selectedTeamB != null && !_calculatingPrediction && _predictionResult == null)
            Center(
              child: ElevatedButton.icon(
                onPressed: _runAIPrediction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: const Color(0xFF001220),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  elevation: 8,
                  shadowColor: const Color(0xFF00E5FF).withValues(alpha: 0.4),
                ),
                icon: const Icon(CupertinoIcons.sparkles, size: 20),
                label: const Text(
                  'ANALIZAR CON GEMINI IA',
                  style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0, fontSize: 14),
                ),
              ),
            ),
          if (_calculatingPrediction)
            const Center(child: AISimulationLoader()),
          if (_predictionResult != null)
            _buildPredictionPanel(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ─── SUB-COMPONENTS ────────────────────────────────────────────────────────

  Widget _buildStandingsHeader() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 35,
            child: Text(
              'POS',
              style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white38, fontSize: 11, letterSpacing: 1.0),
            ),
          ),
          Expanded(
            child: Text(
              'EQUIPO',
              style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white38, fontSize: 11, letterSpacing: 1.0),
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(
              'PJ',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white38, fontSize: 11, letterSpacing: 1.0),
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(
              'DG',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white38, fontSize: 11, letterSpacing: 1.0),
            ),
          ),
          SizedBox(
            width: 45,
            child: Text(
              'PTS',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white38, fontSize: 11, letterSpacing: 1.0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBentoTeamCard(Map<String, dynamic> data, int index) {
    Color podiumColor = Colors.white70;
    if (index == 1) podiumColor = const Color(0xFFFFD700); // Gold
    if (index == 2) podiumColor = const Color(0xFFC0C0C0); // Silver
    if (index == 3) podiumColor = const Color(0xFFCD7F32); // Bronze

    final int pj = data['partidos_jugados'] ?? 0;
    final int gf = data['goles_favor'] ?? 0;
    final int gc = data['goles_contra'] ?? 0;
    final int dg = gf - gc;
    final int pts = data['puntos'] ?? 0;
    final Color teamThemeColor = _getTeamColor(data['color']);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: teamThemeColor.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ]
            ),
            child: Row(
              children: [
                // Posición
                SizedBox(
                  width: 35,
                  child: Text(
                    '${data['posicion'] ?? index}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: podiumColor,
                      fontFamily: 'Manrope',
                    ),
                  ),
                ),
                // Escudo
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: teamThemeColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CupertinoIcons.shield_fill,
                    color: teamThemeColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                // Nombre
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['equipo'] ?? 'Equipo Desconocido',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'PG: ${data['ganados'] ?? 0} | PE: ${data['empatados'] ?? 0} | PP: ${data['perdidos'] ?? 0}',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                // Partidos Jugados
                SizedBox(
                  width: 32,
                  child: Text(
                    '$pj',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
                // Diferencia Goles
                SizedBox(
                  width: 32,
                  child: Text(
                    dg > 0 ? '+$dg' : '$dg',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: dg > 0 ? Colors.greenAccent : (dg < 0 ? Colors.redAccent : Colors.white38),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Puntos
                SizedBox(
                  width: 45,
                  child: Text(
                    '$pts',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: index == 1 ? const Color(0xFF00E5FF) : Colors.white,
                      fontFamily: 'Manrope',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMatchCard(Map<String, dynamic> match) {
    final String state = match['estado'] ?? 'PROGRAMADO';
    final bool isLive = state == 'LIVEMATCH';
    final bool isFinal = state == 'FINALIZADO';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // Equipo Local
                    Expanded(
                      flex: 4,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Text(
                              match['local'] ?? 'Local',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(CupertinoIcons.shield_fill, color: Colors.white60, size: 16),
                        ],
                      ),
                    ),
                    
                    // Score / VS
                    Expanded(
                      flex: 3,
                      child: Center(
                        child: isFinal
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${match['goles_local']} - ${match['goles_visitante']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    color: Colors.white,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              )
                            : isLive
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${match['goles_local']}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 20,
                                          color: Colors.greenAccent,
                                        ),
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 8),
                                        child: Text(':', style: TextStyle(color: Colors.white38, fontSize: 16)),
                                      ),
                                      Text(
                                        '${match['goles_visitante']}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 20,
                                          color: Colors.greenAccent,
                                        ),
                                      ),
                                    ],
                                  )
                                : Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.04),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'VS',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: Colors.white30,
                                      ),
                                    ),
                                  ),
                      ),
                    ),

                    // Equipo Visitante
                    Expanded(
                      flex: 4,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          const Icon(CupertinoIcons.shield_fill, color: Colors.white60, size: 16),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              match['visitante'] ?? 'Visitante',
                              textAlign: TextAlign.start,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Info Adicional / Estado
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(CupertinoIcons.clock, color: Colors.white38, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          '${match['fecha'] ?? ''} a las ${match['hora'] ?? ''}',
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                    if (isLive)
                      const PulsingLiveMatchBadge()
                    else if (isFinal)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'FINALIZADO',
                          style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold, fontSize: 9),
                        ),
                      )
                    else
                      Flexible(
                        child: Text(
                          match['cancha'] ?? 'Cancha Asignada',
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSimulatorIntro() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF00E5FF).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.15)),
      ),
      child: const Row(
        children: [
          Icon(CupertinoIcons.sparkles, color: Color(0xFF00E5FF), size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gemini AI Predictor',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                ),
                SizedBox(height: 4),
                Text(
                  'Selecciona dos equipos de la tabla general para simular un enfrentamiento táctico respaldado por IA.',
                  style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTeamSelectors(List<Map<String, dynamic>> teams) {
    return Column(
      children: [
        // Dropdown Equipo Local
        _buildDropdownCard(
          title: 'Equipo Local',
          selectedTeam: _selectedTeamA,
          items: teams,
          onChanged: (val) {
            setState(() {
              _selectedTeamA = val;
              _predictionResult = null; // resetear predicción anterior
              // Si se selecciona el mismo equipo, limpiar el otro
              if (_selectedTeamB != null && _selectedTeamB!['equipo'] == val?['equipo']) {
                _selectedTeamB = null;
              }
            });
          },
        ),
        const SizedBox(height: 12),
        // Dropdown Equipo Visitante
        _buildDropdownCard(
          title: 'Equipo Visitante',
          selectedTeam: _selectedTeamB,
          items: teams.where((t) => _selectedTeamA == null || t['equipo'] != _selectedTeamA!['equipo']).toList(),
          onChanged: (val) {
            setState(() {
              _selectedTeamB = val;
              _predictionResult = null;
            });
          },
        ),
      ],
    );
  }

  Widget _buildDropdownCard({
    required String title,
    required Map<String, dynamic>? selectedTeam,
    required List<Map<String, dynamic>> items,
    required ValueChanged<Map<String, dynamic>?> onChanged,
  }) {
    final teamColor = selectedTeam != null ? _getTeamColor(selectedTeam['color']) : Colors.white30;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  selectedTeam != null
                      ? Row(
                          children: [
                            Icon(CupertinoIcons.shield_fill, color: teamColor, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              selectedTeam['equipo'],
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ],
                        )
                      : const Text(
                          'Seleccionar Equipo',
                          style: TextStyle(color: Colors.white30, fontSize: 15),
                        ),
                ],
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<Map<String, dynamic>>(
                  icon: const Icon(CupertinoIcons.chevron_down, color: Colors.white60),
                  dropdownColor: const Color(0xFF001F3F),
                  elevation: 8,
                  borderRadius: BorderRadius.circular(16),
                  items: items.map((t) {
                    final color = _getTeamColor(t['color']);
                    return DropdownMenuItem<Map<String, dynamic>>(
                      value: t,
                      child: Row(
                        children: [
                          Icon(CupertinoIcons.shield_fill, color: color, size: 18),
                          const SizedBox(width: 10),
                          Text(
                            t['equipo'],
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPredictionPanel() {
    if (_predictionResult == null) return const SizedBox.shrink();

    final result = _predictionResult!;
    final int probA = result['probabilidad_teamA'] ?? 40;
    final int probEmpate = result['probabilidad_empate'] ?? 20;
    final int probB = result['probabilidad_teamB'] ?? 40;
    final String estimatedScore = result['marcador_estimado'] ?? '1 - 1';
    final String keyMatchup = result['key_matchup'] ?? '';
    final String tacticalReport = result['analisis_tactico'] ?? '';

    final colorA = _getTeamColor(_selectedTeamA!['color']);
    final colorB = _getTeamColor(_selectedTeamB!['color']);

    return Container(
      margin: const EdgeInsets.only(top: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Encabezado
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'PREDICCIÓN DE ENCUENTRO',
                      style: TextStyle(
                        color: Color(0xFF00E5FF),
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 1.5,
                        fontFamily: 'Manrope',
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Marcador Estimado: $estimatedScore',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Grafico barra continuo
                _buildContinuousProbabilityBar(probA, probEmpate, probB, colorA, colorB),
                const SizedBox(height: 24),

                // Key Matchup
                if (keyMatchup.isNotEmpty) ...[
                  const Text(
                    'FACTOR CLAVE DEL DUELO',
                    style: TextStyle(
                      color: Colors.white38,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      keyMatchup,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13,
                        height: 1.4,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Análisis Táctico
                const Text(
                  'REPORTE TÁCTICO DETALLADO',
                  style: TextStyle(
                    color: Colors.white38,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                _buildTacticalAnalysis(tacticalReport),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContinuousProbabilityBar(int pA, int pDraw, int pB, Color cA, Color cB) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Track de barra
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 16,
            width: double.infinity,
            child: Row(
              children: [
                if (pA > 0)
                  Expanded(
                    flex: pA,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [cA, cA.withValues(alpha: 0.7)],
                        ),
                      ),
                    ),
                  ),
                if (pDraw > 0)
                  Expanded(
                    flex: pDraw,
                    child: Container(
                      color: Colors.white24,
                    ),
                  ),
                if (pB > 0)
                  Expanded(
                    flex: pB,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [cB.withValues(alpha: 0.7), cB],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        
        // Etiquetas
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Local
            Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: cA, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(
                  '${_selectedTeamA!['equipo']}: $pA%',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            
            // Empate
            Text(
              'Empate: $pDraw%',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            
            // Visitante
            Row(
              children: [
                Text(
                  '${_selectedTeamB!['equipo']}: $pB%',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 6),
                Container(width: 8, height: 8, decoration: BoxDecoration(color: cB, shape: BoxShape.circle)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTacticalAnalysis(String text) {
    final lines = text.split('\n');
    final List<Widget> children = [];
    
    for (var line in lines) {
      if (line.trim().isEmpty) continue;
      
      if (line.startsWith('###')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              line.replaceFirst('###', '').trim(),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF00E5FF),
                letterSpacing: 0.5,
              ),
            ),
          ),
        );
      } else if (line.startsWith('-')) {
        final content = line.replaceFirst('-', '').trim();
        final parts = content.split('**');
        final List<TextSpan> spans = [];
        for (var i = 0; i < parts.length; i++) {
          final isBold = i % 2 == 1;
          spans.add(
            TextSpan(
              text: parts[i],
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: isBold ? const Color(0xFF00E5FF) : Colors.white.withValues(alpha: 0.9),
              ),
            ),
          );
        }
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• ', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 14)),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      children: spans,
                      style: const TextStyle(fontSize: 13, height: 1.4, fontFamily: 'Inter'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        final parts = line.split('**');
        final List<TextSpan> spans = [];
        for (var i = 0; i < parts.length; i++) {
          final isBold = i % 2 == 1;
          spans.add(
            TextSpan(
              text: parts[i],
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: isBold ? Colors.white : Colors.white70,
              ),
            ),
          );
        }
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: RichText(
              text: TextSpan(
                children: spans,
                style: const TextStyle(fontSize: 13, height: 1.5, fontFamily: 'Inter'),
              ),
            ),
          ),
        );
      }
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.sportscourt, size: 80, color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 16),
          const Text(
            'LIGA NO INICIALIZADA',
            style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.0),
          ),
          const SizedBox(height: 8),
          const Text(
            'No hay datos del torneo registrados.',
            style: TextStyle(color: Colors.white38, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          if (_isAdmin) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadingSeed ? null : _runSeeding,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: const Color(0xFF001220),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('CARGAR DEMO DE LIGA'),
            ),
          ] else ...[
            const SizedBox(height: 16),
            const Text(
              'Un administrador debe inicializar el torneo\ndesde el panel de gestión para habilitar el Hub.',
              style: TextStyle(color: Colors.white24, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// ─── PULSING LIVE BADGE ──────────────────────────────────────────────────────

class PulsingLiveMatchBadge extends StatefulWidget {
  const PulsingLiveMatchBadge({super.key});

  @override
  State<PulsingLiveMatchBadge> createState() => _PulsingLiveMatchBadgeState();
}

class _PulsingLiveMatchBadgeState extends State<PulsingLiveMatchBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _opacityAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacityAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.redAccent.withValues(alpha: _opacityAnimation.value),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.redAccent.withValues(alpha: _opacityAnimation.value),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'EN VIVO',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── AI SIMULATION LOADER ────────────────────────────────────────────────────

class AISimulationLoader extends StatefulWidget {
  const AISimulationLoader({super.key});

  @override
  State<AISimulationLoader> createState() => _AISimulationLoaderState();
}

class _AISimulationLoaderState extends State<AISimulationLoader> {
  int _messageIndex = 0;
  Timer? _timer;
  
  final List<String> _messages = [
    'Conectando con Gemini AI...',
    'Consultando base de datos del torneo...',
    'Analizando rendimiento de sets...',
    'Evaluando histórico de enfrentamientos...',
    'Calculando matriz de probabilidad...',
    'Generando insights tácticos...',
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (mounted) {
        setState(() {
          _messageIndex = (_messageIndex + 1) % _messages.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
        const CircularProgressIndicator(color: Color(0xFF00E5FF)),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            _messages[_messageIndex],
            key: ValueKey<String>(_messages[_messageIndex]),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _AdminTournamentPanel extends StatefulWidget {
  final FirestoreService firestoreService;
  final String activeDiscipline;
  final VoidCallback onSeedPressed;
  final bool loadingSeed;
  final List<Map<String, dynamic>> allTeams;

  const _AdminTournamentPanel({
    required this.firestoreService,
    required this.activeDiscipline,
    required this.onSeedPressed,
    required this.loadingSeed,
    required this.allTeams,
  });

  @override
  State<_AdminTournamentPanel> createState() => _AdminTournamentPanelState();
}

class _AdminTournamentPanelState extends State<_AdminTournamentPanel> {
  int _activeTab = 0; // 0: Registrar Equipo, 1: Programar Partido, 2: Sistema
  
  // Tab 1: Registrar Equipo
  final _teamFormKey = GlobalKey<FormState>();
  String _teamName = '';
  late String _teamDiscipline;
  int _selectedColor = 0xFF00E5FF;
  bool _registeringTeam = false;

  final List<int> _colorPalette = [
    0xFF00E5FF, // Cyan
    0xFF00BFA5, // Teal
    0xFFFFD700, // Gold
    0xFFFF5252, // Coral/Red
    0xFF9E9E9E, // Grey
    0xFFE040FB, // Magenta
    0xFFFFAB00, // Amber/Orange
    0xFF2979FF, // Royal Blue
    0xFF76FF03, // Lime Green
    0xFFFF3D00, // Deep Orange
    0xFFD500F9, // Deep Purple
  ];

  // Tab 2: Programar Partido
  final _matchFormKey = GlobalKey<FormState>();
  String _matchRound = 'Jornada 4';
  late String _matchDiscipline;
  String? _localTeam;
  String? _visitorTeam;
  String _matchCourt = 'Cancha Central Principal';
  String _matchDate = '';
  late TextEditingController _dateController;
  String _matchTime = '';
  bool _schedulingMatch = false;

  @override
  void initState() {
    super.initState();
    _teamDiscipline = widget.activeDiscipline;
    _matchDiscipline = widget.activeDiscipline;
    _matchDate = DateTime.now().toIso8601String().split('T')[0];
    _dateController = TextEditingController(text: _matchDate);
    _matchTime = "10:00";
  }

  @override
  void dispose() {
    _dateController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_matchDate) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF00E5FF),
              onPrimary: Color(0xFF001220),
              surface: Color(0xFF001220),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF001F3F),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _matchDate = picked.toIso8601String().split('T')[0];
        _dateController.text = _matchDate;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredTeams => widget.allTeams
      .where((t) => t['disciplina'] == _matchDiscipline)
      .toList();

  Future<void> _submitTeam() async {
    if (!_teamFormKey.currentState!.validate()) return;
    _teamFormKey.currentState!.save();
    setState(() => _registeringTeam = true);
    try {
      await widget.firestoreService.registerTeam(
        equipo: _teamName.trim(),
        color: _selectedColor,
        disciplina: _teamDiscipline,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('¡Equipo $_teamName registrado con éxito!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al registrar equipo: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _registeringTeam = false);
    }
  }

  Future<void> _submitMatch() async {
    if (!_matchFormKey.currentState!.validate()) return;
    if (_localTeam == null || _visitorTeam == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, selecciona ambos equipos.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    if (_localTeam == _visitorTeam) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El equipo local y el visitante deben ser diferentes.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    _matchFormKey.currentState!.save();
    setState(() => _schedulingMatch = true);
    try {
      await widget.firestoreService.scheduleMatch(
        local: _localTeam!,
        visitante: _visitorTeam!,
        jornada: _matchRound,
        cancha: _matchCourt,
        fecha: _matchDate,
        hora: _matchTime,
        estado: 'PROGRAMADO',
        disciplina: _matchDiscipline,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('¡Partido programado: $_localTeam vs $_visitorTeam!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al programar partido: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _schedulingMatch = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
            decoration: BoxDecoration(
              color: const Color(0xFF001220).withValues(alpha: 0.85),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 45,
                    height: 5,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
                  ),
                  
                  // Header
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    child: Text(
                      'GESTIÓN DE TORNEOS',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Tabs
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          _buildTabButton('EQUIPO 🛡️', 0),
                          _buildTabButton('PARTIDO 📅', 1),
                          _buildTabButton('SISTEMA ⚙️', 2),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Tab View Content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: _buildActiveTabContent(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton(String label, int tabIndex) {
    final isSelected = _activeTab == tabIndex;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = tabIndex),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF00E5FF).withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF00E5FF).withValues(alpha: 0.3) : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? const Color(0xFF00E5FF) : Colors.white54,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTabContent() {
    switch (_activeTab) {
      case 0:
        return _buildTeamRegisterForm();
      case 1:
        return _buildMatchScheduleForm();
      case 2:
        return _buildSystemSettingsForm();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTeamRegisterForm() {
    return Form(
      key: _teamFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'REGISTRAR NUEVO EQUIPO',
            style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
          ),
          const SizedBox(height: 16),
          TextFormField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Nombre del Equipo',
              labelStyle: const TextStyle(color: Colors.white60),
              enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF00E5FF)), borderRadius: BorderRadius.circular(12)),
              errorStyle: const TextStyle(color: Colors.redAccent),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa el nombre del equipo' : null,
            onSaved: (v) => _teamName = v!,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _teamDiscipline,
            dropdownColor: const Color(0xFF001220),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Disciplina',
              labelStyle: const TextStyle(color: Colors.white60),
              enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF00E5FF)), borderRadius: BorderRadius.circular(12)),
            ),
            items: const [
              DropdownMenuItem(value: 'voleibol', child: Text('Voleibol 🏐')),
              DropdownMenuItem(value: 'basquetbol', child: Text('Básquetbol 🏀')),
              DropdownMenuItem(value: 'futbol', child: Text('Fútbol ⚽')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _teamDiscipline = v);
            },
          ),
          const SizedBox(height: 20),
          const Text(
            'COLOR REPRESENTATIVO (HSL / PALETTE)',
            style: TextStyle(color: Colors.white60, fontWeight: FontWeight.bold, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Center(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _colorPalette.map((colorValue) {
                final isSelected = _selectedColor == colorValue;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = colorValue),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Color(colorValue),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.white24,
                        width: isSelected ? 3 : 1.5,
                      ),
                      boxShadow: isSelected
                          ? [BoxShadow(color: Color(colorValue).withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 1)]
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Color(0xFF001220), size: 18)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _registeringTeam ? null : _submitTeam,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: const Color(0xFF001220),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: _registeringTeam
                  ? const CircularProgressIndicator(color: Color(0xFF001220))
                  : const Text('GUARDAR EQUIPO', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchScheduleForm() {
    final list = _filteredTeams;
    
    return Form(
      key: _matchFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PROGRAMAR NUEVO PARTIDO',
            style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _matchDiscipline,
            dropdownColor: const Color(0xFF001220),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Disciplina Deportiva',
              labelStyle: const TextStyle(color: Colors.white60),
              enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF00E5FF)), borderRadius: BorderRadius.circular(12)),
            ),
            items: const [
              DropdownMenuItem(value: 'voleibol', child: Text('Voleibol 🏐')),
              DropdownMenuItem(value: 'basquetbol', child: Text('Básquetbol 🏀')),
              DropdownMenuItem(value: 'futbol', child: Text('Fútbol ⚽')),
            ],
            onChanged: (v) {
              if (v != null) {
                setState(() {
                  _matchDiscipline = v;
                  _localTeam = null;
                  _visitorTeam = null;
                });
              }
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: _matchRound,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Jornada / Ronda',
              labelStyle: const TextStyle(color: Colors.white60),
              enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF00E5FF)), borderRadius: BorderRadius.circular(12)),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa la jornada' : null,
            onSaved: (v) => _matchRound = v!,
          ),
          const SizedBox(height: 16),
          // Local Team
          DropdownButtonFormField<String>(
            value: _localTeam,
            dropdownColor: const Color(0xFF001220),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Equipo Local',
              labelStyle: const TextStyle(color: Colors.white60),
              enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF00E5FF)), borderRadius: BorderRadius.circular(12)),
            ),
            items: list.map((t) {
              return DropdownMenuItem<String>(
                value: t['equipo'],
                child: Text(t['equipo']),
              );
            }).toList(),
            onChanged: (v) => setState(() => _localTeam = v),
          ),
          const SizedBox(height: 16),
          // Visitor Team
          DropdownButtonFormField<String>(
            value: _visitorTeam,
            dropdownColor: const Color(0xFF001220),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Equipo Visitante',
              labelStyle: const TextStyle(color: Colors.white60),
              enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF00E5FF)), borderRadius: BorderRadius.circular(12)),
            ),
            items: list.where((t) => _localTeam == null || t['equipo'] != _localTeam).map((t) {
              return DropdownMenuItem<String>(
                value: t['equipo'],
                child: Text(t['equipo']),
              );
            }).toList(),
            onChanged: (v) => setState(() => _visitorTeam = v),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: _matchCourt,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Cancha / Pista',
              labelStyle: const TextStyle(color: Colors.white60),
              enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF00E5FF)), borderRadius: BorderRadius.circular(12)),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa la cancha' : null,
            onSaved: (v) => _matchCourt = v!,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _dateController,
                  readOnly: true,
                  onTap: () => _selectDate(context),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Fecha (YYYY-MM-DD)',
                    labelStyle: const TextStyle(color: Colors.white60),
                    suffixIcon: const Icon(CupertinoIcons.calendar, color: Color(0xFF00E5FF), size: 18),
                    enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF00E5FF)), borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
                  onSaved: (v) => _matchDate = v!,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: _matchTime,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Hora (HH:MM)',
                    labelStyle: const TextStyle(color: Colors.white60),
                    enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF00E5FF)), borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
                  onSaved: (v) => _matchTime = v!,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _schedulingMatch ? null : _submitMatch,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: const Color(0xFF001220),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: _schedulingMatch
                  ? const CircularProgressIndicator(color: Color(0xFF001220))
                  : const Text('PROGRAMAR ENCUENTRO', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemSettingsForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ACCIONES DEL SISTEMA',
          style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
        ),
        const SizedBox(height: 16),
        const Text(
          'Esta acción restablecerá todas las tablas de clasificación, partidos programados y en vivo de todas las disciplinas, y cargará el set de datos inicial semilla.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: widget.loadingSeed
                ? null
                : () {
                    Navigator.pop(context);
                    widget.onSeedPressed();
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            icon: const Icon(Icons.refresh),
            label: const Text('RESTABLECER Y SEMILLAR LIGA (DEMO)', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}
