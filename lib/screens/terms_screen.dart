import 'package:flutter/material.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Políticas y Términos'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF003F87),
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'POLÍTICA DE PRIVACIDAD Y TÉRMINOS DE USO - OMNISPORT-AI',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF003F87),
              ),
            ),
            const SizedBox(height: 24),
            _buildSection(
              title: '1. Responsable del Tratamiento',
              content: 'Rommel Asitimbay Morales, con domicilio en Quito, Ecuador.',
            ),
            _buildSection(
              title: '2. Finalidad del Tratamiento',
              content: 'Sus datos personales (nombre, correo, teléfono y fotografía) serán tratados exclusivamente para:\n\n'
                  '• Generar rutinas de entrenamiento personalizadas mediante Inteligencia Artificial.\n'
                  '• Gestionar su participación en el torneo AVP2 y mostrar su posición en las tablas de clasificación.\n'
                  '• Mantener comunicación sobre actualizaciones del servicio y seguridad.',
            ),
            _buildSection(
              title: '3. Base Legal',
              content: 'El tratamiento se basa en su consentimiento explícito otorgado al marcar la casilla de aceptación en esta aplicación, conforme al Art. 7 y 8 de la LOPDP.',
            ),
            _buildSection(
              title: '4. Derechos ARCO',
              content: 'Usted tiene derecho al Acceso, Rectificación, Cancelación y Oposición de sus datos. Puede ejercerlos directamente actualizando su perfil en la App o contactando al Delegado de Protección de Datos (DPO) al correo registrado.',
            ),
            _buildSection(
              title: '5. Conservación',
              content: 'Sus datos se conservarán mientras se mantenga la relación como usuario de OmniSport-AI o hasta que usted solicite su eliminación.',
            ),
            _buildSection(
              title: '6. Seguridad',
              content: 'Implementamos medidas técnicas (Cifrado Base64, Google Auth y Firebase Security Rules) para garantizar la integridad de su información.',
            ),
            const SizedBox(height: 40),
            Center(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF003F87),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Entendido y Cerrar'),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required String content}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
