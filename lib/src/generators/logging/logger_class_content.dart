const String logHelperNameKey = 'logHelperName';
const String multiLoggerImports = 'MultiLoggerImport'; // Not used in the final version
const String multipleLoggerOutput = 'MultiLoggerList';
const String disableConsoleOutputInRelease =
    'disableConsoleOutputInRelease'; // Better name

const String loggerClassPrefex = '''
// ignore_for_file: avoid_print, depend_on_referenced_packages

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:teachers_assistant/services/google_cloud_logger_service.dart';

import '../utils/google_cloud_logger_output.dart';
''';

const String loggerClassConstantBody = '''

class SimpleLogPrinter extends LogPrinter {
  final String className;
  final bool printCallingFunctionName;
  final bool printCallStack;
  final List<String> excludeLogsFromClasses;
  final String? showOnlyClass;
  final void Function(LogEvent)? onLogEvent; // Add the callback

  SimpleLogPrinter(
    this.className, {
    this.printCallingFunctionName = true,
    this.printCallStack = false,
    this.excludeLogsFromClasses = const [],
    this.showOnlyClass,
    this.onLogEvent, // Add to constructor
  });

 @override
  List<String> log(LogEvent event) {
    var color = PrettyPrinter.defaultLevelColors[event.level];
    var emoji = PrettyPrinter.defaultLevelEmojis[event.level];
    var methodName = _getMethodName();

    // Call the callback with the LogEvent
    onLogEvent?.call(event);

    var methodNameSection =
        printCallingFunctionName && methodName != null && !kReleaseMode
            ? ' | \$methodName'
            : '';

    // Construct the message and stack trace parts separately
    String message = event.message.toString();
    String stackTrace = event.stackTrace?.toString() ?? ''; // Safe null check

    // Combine message and stack trace for output
    List<String> outputLines = [
      '\$emoji \$className\$methodNameSection - \$message',
       if (event.error != null) 'ERROR: \${event.error}',
    ];

    if (stackTrace.isNotEmpty && printCallStack) {
        outputLines.add('STACKTRACE:');
        outputLines.addAll(stackTrace.split('\\n'));
    }

    // --- Chunking for large messages (important for Cloud Logging limits) ---
    List<String> result = [];
    for (var line in outputLines) {
      final pattern = RegExp('.{1,800}'); // 800 char chunks (adjust as needed)
      result.addAll(pattern.allMatches(line).map((match) {
        if (kReleaseMode) {
          return match.group(0)!;
        } else {
          return color!(match.group(0)!); // Apply color in debug mode
        }
      }));
    }
    //Filter before returning.
    if (excludeLogsFromClasses
            .any((excludeClass) => className == excludeClass) ||
        (showOnlyClass != null && className != showOnlyClass)) return [];

    return result;
  }

    String? _getMethodName() {
      try {
        final currentStack = StackTrace.current;
        final formattedStacktrace = _formatStackTrace(currentStack, 5); // Increased to 5
        if (formattedStacktrace == null) {
            return null;
        }

        if (kIsWeb) {
          // Web-specific logic (improved)
          final classNameParts = _splitClassNameWords(className);
          String? methodNameLine = _findMostMatchedTrace(formattedStacktrace, classNameParts);

            // Extract method name using regex (more robust)
            final match = RegExp(r'\\s+(\\S+)\\s+\\(').firstMatch(methodNameLine ?? '');

            return match?.group(1);
        } else {
          // Mobile/Desktop logic (improved)
          final classNameRegex = RegExp(r'' + className + r'.(?<methodName>[^<\\s]+)');

          final match = formattedStacktrace.map((line) => classNameRegex.firstMatch(line))
                  .firstWhere((match) => match != null, orElse: () => null);

          return match?.namedGroup('methodName');
        }
      } catch (e) {
        return null;
      }
    }

    List<String> _splitClassNameWords(String className) {
      return className
          .split(RegExp(r'(?=[A-Z])'))
          .map((e) => e.toLowerCase())
          .toList();
    }

    /// When the faulty word exists in the begging this method will not be very useful
    String _findMostMatchedTrace(
        List<String> stackTraces, List<String> keyWords) {
      String match = stackTraces.firstWhere(
          (trace) => _doesTraceContainsAllKeywords(trace, keyWords),
          orElse: () => '');
      if (match.isEmpty && keyWords.isNotEmpty) {
        match = _findMostMatchedTrace(
            stackTraces, keyWords.sublist(0, keyWords.length - 1));
      }
      return match;
    }

    bool _doesTraceContainsAllKeywords(String stackTrace, List<String> keywords) {
      final formattedKeywordsAsRegex = RegExp(keywords.join('.*'));
      return stackTrace.contains(formattedKeywordsAsRegex);
    }
}

final stackTraceRegex = RegExp(r'#[0-9]+[\\s]+(.+) \\(([^\\s]+)\\)');

List<String>? _formatStackTrace(StackTrace stackTrace, int methodCount) {
  var lines = stackTrace.toString().split('\\n');

  var formatted = <String>[];
  var count = 0;
  for (var line in lines) {
    var match = stackTraceRegex.matchAsPrefix(line);
    if (match != null) {
      if (match.group(2)!.startsWith('package:logger')) {
        continue;
      }
      var newLine = ("\${match.group(1)}");
      formatted.add(newLine.replaceAll('<anonymous closure>', '()'));
      if (++count == methodCount) {
        break;
      }
    } else {
      formatted.add(line);
    }
  }

  if (formatted.isEmpty) {
    return null;
  } else {
    return formatted;
  }
}
''';

const String loggerClassNameAndOutputs = '''
Logger $logHelperNameKey(
  String className, {
  bool printCallingFunctionName = true,
  bool printCallstack = false,
  List<String> excludeLogsFromClasses = const [],
  String? showOnlyClass,
}) {
     GoogleCloudLoggerOutput? googleCloudLoggerOutput; // Declare here
    if (kReleaseMode) {
      googleCloudLoggerOutput = GoogleCloudLoggerOutput(); //init only in release mode
    }

  return Logger(
    filter: AllLogsFilter(), // Use your AllLogsFilter
    printer: SimpleLogPrinter(
      className,
      printCallingFunctionName: printCallingFunctionName,
      printCallStack: printCallstack,
      showOnlyClass: showOnlyClass,
      excludeLogsFromClasses: excludeLogsFromClasses,
      onLogEvent: (event) {
        if(event.level == Level.error) {
            googleCloudLoggerOutput?._lastErrorEvent = event;
        }
      }
    ),
    output: MultiOutput([
      if (!kReleaseMode) ConsoleOutput(),
      if (kReleaseMode) googleCloudLoggerOutput!,
    ]),
  );
}
''';
