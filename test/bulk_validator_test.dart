import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/bulk_ingestion_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

void main() {
  group('Validator Test - DryRunService (LOPDP Bulk Ingestion)', () {
    late BulkIngestionService ingestionService;

    setUp(() {
      // Instanciamos el servicio pasándole FakeFirebaseFirestore
      ingestionService = BulkIngestionService(firestore: FakeFirebaseFirestore());
    });

    test('Rechaza fechas de consentimiento en formato incorrecto (DD/MM/YY)', () async {
      const csvMock = '''full_name,dni,email,phone,teamOrCategory,consent_date
Juan Perez,1234567890,test@test.com,123,Sub15,20/04/26''';

      final summary = await ingestionService.validate(csvMock, 'test-institution', forceOrder: true);
      
      expect(summary.total, 1);
      expect(summary.failed, 1);
      expect(summary.valid, 0);
      expect(summary.errors.first.message, contains('[ERROR FORMATO] Fecha'));
    });

    test('Rechaza emails sin dominio', () async {
      const csvMock = '''full_name,dni,email,phone,teamOrCategory,consent_date
Maria Lopez,0987654321,maria@,123,Sub15,2026-04-20''';

      final summary = await ingestionService.validate(csvMock, 'test-institution', forceOrder: true);
      
      expect(summary.total, 1);
      expect(summary.failed, 1);
      expect(summary.valid, 0);
      expect(summary.errors.first.message, contains('[ERROR FORMATO] Email inválido'));
    });

    test('Rechaza registros con falta de consentimiento LOPDP', () async {
      // Se omite la fecha de consentimiento (última columna vacía)
      const csvMock = '''full_name,dni,email,phone,teamOrCategory,consent_date
Pedro Paz,5555555555,pedro@test.com,123,Sub10,''';

      final summary = await ingestionService.validate(csvMock, 'test-institution', forceOrder: true);
      
      expect(summary.total, 1);
      expect(summary.failed, 1);
      expect(summary.valid, 0);
      expect(summary.errors.first.message, contains('[ERROR CRÍTICO LOPDP] Consentimiento no proporcionado.'));
    });

    test('Acepta registros completamente válidos', () async {
      const csvMock = '''full_name,dni,email,phone,teamOrCategory,consent_date
Ana Gomez,1723456789,ana@test.com,123,Sub18,2026-04-21''';

      final summary = await ingestionService.validate(csvMock, 'test-institution', forceOrder: true);
      
      expect(summary.total, 1);
      expect(summary.failed, 0);
      expect(summary.valid, 1);
    });
  });
}
