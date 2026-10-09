import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/agent_state.dart';

/// Computes line-by-line insertions, deletions, and unchanged lines.
class DiffComputer {
  static List<DiffLine> compute(String oldText, String newText) {
    final oldLines = oldText.isEmpty ? <String>[] : oldText.split('\n');
    final newLines = newText.isEmpty ? <String>[] : newText.split('\n');
    final m = oldLines.length;
    final n = newLines.length;

    // LCS dynamic programming table
    final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
    for (int i = 0; i < m; i++) {
      for (int j = 0; j < n; j++) {
        if (oldLines[i] == newLines[j]) {
          dp[i + 1][j + 1] = dp[i][j] + 1;
        } else {
          dp[i + 1][j + 1] = dp[i + 1][j] > dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1];
        }
      }
    }

    // Backtrack to build diff lines
    final result = <DiffLine>[];
    int i = m;
    int j = n;
    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && oldLines[i - 1] == newLines[j - 1]) {
        result.add(DiffLine(
          type: DiffType.unchanged,
          oldLineNumber: i,
          newLineNumber: j,
          text: oldLines[i - 1],
        ));
        i--;
        j--;
      } else if (j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j])) {
        result.add(DiffLine(
          type: DiffType.insertion,
          newLineNumber: j,
          text: newLines[j - 1],
        ));
        j--;
      } else if (i > 0 && (j == 0 || dp[i][j - 1] < dp[i - 1][j])) {
        result.add(DiffLine(
          type: DiffType.deletion,
          oldLineNumber: i,
          text: oldLines[i - 1],
        ));
        i--;
      }
    }

    return result.reversed.toList();
  }
}

/// Manages workspace files backed by visible Android storage and memory.
class WorkspaceService extends ChangeNotifier {
  final Map<String, WorkspaceFile> _files = {};
  String? _diskDirectoryPath;

  WorkspaceService() {
    _initStorageLocation();
    _initDefaultFiles();
  }

  Map<String, WorkspaceFile> get files => Map.unmodifiable(_files);
  List<String> get filePaths => _files.keys.toList()..sort();
  String? get diskDirectoryPath => _diskDirectoryPath;

  void _initStorageLocation() {
    try {
      if (Platform.isAndroid) {
        final docsDir = Directory('/storage/emulated/0/Documents/MobileCodingAgent');
        final dlDir = Directory('/storage/emulated/0/Download/MobileCodingAgent');

        if (docsDir.existsSync() || _tryCreateDir(docsDir)) {
          _diskDirectoryPath = docsDir.path;
        } else if (dlDir.existsSync() || _tryCreateDir(dlDir)) {
          _diskDirectoryPath = dlDir.path;
        } else {
          final tempDir = Directory('${Directory.systemTemp.path}/MobileCodingAgent');
          _tryCreateDir(tempDir);
          _diskDirectoryPath = tempDir.path;
        }
      } else {
        final localDir = Directory('${Directory.systemTemp.path}/MobileCodingAgent');
        _tryCreateDir(localDir);
        _diskDirectoryPath = localDir.path;
      }
    } catch (_) {
      _diskDirectoryPath = null;
    }
  }

  bool _tryCreateDir(Directory dir) {
    try {
      dir.createSync(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _initDefaultFiles() {
    _files.clear();

    _registerAndSaveFile(
      'lib/main.dart',
      '''// Entry point of the sample project
import 'calculator.dart';
import 'data_service.dart';

void main() {
  final calc = Calculator();
  print('Result: \${calc.add(10, 20)}');
  
  final service = DataService();
  final data = service.fetchUserProfile('user_123');
  print('User: \$data');
}
''',
    );

    _registerAndSaveFile(
      'lib/calculator.dart',
      '''// Basic calculator utility with known issues
class Calculator {
  double add(double a, double b) => a + b;
  double subtract(double a, double b) => a - b;
  double multiply(double a, double b) => a * b;
  
  // Bug: does not check for division by zero!
  double divide(double a, double b) {
    return a / b;
  }
}
''',
    );

    _registerAndSaveFile(
      'lib/data_service.dart',
      '''// Data fetcher and transformer
class DataService {
  final Map<String, dynamic> _cache = {};

  Map<String, dynamic> fetchUserProfile(String userId) {
    if (_cache.containsKey(userId)) {
      return _cache[userId] as Map<String, dynamic>;
    }
    // Simulated remote payload
    final profile = {
      'id': userId,
      'name': 'Alex Rivera',
      'role': 'Developer',
      'isActive': true,
    };
    _cache[userId] = profile;
    return profile;
  }
}
''',
    );

    _registerAndSaveFile(
      'test/calculator_test.dart',
      '''// Unit tests for calculator
import 'package:flutter_test/flutter_test.dart';
import '../lib/calculator.dart';

void main() {
  test('add adds two numbers', () {
    final calc = Calculator();
    expect(calc.add(2, 3), 5);
  });
}
''',
    );
  }

  void _registerAndSaveFile(String path, String content) {
    final file = WorkspaceFile(
      path: path,
      content: content,
      originalContent: content,
    );
    _files[path] = file;
    _writeToDisk(path, content);
  }

  void resetToDefault() {
    _initDefaultFiles();
    notifyListeners();
  }

  String? readFile(String path) {
    final clean = _normalizePath(path);
    if (_diskDirectoryPath != null) {
      final diskFile = File('$_diskDirectoryPath/$clean');
      if (diskFile.existsSync()) {
        try {
          final content = diskFile.readAsStringSync();
          _files[clean]?.content = content;
          return content;
        } catch (_) {}
      }
    }
    return _files[clean]?.content;
  }

  bool writeFile(String path, String content) {
    final clean = _normalizePath(path);
    final exists = _files.containsKey(clean);

    if (exists) {
      final existing = _files[clean]!;
      existing.originalContent ??= existing.content;
      existing.content = content;
      existing.lastModified = DateTime.now();
      existing.isModifiedByAgent = true;
      existing.diffLines = DiffComputer.compute(existing.originalContent!, content);
    } else {
      final newFile = WorkspaceFile(
        path: clean,
        content: content,
        originalContent: '',
        isCreatedByAgent: true,
      );
      newFile.diffLines = DiffComputer.compute('', content);
      _files[clean] = newFile;
    }

    _writeToDisk(clean, content);
    notifyListeners();
    return true;
  }

  void _writeToDisk(String relativePath, String content) {
    if (_diskDirectoryPath == null) return;
    try {
      final file = File('$_diskDirectoryPath/$relativePath');
      final parent = file.parent;
      if (!parent.existsSync()) {
        parent.createSync(recursive: true);
      }
      file.writeAsStringSync(content);
    } catch (_) {}
  }

  List<String> listFiles([String? prefix]) {
    final normPrefix = prefix != null ? _normalizePath(prefix) : '';
    return _files.keys.where((p) => p.startsWith(normPrefix)).toList()..sort();
  }

  String searchCode(String query) {
    final matches = <String>[];
    for (final entry in _files.entries) {
      final lines = entry.value.content.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].toLowerCase().contains(query.toLowerCase())) {
          matches.add('${entry.key}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    if (matches.isEmpty) return 'No matches found for "$query".';
    return matches.join('\n');
  }

  String analyzeSyntax(String path) {
    final clean = _normalizePath(path);
    final file = _files[clean];
    if (file == null) return 'Error: File "$path" not found.';

    final content = file.content;
    final issues = <String>[];

    final stack = <String>[];
    final lines = content.split('\n');
    for (var l = 0; l < lines.length; l++) {
      final line = lines[l];
      for (var c = 0; c < line.length; c++) {
        final char = line[c];
        if (char == '{' || char == '(' || char == '[') {
          stack.add(char);
        } else if (char == '}' || char == ')' || char == ']') {
          if (stack.isEmpty) {
            issues.add('Line ${l + 1}: Unmatched closing delimiter "$char".');
          } else {
            final last = stack.removeLast();
            if ((char == '}' && last != '{') ||
                (char == ')' && last != '(') ||
                (char == ']' && last != '[')) {
              issues.add('Line ${l + 1}: Mismatched delimiter "$char" (expected closing for "$last").');
            }
          }
        }
      }
    }
    if (stack.isNotEmpty) {
      issues.add('Unclosed opening delimiters remaining: ${stack.join(', ')}');
    }

    if (issues.isEmpty) {
      return 'Syntax Check Passed: 0 delimiter or structural errors detected in $clean (${file.lineCount} lines).';
    } else {
      return 'Syntax Analysis Issues in $clean:\n- ${issues.join('\n- ')}';
    }
  }

  String _normalizePath(String raw) {
    var p = raw.replaceAll('\\', '/').trim();
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    while (p.startsWith('./')) {
      p = p.substring(2);
    }
    return p;
  }
}
