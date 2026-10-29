part of 'bdd_base.dart';

/// One run of a BDD, recorded while it runs so that reporters can tell what
/// happened in each code block: whether it passed, how long it took, and which
/// error it threw.
///
/// A BDD with examples runs once per example row, and a BDD with retries may
/// run more than once for the same row. Each of those runs is a separate
/// [BddExecution]. A BDD that was skipped, or that never ran, has none.
///
/// These are observations of BDD code, not the final test runner outcome.
/// Setup/teardown errors outside that code are not recorded, and a future may
/// complete after the runner has already timed out the test. Use the runner's
/// result, rather than [passed], to determine whether the whole test passed.
///
/// Runs are recorded even when no reporter uses them: one record per attempt
/// and code block, with timestamps, durations, errors and stack traces. They
/// use memory in proportion to the number of attempts and code blocks, and
/// are only written to a file if a reporter, like `CucumberResultsReporter`, does so.
class BddExecution {
  BddExecution._({
    required this.exampleIndex,
    required this.attempt,
    required this.startedAt,
  });

  /// The index of the example row this run used, or `null` if the BDD has no
  /// examples.
  final int? exampleIndex;

  /// Which attempt this is for the same example row: `1` for the first run,
  /// `2` for the first retry, and so on.
  final int attempt;

  /// When this run started.
  final DateTime startedAt;

  final List<BddCodeExecution> _codeExecutions = [];

  /// The code blocks that ran, in the order they ran. The Background code comes
  /// first, then the code of the steps, then the callback given to `.run()`.
  ///
  /// Code blocks after a failing one didn't run, so they are not in this list.
  List<BddCodeExecution> get codeExecutions =>
      List.unmodifiable(_codeExecutions);

  Duration? _duration;
  Object? _error;
  StackTrace? _stackTrace;

  /// How long the BDD body took, or `null` while it has not finished.
  /// It may finish after the surrounding test has already timed out.
  Duration? get duration => _duration;

  /// Whether the run finished, either passing or failing.
  bool get isFinished => _duration != null;

  /// Whether the run finished without errors.
  bool get passed => isFinished && _error == null;

  /// The error that failed the run, if any.
  Object? get error => _error;

  /// The stack trace of [error], if any.
  StackTrace? get stackTrace => _stackTrace;

  /// The result of [codeTerm], or `null` if it didn't run.
  BddCodeExecution? resultOf(BddCodeTerm codeTerm) =>
      _codeExecutions.firstWhereOrNull((code) => code.codeTerm == codeTerm);

  /// The results of the callbacks given to `.run()`, which belong to no step.
  Iterable<BddCodeExecution> get callbackResults =>
      _codeExecutions.where((code) => code.codeTerm == null);

  /// Runs [codeRun] and records its result. Errors are recorded and rethrown.
  ///
  /// Synchronous code stays synchronous: if [codeRun] throws synchronously,
  /// this throws synchronously too, just like calling [codeRun] directly.
  FutureOr<void> _run(
    BddCodeTerm? codeTerm,
    CodeRun codeRun,
    BddContext ctx,
  ) {
    final code = BddCodeExecution._(codeTerm, DateTime.now());
    _codeExecutions.add(code);
    final stopwatch = Stopwatch()..start();

    final FutureOr<void> result;
    try {
      result = codeRun(ctx);
    } catch (error, stackTrace) {
      code._finish(stopwatch.elapsed, error, stackTrace);
      rethrow;
    }

    if (result is Future<void>) return _complete(code, stopwatch, result);
    code._finish(stopwatch.elapsed);
  }

  static Future<void> _complete(
    BddCodeExecution code,
    Stopwatch stopwatch,
    Future<void> result,
  ) async {
    try {
      await result;
    } catch (error, stackTrace) {
      code._finish(stopwatch.elapsed, error, stackTrace);
      rethrow;
    }
    code._finish(stopwatch.elapsed);
  }

  void _finish(Duration duration, [Object? error, StackTrace? stackTrace]) {
    _duration = duration;
    _error = error;
    _stackTrace = stackTrace;
  }

  @override
  String toString() => 'BddExecution{exampleIndex: $exampleIndex, '
      'attempt: $attempt, passed: $passed, duration: $duration}';
}

/// The result of running one code block of a BDD. See [BddExecution].
class BddCodeExecution {
  BddCodeExecution._(this.codeTerm, this.startedAt);

  /// The step code that ran, added with `.code()`. It's `null` for the
  /// callback given to `.run()`, which belongs to no step.
  final BddCodeTerm? codeTerm;

  /// When the code block started.
  final DateTime startedAt;

  Duration? _duration;
  Object? _error;
  StackTrace? _stackTrace;

  /// How long the code block took, or `null` while it has not finished.
  /// It may finish after the surrounding test has already timed out.
  Duration? get duration => _duration;

  /// Whether the code block finished, either passing or failing.
  bool get isFinished => _duration != null;

  /// Whether the code block finished without errors.
  bool get passed => isFinished && _error == null;

  /// The error the code block threw, if any.
  Object? get error => _error;

  /// The stack trace of [error], if any.
  StackTrace? get stackTrace => _stackTrace;

  void _finish(Duration duration, [Object? error, StackTrace? stackTrace]) {
    _duration = duration;
    _error = error;
    _stackTrace = stackTrace;
  }

  @override
  String toString() => 'BddCodeExecution{passed: $passed, duration: $duration}';
}
