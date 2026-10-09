import 'package:flutter/foundation.dart';
import '../models/agent_state.dart';

/// Manages workspace files in memory with simulated IDE capabilities.
class WorkspaceService extends ChangeNotifier {
  final Map<String, WorkspaceFile> _files = {};

  WorkspaceService() {
    _initDefaultFiles();
  }

  Map<String, WorkspaceFile> get files => Map.unmodifiable(_files);

  List<String> get filePaths => _files.keys.toList()..sort();

  void _initDefaultFiles() {
    _files.clear();

    _files['lib/main.dart'] = WorkspaceFile(
      path: 'lib/main.dart',
      content: '''// Entry point of the sample project
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

    _files['lib/calculator.dart'] = WorkspaceFile(
      path: 'lib/calculator.dart',
      content: '''// Basic calculator utility with known issues
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

    _files['lib/data_service.dart'] = WorkspaceFile(
      path: 'lib/data_service.dart',
      content: '''// Data fetcher and transformer
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

    _files['test/calculator_test.dart'] = WorkspaceFile(
      path: 'test/calculator_test.dart',
      content: '''// Unit tests for calculator
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

  void resetToDefault() {
    _initDefaultFiles();
    notifyListeners();
  }

  String? readFile(String path) {
    final clean = _normalizePath(path);
    return _files[clean]?.content;
  }

  bool writeFile(String path, String content) {
    final clean = _normalizePath(path);
    final exists = _files.containsKey(clean);
    
    if (exists) {
      final existing = _files[clean]!;
      existing.content = content;
      existing.lastModified = DateTime.now();
      existing.isModifiedByAgent = true;
    } else {
      _files[clean] = WorkspaceFile(
        path: clean,
        content: content,
        isCreatedByAgent: true,
      );
    }
    notifyListeners();
    return true;
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

    // Bracket & parenthesis matching check
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
