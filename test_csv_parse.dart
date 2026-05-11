import 'dart:io';
import 'package:csv/csv.dart';

void main() async {
  String csvString = await File('uat_valid_records.csv').readAsString();
  String cleanCsv = csvString.replaceAll('\r\n', '\n').replaceAll('\ufeff', '');
  List<List<dynamic>> rows = const CsvToListConverter(eol: '\n').convert(cleanCsv);

  print("Total rows: \${rows.length}");
  if (rows.isNotEmpty) {
    print("Row 0: \${rows.first}");
    List<dynamic> headers = rows.first.map((e) => e.toString().toLowerCase().trim()).toList();
    print("Headers: \$headers");
    int dniIndex = headers.indexOf('dni');
    int nameIndex = headers.indexOf('full_name');
    int consentDateIndex = headers.indexOf('consent_date');
    print("dniIndex: \$dniIndex, nameIndex: \$nameIndex, consentDateIndex: \$consentDateIndex");
  }
}
