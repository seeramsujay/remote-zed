import 'package:flutter_test/flutter_test.dart';
import 'package:zed_remote_app/models/terminal_models.dart';

void main() {
  group('Terminal Models Test', () {
    test('TerminalExecResult parses stdout, stderr, and cwd', () {
      final json = {
        'stdout': 'drwxr-xr-x 2 user user 4096 Oct 6 12:00 myapp\n',
        'stderr': '',
        'exit_code': 0,
        'cwd': '/home/user/Projects',
      };

      final result = TerminalExecResult.fromJson(json);
      expect(result.stdout, contains('myapp'));
      expect(result.stderr, isEmpty);
      expect(result.exitCode, equals(0));
      expect(result.cwd, equals('/home/user/Projects'));
    });

    test('FileEntry calculates human-readable sizes', () {
      final dirEntry = FileEntry(
        name: 'src',
        path: '/home/user/src',
        isDir: true,
        sizeBytes: 4096,
        modifiedEpochSecs: 1728218400,
      );
      final fileEntry = FileEntry(
        name: 'main.rs',
        path: '/home/user/src/main.rs',
        isDir: false,
        sizeBytes: 2048,
        modifiedEpochSecs: 1728218400,
      );

      expect(dirEntry.humanSize, isEmpty);
      expect(fileEntry.humanSize, equals('2.0 KB'));
    });

    test('FsListResult parses directory listing and parent path', () {
      final json = {
        'current_path': '/home/user/Projects/myapp',
        'parent_path': '/home/user/Projects',
        'entries': [
          {
            'name': 'src',
            'path': '/home/user/Projects/myapp/src',
            'is_dir': true,
            'size_bytes': 4096,
            'modified_epoch_secs': 1728218400,
          },
          {
            'name': 'Cargo.toml',
            'path': '/home/user/Projects/myapp/Cargo.toml',
            'is_dir': false,
            'size_bytes': 350,
            'modified_epoch_secs': 1728218400,
          },
        ],
      };

      final list = FsListResult.fromJson(json);
      expect(list.currentPath, equals('/home/user/Projects/myapp'));
      expect(list.parentPath, equals('/home/user/Projects'));
      expect(list.entries.length, equals(2));
      expect(list.entries.first.isDir, isTrue);
      expect(list.entries.last.name, equals('Cargo.toml'));
    });
  });
}
