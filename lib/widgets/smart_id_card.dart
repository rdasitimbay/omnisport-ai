import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';
import '../models/smart_id_credential.dart';

/// Pasaporte Deportivo Digital — tarjeta Diamond Glass.
///
/// Proporciones de tarjeta de identificación estándar (CR-80): relación 1.586:1.
/// Efecto Diamond Glass: gradiente multicapa + franja holográfica diagonal
/// + borde con gradiente prismático.
class SmartIdCard extends StatelessWidget {
  final SmartIdCredential credential;

  const SmartIdCard({super.key, required this.credential});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.586,
      child: Stack(
        children: [
          _buildCardBase(),
          _buildHolographicStripe(),
          _buildContent(),
        ],
      ),
    );
  }

  Widget _buildCardBase() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0D1B3E),
                Color(0xFF0A2A5C),
                Color(0xFF0D3060),
                Color(0xFF082244),
              ],
              stops: [0.0, 0.35, 0.65, 1.0],
            ),
            border: Border.all(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.25),
                blurRadius: 24,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHolographicStripe() {
    return Positioned.fill(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Transform.rotate(
          angle: -0.4,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.transparent,
                  const Color(0xFF00E5FF).withValues(alpha: 0.04),
                  const Color(0xFF7B2FBE).withValues(alpha: 0.06),
                  const Color(0xFF00E5FF).withValues(alpha: 0.03),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLeftColumn(),
          const SizedBox(width: 12),
          Expanded(child: _buildRightColumn()),
        ],
      ),
    );
  }

  Widget _buildLeftColumn() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildPhoto(),
        const SizedBox(height: 8),
        _buildQrCode(),
      ],
    );
  }

  Widget _buildPhoto() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF00E5FF), Color(0xFF0066CC)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: ClipOval(
          child: credential.photoUrl.isNotEmpty
              ? Image.network(
                  credential.photoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _avatarFallback(),
                )
              : _avatarFallback(),
        ),
      ),
    );
  }

  Widget _avatarFallback() => Container(
    color: const Color(0xFF1A3A6B),
    child: const Icon(Icons.person, color: Colors.white54, size: 32),
  );

  Widget _buildQrCode() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
            blurRadius: 8,
          ),
        ],
      ),
      padding: const EdgeInsets.all(3),
      child: QrImageView(
        data: credential.token,
        version: QrVersions.auto,
        size: 64,
        backgroundColor: Colors.white,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Color(0xFF001F3F),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFF001F3F),
        ),
      ),
    );
  }

  Widget _buildRightColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildHeader(),
        _buildAthleteInfo(),
        _buildStatusRow(),
        _buildFooter(),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.shield, color: Color(0xFF00E5FF), size: 12),
        const SizedBox(width: 4),
        const Text(
          'OMNISPORT-AI',
          style: TextStyle(
            color: Color(0xFF00E5FF),
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: const Text(
            'SMART ID',
            style: TextStyle(color: Colors.white54, fontSize: 7, letterSpacing: 1),
          ),
        ),
      ],
    );
  }

  Widget _buildAthleteInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          credential.fullName.toUpperCase(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          credential.category,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 10,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusRow() {
    return Row(
      children: [
        _statusChip(
          credential.isEligible,
          credential.isEligible ? 'ELEGIBLE' : 'NO ELEGIBLE',
          credential.isEligible ? const Color(0xFF00E676) : const Color(0xFFFF1744),
        ),
        const SizedBox(width: 6),
        _statusChip(
          credential.medicalOk,
          credential.medicalOk ? 'MED ✓' : 'MED ✗',
          credential.medicalOk ? const Color(0xFF00E5FF) : Colors.orangeAccent,
        ),
      ],
    );
  }

  Widget _statusChip(bool ok, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildFooter() {
    final expiry = DateFormat('dd/MM/yyyy').format(credential.expiryDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          credential.smartIdNum,
          style: const TextStyle(
            color: Color(0xFF00E5FF),
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            fontFamily: 'monospace',
          ),
        ),
        Text(
          'Válido hasta $expiry',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 8),
        ),
      ],
    );
  }
}
