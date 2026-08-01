// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SessionModelAdapter extends TypeAdapter<SessionModel> {
  @override
  final int typeId = 1;

  @override
  SessionModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SessionModel(
      id: fields[0] as String,
      athleteId: fields[1] as String,
      sport: fields[2] as String,
      ejerciciosCompletados: fields[3] as int,
      atletaNombre: fields[4] as String,
      tipo: fields[5] as String,
      fecha: fields[6] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, SessionModel obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.athleteId)
      ..writeByte(2)
      ..write(obj.sport)
      ..writeByte(3)
      ..write(obj.ejerciciosCompletados)
      ..writeByte(4)
      ..write(obj.atletaNombre)
      ..writeByte(5)
      ..write(obj.tipo)
      ..writeByte(6)
      ..write(obj.fecha);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
