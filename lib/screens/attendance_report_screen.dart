import 'dart:ui';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
// ignore: avoid_web_libraries_in_flutter
import 'package:universal_html/html.dart' as html;

/// Reporte de control de asistencia para el backoffice.
/// Llama a la CF getAttendanceReport con rango de fechas y categoría,
/// muestra tabla con stats por atleta y permite exportar CSV.
class AttendanceReportScreen extends StatefulWidget {
  final String institutionId;

  const AttendanceReportScreen({super.key, required this.institutionId});

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  // Filtros
  DateTimeRange _range = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end:   DateTime.now(),
  );
  String _category = 'Todas';
  String _sortBy   = 'percentage'; // percentage | name | sessionsAttended

  // Estado
  bool   _loading = false;
  String? _error;
  List<Map<String, dynamic>> _report = [];
  int    _totalSessions = 0;

  List<String> _categories = ['Todas'];

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _fetchReport();
  }

  Future<void> _loadCategories() async {
    final snap = await FirebaseFirestore.instance
        .collection('athletes')
        .where('ownerInstitutionId', isEqualTo: widget.institutionId)
        .get();
    final cats = <String>{'Todas'};
    for (final d in snap.docs) {
      final c = d.data()['teamOrCategory'] as String?;
      if (c != null && c.isNotEmpty) cats.add(c);
    }
    if (mounted) setState(() => _categories = cats.toList()..sort());
  }

  Future<void> _fetchReport() async {
    setState(() { _loading = true; _error = null; });
    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('getAttendanceReport');
      final result = await callable.call({
        'institutionId': widget.institutionId,
        'startMs':       _range.start.millisecondsSinceEpoch,
        'endMs':         _range.end.add(const Duration(hours: 23, minutes: 59, seconds: 59))
                         .millisecondsSinceEpoch,
        if (_category != 'Todas') 'category': _category,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final raw  = List<dynamic>.from(data['report'] as List? ?? []);
      setState(() {
        _report        = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _totalSessions = (data['totalSessions'] as int?) ?? 0;
        _loading       = false;
      });
      _applySorting();
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _applySorting() {
    setState(() {
      if (_sortBy == 'percentage') {
        _report.sort((a, b) =>
            ((b['percentage'] as int?) ?? 0).compareTo((a['percentage'] as int?) ?? 0));
      } else if (_sortBy == 'name') {
        _report.sort((a, b) =>
            ((a['fullName'] as String?) ?? '').compareTo((b['fullName'] as String?) ?? ''));
      } else {
        _report.sort((a, b) =>
            ((b['sessionsAttended'] as int?) ?? 0)
                .compareTo((a['sessionsAttended'] as int?) ?? 0));
      }
    });
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate:  DateTime.now(),
      initialDateRange: _range,
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary:   Color(0xFF00E5FF),
            onPrimary: Color(0xFF001F3F),
            surface:   Color(0xFF1A1A2E),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _range = picked);
      _fetchReport();
    }
  }

  void _exportCsv() {
    if (_report.isEmpty) return;

    final df   = DateFormat('dd/MM/yyyy');
    final buf  = StringBuffer();
    buf.writeln('OmniSport-AI — Reporte de Asistencia');
    buf.writeln('Institución: ${widget.institutionId}');
    buf.writeln('Período: ${df.format(_range.start)} — ${df.format(_range.end)}');
    buf.writeln('Sesiones detectadas: $_totalSessions');
    buf.writeln('Categoría: $_category');
    buf.writeln('');
    buf.writeln('Nombre,Categoría,Estado,Sesiones Asistidas,Total Sesiones,Porcentaje %,Menor');

    for (final row in _report) {
      final name      = (row['fullName']         as String?) ?? '';
      final cat       = (row['category']         as String?) ?? '';
      final status    = (row['status']           as String?) ?? '';
      final attended  = (row['sessionsAttended'] as int?)    ?? 0;
      final total     = (row['totalSessions']    as int?)    ?? 0;
      final pct       = (row['percentage']       as int?)    ?? 0;
      final isMinor   = (row['isMinor']          as bool?)   ?? false;
      buf.writeln('"$name","$cat","$status",$attended,$total,$pct,${isMinor ? "Sí" : "No"}');
    }

    final content  = buf.toString();
    final filename = 'asistencia_${_range.start.year}${_range.start.month.toString().padLeft(2,'0')}'
        '_${_range.end.year}${_range.end.month.toString().padLeft(2,'0')}.csv';

    if (kIsWeb) {
      final bytes  = utf8.encode(content);
      final blob   = html.Blob([bytes]);
      final url    = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.document.createElement('a') as html.AnchorElement
        ..href     = url
        ..download = filename
        ..style.display = 'none';
      html.document.body!.children.add(anchor);
      anchor.click();
      html.document.body!.children.remove(anchor);
      html.Url.revokeObjectUrl(url);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Exportación CSV disponible solo en el backoffice web'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM yyyy', 'es');
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.black.withValues(alpha: 0.4)),
          ),
        ),
        title: const Text('Control de Asistencia',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold,
                letterSpacing: 1.1)),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.arrow_down_doc_fill, color: Color(0xFF00E5FF)),
            tooltip: 'Exportar CSV',
            onPressed: _report.isEmpty ? null : _exportCsv,
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.refresh, color: Colors.white54),
            onPressed: _loading ? null : _fetchReport,
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF0A0A0A), Color(0xFF111827)],
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            // ── Filtros ────────────────────────────────────────────────
            _buildFiltersBar(df),

            // ── Resumen ────────────────────────────────────────────────
            if (_report.isNotEmpty) _buildSummaryBanner(),

            // ── Tabla / Estado ─────────────────────────────────────────
            Expanded(child: _buildContent()),
          ]),
        ),
      ),
    );
  }

  Widget _buildFiltersBar(DateFormat df) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(children: [
        // Rango de fechas
        GestureDetector(
          onTap: _pickDateRange,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(CupertinoIcons.calendar, color: Color(0xFF00E5FF), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${df.format(_range.start)}  →  ${df.format(_range.end)}',
                  style: const TextStyle(color: Colors.white, fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
              ),
              const Icon(CupertinoIcons.chevron_down, color: Colors.white38, size: 14),
            ]),
          ),
        ),
        const SizedBox(height: 10),

        // Categoría + orden
        Row(children: [
          // Categoría
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _category,
                  dropdownColor: const Color(0xFF1A1A2E),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  icon: const Icon(CupertinoIcons.chevron_down,
                      color: Colors.white38, size: 14),
                  items: _categories.map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(c),
                  )).toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _category = v);
                    _fetchReport();
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Ordenar por
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _sortBy,
                dropdownColor: const Color(0xFF1A1A2E),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                icon: const Icon(CupertinoIcons.chevron_down,
                    color: Colors.white38, size: 14),
                items: const [
                  DropdownMenuItem(value: 'percentage',       child: Text('% Mayor')),
                  DropdownMenuItem(value: 'sessionsAttended', child: Text('Sesiones')),
                  DropdownMenuItem(value: 'name',             child: Text('Nombre')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _sortBy = v);
                  _applySorting();
                },
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
      ]),
    );
  }

  Widget _buildSummaryBanner() {
    final total   = _report.length;
    final perfect = _report.where((r) => (r['percentage'] as int? ?? 0) >= 100).length;
    final atRisk = _report.where((r) => (r['percentage'] as int? ?? 0) < 50).length;
    final avgPct  = total > 0
        ? (_report.fold<int>(0, (s, r) => s + ((r['percentage'] as int?) ?? 0)) / total).round()
        : 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _summaryItem('$total',           'Atletas',  Colors.white70),
                _summaryItem('$_totalSessions',  'Sesiones', const Color(0xFF00E5FF)),
                _summaryItem('$avgPct%',         'Promedio', Colors.amber),
                _summaryItem('$perfect',         '100%',     const Color(0xFF00C853)),
                _summaryItem('$atRisk',          '<50%',     Colors.redAccent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryItem(String value, String label, Color color) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
    ]);
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
    }
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(CupertinoIcons.exclamationmark_triangle, color: Colors.redAccent, size: 40),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _fetchReport,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
          ),
        ]),
      ));
    }
    if (_report.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(CupertinoIcons.doc_chart, size: 56, color: Colors.white.withValues(alpha: 0.15)),
        const SizedBox(height: 14),
        const Text('Sin datos para el período seleccionado',
            style: TextStyle(color: Colors.white38, fontSize: 15)),
      ]));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _report.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return _buildTableHeader();
        return _buildAthleteRow(_report[i - 1], i);
      },
    );
  }

  Widget _buildTableHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: const [
        SizedBox(width: 32, child: Text('#', style: TextStyle(color: Colors.white24, fontSize: 11))),
        Expanded(child: Text('ATLETA', style: TextStyle(color: Colors.white24, fontSize: 11,
            letterSpacing: 0.8))),
        SizedBox(width: 70, child: Text('SESIONES', textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white24, fontSize: 11))),
        SizedBox(width: 58, child: Text('%', textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white24, fontSize: 11))),
      ]),
    );
  }

  Widget _buildAthleteRow(Map<String, dynamic> row, int position) {
    final name     = (row['fullName']         as String?) ?? '—';
    final category = (row['category']         as String?) ?? '—';
    final attended = (row['sessionsAttended'] as int?)    ?? 0;
    final total    = (row['totalSessions']    as int?)    ?? 0;
    final pct      = (row['percentage']       as int?)    ?? 0;
    final isMinor  = (row['isMinor']          as bool?)   ?? false;

    final Color barColor;
    if (pct >= 80) {
      barColor = const Color(0xFF00C853);
    } else if (pct >= 50) {
      barColor = Colors.amber;
    } else {
      barColor = Colors.redAccent;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Column(children: [
              Row(children: [
                // Posición
                SizedBox(
                  width: 32,
                  child: Text('$position',
                      style: const TextStyle(color: Colors.white24, fontSize: 12)),
                ),

                // Nombre y categoría
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(name, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white,
                                fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                      if (isMinor) ...[
                        const SizedBox(width: 4),
                        const Icon(CupertinoIcons.person_fill,
                            size: 10, color: Colors.amber),
                      ],
                    ]),
                    Text(category,
                        style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  ],
                )),

                // Sesiones asistidas / total
                SizedBox(
                  width: 70,
                  child: Text('$attended / $total',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white60, fontSize: 12)),
                ),

                // Porcentaje
                SizedBox(
                  width: 58,
                  child: Text('$pct%',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: barColor,
                          fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ]),

              const SizedBox(height: 6),

              // Barra de progreso
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (pct / 100).clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation<Color>(barColor),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
