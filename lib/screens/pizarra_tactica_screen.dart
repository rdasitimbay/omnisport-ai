import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


class TacticalItem {
  final String id;
  final String label;
  final Color color;
  final bool isBall;
  Offset normalizedPos; // X and Y are between 0.0 and 1.0 relative to the court boundaries

  TacticalItem({
    required this.id,
    required this.label,
    required this.color,
    this.isBall = false,
    required this.normalizedPos,
  });
}

class DrawingPath {
  final List<Offset> normalizedPoints;
  final Color color;
  final double strokeWidth;

  DrawingPath({
    required this.normalizedPoints,
    required this.color,
    required this.strokeWidth,
  });
}

class PizarraTacticaScreen extends StatefulWidget {
  const PizarraTacticaScreen({super.key});

  @override
  State<PizarraTacticaScreen> createState() => _PizarraTacticaScreenState();
}

class _PizarraTacticaScreenState extends State<PizarraTacticaScreen> {
  // Key for the interactive canvas/court area to get localized coordinates
  final GlobalKey _canvasKey = GlobalKey();

  // Tools
  // 'move' - drag players/ball
  // 'draw' - freehand draw lines
  // 'erase' - tap a line to erase or clear all
  String _activeTool = 'move';
  Color _selectedColor = const Color(0xFF00E5FF); // default cyan neon
  double _strokeWidth = 4.0;

  // State for items
  List<TacticalItem> _items = [];
  List<DrawingPath> _paths = [];
  List<Offset> _currentPathPoints = [];

  // Dragging state
  TacticalItem? _draggingItem;

  // Active Preset name
  String _activePreset = 'Posición Inicial';

  @override
  void initState() {
    super.initState();
    // Enable landscape rotation if desired, but we can design it to fit vertically or horizontally dynamically.
    // Let's force it to allow both portrait and landscape, the LayoutBuilder will handle it!
    _resetPositions();
  }

  void _resetPositions() {
    setState(() {
      _activePreset = 'Posición Inicial';
      _items = [
        // Blue Team (Local, bottom half: y from 0.5 to 1.0)
        TacticalItem(id: 'B1', label: 'C1', color: const Color(0xFF00E5FF), normalizedPos: const Offset(0.80, 0.85)), // Setter in Pos 1
        TacticalItem(id: 'B2', label: 'O2', color: const Color(0xFF00E5FF), normalizedPos: const Offset(0.75, 0.58)), // Opposite in Pos 2
        TacticalItem(id: 'B3', label: 'C3', color: const Color(0xFF00E5FF), normalizedPos: const Offset(0.50, 0.55)), // Middle Blocker in Pos 3
        TacticalItem(id: 'B4', label: 'P4', color: const Color(0xFF00E5FF), normalizedPos: const Offset(0.25, 0.58)), // Outside Hitter in Pos 4
        TacticalItem(id: 'B5', label: 'P5', color: const Color(0xFF00E5FF), normalizedPos: const Offset(0.20, 0.85)), // Outside Hitter in Pos 5
        TacticalItem(id: 'B6', label: 'L6', color: const Color(0xFF00E676), normalizedPos: const Offset(0.50, 0.85)), // Libero in Pos 6

        // Red Team (Visitor/Opponent, top half: y from 0.0 to 0.5)
        TacticalItem(id: 'R1', label: '1', color: const Color(0xFFFF1744), normalizedPos: const Offset(0.20, 0.15)),
        TacticalItem(id: 'R2', label: '2', color: const Color(0xFFFF1744), normalizedPos: const Offset(0.25, 0.42)),
        TacticalItem(id: 'R3', label: '3', color: const Color(0xFFFF1744), normalizedPos: const Offset(0.50, 0.45)),
        TacticalItem(id: 'R4', label: '4', color: const Color(0xFFFF1744), normalizedPos: const Offset(0.75, 0.42)),
        TacticalItem(id: 'R5', label: '5', color: const Color(0xFFFF1744), normalizedPos: const Offset(0.80, 0.15)),
        TacticalItem(id: 'R6', label: '6', color: const Color(0xFFFF1744), normalizedPos: const Offset(0.50, 0.15)),

        // Ball
        TacticalItem(id: 'ball', label: '⚽', color: const Color(0xFFFFD600), isBall: true, normalizedPos: const Offset(0.50, 0.50)),
      ];
    });
  }

  void _applyPresetRotation51Receive() {
    setState(() {
      _activePreset = 'Rotación 5-1 (Recepción)';
      _items = [
        // Blue Team arranged in "W" reception shape to protect setter
        TacticalItem(id: 'B1', label: 'C1', color: const Color(0xFF00E5FF), normalizedPos: const Offset(0.88, 0.88)), // Setter (hiding in corner ready to run)
        TacticalItem(id: 'B2', label: 'O2', color: const Color(0xFF00E5FF), normalizedPos: const Offset(0.68, 0.60)), // Hitter front
        TacticalItem(id: 'B3', label: 'C3', color: const Color(0xFF00E5FF), normalizedPos: const Offset(0.35, 0.60)), // Middle Blocker front
        TacticalItem(id: 'B4', label: 'P4', color: const Color(0xFF00E5FF), normalizedPos: const Offset(0.18, 0.72)), // Hitter back-left (W left arm)
        TacticalItem(id: 'B5', label: 'P5', color: const Color(0xFF00E5FF), normalizedPos: const Offset(0.82, 0.72)), // Hitter back-right (W right arm)
        TacticalItem(id: 'B6', label: 'L6', color: const Color(0xFF00E676), normalizedPos: const Offset(0.50, 0.78)), // Libero deep center (W center point)

        // Opponents ready to serve
        TacticalItem(id: 'R1', label: 'S1', color: const Color(0xFFFF1744), normalizedPos: const Offset(0.50, 0.05)), // Server at backline
        TacticalItem(id: 'R2', label: '2', color: const Color(0xFFFF1744), normalizedPos: const Offset(0.25, 0.35)),
        TacticalItem(id: 'R3', label: '3', color: const Color(0xFFFF1744), normalizedPos: const Offset(0.50, 0.40)),
        TacticalItem(id: 'R4', label: '4', color: const Color(0xFFFF1744), normalizedPos: const Offset(0.75, 0.35)),
        TacticalItem(id: 'R5', label: '5', color: const Color(0xFFFF1744), normalizedPos: const Offset(0.80, 0.18)),
        TacticalItem(id: 'R6', label: '6', color: const Color(0xFFFF1744), normalizedPos: const Offset(0.50, 0.20)),

        TacticalItem(id: 'ball', label: '⚽', color: const Color(0xFFFFD600), isBall: true, normalizedPos: const Offset(0.50, 0.02)),
      ];
    });
  }

  void _applyPresetRotation51Defense() {
    setState(() {
      _activePreset = 'Defensa K2 (Bloqueo)';
      _items = [
        // Blue Team set up for defense against an attack from Pos 4 (opponent left)
        TacticalItem(id: 'B1', label: 'C1', color: const Color(0xFF00E5FF), normalizedPos: const Offset(0.70, 0.65)), // Covering short/tip
        TacticalItem(id: 'B2', label: 'O2', color: const Color(0xFF00E5FF), normalizedPos: const Offset(0.78, 0.52)), // Blocker line (Pos 2)
        TacticalItem(id: 'B3', label: 'C3', color: const Color(0xFF00E5FF), normalizedPos: const Offset(0.58, 0.52)), // Blocker assist (Middle)
        TacticalItem(id: 'B4', label: 'P4', color: const Color(0xFF00E5FF), normalizedPos: const Offset(0.18, 0.60)), // Off blocker covering cross-court
        TacticalItem(id: 'B5', label: 'P5', color: const Color(0xFF00E5FF), normalizedPos: const Offset(0.25, 0.85)), // Deep defender left
        TacticalItem(id: 'B6', label: 'L6', color: const Color(0xFF00E676), normalizedPos: const Offset(0.55, 0.90)), // Deep defender center-back

        // Opponents attacking from left
        TacticalItem(id: 'R1', label: '1', color: const Color(0xFFFF1744), normalizedPos: const Offset(0.20, 0.20)),
        TacticalItem(id: 'R2', label: '2', color: const Color(0xFFFF1744), normalizedPos: const Offset(0.30, 0.35)),
        TacticalItem(id: 'R3', label: '3', color: const Color(0xFFFF1744), normalizedPos: const Offset(0.50, 0.38)),
        TacticalItem(id: 'R4', label: 'A4', color: const Color(0xFFFF1744), normalizedPos: const Offset(0.82, 0.48)), // Attacker in Pos 4 at net
        TacticalItem(id: 'R5', label: '5', color: const Color(0xFFFF1744), normalizedPos: const Offset(0.75, 0.15)),
        TacticalItem(id: 'R6', label: '6', color: const Color(0xFFFF1744), normalizedPos: const Offset(0.48, 0.22)),

        TacticalItem(id: 'ball', label: '⚽', color: const Color(0xFFFFD600), isBall: true, normalizedPos: const Offset(0.79, 0.49)),
      ];
    });
  }

  void _clearCanvas() {
    setState(() {
      _paths.clear();
      _currentPathPoints.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Force device orientation settings for presentation comfort
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    return Scaffold(
      backgroundColor: const Color(0xFF000D1A), // Dark space theme
      appBar: AppBar(
        backgroundColor: const Color(0xFF001F3F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () {
            // Restore normal mobile orientation lock on exit if desired
            SystemChrome.setPreferredOrientations([
              DeviceOrientation.portraitUp,
            ]);
            Navigator.pop(context);
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pizarra Táctica Móvil / iPad',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              'Esquema activo: $_activePreset',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            tooltip: 'Reiniciar Fichas',
            onPressed: _resetPositions,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: 'Borrar Dibujos',
            onPressed: _clearCanvas,
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Calculate sizes and layout responsive orientation
            final bool isLandscape = constraints.maxWidth > constraints.maxHeight;

            return isLandscape 
                ? Row(
                    children: [
                      // Sidebar Controls for iPad landscape
                      _buildSidebarControls(constraints.maxHeight),
                      // Court + Canvas Area
                      Expanded(
                        child: _buildCourtInteractiveArea(isLandscape),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      // Court + Canvas Area
                      Expanded(
                        child: _buildCourtInteractiveArea(isLandscape),
                      ),
                      // Bottom Toolbar for Portrait mobile/iPad
                      _buildBottomToolbar(),
                    ],
                  );
          },
        ),
      ),
    );
  }

  // INTERACTIVE CANVAS & COURT STACK
  Widget _buildCourtInteractiveArea(bool isLandscape) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Define sizes for Court
        final double padX = isLandscape ? 32 : 16;
        final double padY = isLandscape ? 16 : 32;

        // A volleyball court is exactly 9x18 meters (aspect ratio 1:2)
        // Let's calculate the largest court rectangle that can fit the available area
        double courtHeight, courtWidth;
        if (isLandscape) {
          // In landscape, we lay out the court vertically in the center
          courtHeight = constraints.maxHeight - (padY * 2);
          courtWidth = courtHeight / 2.0;
          // If it overflows width, constrain by width
          if (courtWidth > constraints.maxWidth) {
            courtWidth = constraints.maxWidth - (padX * 2);
            courtHeight = courtWidth * 2.0;
          }
        } else {
          // Portrait layout: standard vertical court filling center
          courtWidth = constraints.maxWidth - (padX * 2);
          courtHeight = courtWidth * 2.0;
          // If height overflows, constrain by height
          if (courtHeight > constraints.maxHeight - (padY * 2)) {
            courtHeight = constraints.maxHeight - (padY * 2);
            courtWidth = courtHeight / 2.0;
          }
        }

        // Centralized origin points of the court within the available interactive area
        final double courtLeft = (constraints.maxWidth - courtWidth) / 2.0;
        final double courtTop = (constraints.maxHeight - courtHeight) / 2.0;

        final Rect courtRect = Rect.fromLTWH(courtLeft, courtTop, courtWidth, courtHeight);

        return GestureDetector(
          key: _canvasKey,
          // Canvas drawing logic via touch coordinates
          onPanStart: (details) {
            if (_activeTool == 'draw') {
              final RenderBox? renderBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
              if (renderBox != null) {
                final localPos = renderBox.globalToLocal(details.globalPosition);
                // Convert to normalized coordinates relative to court rect
                final nx = (localPos.dx - courtRect.left) / courtRect.width;
                final ny = (localPos.dy - courtRect.top) / courtRect.height;
                setState(() {
                  _currentPathPoints = [Offset(nx, ny)];
                });
              }
            }
          },
          onPanUpdate: (details) {
            if (_activeTool == 'draw') {
              final RenderBox? renderBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
              if (renderBox != null) {
                final localPos = renderBox.globalToLocal(details.globalPosition);
                final nx = (localPos.dx - courtRect.left) / courtRect.width;
                final ny = (localPos.dy - courtRect.top) / courtRect.height;
                setState(() {
                  _currentPathPoints.add(Offset(nx, ny));
                });
              }
            }
          },
          onPanEnd: (details) {
            if (_activeTool == 'draw' && _currentPathPoints.isNotEmpty) {
              setState(() {
                _paths.add(DrawingPath(
                  normalizedPoints: List.from(_currentPathPoints),
                  color: _selectedColor,
                  strokeWidth: _strokeWidth,
                ));
                _currentPathPoints.clear();
              });
            }
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 1. Basketball/Volleyball Court Render Background
              Positioned.fromRect(
                rect: courtRect,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A2B4E), // Deep Blue Court color
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.08),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: CustomPaint(
                    painter: VolleyballCourtPainter(),
                  ),
                ),
              ),

              // 2. Drawings Canvas Layer (Rendered Lines)
              Positioned.fromRect(
                rect: courtRect,
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: TacticalDrawingPainter(
                      paths: _paths,
                      activePath: _currentPathPoints,
                      activeColor: _selectedColor,
                      strokeWidth: _strokeWidth,
                    ),
                  ),
                ),
              ),

              // 3. Draggable Player widgets
              ..._items.map((item) {
                // Absolute coordinates based on responsive court size
                final double itemX = courtRect.left + (item.normalizedPos.dx * courtRect.width);
                final double itemY = courtRect.top + (item.normalizedPos.dy * courtRect.height);
                final double radius = item.isBall ? 16 : 22;

                return Positioned(
                  left: itemX - radius,
                  top: itemY - radius,
                  child: GestureDetector(
                    onPanStart: (_) {
                      if (_activeTool == 'move') {
                        _draggingItem = item;
                      }
                    },
                    onPanUpdate: (details) {
                      if (_activeTool == 'move' && _draggingItem == item) {
                        final RenderBox? renderBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
                        if (renderBox != null) {
                          final localPos = renderBox.globalToLocal(details.globalPosition);

                          // Normalize the new position
                          double nx = (localPos.dx - courtRect.left) / courtRect.width;
                          double ny = (localPos.dy - courtRect.top) / courtRect.height;

                          // Clamping within bounds of the court + buffer
                          nx = nx.clamp(-0.05, 1.05);
                          ny = ny.clamp(-0.05, 1.05);

                          setState(() {
                            item.normalizedPos = Offset(nx, ny);
                          });
                        }
                      }
                    },
                    onPanEnd: (_) {
                      _draggingItem = null;
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 150),
                        scale: _draggingItem == item ? 1.2 : 1.0,
                        child: Container(
                          width: radius * 2,
                          height: radius * 2,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: item.isBall ? Colors.yellow.shade700 : item.color,
                            boxShadow: [
                              BoxShadow(
                                color: (item.isBall ? Colors.yellow : item.color).withValues(alpha: 0.5),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                            border: Border.all(
                              color: Colors.white,
                              width: item.isBall ? 1.5 : 2.5,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              item.label,
                              style: TextStyle(
                                color: item.isBall ? Colors.black : Colors.white,
                                fontSize: item.isBall ? 11 : 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  // CONTROLS BAR: SIDEBAR (LANDSCAPE / IPAD)
  Widget _buildSidebarControls(double height) {
    return Container(
      width: 130,
      height: height,
      color: const Color(0xFF001F3F),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: ListView(
        children: [
          const Text(
            'HERRAMIENTAS',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
          const SizedBox(height: 12),
          _sidebarToolButton('move', 'Mover', Icons.back_hand),
          const SizedBox(height: 8),
          _sidebarToolButton('draw', 'Dibujar', Icons.edit),
          const SizedBox(height: 16),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 16),
          const Text(
            'COLORES',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _colorDot(const Color(0xFF00E5FF)),
              _colorDot(const Color(0xFF00E676)),
              _colorDot(const Color(0xFFFF1744)),
              _colorDot(const Color(0xFFFFD600)),
              _colorDot(const Color(0xFFFFFFFF)),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 16),
          const Text(
            'TÁCTICAS',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
          const SizedBox(height: 12),
          _sidebarPresetButton('Inicio', _resetPositions),
          const SizedBox(height: 8),
          _sidebarPresetButton('5-1 Rec.', _applyPresetRotation51Receive),
          const SizedBox(height: 8),
          _sidebarPresetButton('5-1 Def.', _applyPresetRotation51Defense),
        ],
      ),
    );
  }

  Widget _sidebarToolButton(String toolKey, String label, IconData icon) {
    final active = _activeTool == toolKey;
    return GestureDetector(
      onTap: () => setState(() => _activeTool = toolKey),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF00E5FF).withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? const Color(0xFF00E5FF) : Colors.transparent),
        ),

        child: Column(
          children: [
            Icon(icon, size: 20, color: active ? const Color(0xFF00E5FF) : Colors.white60),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: active ? Colors.white : Colors.white60, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _sidebarPresetButton(String label, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.05),
          foregroundColor: Colors.white,

          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Colors.white12),
          ),
        ),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // CONTROLS BAR: BOTTOM TOOLBAR (PORTRAIT / MOBILE)
  Widget _buildBottomToolbar() {
    return Container(
      height: 90,
      decoration: const BoxDecoration(
        color: Color(0xFF001F3F),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Tool Toggle (Move vs Draw)
          Row(
            children: [
              _bottomIconButton(
                active: _activeTool == 'move',
                icon: Icons.back_hand_outlined,
                label: 'Mover',
                onTap: () => setState(() => _activeTool = 'move'),
              ),
              const SizedBox(width: 8),
              _bottomIconButton(
                active: _activeTool == 'draw',
                icon: Icons.gesture,
                label: 'Dibujar',
                onTap: () => setState(() => _activeTool = 'draw'),
              ),
            ],
          ),

          // Dynamic settings or colors depending on active tool
          Expanded(
            child: Center(
              child: _activeTool == 'draw'
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _colorDot(const Color(0xFF00E5FF)),
                          const SizedBox(width: 10),
                          _colorDot(const Color(0xFF00E676)),
                          const SizedBox(width: 10),
                          _colorDot(const Color(0xFFFF1744)),
                          const SizedBox(width: 10),
                          _colorDot(const Color(0xFFFFD600)),
                          const SizedBox(width: 10),
                          _colorDot(const Color(0xFFFFFFFF)),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _presetPill('Inicio', _resetPositions),
                          const SizedBox(width: 8),
                          _presetPill('5-1 Rec.', _applyPresetRotation51Receive),
                          const SizedBox(width: 8),
                          _presetPill('5-1 Def.', _applyPresetRotation51Defense),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomIconButton({
    required bool active,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF00E5FF).withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),

          border: Border.all(
            color: active ? const Color(0xFF00E5FF) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: active ? const Color(0xFF00E5FF) : Colors.white54, size: 22),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: active ? Colors.white : Colors.white54, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _presetPill(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24, width: 1),
        ),

        child: Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _colorDot(Color color) {
    final active = _selectedColor == color && _activeTool == 'draw';
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedColor = color;
          _activeTool = 'draw'; // Switch to draw automatically
        });
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: active ? Colors.white : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],

        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// VOLLEYBALL COURT PAINTER
// ═══════════════════════════════════════════════════════════════════════════
class VolleyballCourtPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final netPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    // Court boundaries
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), linePaint);

    // Center Net Line
    final double midY = size.height / 2.0;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), netPaint);

    // Net visual overlay pattern (mini ticks for a mesh look)
    final Paint netTicksPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 1.0;
    for (double i = 0; i < size.width; i += 8) {
      canvas.drawLine(Offset(i, midY - 2), Offset(i + 2, midY + 2), netTicksPaint);
    }


    // 3-Meter Attack Lines (calculated at exactly 1/3 of the court half: 3m out of 9m)
    final double attackOffset = size.height / 6.0; // height / 2 / 3

    // Bottom Half Attack Line
    canvas.drawLine(Offset(0, midY + attackOffset), Offset(size.width, midY + attackOffset), linePaint);

    // Top Half Attack Line
    canvas.drawLine(Offset(0, midY - attackOffset), Offset(size.width, midY - attackOffset), linePaint);

    // Draw court zone text guides in subtle faded font (volleyball rotation zones 1-6)
    // Bottom court zones
    _drawZoneText(canvas, 'Z4', Offset(size.width * 0.2, midY + attackOffset * 0.5), size);
    _drawZoneText(canvas, 'Z3', Offset(size.width * 0.5, midY + attackOffset * 0.5), size);
    _drawZoneText(canvas, 'Z2', Offset(size.width * 0.8, midY + attackOffset * 0.5), size);
    _drawZoneText(canvas, 'Z5', Offset(size.width * 0.2, midY + attackOffset * 2.0), size);
    _drawZoneText(canvas, 'Z6', Offset(size.width * 0.5, midY + attackOffset * 2.0), size);
    _drawZoneText(canvas, 'Z1', Offset(size.width * 0.8, midY + attackOffset * 2.0), size);

    // Top court zones (inverted)
    _drawZoneText(canvas, 'Z2', Offset(size.width * 0.2, midY - attackOffset * 0.5), size);
    _drawZoneText(canvas, 'Z3', Offset(size.width * 0.5, midY - attackOffset * 0.5), size);
    _drawZoneText(canvas, 'Z4', Offset(size.width * 0.8, midY - attackOffset * 0.5), size);
    _drawZoneText(canvas, 'Z1', Offset(size.width * 0.2, midY - attackOffset * 2.0), size);
    _drawZoneText(canvas, 'Z6', Offset(size.width * 0.5, midY - attackOffset * 2.0), size);
    _drawZoneText(canvas, 'Z5', Offset(size.width * 0.8, midY - attackOffset * 2.0), size);
  }

  void _drawZoneText(Canvas canvas, String text, Offset center, Size courtSize) {
    // Responsive font sizing based on court width
    final double fontSize = (courtSize.width / 360.0) * 14.0;
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.08),
          fontSize: fontSize.clamp(8, 16),
          fontWeight: FontWeight.w800,
        ),

      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════
// TACTICAL DRAWING CANVAS PAINTER
// ═══════════════════════════════════════════════════════════════════════════
class TacticalDrawingPainter extends CustomPainter {
  final List<DrawingPath> paths;
  final List<Offset> activePath;
  final Color activeColor;
  final double strokeWidth;

  TacticalDrawingPainter({
    required this.paths,
    required this.activePath,
    required this.activeColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Render completed paths
    for (final path in paths) {
      if (path.normalizedPoints.length < 2) continue;

      final paint = Paint()
        ..color = path.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = path.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final absolutePoints = path.normalizedPoints.map((p) {
        return Offset(p.dx * size.width, p.dy * size.height);
      }).toList();

      for (int i = 0; i < absolutePoints.length - 1; i++) {
        canvas.drawLine(absolutePoints[i], absolutePoints[i + 1], paint);
      }
    }

    // Render active drawing path
    if (activePath.length >= 2) {
      final paint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final absolutePoints = activePath.map((p) {
        return Offset(p.dx * size.width, p.dy * size.height);
      }).toList();

      for (int i = 0; i < absolutePoints.length - 1; i++) {
        canvas.drawLine(absolutePoints[i], absolutePoints[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
