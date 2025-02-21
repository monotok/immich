import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:immich_mobile/shared/models/logger_message.model.dart';
import 'package:isar/isar.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// [ImmichLogger] is a custom logger that is built on top of the [logging] package.
/// The logs are written to the database and onto console, using `debugPrint` method.
///
/// The logs are deleted when exceeding the `maxLogEntries` (default 200) property
/// in the class.
///
/// Logs can be shared by calling the `shareLogs` method, which will open a share dialog
/// and generate a csv file.
class ImmichLogger {
  static final ImmichLogger _instance = ImmichLogger._internal();
  final maxLogEntries = 200;
  final Isar _db = Isar.getInstance()!;
  final List<LoggerMessage> _msgBuffer = [];
  Timer? _timer;

  factory ImmichLogger() => _instance;

  ImmichLogger._internal() {
    _removeOverflowMessages();
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen(_writeLogToDatabase);
  }

  List<LoggerMessage> get messages {
    final inDb =
        _db.loggerMessages.where(sort: Sort.desc).anyId().findAllSync();
    return _msgBuffer.isEmpty ? inDb : _msgBuffer.reversed.toList() + inDb;
  }

  void _removeOverflowMessages() {
    final msgCount = _db.loggerMessages.countSync();
    if (msgCount > maxLogEntries) {
      final numberOfEntryToBeDeleted = msgCount - maxLogEntries;
      _db.loggerMessages.where().limit(numberOfEntryToBeDeleted).deleteAll();
    }
  }

  void _writeLogToDatabase(LogRecord record) {
    debugPrint('[${record.level.name}] [${record.time}] ${record.message}');
    final lm = LoggerMessage(
      message: record.message,
      level: record.level.toLogLevel(),
      createdAt: record.time,
      context1: record.loggerName,
      context2: record.stackTrace?.toString(),
    );
    _msgBuffer.add(lm);

    // delayed batch writing to database: increases performance when logging
    // messages in quick succession and reduces NAND wear
    _timer ??= Timer(const Duration(seconds: 5), _flushBufferToDatabase);
  }

  void _flushBufferToDatabase() {
    _timer = null;
    _db.writeTxnSync(() => _db.loggerMessages.putAllSync(_msgBuffer));
    _msgBuffer.clear();
  }

  void clearLogs() {
    _timer?.cancel();
    _timer = null;
    _msgBuffer.clear();
    _db.writeTxn(() => _db.loggerMessages.clear());
  }

  Future<void> shareLogs() async {
    final tempDir = await getTemporaryDirectory();
    final dateTime = DateTime.now().toIso8601String();
    final filePath = '${tempDir.path}/Immich_log_$dateTime.csv';
    final logFile = await File(filePath).create();
    final io = logFile.openWrite();
    try {
      // Write header
      io.write("created_at,level,context,message,stacktrace\n");

      // Write messages
      for (final m in messages) {
        io.write(
          '${m.createdAt},${m.level},"${m.context1 ?? ""}","${m.message}","${m.context2 ?? ""}"\n',
        );
      }
    } finally {
      await io.flush();
      await io.close();
    }

    // Share file
    // ignore: deprecated_member_use
    await Share.shareFiles(
      [filePath],
      subject: "Immich logs $dateTime",
      sharePositionOrigin: Rect.zero,
    );

    // Clean up temp file
    await logFile.delete();
  }

  /// Flush pending log messages to persistent storage
  void flush() {
    if (_timer != null) {
      _timer!.cancel();
      _flushBufferToDatabase();
    }
  }
}
