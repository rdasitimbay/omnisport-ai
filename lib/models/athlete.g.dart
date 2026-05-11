// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'athlete.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AthleteAdapter extends TypeAdapter<Athlete> {
  @override
  final int typeId = 0;

  @override
  Athlete read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Athlete(
      uid: fields[0] as String,
      fullName: fields[1] as String,
      photoUrl: fields[2] as String,
      teamOrCategory: fields[3] as String,
      paymentStatus: fields[4] as String,
      status: fields[5] as String,
      representativeUid: fields[6] as String,
      lastMedicalReview: fields[7] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Athlete obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.uid)
      ..writeByte(1)
      ..write(obj.fullName)
      ..writeByte(2)
      ..write(obj.photoUrl)
      ..writeByte(3)
      ..write(obj.teamOrCategory)
      ..writeByte(4)
      ..write(obj.paymentStatus)
      ..writeByte(5)
      ..write(obj.status)
      ..writeByte(6)
      ..write(obj.representativeUid)
      ..writeByte(7)
      ..write(obj.lastMedicalReview);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AthleteAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
